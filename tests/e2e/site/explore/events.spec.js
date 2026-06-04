import { expect, test } from "@playwright/test";

import {
  TEST_COMMUNITY_NAME,
  TEST_EVENT_NAMES,
  navigateToPath,
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
      await Promise.all([
        page.waitForResponse(
          (response) =>
            response.request().method() === "GET" &&
            response.url().includes("/explore/events/search") &&
            response.ok(),
        ),
        navigationButton.click(),
      ]);
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
      await Promise.all([
        page.waitForResponse(
          (response) =>
            response.request().method() === "GET" &&
            response.url().includes("/explore/events/search") &&
            response.ok(),
        ),
        navigationButton.click(),
      ]);
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
