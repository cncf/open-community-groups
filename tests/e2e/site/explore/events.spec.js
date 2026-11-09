import { randomUUID } from "node:crypto";
import { expect, test } from "../../fixtures.js";
import { cleanupEventsByIds, insertOwnedEvent } from "../../data-graphs/events.js";
import { getSeedClock } from "../../database.js";
import {
  TEST_CALENDAR_EVENTS,
  TEST_COHOSTED_EVENT,
  TEST_COMMUNITY_NAME,
  TEST_COMMUNITY_NAME_2,
  TEST_COMMUNITY_TITLE,
  TEST_EVENT_NAMES,
  TEST_GROUP_IDS,
  TEST_GROUP_NAMES,
  TEST_GROUP_SLUG,
} from "../../seed.js";
import { enableDesktopVersion, expectPageLayout } from "../../snapshots.js";
import {
  buildE2eUrl,
  expectPaginationNavigation,
  futureDate,
  navigateToPath,
  uniqueName,
  waitForActionResponse,
} from "../../utils.js";

// Approved co-host names in their alphabetical display order.
const COHOSTED_EVENT_COHOST_NAMES = [TEST_GROUP_NAMES.delta, TEST_GROUP_NAMES.zeta, TEST_GROUP_NAMES.gamma];

// Path of the explore event card requested when a calendar event opens its tooltip.
const EVENT_CARD_PATHNAME = /^\/explore\/events\/[0-9a-f-]+\/card$/;

// Explore URLs and what the Groups switch must send from each one.
const ENTITY_SWITCH_CASES = [
  {
    path: "/explore?entity=events&ts_query=Platform",
    params: { "community[0]": null, ts_query: "Platform" },
  },
  {
    path: `/explore?entity=events&community[0]=${TEST_COMMUNITY_NAME}`,
    params: { "community[0]": TEST_COMMUNITY_NAME, ts_query: null },
  },
  {
    path: `/explore?entity=events&community[0]=${TEST_COMMUNITY_NAME}&ts_query=Platform`,
    params: { "community[0]": TEST_COMMUNITY_NAME, ts_query: "Platform" },
  },
  {
    path: `/explore?entity=events&community[0]=${TEST_COMMUNITY_NAME}&community[1]=${TEST_COMMUNITY_NAME_2}`,
    params: { "community[0]": null, "community[1]": null, ts_query: null },
  },
];

// Date filter values `SearchEventsFilters` rejects: unparsable, out-of-range and non-`YYYY` years.
const INVALID_DATE_FILTERS = ["not-a-date", "2031-13-45", "2031/01/15", "0000-01-01", "-5000-01-01"];

/** Selects the applied filter chips of the phone chip row. */
const getAppliedFilterChips = (page) =>
  page.getByRole("group", { name: "Applied filters" }).getByRole("button");

/** Selects the phone Events and Groups switch. */
const getEntitySwitch = (page) => page.getByRole("group", { name: "Show" });

/** Selects the option label of a collapsible filter by its value. */
const getFilterOption = (filter, value) =>
  filter.locator("label").filter({ has: filter.page().locator(`input[value="${value}"]`) });

/** Opens the phone filter sheet and returns it. */
const openFilterSheet = async (page) => {
  await page.locator("#open-filters").click();
  const sheet = page.locator("#drawer-filters");
  await expect(page.getByRole("dialog", { name: "Filters" })).toBeVisible();
  return sheet;
};

/** Records the URL of every HTMX section request sent from now on. */
const trackSectionRequests = (page, pathname) => {
  const requests = [];
  page.on("request", (request) => {
    if (request.resourceType() === "xhr" && new URL(request.url()).pathname === pathname) {
      requests.push(request.url());
    }
  });
  return requests;
};

test.describe("site explore events page", () => {
  test("entity switch keeps the search and a single selected community", async ({ page }) => {
    for (const { params, path } of ENTITY_SWITCH_CASES) {
      // Load the filtered events page.
      await navigateToPath(page, path);

      // Switch to groups from the visible sidebar and verify the values sent.
      await waitForActionResponse(page, () => page.locator("#explore-filters #groups-button").click(), {
        method: "GET",
        params,
        pathname: "/explore/groups-section",
        status: 200,
      });
      await expect(page.locator("#groups-form")).toBeAttached();
    }
  });

  test("entity switch keeps the search and a single selected community @mobile", async ({ page }) => {
    for (const { params, path } of ENTITY_SWITCH_CASES) {
      // Load the filtered events page.
      await navigateToPath(page, path);

      // Switch to groups from the phone switch and verify the values sent.
      const groupsSwitch = getEntitySwitch(page).getByRole("button", { name: "Groups" });
      await waitForActionResponse(page, () => groupsSwitch.click(), {
        method: "GET",
        params,
        pathname: "/explore/groups-section",
        status: 200,
      });
      await expect(page.locator("#groups-form-mobile")).toBeAttached();
    }
  });

  test("omits free badges from explore and calendar event cards", async ({ page }) => {
    // Load community event results before checking free badge visibility.
    await navigateToPath(page, `/explore?entity=events&community[0]=${TEST_COMMUNITY_NAME}`);

    // Free list cards do not render an empty-value price badge.
    const freeEventName = TEST_EVENT_NAMES.alpha[0];
    const exploreCard = page.getByRole("link").filter({ hasText: freeEventName }).first();
    await expect(exploreCard).toBeVisible();
    await expect(exploreCard.getByText("Free", { exact: true })).toHaveCount(0);
    await expect(exploreCard.locator("[data-localized-currency]")).toHaveCount(0);

    // Find the event's seeded month so the same assertion reaches its calendar popover.
    const startsAt = await page.evaluate(
      async ({ communityName, eventName }) => {
        const params = new URLSearchParams();
        params.append("community[0]", communityName);
        params.set("view_mode", "calendar");
        params.set("date_from", "1900-01-01");
        params.set("date_to", "2100-12-31");
        const response = await fetch(`/explore/events/search?${params.toString()}`, {
          headers: { Accept: "application/json" },
        });
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

    // Verify the calendar popover loads the calendar card and omits free price badges.
    const calendarEvent = page.locator(".fc-daygrid-event").filter({ hasText: freeEventName }).first();
    await expect(calendarEvent).toBeVisible();
    await waitForActionResponse(page, () => calendarEvent.hover(), {
      method: "GET",
      params: { view_mode: "calendar" },
      pathname: EVENT_CARD_PATHNAME,
      status: 200,
    });
    const calendarPopover = page.locator('[data-popover="true"]').filter({ hasText: freeEventName });
    await expect(calendarPopover).toBeVisible();
    await expect(calendarPopover.getByText("Free", { exact: true })).toHaveCount(0);
    await expect(calendarPopover.locator("[data-localized-currency]")).toHaveCount(0);
  });

  test("shows every co-host name when the card has room", async ({ page }) => {
    // Load the seeded co-hosted event card in a desktop viewport.
    await page.setViewportSize({ width: 1280, height: 720 });
    await navigateToPath(page, `/explore?entity=events&community[0]=${TEST_COMMUNITY_NAME_2}`);
    const eventCard = page.getByRole("link").filter({ hasText: TEST_COHOSTED_EVENT.name }).first();
    await expect(eventCard).toBeVisible();

    // Verify the full credit stays visible without a hover panel.
    const cohostsLine = eventCard.locator("[data-cohosts-line]:visible");
    const cohostsCredit = `Co-hosted with ${COHOSTED_EVENT_COHOST_NAMES.join(", ")}`;
    await expect(cohostsLine).toHaveAttribute("data-cohosts-fit", "full");
    await expect(cohostsLine).toHaveAttribute("title", cohostsCredit);
    await expect(cohostsLine.getByText(cohostsCredit, { exact: true })).toBeVisible();
    await expect(cohostsLine.locator("[data-cohosts-summary]")).toBeHidden();
    await cohostsLine.hover();
    await expect(page.locator("[data-cohosts-panel]")).toHaveCount(0);
  });

  test("summarizes overflowing co-hosts and reveals them on hover or keyboard focus", async ({ page }) => {
    // Load the seeded co-hosted event card in a narrow viewport.
    await page.setViewportSize({ width: 390, height: 844 });
    await navigateToPath(page, `/explore?entity=events&community[0]=${TEST_COMMUNITY_NAME_2}`);
    const eventCard = page.getByRole("link").filter({ hasText: TEST_COHOSTED_EVENT.name }).first();
    await expect(eventCard).toBeVisible();

    // Verify the overflowing names collapse into a count while staying accessible.
    const cohostsLine = eventCard.locator("[data-cohosts-line]:visible");
    await expect(cohostsLine).toHaveAttribute("data-cohosts-fit", "summary");
    await expect(cohostsLine).not.toHaveAttribute("title");
    const summary = cohostsLine.locator("[data-cohosts-summary]");
    await expect(summary).toBeVisible();
    await expect(summary).toHaveText("Co-hosted with 3 groups");
    await expect(cohostsLine.locator("[data-cohosts-full]")).toHaveText(
      `Co-hosted with ${COHOSTED_EVENT_COHOST_NAMES.join(", ")}`,
    );

    // Hover the summary to open the co-hosts panel, then dismiss it with Escape.
    const cohostsPanel = page.locator("[data-cohosts-panel]");
    await summary.hover();
    await expect(cohostsPanel).toBeVisible();
    await expect(cohostsPanel.getByText("Co-hosted with", { exact: true })).toBeVisible();
    for (const name of COHOSTED_EVENT_COHOST_NAMES) {
      await expect(cohostsPanel.getByText(name, { exact: true })).toBeVisible();
    }
    await page.keyboard.press("Escape");
    await expect(cohostsPanel).toHaveCount(0);

    // Open the panel from keyboard focus and close it when focus leaves the card.
    await page.mouse.move(0, 0);
    await eventCard.focus();
    await page.keyboard.press("Shift+Tab");
    await page.keyboard.press("Tab");
    await expect(eventCard).toBeFocused();
    await expect(cohostsPanel).toBeVisible();
    await page.keyboard.press("Tab");
    await expect(cohostsPanel).toHaveCount(0);
  });

  test("moves between event result pages and restores the first card", async ({ page }) => {
    // Paginate seeded event cards with one result per page.
    await expectPaginationNavigation(
      page,
      `/explore?entity=events&community[0]=${TEST_COMMUNITY_NAME}&limit=1&offset=0`,
      "#cards-list article",
    );
  });

  test("restores every event filter and sort option from the URL", async ({ page }) => {
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
    await expect(desktopForm.locator('collapsible-filter[name="community"]')).toHaveAttribute(
      "selected",
      JSON.stringify([TEST_COMMUNITY_NAME]),
    );
    await expect(desktopForm.locator('multi-select-filter[name="group"]')).toHaveAttribute(
      "selected",
      JSON.stringify([TEST_GROUP_SLUG]),
    );
    await expect(desktopForm.locator('collapsible-filter[name="group_category"]')).toHaveAttribute(
      "selected",
      JSON.stringify(["e2e-category-one"]),
    );
    await expect(desktopForm.locator('collapsible-filter[name="region"]')).toHaveAttribute(
      "selected",
      JSON.stringify(["north-america"]),
    );
    await expect(desktopForm.locator('collapsible-filter[name="event_category"]')).toHaveAttribute(
      "selected",
      JSON.stringify(["general"]),
    );
    await expect(desktopForm.locator('input[name="kind[]"][value="hybrid"]')).toBeChecked();
    await expect(desktopForm.locator('input[name="date_from"]')).toHaveValue("2026-01-01");
    await expect(desktopForm.locator('input[name="date_to"]')).toHaveValue("2027-12-31");
    await expect(page.locator("#sort_selector")).toHaveValue("date-desc");
    await expect(page.locator("#sort_by")).toHaveValue("date");
    await expect(page.locator("#sort_direction")).toHaveValue("desc");
  });

  test("sorts events in both date directions", async ({ page }) => {
    // Create owned events with distinct dates so the sort order is exact.
    const sortToken = uniqueName("event sort");
    const sortEvents = [
      {
        endsAt: futureDate({ days: 181, hour: 12 }),
        id: randomUUID(),
        name: `${sortToken} Earlier`,
        slug: slugify(`${sortToken} earlier`),
        startsAt: futureDate({ days: 181, hour: 10 }),
      },
      {
        endsAt: futureDate({ days: 182, hour: 12 }),
        id: randomUUID(),
        name: `${sortToken} Later`,
        slug: slugify(`${sortToken} later`),
        startsAt: futureDate({ days: 182, hour: 10 }),
      },
    ];

    try {
      // Insert owned events for deterministic sorting.
      for (const sortEvent of sortEvents) {
        insertSortEvent(sortEvent);
      }

      // Load only the owned events using their unique search token.
      const params = new URLSearchParams({
        entity: "events",
        "community[0]": TEST_COMMUNITY_NAME,
        sort_by: "date",
        sort_direction: "asc",
        ts_query: sortToken,
      });
      await navigateToPath(page, `/explore?${params.toString()}`);

      // Verify ascending order by exact identity.
      const eventCards = page.locator("#cards-list article");
      await expect(eventCards).toHaveCount(sortEvents.length);
      await expect(eventCards.locator(".card-title")).toHaveText(sortEvents.map((event) => event.name));

      // Switch to descending dates and wait for the event list to refresh.
      await waitForActionResponse(page, () => page.locator("#sort_selector").selectOption("date-desc"), {
        method: "GET",
        params: { sort_direction: "desc" },
        pathname: "/explore/events-section",
        status: 200,
      });

      // Verify descending order by exact identity.
      await expect(page.locator("#sort_selector")).toHaveValue("date-desc");
      await expect(page.locator("#sort_direction")).toHaveValue("desc");
      await expect(eventCards).toHaveCount(sortEvents.length);
      await expect(eventCards.locator(".card-title")).toHaveText(
        [...sortEvents].reverse().map((event) => event.name),
      );
    } finally {
      // Remove owned sorting fixtures.
      cleanupEventsByIds(sortEvents.map((event) => event.id));
    }
  });

  test("opens, resets, and closes the mobile filters drawer @mobile", async ({ page }) => {
    // Load community events using the mobile project viewport.
    await navigateToPath(page, `/explore?entity=events&community[0]=${TEST_COMMUNITY_NAME}`);

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
    await expect(mobileForm.locator('collapsible-filter[name="community"]')).toHaveAttribute(
      "selected",
      JSON.stringify([TEST_COMMUNITY_NAME]),
    );

    // Reset the mobile form and capture the unfiltered results request.
    const resetResponse = await waitForActionResponse(
      page,
      () => drawer.getByRole("button", { name: "Reset", exact: true }).last().click(),
      { method: "GET", pathname: "/explore/events-section", status: 200 },
    );
    const resetRequestUrl = resetResponse.url();

    // Verify reset clears the filter contract and closes the replaced drawer.
    expect(new URL(resetRequestUrl).searchParams.getAll("community[]")).toEqual([]);
    await expect(page.locator('#events-form-mobile collapsible-filter[name="community"]')).toHaveAttribute(
      "selected",
      "[]",
    );
    await expect(page.locator("#sort_by")).toHaveValue("date");
    await expect(page.locator("#sort_direction")).toHaveValue("asc");
    await expect(drawer).toHaveClass(/-translate-x-full/);
    await expect(backdrop).toHaveClass(/hidden/);
  });

  test("pushes the kind filter to the URL and restores the results on back navigation @smoke", async ({
    page,
  }) => {
    // Load the events explore page with the community filter applied.
    await navigateToPath(page, `/explore?entity=events&community[0]=${TEST_COMMUNITY_NAME}`);
    const initialUrl = page.url();

    // Verify every seeded alpha event kind renders before filtering.
    const desktopForm = page.locator("#events-form");
    const inPersonInput = desktopForm.locator('input[name="kind[]"][value="in-person"]');
    const [inPersonEvent, virtualEvent, hybridEvent] = TEST_EVENT_NAMES.alpha.map((name) =>
      page.getByText(name, { exact: true }),
    );
    await expect(inPersonEvent).toBeVisible();
    await expect(virtualEvent).toBeVisible();
    await expect(hybridEvent).toBeVisible();
    await expect(inPersonInput).not.toBeChecked();

    // Select in-person through its visible label and wait for the pushed URL.
    await desktopForm.getByText("In-person", { exact: true }).click();
    await expect(page).toHaveURL((url) => url.searchParams.get("kind[0]") === "in-person");

    // Verify only the in-person event remains and the filter stays selected.
    await expect(inPersonEvent).toBeVisible();
    await expect(virtualEvent).toHaveCount(0);
    await expect(hybridEvent).toHaveCount(0);
    await expect(inPersonInput).toBeChecked();

    // Go back and verify the URL, results and checkbox return to the unfiltered state.
    await page.goBack();
    await expect(page).toHaveURL(initialUrl);
    await expect(inPersonEvent).toBeVisible();
    await expect(virtualEvent).toBeVisible();
    await expect(hybridEvent).toBeVisible();
    await expect(inPersonInput).not.toBeChecked();
  });

  test("switches event results to the calendar view @smoke", async ({ page }) => {
    // Load the events explore page with the community filter applied.
    await navigateToPath(page, `/explore?entity=events&community[0]=${TEST_COMMUNITY_NAME}`);
    await expect(page.getByText(TEST_EVENT_NAMES.alpha[0], { exact: true })).toBeVisible();

    // Switch to the calendar view and wait for the results to refresh.
    await waitForActionResponse(page, () => page.locator('label[for="calendar"]').click(), {
      method: "GET",
      params: { view_mode: "calendar" },
      pathname: "/explore/events-section",
      status: 200,
    });

    // Verify calendar controls appear after switching views.
    await expect(page.locator("#calendar-box")).toBeVisible();
    await expect(page.locator("#calendar-date")).toBeVisible();
    await expect(page.locator("#current-month-btn")).toBeVisible();
    await expect(page.locator("#sort_selector")).toHaveCount(0);
  });

  test("shows a filtered empty state when no events match the search", async ({ page }) => {
    // Load the events explore page for an empty search result.
    await navigateToPath(page, `/explore?entity=events&community[0]=${TEST_COMMUNITY_NAME}`);

    // Submit a search query that has no matching events.
    const searchInput = page.getByPlaceholder("Search events");
    await expect(searchInput).toBeVisible();

    // Submit the unmatched search query and wait for filtered results.
    await waitForActionResponse(
      page,
      () => searchInput.fill("No matching event").then(() => searchInput.press("Enter")),
      {
        method: "GET",
        params: { ts_query: "No matching event" },
        pathname: "/explore/events-section",
        status: 200,
      },
    );

    // Find the filtered empty state.
    const filteredEmptyState = page.locator(".no-results-filtered:not(.hidden)");

    // Verify the filtered empty state explains the missing matches.
    await expect(filteredEmptyState).toBeVisible();
    await expect(filteredEmptyState.getByText("No events found", { exact: true })).toBeVisible();
    await expect(
      filteredEmptyState.getByText(
        "We can't seem to find any events that match your search criteria. You can reset your filters or try a different search.",
      ),
    ).toBeVisible();

    // Switch to calendar view and wait for the empty state to refresh.
    await waitForActionResponse(page, () => page.locator('label[for="calendar"]').click(), {
      method: "GET",
      params: { view_mode: "calendar" },
      pathname: "/explore/events-section",
      status: 200,
    });

    // Verify calendar mode keeps the filtered empty state visible.
    await expect(page.locator("#calendar-box")).toBeVisible();
    await expect(page.locator(".no-results-filtered:not(.hidden)")).toBeVisible();
    await expect(page.locator(".no-results-default:not(.hidden)")).toHaveCount(0);
  });

  test("hides the empty state after navigating from an empty month to one with events", async ({ page }) => {
    // Load the calendar one month before the seeded current-month event.
    const currentMonth = getSeedMonthStart();
    const emptyMonth = addMonths(currentMonth, -1);
    await navigateToPath(page, buildCalendarPath(TEST_CALENDAR_EVENTS.thisMonth, emptyMonth));

    // Verify the calendar starts on an empty month for the pinned event query.
    const calendarEvents = page.locator(".fc-daygrid-event");
    const filteredEmptyState = page.locator(".no-results-filtered:not(.hidden)");
    await expect(page.locator("#calendar-box")).toBeVisible();
    await expect(filteredEmptyState).toBeVisible();
    await expect(page.locator(".no-results-default:not(.hidden)")).toHaveCount(0);
    await expect(calendarEvents).toHaveCount(0);

    // Navigate into the seeded current month through the named month button.
    const populatedRange = getMonthRange(currentMonth);
    const response = await waitForActionResponse(
      page,
      () => page.getByRole("button", { name: "Next month" }).click(),
      { method: "GET", pathname: "/explore/events/search", status: 200 },
    );
    expectWidgetMonthRequest(response, populatedRange);

    // Verify empty fallback content clears after the pinned event appears.
    await expect(page.locator(".no-results-filtered:not(.hidden)")).toHaveCount(0);
    await expect(page.locator(".no-results-default:not(.hidden)")).toHaveCount(0);
    await expect(
      calendarEvents.filter({ hasText: TEST_CALENDAR_EVENTS.thisMonth.name }).first(),
    ).toBeVisible();
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

  test("shows the empty state after navigating from a populated month to an empty one", async ({ page }) => {
    // Load the calendar on the seeded next-month event.
    const nextMonth = addMonths(getSeedMonthStart(), 1);
    const emptyMonth = addMonths(nextMonth, 1);
    await navigateToPath(page, buildCalendarPath(TEST_CALENDAR_EVENTS.nextMonth, nextMonth));

    // Verify the calendar starts on the pinned populated month.
    const calendarEvents = page.locator(".fc-daygrid-event");
    await expect(page.locator("#calendar-box")).toBeVisible();
    await expect(
      calendarEvents.filter({ hasText: TEST_CALENDAR_EVENTS.nextMonth.name }).first(),
    ).toBeVisible();
    await expect(page.locator(".no-results-filtered:not(.hidden)")).toHaveCount(0);
    await expect(page.locator(".no-results-default:not(.hidden)")).toHaveCount(0);

    // Navigate to the adjacent empty month for the same pinned event query.
    const emptyRange = getMonthRange(emptyMonth);
    const response = await waitForActionResponse(
      page,
      () => page.getByRole("button", { name: "Next month" }).click(),
      { method: "GET", pathname: "/explore/events/search", status: 200 },
    );
    expectWidgetMonthRequest(response, emptyRange);

    // Verify the filtered empty state appears for the empty month because the pinned event query remains active.
    const filteredEmptyState = page.locator(".no-results-filtered:not(.hidden)");
    await expect(filteredEmptyState).toBeVisible();
    await expect(page.locator(".no-results-default:not(.hidden)")).toHaveCount(0);
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

  test("opens a calendar event card on keyboard focus and closes it with Escape", async ({ page }) => {
    // Load the calendar on the seeded current-month event.
    await navigateToPath(page, buildCalendarPath(TEST_CALENDAR_EVENTS.thisMonth, getSeedMonthStart()));
    const calendarEvent = page
      .locator(".fc-daygrid-event")
      .filter({ hasText: TEST_CALENDAR_EVENTS.thisMonth.name })
      .first();
    await expect(calendarEvent).toBeVisible();

    // Focus the event link and wait for its card to load.
    await waitForActionResponse(page, () => calendarEvent.focus(), {
      method: "GET",
      params: { view_mode: "calendar" },
      pathname: `/explore/events/${TEST_CALENDAR_EVENTS.thisMonth.id}/card`,
      status: 200,
    });

    // Verify the focused event is described by its card tooltip.
    const tooltip = page.getByRole("tooltip").filter({ hasText: TEST_CALENDAR_EVENTS.thisMonth.name });
    await expect(tooltip).toBeVisible();
    await expect(tooltip).toHaveAttribute("aria-busy", "false");
    const tooltipId = await tooltip.getAttribute("id");
    await expect(calendarEvent).toHaveAttribute("aria-describedby", tooltipId);

    // Close the card with Escape while focus stays on the event.
    await page.keyboard.press("Escape");
    await expect(tooltip).toHaveCount(0);
    await expect(calendarEvent).not.toHaveAttribute("aria-describedby");
    await expect(calendarEvent).toBeFocused();
  });

  test("opens a calendar event in a new tab on a modified click", async ({ page }) => {
    // Load the calendar on the seeded current-month event.
    await navigateToPath(page, buildCalendarPath(TEST_CALENDAR_EVENTS.thisMonth, getSeedMonthStart()));
    const calendarEvent = page
      .locator(".fc-daygrid-event")
      .filter({ hasText: TEST_CALENDAR_EVENTS.thisMonth.name })
      .first();
    await expect(calendarEvent).toBeVisible();
    await expect(calendarEvent).toHaveAttribute(
      "href",
      new RegExp(`/event/${TEST_CALENDAR_EVENTS.thisMonth.slug}$`),
    );
    const calendarUrl = page.url();

    // Open the event with the platform modifier and verify a new tab loads it.
    const [eventPage] = await Promise.all([
      page.context().waitForEvent("page"),
      calendarEvent.click({ modifiers: ["ControlOrMeta"] }),
    ]);
    await eventPage.waitForURL(new RegExp(`/event/${TEST_CALENDAR_EVENTS.thisMonth.slug}$`));
    expect(page.url()).toBe(calendarUrl);
    await eventPage.close();
  });

  test("opens a calendar event card link in a new tab on a modified click", async ({ page }) => {
    // Load the calendar on the seeded current-month event and open its card.
    await navigateToPath(page, buildCalendarPath(TEST_CALENDAR_EVENTS.thisMonth, getSeedMonthStart()));
    const calendarEvent = page
      .locator(".fc-daygrid-event")
      .filter({ hasText: TEST_CALENDAR_EVENTS.thisMonth.name })
      .first();
    await expect(calendarEvent).toBeVisible();
    await waitForActionResponse(page, () => calendarEvent.hover(), {
      method: "GET",
      params: { view_mode: "calendar" },
      pathname: EVENT_CARD_PATHNAME,
      status: 200,
    });
    const tooltip = page.getByRole("tooltip").filter({ hasText: TEST_CALENDAR_EVENTS.thisMonth.name });
    await expect(tooltip).toBeVisible();
    const calendarUrl = page.url();

    // Click the card with the platform modifier and verify a new tab loads the event.
    const [eventPage] = await Promise.all([
      page.context().waitForEvent("page"),
      tooltip.click({ modifiers: ["ControlOrMeta"] }),
    ]);
    await eventPage.waitForURL(new RegExp(`/event/${TEST_CALENDAR_EVENTS.thisMonth.slug}$`));
    expect(page.url()).toBe(calendarUrl);
    await eventPage.close();
  });

  test("keeps calendar cards independent across event segments and the more-events popover", async ({
    page,
  }) => {
    // Serve next month's events and their cards from routed responses.
    const nextMonth = addMonths(getSeedMonthStart(), 1);
    const crowdedEvents = Array.from({ length: 6 }, (_, index) =>
      buildMinimalEvent(
        `Crowded day event ${index + 1}`,
        getMonthDayAt(nextMonth, 3, 9 + index),
        getMonthDayAt(nextMonth, 3, 10 + index),
      ),
    );
    const multiWeekEvent = buildMinimalEvent(
      "Multi-week event",
      getMonthDayAt(nextMonth, 13, 9),
      getMonthDayAt(nextMonth, 24, 17),
    );
    const routedEvents = [...crowdedEvents, multiWeekEvent];
    await page.route(/\/explore\/events\/search\?/, (route) =>
      route.fulfill({ json: { events: routedEvents, total: routedEvents.length, truncated: false } }),
    );
    const cardRequests = [];
    await page.route(/\/explore\/events\/[0-9a-f-]+\/card\?/, (route) => {
      const eventId = new URL(route.request().url()).pathname.split("/")[3];
      const event = routedEvents.find((item) => item.event_id === eventId);
      cardRequests.push(eventId);
      return route.fulfill({ body: `<article>${event.name} card</article>`, contentType: "text/html" });
    });

    // Load the calendar and move to the routed month.
    await navigateToPath(page, buildCalendarPath(TEST_CALENDAR_EVENTS.thisMonth, getSeedMonthStart()));
    await waitForActionResponse(page, () => page.getByRole("button", { name: "Next month" }).click(), {
      method: "GET",
      pathname: "/explore/events/search",
      status: 200,
    });

    // Hover two segments of the multi-week event.
    const segments = page.locator(".fc-daygrid-event").filter({ hasText: multiWeekEvent.name });
    await expect(segments.first()).toBeVisible();
    expect(await segments.count()).toBeGreaterThanOrEqual(2);
    const firstTooltipId = await openCalendarCard(segments.nth(0), `${multiWeekEvent.name} card`);
    const secondTooltipId = await openCalendarCard(segments.nth(1), `${multiWeekEvent.name} card`);

    // Each segment has its own tooltip, sharing one card request.
    expect(secondTooltipId).not.toBe(firstTooltipId);
    await expect(page.locator(`[id="${firstTooltipId}"]`)).toHaveCount(0);
    await expect(segments.nth(0)).not.toHaveAttribute("aria-describedby");
    expect(cardRequests.filter((id) => id === multiWeekEvent.event_id)).toHaveLength(1);

    // Hover a crowded-day event in the grid, then open the more-events popover.
    await page.mouse.move(0, 0);
    const [crowdedEvent] = crowdedEvents;
    const gridEvent = page
      .locator(".fc-daygrid-day-events .fc-daygrid-event")
      .filter({ hasText: crowdedEvent.name })
      .first();
    const gridTooltipId = await openCalendarCard(gridEvent, `${crowdedEvent.name} card`);
    await page.mouse.move(0, 0);
    await expect(page.locator(`[id="${gridTooltipId}"]`)).toHaveCount(0);
    await page.locator(".fc-daygrid-more-link").first().click();
    const popover = page.locator(".fc-popover");
    await expect(popover).toBeVisible();

    // The popover mount of the same event gets its own tooltip from the cached card.
    const popoverEvent = popover.locator(".fc-daygrid-event").filter({ hasText: crowdedEvent.name });
    const popoverTooltipId = await openCalendarCard(popoverEvent, `${crowdedEvent.name} card`);
    expect(popoverTooltipId).not.toBe(gridTooltipId);
    expect(cardRequests.filter((id) => id === crowdedEvent.event_id)).toHaveLength(1);

    // Closing the popover releases the cards mounted inside it.
    await popover.locator(".fc-popover-close").click();
    await expect(popover).toHaveCount(0);
    await expect(page.locator(`[id="${popoverTooltipId}"]`)).toHaveCount(0);
    await expect(page.getByRole("tooltip")).toHaveCount(0);
  });

  test("keeps one calendar card open and closes hovered cards with Escape", async ({ page }) => {
    // Serve two next-month events and their cards from routed responses.
    const nextMonth = addMonths(getSeedMonthStart(), 1);
    const focusedEvent = buildMinimalEvent(
      "Focused card event",
      getMonthDayAt(nextMonth, 8, 9),
      getMonthDayAt(nextMonth, 8, 10),
    );
    const hoveredEvent = buildMinimalEvent(
      "Hovered card event",
      getMonthDayAt(nextMonth, 17, 9),
      getMonthDayAt(nextMonth, 17, 10),
    );
    const routedEvents = [focusedEvent, hoveredEvent];
    await page.route(/\/explore\/events\/search\?/, (route) =>
      route.fulfill({ json: { events: routedEvents, total: routedEvents.length, truncated: false } }),
    );
    await page.route(/\/explore\/events\/[0-9a-f-]+\/card\?/, (route) => {
      const eventId = new URL(route.request().url()).pathname.split("/")[3];
      const event = routedEvents.find((item) => item.event_id === eventId);
      return route.fulfill({ body: `<article>${event.name} card</article>`, contentType: "text/html" });
    });

    // Load the calendar and move to the routed month.
    await navigateToPath(page, buildCalendarPath(TEST_CALENDAR_EVENTS.thisMonth, getSeedMonthStart()));
    await waitForActionResponse(page, () => page.getByRole("button", { name: "Next month" }).click(), {
      method: "GET",
      pathname: "/explore/events/search",
      status: 200,
    });

    // Open the card of a focused event.
    const focusedLink = page.locator(".fc-daygrid-event").filter({ hasText: focusedEvent.name });
    await focusedLink.focus();
    await expect(page.getByRole("tooltip")).toContainText(`${focusedEvent.name} card`);

    // Hovering another event replaces the focused event card.
    const hoveredLink = page.locator(".fc-daygrid-event").filter({ hasText: hoveredEvent.name });
    await openCalendarCard(hoveredLink, `${hoveredEvent.name} card`);
    await expect(page.getByRole("tooltip")).toHaveCount(1);
    await expect(focusedLink).not.toHaveAttribute("aria-describedby");
    await expect(focusedLink).toBeFocused();

    // Escape closes the hovered card while focus stays on the other event.
    await page.keyboard.press("Escape");
    await expect(page.getByRole("tooltip")).toHaveCount(0);
    await expect(hoveredLink).not.toHaveAttribute("aria-describedby");
    await expect(focusedLink).toBeFocused();
  });

  test("scrolls long more-events lists and closes them when another day card opens", async ({ page }) => {
    // Serve a crowded next-month day, an event on an earlier day, and their cards.
    const nextMonth = addMonths(getSeedMonthStart(), 1);
    const crowdedEvents = Array.from({ length: 30 }, (_, index) =>
      buildMinimalEvent(
        `Long day event ${String(index + 1).padStart(2, "0")}`,
        getMonthDayAt(nextMonth, 10, 9),
        getMonthDayAt(nextMonth, 10, 10),
      ),
    );
    const otherDayEvent = buildMinimalEvent(
      "Other day event",
      getMonthDayAt(nextMonth, 1, 9),
      getMonthDayAt(nextMonth, 1, 10),
    );
    const routedEvents = [...crowdedEvents, otherDayEvent];
    await page.route(/\/explore\/events\/search\?/, (route) =>
      route.fulfill({ json: { events: routedEvents, total: routedEvents.length, truncated: false } }),
    );
    await page.route(/\/explore\/events\/[0-9a-f-]+\/card\?/, (route) => {
      const eventId = new URL(route.request().url()).pathname.split("/")[3];
      const event = routedEvents.find((item) => item.event_id === eventId);
      return route.fulfill({ body: `<article>${event.name} card</article>`, contentType: "text/html" });
    });

    // Load the calendar, move to the routed month, and open the crowded day list.
    await navigateToPath(page, buildCalendarPath(TEST_CALENDAR_EVENTS.thisMonth, getSeedMonthStart()));
    await waitForActionResponse(page, () => page.getByRole("button", { name: "Next month" }).click(), {
      method: "GET",
      pathname: "/explore/events/search",
      status: 200,
    });
    const moreLink = page.locator(".fc-daygrid-more-link").first();
    await moreLink.click();
    const popover = page.locator(".fc-more-popover");
    await expect(popover).toBeVisible();

    // The list scrolls instead of growing with every event.
    const popoverBody = popover.locator(".fc-popover-body");
    expect(await popoverBody.evaluate((body) => body.scrollHeight > body.clientHeight)).toBe(true);

    // A popover event card is positioned against the viewport so the list does not clip it.
    const popoverEvent = popover.locator(".fc-daygrid-event").filter({ hasText: crowdedEvents[0].name });
    await popoverEvent.focus();
    const popoverTooltip = page.getByRole("tooltip");
    await expect(popoverTooltip).toContainText(`${crowdedEvents[0].name} card`);
    await expect(popoverTooltip).toHaveClass(/(^|\s)fixed(\s|$)/);
    await expect(popoverTooltip).toBeInViewport({ ratio: 1 });

    // Scrolling the list closes the card left behind by its event.
    await popoverBody.evaluate((body) => {
      body.scrollTop = 100;
    });
    await expect(page.getByRole("tooltip")).toHaveCount(0);
    await expect(popoverEvent).not.toHaveAttribute("aria-describedby");
    await expect(popover).toBeVisible();

    // Opening another day card closes the list and returns focus to its "+N more" link.
    const otherDayLink = page.locator(".fc-daygrid-event").filter({ hasText: otherDayEvent.name });
    await openCalendarCard(otherDayLink, `${otherDayEvent.name} card`);
    await expect(popover).toHaveCount(0);
    await expect(moreLink).toBeFocused();
  });

  test("shows how many events the calendar draws when the month is capped", async ({ page }) => {
    // Load the calendar and verify the notice starts hidden for uncapped results.
    await navigateToPath(page, buildCalendarPath(TEST_CALENDAR_EVENTS.thisMonth, getSeedMonthStart()));
    const notice = page.locator("[data-explore-truncation-notice]");
    await expect(notice).toBeHidden();

    // Answer the next month with capped results.
    const nextMonth = addMonths(getSeedMonthStart(), 1);
    const routedEvents = [
      buildMinimalEvent(
        "Capped month event",
        getMonthDayAt(nextMonth, 10, 9),
        getMonthDayAt(nextMonth, 10, 10),
      ),
    ];
    await page.route(/\/explore\/events\/search\?/, (route) =>
      route.fulfill({ json: { events: routedEvents, total: 1865, truncated: true } }),
    );
    await waitForActionResponse(page, () => page.getByRole("button", { name: "Next month" }).click(), {
      method: "GET",
      pathname: "/explore/events/search",
      status: 200,
    });

    // Verify the notice reports the drawn and matching counts inside its status region.
    await expect(notice).toBeVisible();
    await expect(notice).toContainText("Showing 1 of 1865 events.");
    await expect(notice).toContainText("Refine your filters to see them all.");
    await expect(page.getByRole("status").filter({ has: notice })).toHaveCount(1);
  });

  test("pins the results bar under the header while the controls scroll away @mobile", async ({ page }) => {
    // Load the bare landing, long enough to scroll.
    await navigateToPath(page, "/explore?entity=events");
    await expect(getEntitySwitch(page).getByRole("button", { name: "Events" })).toHaveAttribute(
      "aria-pressed",
      "true",
    );

    // Scroll past the controls.
    const header = page.locator("#header");
    const resultsBar = page.locator(".section-strip-results");
    await page.evaluate(() => window.scrollTo({ top: 500, behavior: "instant" }));

    // Verify the bar pins right under the header, and the controls left the screen.
    const headerBox = await header.boundingBox();
    await expect
      .poll(async () => (await resultsBar.boundingBox()).y)
      .toBeCloseTo(headerBox.y + headerBox.height - 1, 0);
    await expect(page.getByPlaceholder("Search events")).not.toBeInViewport();
  });

  test("hides the calendar and map switch and the desktop title @mobile", async ({ page }) => {
    // Load the bare landing.
    await navigateToPath(page, "/explore?entity=events");

    // Verify one page title and the list as the only view.
    await expect(page.getByRole("heading", { level: 1 })).toHaveText("Explore");
    await expect(page.locator('label[for="calendar"]')).toBeHidden();
    await expect(page.locator("#cards-list article").first()).toBeVisible();
  });

  test("shows no chip row on the bare landing @mobile", async ({ page }) => {
    // Load Explore with no filters.
    await navigateToPath(page, "/explore?entity=events");

    // Verify nothing reads as applied.
    await expect(page.getByRole("group", { name: "Applied filters" })).toHaveCount(0);
    await expect(page.getByRole("button", { name: "Open filters", exact: true })).toBeVisible();
  });

  test("puts the title above a full-width switch @mobile", async ({ page }) => {
    // Load the bare landing.
    await navigateToPath(page, "/explore?entity=events");
    const title = await page.getByRole("heading", { level: 1 }).boundingBox();
    const entitySwitch = await getEntitySwitch(page).boundingBox();
    const filters = await page.getByRole("button", { name: "Open filters", exact: true }).boundingBox();
    const filtersRight = filters.x + filters.width;
    const inset = page.viewportSize().width - filtersRight;

    // Verify the switch starts below the title and spans the controls row.
    expect(entitySwitch.y).toBeGreaterThanOrEqual(title.y + title.height);
    expect(entitySwitch.x + entitySwitch.width).toBeCloseTo(filtersRight, 0);
    expect(entitySwitch.width).toBeGreaterThan(page.viewportSize().width - 2 * inset - 1);
  });

  test("fits the active filters on one line and shows the rest from the toggle @mobile", async ({ page }) => {
    // Load more filters than one line holds.
    await navigateToPath(
      page,
      `/explore?entity=events&community[0]=${TEST_COMMUNITY_NAME}&group[0]=${TEST_GROUP_SLUG}&kind[0]=in-person&kind[1]=virtual&kind[2]=hybrid`,
    );
    const chips = getAppliedFilterChips(page);
    const toggle = page.locator("[data-applied-filters-toggle]");

    // Verify the shown chips share one line, and the toggle counts the rest.
    await expect(toggle).toBeVisible();
    await expect(toggle).toHaveAttribute("aria-expanded", "false");
    const shown = await chips.count();
    expect(shown).toBeLessThan(5);
    await expect(toggle).toHaveText(`+${5 - shown} more`);
    const tops = await chips.evaluateAll((items) => items.map((item) => item.getBoundingClientRect().top));
    const toggleBox = await toggle.boundingBox();
    expect(new Set([...tops, toggleBox.y]).size).toBe(1);
    const lastChip = await chips.last().boundingBox();
    expect(toggleBox.x - (lastChip.x + lastChip.width)).toBeLessThanOrEqual(8);

    // Expand and collapse the card.
    await toggle.click();
    await expect(chips).toHaveCount(5);
    await expect(toggle).toHaveText("Show less");
    await expect(toggle).toHaveAttribute("aria-expanded", "true");
    await toggle.click();
    await expect(chips).toHaveCount(shown);
  });

  test("truncates a chip wider than the card to one line @mobile", async ({ page }) => {
    // Give the first of two chips a label wider than the narrowest phone.
    await page.setViewportSize({ height: 640, width: 320 });
    await navigateToPath(page, `/explore?entity=events&community[0]=${TEST_COMMUNITY_NAME}&kind[0]=virtual`);
    const card = page.locator("[data-applied-filters]");
    const chips = getAppliedFilterChips(page);
    const toggle = page.locator("[data-applied-filters-toggle]");
    await chips
      .first()
      .locator("span span")
      .first()
      .evaluate((label) => {
        label.textContent = "A very long community name that never fits ".repeat(3);
        window.dispatchEvent(new Event("resize"));
      });
    const expectTruncatedInCard = async () => {
      const chip = chips.first();
      const label = chip.locator("span span").first();
      const [cardBox, chipBox, text] = await Promise.all([
        card.boundingBox(),
        chip.boundingBox(),
        label.evaluate((element) => ({
          clipped: element.scrollWidth > element.clientWidth,
          height: element.clientHeight,
        })),
      ]);
      expect(chipBox.x + chipBox.width).toBeLessThanOrEqual(cardBox.x + cardBox.width);
      expect(text.clipped).toBe(true);
      expect(text.height).toBeLessThan(24);
      await expect(label).toHaveCSS("text-overflow", "ellipsis");
      await expect(label).toHaveCSS("white-space", "nowrap");
    };

    // Verify the long chip stays shown, on one line with an ellipsis.
    await expect(toggle).toHaveText("+1 more");
    await expect(chips).toHaveCount(1);
    await expectTruncatedInCard();

    // Verify it still holds one line once the card is expanded.
    await toggle.click();
    await expect(chips).toHaveCount(2);
    await expectTruncatedInCard();
  });

  test("resets every filter from the Active filters card @mobile", async ({ page }) => {
    // Load two filters.
    await navigateToPath(page, "/explore?entity=events&kind[0]=virtual&kind[1]=hybrid");

    // Reset them from the card.
    await waitForActionResponse(
      page,
      () => page.getByRole("button", { name: "Reset", exact: true }).click(),
      {
        method: "GET",
        pathname: "/explore/events-section",
        status: 200,
      },
    );

    // Verify the card is gone, focus is on Filters and the change was announced.
    await expect(page.getByRole("group", { name: "Applied filters" })).toHaveCount(0);
    await expect(page).not.toHaveURL(/kind(\[|%5B)/);
    await expect(page.locator("#open-filters")).toBeFocused();
    await expect(page.locator("#explore-filter-status")).toContainText("Filters reset.");
  });

  test("defers sheet changes and applies them with one request @mobile", async ({ page }) => {
    // Count the section requests of a filter session.
    await navigateToPath(page, "/explore?entity=events");
    const requests = trackSectionRequests(page, "/explore/events-section");
    const historyLength = await page.evaluate(() => history.length);

    // Pick two types inside the sheet.
    const sheet = await openFilterSheet(page);
    await expect(sheet.getByRole("button", { name: "Close filters" })).toBeFocused();
    await sheet.locator("label").filter({ hasText: "Virtual" }).click();
    await sheet.locator("label").filter({ hasText: "Hybrid" }).click();

    // Verify nothing went out and the sheet stayed.
    await expect(sheet).toBeVisible();
    expect(requests).toHaveLength(0);

    // Apply both with one tap.
    await waitForActionResponse(page, () => sheet.getByRole("button", { name: "Show results" }).click(), {
      method: "GET",
      pathname: "/explore/events-section",
      status: 200,
    });

    // Verify one request, one history entry, and a released sheet.
    expect(requests).toHaveLength(1);
    expect(new URL(requests[0]).searchParams.getAll("kind[]")).toEqual(["virtual", "hybrid"]);
    expect(await page.evaluate(() => history.length)).toBe(historyLength + 1);
    await expect(page.getByRole("dialog", { name: "Filters" })).toHaveCount(0);
    await expect(page.locator("#open-filters")).toBeFocused();
    await expect(page.locator("body")).not.toHaveCSS("overflow", "hidden");
    await expect(getAppliedFilterChips(page)).toHaveCount(2);
  });

  test("outlines a Type tile as soon as it is tapped, and clears it on the next tap @mobile", async ({
    page,
  }) => {
    // Open the sheet with one type applied, which the server outlines.
    await navigateToPath(page, "/explore?entity=events&kind[0]=virtual");
    const sheet = await openFilterSheet(page);
    const applied = sheet.locator("label").filter({ hasText: "Virtual" });
    const tile = sheet.locator("label").filter({ hasText: "Hybrid" });
    const borderColor = (label) => label.evaluate((node) => getComputedStyle(node).borderTopColor);
    const [appliedColor, restingColor] = [await borderColor(applied), await borderColor(tile)];
    expect(appliedColor).not.toBe(restingColor);

    // Verify the deferred choice looks like an applied one, and an unticked one like a resting one.
    await tile.click();
    await expect.poll(() => borderColor(tile)).toBe(appliedColor);
    await applied.click();
    await expect.poll(() => borderColor(applied)).toBe(restingColor);
  });

  test("keeps one community selected and highlighted across taps @mobile", async ({ page }) => {
    // Open the sheet on the bare landing.
    await navigateToPath(page, "/explore?entity=events");
    const sheet = await openFilterSheet(page);
    const community = sheet.locator('collapsible-filter[name="community"]');
    const firstOption = getFilterOption(community, TEST_COMMUNITY_NAME);
    const secondOption = getFilterOption(community, TEST_COMMUNITY_NAME_2);

    // Tap two options.
    await firstOption.click();
    await secondOption.click();

    // Verify only the second is checked and highlighted.
    await expect(community.locator("input:checked")).toHaveCount(1);
    await expect(secondOption.locator("input")).toBeChecked();
    await expect(secondOption).toHaveClass(/border-primary-500/);
    await expect(firstOption).not.toHaveClass(/border-primary-500/);
  });

  test("reveals a community's filters in the sheet before applying @mobile", async ({ page }) => {
    // Open the sheet on the bare landing, which has no community filters.
    await navigateToPath(page, "/explore?entity=events");
    const requests = trackSectionRequests(page, "/explore/events-section");
    const sheet = await openFilterSheet(page);
    await expect(sheet.locator('collapsible-filter[name="region"]')).toHaveCount(0);

    // Keep a choice, then pick a community.
    await sheet.locator("label").filter({ hasText: "Virtual" }).click();
    const community = sheet.locator('collapsible-filter[name="community"]');
    await getFilterOption(community, TEST_COMMUNITY_NAME).click();

    // Verify the filters appear at once, with the choice and the focus kept.
    await expect(sheet.locator('collapsible-filter[name="region"]')).toBeAttached();
    await expect(sheet.locator('input[name="kind[]"][value="virtual"]')).toBeChecked();
    await expect(community.locator("input:checked")).toBeFocused();

    // Verify the results, the URL and the history wait for Show results.
    expect(requests).toHaveLength(0);
    expect(new URL(page.url()).searchParams.has("community[]")).toBe(false);

    // Apply and verify the community lands.
    await waitForActionResponse(page, () => sheet.getByRole("button", { name: "Show results" }).click(), {
      method: "GET",
      pathname: "/explore/events-section",
      status: 200,
    });
    expect(requests).toHaveLength(1);
    await expect(page.getByRole("button", { name: `Remove filter ${TEST_COMMUNITY_TITLE}` })).toBeVisible();
  });

  test("leaves a refreshed sheet out of the history entry it applied from @mobile", async ({ page }) => {
    // Apply a community from the sheet, which refreshes its form first.
    await navigateToPath(page, "/explore?entity=events");
    const sheet = await openFilterSheet(page);
    const community = sheet.locator('collapsible-filter[name="community"]');
    await getFilterOption(community, TEST_COMMUNITY_NAME).click();
    await expect(sheet.locator('collapsible-filter[name="region"]')).toBeAttached();
    await waitForActionResponse(page, () => sheet.getByRole("button", { name: "Show results" }).click(), {
      method: "GET",
      pathname: "/explore/events-section",
      status: 200,
    });
    await expect(getAppliedFilterChips(page)).toHaveCount(1);

    // Go back to the bare landing.
    await page.goBack();
    await expect(page).not.toHaveURL(/community/);
    await expect(page.getByRole("group", { name: "Applied filters" })).toHaveCount(0);

    // Verify the sheet matches the page again, in the DOM and once reopened.
    await expect(sheet.locator('collapsible-filter[name="region"]')).toHaveCount(0);
    await openFilterSheet(page);
    await expect(sheet.locator('collapsible-filter[name="community"] input:checked')).toHaveCount(0);
    await expect(sheet.locator('collapsible-filter[name="region"]')).toHaveCount(0);
  });

  test("keeps a refreshed sheet out of the entry Forward leaves @mobile", async ({ page }) => {
    // Build a history entry to go forward to, and return to the bare landing.
    await navigateToPath(page, "/explore?entity=events");
    await waitForActionResponse(
      page,
      () => getEntitySwitch(page).getByRole("button", { name: "Groups" }).click(),
      { method: "GET", pathname: "/explore/groups-section", status: 200 },
    );
    await page.goBack();
    await expect(page.locator("#events-form-mobile")).toBeAttached();

    // Refresh the sheet's form, then leave with the sheet open.
    const sheet = await openFilterSheet(page);
    const community = sheet.locator('collapsible-filter[name="community"]');
    await getFilterOption(community, TEST_COMMUNITY_NAME).click();
    await expect(sheet.locator('collapsible-filter[name="region"]')).toBeAttached();
    await page.goForward();
    await expect(page.locator("#groups-form-mobile")).toBeAttached();

    // Verify the landing comes back with only the filters it applied.
    await page.goBack();
    await expect(page.locator("#events-form-mobile")).toBeAttached();
    await expect(sheet.locator('collapsible-filter[name="region"]')).toHaveCount(0);
  });

  test("removes chips one after the other with no lost tap @mobile", async ({ page }) => {
    // Load two chips of the same filter.
    await navigateToPath(page, "/explore?entity=events&kind[0]=virtual&kind[1]=hybrid");
    const chips = getAppliedFilterChips(page);
    await expect(chips).toHaveCount(2);

    // Tap both without waiting for the first swap.
    await chips.first().click();
    await chips.last().click();

    // Verify both went, and the last request wins.
    await expect(chips).toHaveCount(0);
    await expect(page).not.toHaveURL(/kind(\[|%5B)/);
    await expect(page.locator("#results")).toBeFocused();
    await expect(page.locator("#explore-filter-status")).toContainText("Removed filter");
  });

  test("moves focus to the next chip after a removal @mobile", async ({ page }) => {
    // Load two chips.
    await navigateToPath(page, "/explore?entity=events&kind[0]=virtual&kind[1]=hybrid");
    const chips = getAppliedFilterChips(page);

    // Remove the first.
    await waitForActionResponse(page, () => chips.first().click(), {
      method: "GET",
      pathname: "/explore/events-section",
      status: 200,
    });

    // Verify the remaining chip takes focus.
    await expect(chips).toHaveCount(1);
    await expect(chips.first()).toBeFocused();
  });

  test("moves focus to the pressed side of the switch after each swap @mobile", async ({ page }) => {
    // Load events, then press Groups.
    await navigateToPath(page, "/explore?entity=events");
    const entitySwitch = getEntitySwitch(page);
    await waitForActionResponse(page, () => entitySwitch.getByRole("button", { name: "Groups" }).click(), {
      method: "GET",
      pathname: "/explore/groups-section",
      status: 200,
    });

    // Verify the new pressed button takes focus instead of the body.
    await expect(page.locator("#groups-form-mobile")).toBeAttached();
    const pressedGroups = entitySwitch.getByRole("button", { name: "Groups", pressed: true });
    await expect(pressedGroups).toBeFocused();

    // Verify the way back behaves the same.
    await waitForActionResponse(page, () => entitySwitch.getByRole("button", { name: "Events" }).click(), {
      method: "GET",
      pathname: "/explore/events-section",
      status: 200,
    });
    await expect(page.locator("#events-form-mobile")).toBeAttached();
    await expect(entitySwitch.getByRole("button", { name: "Events", pressed: true })).toBeFocused();

    // Verify the buttons stay free of ids.
    await expect(entitySwitch.locator("button[id]")).toHaveCount(0);
  });

  test("alerts when a switch press fails and leaves focus alone @mobile", async ({ page }) => {
    // Fail the Groups section request.
    await navigateToPath(page, "/explore?entity=events");
    await page.route("**/explore/groups-section*", (route) => route.fulfill({ status: 500 }));
    const groupsResponse = page.waitForResponse((response) =>
      response.url().includes("/explore/groups-section"),
    );
    const entitySwitch = getEntitySwitch(page);
    await entitySwitch.getByRole("button", { name: "Groups" }).click();
    await groupsResponse;

    // Verify the failure is reported, and the page stays on Events.
    await expect(page.locator(".swal2-popup")).toBeVisible();
    await expect(entitySwitch.getByRole("button", { name: "Events", pressed: true })).toBeVisible();
    await page.locator(".swal2-confirm").click();
    await expect(page.locator(".swal2-popup")).toHaveCount(0);

    // Run a search, which swaps the same side of the section, and wait for it to settle.
    const sectionSettled = page.evaluate(
      () =>
        new Promise((resolve) => {
          const handleSettle = (event) => {
            if (event.target.id === "entity-section") {
              document.removeEventListener("htmx:afterSettle", handleSettle);
              resolve();
            }
          };
          document.addEventListener("htmx:afterSettle", handleSettle);
        }),
    );
    const search = page.locator("#ts_query");
    await search.fill("alpha");
    await search.press("Enter");
    await sectionSettled;

    // Verify the failed press did not pull focus to the switch.
    await expect(entitySwitch.getByRole("button", { name: "Events", pressed: true })).not.toBeFocused();
  });

  test("rings an option in the sheet while its hidden checkbox has keyboard focus @mobile", async ({
    page,
  }) => {
    // Open the sheet and reach a Community option from the keyboard.
    await navigateToPath(page, "/explore?entity=events");
    const sheet = await openFilterSheet(page);
    const community = sheet.locator('collapsible-filter[name="community"]');
    const option = community.locator("label").first();
    await page.keyboard.press("Tab");
    await option.locator("input").focus();

    // Verify the label shows the focus its clipped checkbox cannot.
    await expect(option).toHaveCSS("box-shadow", /0px 0px 0px 2px/);
  });

  test("recovers a chip whose removal failed @mobile", async ({ page }) => {
    // Load a checkbox chip and a community chip, then fail the section request.
    await navigateToPath(page, `/explore?entity=events&community[0]=${TEST_COMMUNITY_NAME}&kind[0]=virtual`);
    const chips = getAppliedFilterChips(page);
    await expect(chips).toHaveCount(2);
    const failSection = (route) => route.fulfill({ status: 500, body: "" });
    await page.route("**/explore/events-section?**", failSection);

    // Fail one removal of each, dismissing the alert each time.
    const form = page.locator("#explore-filters .filters-form");
    const virtual = page.getByRole("button", { name: "Remove filter Virtual" });
    const community = page.getByRole("button", { name: `Remove filter ${TEST_COMMUNITY_TITLE}` });
    for (const chip of [virtual, community]) {
      await chip.click();
      await expect(page.locator(".swal2-popup")).toBeVisible();
      await page.locator(".swal2-confirm").click();
      await expect(page.locator(".swal2-popup")).toHaveCount(0);
    }

    // Verify the chips stay, the form matches them, and nothing read as removed.
    await expect(chips).toHaveCount(2);
    await expect(form.locator('input[name="kind[]"][value="virtual"]')).toBeChecked();
    await expect(form.locator(`input[name="community[]"][value="${TEST_COMMUNITY_NAME}"]`)).toBeChecked();
    await expect(page.locator("#explore-filter-status")).toHaveText("");

    // Verify an unrelated request does not carry the removal.
    await page.unroute("**/explore/events-section?**", failSection);
    await waitForActionResponse(page, () => page.locator("#sort_selector").selectOption("date-desc"), {
      method: "GET",
      pathname: "/explore/events-section",
      status: 200,
    });
    await expect(chips).toHaveCount(2);
    await expect(page.locator("#explore-filter-status")).toHaveText("");

    // Verify the chip works once the server is back.
    await waitForActionResponse(page, () => virtual.click(), {
      method: "GET",
      pathname: "/explore/events-section",
      status: 200,
    });
    await expect(chips).toHaveCount(1);
    await expect(page.locator("#explore-filter-status")).toContainText("Removed filter Virtual");
  });

  test("restores a closed sheet when Back leaves an open one @mobile", async ({ page }) => {
    // Build a history entry to go back to.
    await navigateToPath(page, "/explore?entity=events");
    await waitForActionResponse(
      page,
      () => getEntitySwitch(page).getByRole("button", { name: "Groups" }).click(),
      { method: "GET", pathname: "/explore/groups-section", status: 200 },
    );

    // Go back with the sheet open.
    await openFilterSheet(page);
    await page.goBack();

    // Verify the restored page holds no open state.
    await expect(page.locator("#events-form-mobile")).toBeAttached();
    await expect(page.getByRole("dialog", { name: "Filters" })).toHaveCount(0);
    await expect(page.locator("#drawer-filters")).toHaveClass(/-translate-x-full/);
    await expect(page.locator("#drawer-backdrop")).toHaveClass(/hidden/);
    await expect(page.locator("body")).not.toHaveCSS("overflow", "hidden");

    // Verify Forward restores a closed sheet, which still opens.
    await page.goForward();
    await expect(page.locator("#groups-form-mobile")).toBeAttached();
    await expect(page.getByRole("dialog", { name: "Filters" })).toHaveCount(0);
    await openFilterSheet(page);
  });

  test("applies pending changes through the sheet's close request @mobile", async ({ page }) => {
    // Leave a pending change in the sheet.
    await navigateToPath(page, "/explore?entity=events");
    const requests = trackSectionRequests(page, "/explore/events-section");
    const sheet = await openFilterSheet(page);
    await sheet.locator("label").filter({ hasText: "Virtual" }).click();

    // Reach the CloseWatcher, as Android Back does, past the sheet's own Escape handler.
    await page.evaluate(() => {
      window.addEventListener("keydown", (event) => event.stopImmediatePropagation(), {
        capture: true,
        once: true,
      });
    });
    await waitForActionResponse(page, () => page.keyboard.press("Escape"), {
      method: "GET",
      pathname: "/explore/events-section",
      status: 200,
    });

    // Verify the choice was applied in one request and the sheet went away.
    expect(requests).toHaveLength(1);
    await expect(page.getByRole("dialog", { name: "Filters" })).toHaveCount(0);
    await expect(getAppliedFilterChips(page)).toHaveCount(1);
  });

  test("closes an Escape in the Group filter on its dropdown only @mobile", async ({ page }) => {
    // Open the sheet with a community, which brings the Group filter.
    await navigateToPath(page, `/explore?entity=events&community[0]=${TEST_COMMUNITY_NAME}`);
    const sheet = await openFilterSheet(page);
    const groupSearch = sheet.getByRole("combobox", { name: "Group filter" });
    await groupSearch.click();
    await expect(groupSearch).toHaveAttribute("aria-expanded", "true");

    // Escape closes the dropdown and leaves the sheet.
    await page.keyboard.press("Escape");
    await expect(groupSearch).toHaveAttribute("aria-expanded", "false");
    await expect(sheet).toBeVisible();

    // A second Escape closes the sheet.
    await page.keyboard.press("Escape");
    await expect(page.getByRole("dialog", { name: "Filters" })).toHaveCount(0);
  });

  test("closes the Group dropdown once an option is picked @mobile", async ({ page }) => {
    // Open the sheet with a community, which brings the Group filter.
    await navigateToPath(page, `/explore?entity=events&community[0]=${TEST_COMMUNITY_NAME}`);
    const sheet = await openFilterSheet(page);
    const groupSearch = sheet.getByRole("combobox", { name: "Group filter" });
    await groupSearch.click();
    await expect(groupSearch).toHaveAttribute("aria-expanded", "true");

    // Pick the first option.
    const firstOption = sheet.getByRole("option").first();
    const optionName = (await firstOption.innerText()).trim();
    await firstOption.click();

    // Verify the pick closes the dropdown and keeps the chosen group.
    await expect(groupSearch).toHaveAttribute("aria-expanded", "false");
    await expect(sheet.getByRole("button", { name: `Remove ${optionName}` })).toBeVisible();
  });

  test("keeps the sheet's title and footer in place when a low option takes focus @mobile", async ({
    page,
  }) => {
    // Open the sheet in landscape, where the options run past the footer.
    await page.setViewportSize({ height: 375, width: 667 });
    await navigateToPath(page, `/explore?entity=events&community[0]=${TEST_COMMUNITY_NAME}`);
    const sheet = await openFilterSheet(page);

    // Focus the last option, as a keyboard or a screen reader does.
    await sheet.locator('input[name="event_category[]"]').last().focus();

    // Verify the form scrolled to it, and the panel around it stayed put.
    expect(await sheet.locator("form").evaluate((form) => form.scrollTop)).toBeGreaterThan(0);
    expect(await sheet.evaluate((panel) => panel.scrollTop)).toBe(0);
    await expect(sheet.getByRole("button", { name: "Close filters" })).toBeInViewport();
    await expect(sheet.getByRole("button", { name: "Show results" })).toBeInViewport();
  });

  test("closes the sheet by dragging its title row @mobile", async ({ page }) => {
    // Open the sheet with nothing pending.
    await navigateToPath(page, "/explore?entity=events");
    const sheet = await openFilterSheet(page);
    const grabber = sheet.locator(".sheet-grab");
    const box = await grabber.boundingBox();

    // Drag the row down past the threshold.
    await page.mouse.move(box.x + 60, box.y + 12);
    await page.mouse.down();
    await page.mouse.move(box.x + 60, box.y + 212, { steps: 8 });
    await page.mouse.up();

    // Verify the sheet closed and focus went back.
    await expect(page.getByRole("dialog", { name: "Filters" })).toHaveCount(0);
    await expect(page.locator("#open-filters")).toBeFocused();
  });

  test("alerts on a failed apply and keeps the choices in the sheet @mobile", async ({ page }) => {
    // Fail the section request.
    await navigateToPath(page, "/explore?entity=events");
    await page.route("**/explore/events-section?**", (route) => route.fulfill({ status: 500, body: "" }));

    // Apply a change.
    const sheet = await openFilterSheet(page);
    await sheet.locator("label").filter({ hasText: "Virtual" }).click();
    await sheet.getByRole("button", { name: "Show results" }).click();

    // Verify the alert shows above the sheet, and the choice stays.
    await expect(page.locator(".swal2-popup")).toBeVisible();
    await expect(page.getByRole("dialog", { name: "Filters" })).toBeAttached();
    await expect(sheet.locator('input[name="kind[]"][value="virtual"]')).toBeChecked();
  });

  test("leaves the calendar for the list when a rotation reaches phone width @mobile", async ({ page }) => {
    // Load the calendar in landscape, above the phone width.
    await page.setViewportSize({ height: 390, width: 844 });
    await navigateToPath(
      page,
      "/explore?entity=events&view_mode=calendar&date_from=2030-01-01&date_to=2030-01-31",
    );
    await expect(page.locator("#calendar-box")).toBeVisible();

    // Rotate into phone width.
    await page.setViewportSize({ height: 844, width: 390 });

    // Verify the list replaced the calendar, without its month.
    await expect(page).not.toHaveURL(/view_mode|date_from|date_to/);
    await expect(page.locator("#cards-list article").first()).toBeVisible();
  });

  test("closes the sheet and drops phone attributes on rotation out of phone width @mobile", async ({
    page,
  }) => {
    // Open the sheet on a phone.
    await navigateToPath(page, "/explore?entity=events");
    await expect(page.locator(".filters-form").first()).toHaveAttribute("hx-sync", /#entity-section/);
    await openFilterSheet(page);

    // Rotate past the phone width.
    await page.setViewportSize({ height: 390, width: 844 });

    // Verify nothing held survives.
    await expect(page.getByRole("dialog", { name: "Filters" })).toHaveCount(0);
    await expect(page.locator("body")).not.toHaveCSS("overflow", "hidden");
    await expect(page.locator(".filters-form[hx-sync]")).toHaveCount(0);
    await expect(page.locator("#ts_query")).not.toHaveAttribute("enterkeyhint", /.*/);
  });

  test("lands paging below the results bar @mobile", async ({ page }) => {
    // Load a paged list and reach its pager.
    await navigateToPath(page, "/explore?entity=events&limit=3&offset=0");
    const nextLink = page.locator(".pagination").getByRole("link", { name: "Next" });
    await nextLink.scrollIntoViewIfNeeded();
    await expect(page.locator(".pagination").getByRole("link", { name: "First" })).toBeHidden();

    // Go to the next page.
    await waitForActionResponse(page, () => nextLink.click(), {
      method: "GET",
      pathname: "/explore/events-results-section",
      status: 200,
    });

    // Verify the first card lands right under the pinned bar.
    const resultsBar = page.locator(".section-strip-results");
    const firstCard = page.locator("#cards-list article").first();
    await expect
      .poll(async () => {
        const [bar, card] = [await resultsBar.boundingBox(), await firstCard.boundingBox()];
        return card.y - (bar.y + bar.height);
      })
      .toBeGreaterThanOrEqual(0);
    await expect.poll(async () => (await firstCard.boundingBox()).y).toBeLessThan(160);
  });

  test("offers Reset filters from the filtered empty state @mobile", async ({ page }) => {
    // Load a search with no matches.
    await navigateToPath(page, "/explore?entity=events&ts_query=No%20matching%20event");
    const emptyState = page.locator(".no-results-filtered:not(.hidden)");
    await expect(emptyState).toBeVisible();
    await expect(page.locator("#sort_selector")).toBeHidden();
    await expect(page.getByText("0 results", { exact: true })).toBeVisible();

    // Reset from the alert.
    await waitForActionResponse(
      page,
      () => emptyState.getByRole("button", { name: "Reset filters" }).click(),
      { method: "GET", pathname: "/explore/events-section", status: 200 },
    );

    // Verify the search cleared and results came back.
    await expect(page.getByPlaceholder("Search events")).toHaveValue("");
    await expect(page.locator("#cards-list article").first()).toBeVisible();
  });

  test("fits filters and chips at 320px @mobile", async ({ page }) => {
    // Load a filtered list on the narrowest phone.
    await page.setViewportSize({ height: 640, width: 320 });
    await navigateToPath(
      page,
      `/explore?entity=events&community[0]=${TEST_COMMUNITY_NAME}&kind[0]=in-person&kind[1]=virtual&kind[2]=hybrid`,
    );

    // Verify the page does not scroll sideways, open or closed.
    await expectPageLayout(page, { regions: [page.locator("#explore-cards")] });
    await openFilterSheet(page);
    await expectPageLayout(page, { regions: [page.getByRole("dialog", { name: "Filters" })] });
  });

  test("keeps each chip in the casing of its filter @mobile", async ({ page }) => {
    // Load a list with a Type, a Group and a Community chip.
    await navigateToPath(
      page,
      `/explore?entity=events&community[0]=${TEST_COMMUNITY_NAME}&group[0]=${TEST_GROUP_SLUG}&kind[0]=in-person`,
    );
    const chips = page.getByRole("group", { name: "Applied filters" });
    const chipLabel = (name) => chips.locator(`[data-applied-filter="${name}"] span span`).first();

    // Verify Type and Group read as desktop's tile and search chip do.
    await expect(chipLabel("kind")).toHaveText("In-person", { useInnerText: true });
    await expect(chipLabel("group")).toHaveCSS("text-transform", "none");
    await expect(chipLabel("community")).toHaveCSS("text-transform", "capitalize");
  });

  test("wraps a long unbroken option inside its tile @mobile", async ({ page }) => {
    // Give the Community filter a name with no break opportunity.
    await page.setViewportSize({ height: 640, width: 320 });
    await navigateToPath(page, "/explore?entity=events");
    const sheet = await openFilterSheet(page);
    const filter = sheet.locator('collapsible-filter[name="community"]');
    await filter.evaluate((element, name) => {
      element.visibleOptions = [{ name, value: "long-name" }, ...element.visibleOptions];
    }, "Supercalifragilistic".repeat(4));
    const tile = getFilterOption(filter, "long-name");
    await expect(tile).toBeVisible();

    // Verify the text stays within the tile's own edge.
    const overflow = await tile.evaluate(
      (label) =>
        label.querySelector("div").getBoundingClientRect().right - label.getBoundingClientRect().right,
    );
    expect(overflow).toBeLessThanOrEqual(0);
  });

  test("lets the Group search fill its box @mobile", async ({ page }) => {
    // Open a sheet that has the Group filter.
    await navigateToPath(page, `/explore?entity=events&community[0]=${TEST_COMMUNITY_NAME}`);
    const sheet = await openFilterSheet(page);
    const search = sheet.getByRole("combobox", { name: "Group filter" });
    await expect(search).toBeVisible();

    // Verify a tap anywhere on the box's height lands on the input.
    const box = await search.boundingBox();
    expect(box.height).toBeGreaterThanOrEqual(42);
  });

  test("shows a whole co-hosted title at 320px @mobile", async ({ page }) => {
    // Load the co-hosted card on the narrowest phone.
    await page.setViewportSize({ height: 640, width: 320 });
    await navigateToPath(page, `/explore?entity=events&community[0]=${TEST_COMMUNITY_NAME_2}`);
    const eventCard = page.getByRole("link").filter({ hasText: TEST_COHOSTED_EVENT.name }).first();
    const title = eventCard.getByText(TEST_COHOSTED_EVENT.name, { exact: true });
    await expect(title).toBeVisible();

    // Verify the title takes two lines instead of cutting off.
    await expect(title).toHaveCSS("-webkit-line-clamp", "2");
    const clipped = await title.evaluate((node) => node.scrollHeight > node.clientHeight);
    expect(clipped).toBe(false);
  });

  test("keeps the location readable beside two badges @mobile", async ({ page }) => {
    // Load a Hybrid card with a price at a large phone width.
    await page.setViewportSize({ height: 874, width: 402 });
    await navigateToPath(page, "/explore?entity=events&ts_query=Secondary%20Hybrid");
    const eventCard = page.getByRole("link").filter({ hasText: "Secondary Hybrid Event" }).first();
    await expect(eventCard).toBeVisible();

    // Verify the badges wrap before the place name is cut short.
    const location = eventCard.locator(".icon-text span").filter({ hasText: "E2E Admission Hall" });
    const truncated = await location.evaluate((node) => node.scrollWidth > node.clientWidth);
    expect(truncated).toBe(false);
  });

  test("keeps the desktop layout in the desktop version @mobile", async ({ page }) => {
    // Load a filtered list in the desktop version of a phone.
    await enableDesktopVersion(page);
    await navigateToPath(page, "/explore?entity=events&kind[0]=virtual");

    // Verify the side panel is back, with nothing of the phone layout around it.
    await expect(page.locator("#explore-filters")).toBeVisible();
    await expect(page.locator('label[for="calendar"]')).toBeVisible();
    await expect(getEntitySwitch(page)).toHaveCount(0);
    await expect(page.getByRole("group", { name: "Applied filters" })).toHaveCount(0);
    await expect(page.locator(".section-strip-results")).not.toHaveCSS("position", "sticky");
    await expect(page.locator(".filters-form[hx-sync]")).toHaveCount(0);
    await expect(page.locator("#ts_query")).not.toHaveAttribute("enterkeyhint", /.*/);
  });

  test("treats blank date filters as missing and rejects malformed ones", async ({ request }) => {
    const searchUrl = (dateFrom, dateTo = "") =>
      buildE2eUrl(
        `/explore/events/search?community[0]=${TEST_COMMUNITY_NAME}&view_mode=map` +
          `&date_from=${dateFrom}&date_to=${dateTo}`,
      );

    // Blank dates fall back to the default upcoming window instead of failing to parse.
    const blankResponse = await request.get(searchUrl(""));
    expect(blankResponse.status()).toBe(200);
    const blankResults = await blankResponse.json();
    expect(blankResults.total).toBeGreaterThan(0);
    expect(blankResults.events.length).toBeGreaterThan(0);

    // Each invalid spelling is rejected before the search reaches the database.
    for (const invalidDate of INVALID_DATE_FILTERS) {
      const response = await request.get(searchUrl(invalidDate));

      expect(response.status(), `date_from=${invalidDate}`).toBe(422);
    }
  });
});

/** Adds months to a UTC month date. */
const addMonths = (date, delta) => new Date(Date.UTC(date.getUTCFullYear(), date.getUTCMonth() + delta, 1));

/** Builds the explore calendar path for a seeded event month. */
const buildCalendarPath = (calendarEvent, month) => {
  const range = getMonthRange(month);
  const params = new URLSearchParams({
    entity: "events",
    "community[0]": TEST_COMMUNITY_NAME,
    date_from: range.first,
    date_to: range.last,
    ts_query: calendarEvent.name,
    view_mode: "calendar",
  });

  return `/explore?${params.toString()}`;
};

/** Builds a minimal calendar event for routed search responses. */
const buildMinimalEvent = (name, startsAt, endsAt) => ({
  community_name: TEST_COMMUNITY_NAME,
  ends_at: Math.floor(endsAt.getTime() / 1000),
  event_id: randomUUID(),
  group_slug: TEST_GROUP_SLUG,
  name,
  slug: slugify(name),
  starts_at: Math.floor(startsAt.getTime() / 1000),
});

/** Verifies a calendar search request covers the expected month. */
const expectWidgetMonthRequest = (response, range) => {
  const url = new URL(response.url());
  expect(url.searchParams.get("view_mode")).toBe("calendar");
  expect(url.searchParams.get("date_from")).toBe(range.first);
  expect(url.searchParams.get("date_to")).toBe(range.last);
};

/** Formats a date as YYYY-MM-DD using UTC components. */
const formatDate = (date) => {
  const year = date.getUTCFullYear();
  const month = String(date.getUTCMonth() + 1).padStart(2, "0");
  const day = String(date.getUTCDate()).padStart(2, "0");

  return `${year}-${month}-${day}`;
};

/** Returns a UTC date at an hour of a day of a UTC month. */
const getMonthDayAt = (month, day, hour) =>
  new Date(Date.UTC(month.getUTCFullYear(), month.getUTCMonth(), day, hour));

/** Returns the last day of the UTC month. */
const getMonthEnd = (date) => new Date(Date.UTC(date.getUTCFullYear(), date.getUTCMonth() + 1, 0));

/** Returns the inclusive date range for a UTC month. */
const getMonthRange = (date) => ({
  first: formatDate(getMonthStart(date)),
  last: formatDate(getMonthEnd(date)),
});

/** Returns the first day of the UTC month. */
const getMonthStart = (date) => new Date(Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), 1));

/** Returns the first day of the seed's current month, which holds the this-month calendar event. */
const getSeedMonthStart = () => getSeedClock(TEST_CALENDAR_EVENTS.thisMonth.id).monthStart;

/** Inserts a published in-person alpha sort fixture without a publish timestamp or publisher. */
const insertSortEvent = ({ id, name, slug, startsAt, endsAt }) => {
  insertOwnedEvent({
    description: `${name} generated for deterministic sorting coverage.`,
    descriptionShort: null,
    endsAt,
    eventId: id,
    groupId: TEST_GROUP_IDS.community1.alpha,
    kind: "in-person",
    name,
    organizerUserIds: [],
    publishedAgo: null,
    publishedBy: null,
    slug,
    startsAt,
    tiers: [
      {
        description: "Default ticket type for deterministic sorting coverage.",
        key: "general",
        seats: 30,
        title: "General admission",
      },
    ],
  });
};

/** Hovers a calendar event, waits for its card, and returns the tooltip id. */
const openCalendarCard = async (calendarEvent, cardText) => {
  await calendarEvent.hover();
  await expect(calendarEvent).toHaveAttribute("aria-describedby", /^explore-calendar-card-/);
  const tooltipId = await calendarEvent.getAttribute("aria-describedby");
  const tooltip = calendarEvent.page().locator(`[id="${tooltipId}"]`);
  await expect(tooltip).toBeVisible();
  await expect(tooltip).toHaveAttribute("role", "tooltip");
  await expect(tooltip).toContainText(cardText);
  return tooltipId;
};

/** Builds a URL slug for deterministic sort fixture names. */
const slugify = (value) =>
  value
    .toLowerCase()
    .replace(/[^a-z0-9]+/gu, "-")
    .replace(/^-|-$/gu, "");
