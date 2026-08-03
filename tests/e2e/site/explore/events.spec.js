import { expect, test } from "@playwright/test";

import {
  TEST_COMMUNITY_NAME,
  TEST_EVENT_NAMES,
  TEST_GROUP_SLUG,
  expectPaginationNavigation,
  navigateToPath,
  waitForActionResponse,
} from "../../utils.js";

// Format a date as YYYY-MM-DD using UTC components.
const formatDate = (date) => {
  const year = date.getUTCFullYear();
  const month = String(date.getUTCMonth() + 1).padStart(2, "0");
  const day = String(date.getUTCDate()).padStart(2, "0");

  return `${year}-${month}-${day}`;
};

// Return the first day of the UTC month.
const getMonthStart = (date) =>
  new Date(Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), 1));

// Return the last day of the UTC month.
const getMonthEnd = (date) =>
  new Date(Date.UTC(date.getUTCFullYear(), date.getUTCMonth() + 1, 0));

// Add months to a UTC month date.
const addMonths = (date, delta) =>
  new Date(Date.UTC(date.getUTCFullYear(), date.getUTCMonth() + delta, 1));

// Return a stable key for a UTC month.
const getMonthKey = (date) => formatDate(getMonthStart(date)).slice(0, 7);

// Return the inclusive date range for a UTC month.
const getMonthRange = (date) => ({
  first: formatDate(getMonthStart(date)),
  last: formatDate(getMonthEnd(date)),
});

// Return the distance in whole months between two UTC month dates.
const getMonthDistance = (from, to) =>
  (to.getUTCFullYear() - from.getUTCFullYear()) * 12 +
  (to.getUTCMonth() - from.getUTCMonth());

// Find a populated month with an adjacent empty month for navigation coverage.
const findCalendarNavigationScenario = async (page) => {
  const data = await page.evaluate(async (communityName) => {
    const params = new URLSearchParams();
    params.append("community[0]", communityName);
    params.set("view_mode", "calendar");
    params.set("date_from", "1900-01-01");
    params.set("date_to", "2100-12-31");

    // Fetch the full calendar data set for the selected community.
    const response = await fetch(
      `/explore/events/search?${params.toString()}`,
      {
        headers: { Accept: "application/json" },
      },
    );

    if (!response.ok) {
      throw new Error(`Unable to load event data: ${response.status}`);
    }

    return response.json();
  }, TEST_COMMUNITY_NAME);

  // Build the set of months that currently have events.
  const populatedMonths = new Set(
    data.events.map((event) => getMonthKey(new Date(event.starts_at * 1000))),
  );
  const sortedMonths = [...populatedMonths].sort();

  if (sortedMonths.length === 0) {
    return null;
  }

  for (const monthKey of sortedMonths) {
    const populatedMonth = new Date(`${monthKey}-01T00:00:00.000Z`);
    const previousMonth = addMonths(populatedMonth, -1);

    if (!populatedMonths.has(getMonthKey(previousMonth))) {
      return {
        emptyMonth: previousMonth,
        populatedMonth,
        direction: "next",
      };
    }

    const nextMonth = addMonths(populatedMonth, 1);
    if (!populatedMonths.has(getMonthKey(nextMonth))) {
      return {
        emptyMonth: nextMonth,
        populatedMonth,
        direction: "previous",
      };
    }
  }

  throw new Error(
    "Could not find an empty month adjacent to populated calendar data",
  );
};

test.describe("site explore events page", () => {
  test("omits free badges from explore and calendar event cards", async ({
    page,
  }) => {
    await navigateToPath(
      page,
      `/explore?entity=events&community[0]=${TEST_COMMUNITY_NAME}`,
    );

    // Free list cards do not render an empty-value price badge.
    const freeEventName = TEST_EVENT_NAMES.alpha[0];
    const exploreCard = page
      .getByRole("link")
      .filter({ hasText: freeEventName })
      .first();
    await expect(exploreCard).toBeVisible();
    await expect(exploreCard.getByText("Free", { exact: true })).toHaveCount(0);
    await expect(exploreCard.locator("[data-localized-currency]")).toHaveCount(
      0,
    );

    // Find the event's seeded month so the same assertion reaches its calendar popover.
    const startsAt = await page.evaluate(
      async ({ communityName, eventName }) => {
        const params = new URLSearchParams();
        params.append("community[0]", communityName);
        params.set("view_mode", "calendar");
        params.set("date_from", "1900-01-01");
        params.set("date_to", "2100-12-31");
        const response = await fetch(
          `/explore/events/search?${params.toString()}`,
          {
            headers: { Accept: "application/json" },
          },
        );
        if (!response.ok) {
          throw new Error(`Unable to load event data: ${response.status}`);
        }
        const data = await response.json();
        const event = data.events.find((item) => item.name === eventName);
        return event?.starts_at ?? null;
      },
      { communityName: TEST_COMMUNITY_NAME, eventName: freeEventName },
    );
    expect(startsAt).not.toBeNull();
    const eventMonth = new Date(startsAt * 1000);
    const calendarRange = getMonthRange(eventMonth);
    await navigateToPath(
      page,
      `/explore?entity=events&community[0]=${TEST_COMMUNITY_NAME}` +
        `&view_mode=calendar&date_from=${calendarRange.first}` +
        `&date_to=${calendarRange.last}`,
    );

    const calendarEvent = page
      .locator(".fc-daygrid-event")
      .filter({ hasText: freeEventName })
      .first();
    await expect(calendarEvent).toBeVisible();
    await calendarEvent.hover();
    const calendarPopover = page
      .locator('[data-popover="true"]')
      .filter({ hasText: freeEventName });
    await expect(calendarPopover).toBeVisible();
    await expect(
      calendarPopover.getByText("Free", { exact: true }),
    ).toHaveCount(0);
    await expect(
      calendarPopover.locator("[data-localized-currency]"),
    ).toHaveCount(0);
  });

  test("moves between event result pages and restores the first card", async ({
    page,
  }) => {
    // Paginate seeded event cards with one result per page.
    await expectPaginationNavigation(
      page,
      `/explore?entity=events&community[0]=${TEST_COMMUNITY_NAME}&limit=1&offset=0`,
      "#cards-list article",
    );
  });

  test("restores every event filter and sort option from the URL", async ({
    page,
  }) => {
    // Build a URL containing every supported event filter and sort option.
    const filters = new URLSearchParams({
      entity: "events",
      "community[0]": TEST_COMMUNITY_NAME,
      "group[0]": TEST_GROUP_SLUG,
      "group_category[0]": "e2e-category-one",
      "region[0]": "north-america",
      "event_category[0]": "general",
      "kind[0]": "hybrid",
      date_from: "2026-01-01",
      date_to: "2027-12-31",
      sort_by: "date",
      sort_direction: "desc",
    });

    // Load the filtered events page.
    await navigateToPath(page, `/explore?${filters.toString()}`);

    // Find the desktop form and verify every control restores its URL value.
    const desktopForm = page.locator("#events-form");
    await expect(desktopForm).toBeAttached();
    await expect(
      desktopForm.locator('collapsible-filter[name="community"]'),
    ).toHaveAttribute("selected", JSON.stringify([TEST_COMMUNITY_NAME]));
    await expect(
      desktopForm.locator('multi-select-filter[name="group"]'),
    ).toHaveAttribute("selected", JSON.stringify([TEST_GROUP_SLUG]));
    await expect(
      desktopForm.locator('collapsible-filter[name="group_category"]'),
    ).toHaveAttribute("selected", JSON.stringify(["e2e-category-one"]));
    await expect(
      desktopForm.locator('collapsible-filter[name="region"]'),
    ).toHaveAttribute("selected", JSON.stringify(["north-america"]));
    await expect(
      desktopForm.locator('collapsible-filter[name="event_category"]'),
    ).toHaveAttribute("selected", JSON.stringify(["general"]));
    await expect(
      desktopForm.locator('input[name="kind[]"][value="hybrid"]'),
    ).toBeChecked();
    await expect(desktopForm.locator('input[name="date_from"]')).toHaveValue(
      "2026-01-01",
    );
    await expect(desktopForm.locator('input[name="date_to"]')).toHaveValue(
      "2027-12-31",
    );
    await expect(page.locator("#sort_selector")).toHaveValue("date-desc");
    await expect(page.locator("#sort_by")).toHaveValue("date");
    await expect(page.locator("#sort_direction")).toHaveValue("desc");
  });

  test("sorts events in both date directions", async ({ page }) => {
    // Load community events using their default date direction.
    await navigateToPath(
      page,
      `/explore?entity=events&community[0]=${TEST_COMMUNITY_NAME}`,
    );

    // Capture the initial card order before changing the sort.
    const eventCards = page.locator("#cards-list article");
    const initialEventNames = await eventCards
      .locator(".card-title")
      .allTextContents();

    // Switch to descending dates and wait for the event list to refresh.
    await Promise.all([
      page.waitForResponse(
        (response) =>
          response.request().method() === "GET" &&
          response.url().includes("/explore/events-section") &&
          response.url().includes("sort_direction=desc") &&
          response.ok(),
      ),
      page.locator("#sort_selector").selectOption("date-desc"),
    ]);

    // Verify the sort state and refreshed card order. Pagination and date
    // ties make a strict reversal unreliable, so assert the order changed.
    await expect(page.locator("#sort_selector")).toHaveValue("date-desc");
    await expect(page.locator("#sort_direction")).toHaveValue("desc");
    const descendingEventNames = await eventCards
      .locator(".card-title")
      .allTextContents();
    expect(initialEventNames.length).toBeGreaterThan(0);
    expect(descendingEventNames.length).toBeGreaterThan(0);
    expect(descendingEventNames).not.toEqual(initialEventNames);
  });

  test("opens, resets, and closes the mobile filters drawer @mobile", async ({
    page,
  }) => {
    // Load community events using the mobile project viewport.
    await navigateToPath(
      page,
      `/explore?entity=events&community[0]=${TEST_COMMUNITY_NAME}`,
    );

    // Find the filter drawer and verify its initial hidden state.
    const drawer = page.locator("#drawer-filters");
    const backdrop = page.locator("#drawer-backdrop");
    await expect(drawer).toHaveClass(/-translate-x-full/);
    await expect(backdrop).toHaveClass(/hidden/);

    // Open the drawer and verify its mobile form restores the URL filter.
    await page.locator("#open-filters").click();
    await expect(drawer).not.toHaveClass(/-translate-x-full/);
    await expect(backdrop).not.toHaveClass(/hidden/);
    await expect(drawer.getByText("Filters", { exact: true })).toBeVisible();
    const mobileForm = page.locator("#events-form-mobile");
    await expect(mobileForm).toBeAttached();
    await expect(
      mobileForm.locator('collapsible-filter[name="community"]'),
    ).toHaveAttribute("selected", JSON.stringify([TEST_COMMUNITY_NAME]));

    // Reset the mobile form and capture the unfiltered results request.
    const resetResponse = await waitForActionResponse(
      page,
      () =>
        drawer
          .getByRole("button", { name: "Reset", exact: true })
          .last()
          .click(),
      {
        method: "GET",
        urlIncludes: "/explore/events-section",
      },
    );
    const resetRequestUrl = resetResponse.url();

    // Verify reset clears the filter contract and closes the replaced drawer.
    expect(new URL(resetRequestUrl).searchParams.getAll("community[]")).toEqual(
      [],
    );
    await expect(
      page.locator('#events-form-mobile collapsible-filter[name="community"]'),
    ).toHaveAttribute("selected", "[]");
    await expect(page.locator("#sort_by")).toHaveValue("date");
    await expect(page.locator("#sort_direction")).toHaveValue("asc");
    await expect(drawer).toHaveClass(/-translate-x-full/);
    await expect(backdrop).toHaveClass(/hidden/);
  });

  test("supports kind filtering and switching to calendar view", async ({
    page,
  }) => {
    // Load the events explore page with the community filter applied.
    await navigateToPath(
      page,
      `/explore?entity=events&community[0]=${TEST_COMMUNITY_NAME}`,
    );

    // Verify events render before applying filters.
    await expect(page.getByPlaceholder("Search events")).toBeVisible();
    await expect(
      page.getByText(TEST_EVENT_NAMES.alpha[0], { exact: true }),
    ).toBeVisible();
    await expect(
      page.getByText(TEST_EVENT_NAMES.alpha[1], { exact: true }),
    ).toBeVisible();

    // Apply the in-person filter and wait for the event list to narrow.
    const inPersonFilter = page
      .locator('input[name="kind[]"][value="in-person"]')
      .first();
    await inPersonFilter.evaluate((input) => {
      if (!(input instanceof HTMLInputElement)) {
        throw new Error("in-person filter input not found");
      }

      // Select the answer option.
      input.checked = true;
      input.dispatchEvent(new Event("change", { bubbles: true }));
    });

    // Verify only matching in-person events remain visible.
    await expect(
      page.getByText(TEST_EVENT_NAMES.alpha[0], { exact: true }),
    ).toBeVisible();
    await expect(
      page.getByText(TEST_EVENT_NAMES.alpha[1], { exact: true }),
    ).toHaveCount(0);

    // Switch to the calendar view and wait for the results to refresh.
    await Promise.all([
      page.waitForResponse(
        (response) =>
          response.request().method() === "GET" &&
          response.url().includes("/explore/events-section") &&
          response.url().includes("view_mode=calendar") &&
          response.ok(),
      ),
      page.locator('label[for="calendar"]').click(),
    ]);

    // Verify calendar controls appear after switching views.
    await expect(page.locator("#calendar-box")).toBeVisible();
    await expect(page.locator("#calendar-date")).toBeVisible();
    await expect(page.locator("#current-month-btn")).toBeVisible();
    await expect(page.locator("#sort_selector")).toHaveCount(0);
  });

  test("shows a filtered empty state when no events match the search", async ({
    page,
  }) => {
    // Load the events explore page for an empty search result.
    await navigateToPath(
      page,
      `/explore?entity=events&community[0]=${TEST_COMMUNITY_NAME}`,
    );

    // Submit a search query that has no matching events.
    const searchInput = page.getByPlaceholder("Search events");
    await expect(searchInput).toBeVisible();

    // Submit the unmatched search query and wait for filtered results.
    await Promise.all([
      page.waitForResponse(
        (response) =>
          response.request().method() === "GET" &&
          response.url().includes("/explore/events-section") &&
          response.url().includes("ts_query=No%20matching%20event") &&
          response.ok(),
      ),
      searchInput
        .fill("No matching event")
        .then(() => searchInput.press("Enter")),
    ]);

    // Find the filtered empty state.
    const filteredEmptyState = page.locator(
      ".no-results-filtered:not(.hidden)",
    );

    // Verify the filtered empty state explains the missing matches.
    await expect(filteredEmptyState).toBeVisible();
    await expect(
      filteredEmptyState.getByText("No events found", { exact: true }),
    ).toBeVisible();
    await expect(
      filteredEmptyState.getByText(
        "We can't seem to find any events that match your search criteria. You can reset your filters or try a different search.",
      ),
    ).toBeVisible();

    // Switch to calendar view and wait for the empty state to refresh.
    await Promise.all([
      page.waitForResponse(
        (response) =>
          response.request().method() === "GET" &&
          response.url().includes("/explore/events-section") &&
          response.url().includes("view_mode=calendar") &&
          response.ok(),
      ),
      page.locator('label[for="calendar"]').click(),
    ]);

    // Verify calendar mode keeps the filtered empty state visible.
    await expect(page.locator("#calendar-box")).toBeVisible();
    await expect(
      page.locator(".no-results-filtered:not(.hidden)"),
    ).toBeVisible();
    await expect(page.locator(".no-results-default:not(.hidden)")).toHaveCount(
      0,
    );
  });

  test("hides the empty state after navigating from an empty month to one with events", async ({
    page,
  }) => {
    // Load events data to find adjacent calendar months.
    await navigateToPath(
      page,
      `/explore?entity=events&community[0]=${TEST_COMMUNITY_NAME}`,
    );

    // Set up scenario.
    const scenario = await findCalendarNavigationScenario(page);
    test.skip(!scenario, "Requires seeded calendar event data");

    // Set up the data for this check.
    const { emptyMonth, populatedMonth, direction } = scenario;
    const emptyRange = getMonthRange(emptyMonth);

    // Load the calendar on the empty adjacent month.
    await navigateToPath(
      page,
      `/explore?entity=events&community[0]=${TEST_COMMUNITY_NAME}` +
        `&view_mode=calendar&date_from=${emptyRange.first}&date_to=${emptyRange.last}`,
    );

    // Verify the calendar starts on an empty month.
    await expect(page.locator("#calendar-box")).toBeVisible();

    // Target empty-state, navigation, and event locators for the calendar.
    const defaultEmptyState = page.locator(".no-results-default:not(.hidden)");
    const navigationButton =
      direction === "next"
        ? page.locator("#next-month-btn")
        : page.locator("#prev-month-btn");
    const calendarEvents = page.locator(".fc-daygrid-event");
    await expect(defaultEmptyState).toBeVisible();
    await expect(page.locator(".no-results-filtered:not(.hidden)")).toHaveCount(
      0,
    );
    await expect(calendarEvents).toHaveCount(0);

    // Set up month steps.
    const monthSteps = Math.abs(getMonthDistance(emptyMonth, populatedMonth));
    expect(monthSteps).toBeGreaterThan(0);

    // Navigate month by month until events appear.
    for (let step = 0; step < monthSteps; step += 1) {
      // Navigate toward the populated month and wait for calendar data.
      await waitForActionResponse(page, () => navigationButton.click(), {
        method: "GET",
        urlIncludes: "/explore/events/search",
      });
    }

    // Verify empty fallback content clears after landing on a populated month.
    const populatedRange = getMonthRange(populatedMonth);
    await expect(page.locator(".no-results-filtered:not(.hidden)")).toHaveCount(
      0,
    );
    await expect(page.locator(".no-results-default:not(.hidden)")).toHaveCount(
      0,
    );
    await expect(defaultEmptyState).toHaveCount(0);
    await expect(calendarEvents.first()).toBeVisible();
    await expect
      .poll(async () =>
        page.evaluate(() => {
          const params = new URLSearchParams(window.location.search);

          // Return the values used by the caller.
          return {
            viewMode: params.get("view_mode"),
            dateFrom: params.get("date_from"),
            dateTo: params.get("date_to"),
          };
        }),
      )
      .toEqual({
        viewMode: "calendar",
        dateFrom: populatedRange.first,
        dateTo: populatedRange.last,
      });
  });

  test("shows the empty state after navigating from a populated month to an empty one", async ({
    page,
  }) => {
    // Load events data to find adjacent calendar months.
    await navigateToPath(
      page,
      `/explore?entity=events&community[0]=${TEST_COMMUNITY_NAME}`,
    );

    // Set up scenario.
    const scenario = await findCalendarNavigationScenario(page);
    test.skip(!scenario, "Requires seeded calendar event data");

    // Set up the data for this check.
    const { emptyMonth, populatedMonth } = scenario;
    const populatedRange = getMonthRange(populatedMonth);

    // Load the calendar on the populated adjacent month.
    await navigateToPath(
      page,
      `/explore?entity=events&community[0]=${TEST_COMMUNITY_NAME}` +
        `&view_mode=calendar&date_from=${populatedRange.first}&date_to=${populatedRange.last}`,
    );

    // Verify the calendar starts on a populated month.
    await expect(page.locator("#calendar-box")).toBeVisible();

    // Find the calendar events.
    const calendarEvents = page.locator(".fc-daygrid-event");
    await expect(calendarEvents.first()).toBeVisible();
    await expect(page.locator(".no-results-filtered:not(.hidden)")).toHaveCount(
      0,
    );
    await expect(page.locator(".no-results-default:not(.hidden)")).toHaveCount(
      0,
    );

    // Set up month distance.
    const monthDistance = getMonthDistance(populatedMonth, emptyMonth);
    expect(monthDistance).not.toBe(0);

    // Set up navigation button.
    const navigationButton =
      monthDistance > 0
        ? page.locator("#next-month-btn")
        : page.locator("#prev-month-btn");

    // Navigate month by month until the calendar has no events.
    for (let step = 0; step < Math.abs(monthDistance); step += 1) {
      // Navigate toward the empty month and wait for calendar data.
      await waitForActionResponse(page, () => navigationButton.click(), {
        method: "GET",
        urlIncludes: "/explore/events/search",
      });
    }

    // Verify the default empty state appears for the empty month.
    const emptyRange = getMonthRange(emptyMonth);
    const defaultEmptyState = page.locator(".no-results-default:not(.hidden)");
    await expect(defaultEmptyState).toBeVisible();
    await expect(page.locator(".no-results-filtered:not(.hidden)")).toHaveCount(
      0,
    );
    await expect(calendarEvents).toHaveCount(0);
    await expect
      .poll(async () =>
        page.evaluate(() => {
          const params = new URLSearchParams(window.location.search);

          // Return the values used by the caller.
          return {
            viewMode: params.get("view_mode"),
            dateFrom: params.get("date_from"),
            dateTo: params.get("date_to"),
          };
        }),
      )
      .toEqual({
        viewMode: "calendar",
        dateFrom: emptyRange.first,
        dateTo: emptyRange.last,
      });
  });
});
