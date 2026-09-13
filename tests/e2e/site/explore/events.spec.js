import { randomUUID } from "node:crypto";
import { expect, test } from "@playwright/test";
import { queryE2eDatabase } from "../../database.js";
import {
  TEST_CALENDAR_EVENTS,
  TEST_COMMUNITY_NAME,
  TEST_EVENT_NAMES,
  TEST_GROUP_IDS,
  TEST_GROUP_SLUG,
} from "../../seed.js";
import {
  buildE2eUrl,
  expectPaginationNavigation,
  futureDate,
  navigateToPath,
  uniqueName,
  waitForActionResponse,
} from "../../utils.js";

const SORT_EVENT_CATEGORY_ID = "33333333-3333-3333-3333-333333333331";

// Date filter values `SearchEventsFilters` rejects: unparsable, out-of-range and non-`YYYY` years.
const INVALID_DATE_FILTERS = ["not-a-date", "2031-13-45", "2031/01/15", "0000-01-01", "-5000-01-01"];

test.describe("site explore events page", () => {
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

    // Verify the calendar popover also omits free price badges.
    const calendarEvent = page.locator(".fc-daygrid-event").filter({ hasText: freeEventName }).first();
    await expect(calendarEvent).toBeVisible();
    await calendarEvent.hover();
    const calendarPopover = page.locator('[data-popover="true"]').filter({ hasText: freeEventName });
    await expect(calendarPopover).toBeVisible();
    await expect(calendarPopover.getByText("Free", { exact: true })).toHaveCount(0);
    await expect(calendarPopover.locator("[data-localized-currency]")).toHaveCount(0);
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
        priceWindowId: randomUUID(),
        slug: slugify(`${sortToken} earlier`),
        startsAt: futureDate({ days: 181, hour: 10 }),
        ticketTypeId: randomUUID(),
      },
      {
        endsAt: futureDate({ days: 182, hour: 12 }),
        id: randomUUID(),
        name: `${sortToken} Later`,
        priceWindowId: randomUUID(),
        slug: slugify(`${sortToken} later`),
        startsAt: futureDate({ days: 182, hour: 10 }),
        ticketTypeId: randomUUID(),
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

      // Verify descending order by exact identity.
      await expect(page.locator("#sort_selector")).toHaveValue("date-desc");
      await expect(page.locator("#sort_direction")).toHaveValue("desc");
      await expect(eventCards).toHaveCount(sortEvents.length);
      await expect(eventCards.locator(".card-title")).toHaveText(
        [...sortEvents].reverse().map((event) => event.name),
      );
    } finally {
      // Remove owned sorting fixtures.
      deleteSortEvents(sortEvents.map((event) => event.slug));
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
      {
        method: "GET",
        urlIncludes: "/explore/events-section",
      },
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

  test("supports kind filtering and switching to calendar view", async ({ page }) => {
    // Load the events explore page with the community filter applied.
    await navigateToPath(page, `/explore?entity=events&community[0]=${TEST_COMMUNITY_NAME}`);

    // Verify events render before applying filters.
    await expect(page.getByPlaceholder("Search events")).toBeVisible();
    await expect(page.getByText(TEST_EVENT_NAMES.alpha[0], { exact: true })).toBeVisible();
    await expect(page.getByText(TEST_EVENT_NAMES.alpha[1], { exact: true })).toBeVisible();

    // Apply the in-person filter and wait for the event list to narrow.
    const inPersonFilter = page.locator('input[name="kind[]"][value="in-person"]').first();
    await inPersonFilter.evaluate((input) => {
      if (!(input instanceof HTMLInputElement)) {
        throw new Error("in-person filter input not found");
      }

      // Select the answer option.
      input.checked = true;
      input.dispatchEvent(new Event("change", { bubbles: true }));
    });

    // Verify only matching in-person events remain visible.
    await expect(page.getByText(TEST_EVENT_NAMES.alpha[0], { exact: true })).toBeVisible();
    await expect(page.getByText(TEST_EVENT_NAMES.alpha[1], { exact: true })).toHaveCount(0);

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

  test("shows a filtered empty state when no events match the search", async ({ page }) => {
    // Load the events explore page for an empty search result.
    await navigateToPath(page, `/explore?entity=events&community[0]=${TEST_COMMUNITY_NAME}`);

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
      searchInput.fill("No matching event").then(() => searchInput.press("Enter")),
    ]);

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
    await expect(page.locator(".no-results-filtered:not(.hidden)")).toBeVisible();
    await expect(page.locator(".no-results-default:not(.hidden)")).toHaveCount(0);
  });

  test("hides the empty state after navigating from an empty month to one with events", async ({ page }) => {
    // Load the calendar one month before the seeded current-month event.
    const currentMonth = getMonthStart(new Date());
    const emptyMonth = addMonths(currentMonth, -1);
    await navigateToPath(page, buildCalendarPath(TEST_CALENDAR_EVENTS.thisMonth, emptyMonth));

    // Verify the calendar starts on an empty month for the pinned event query.
    const calendarEvents = page.locator(".fc-daygrid-event");
    const filteredEmptyState = page.locator(".no-results-filtered:not(.hidden)");
    await expect(page.locator("#calendar-box")).toBeVisible();
    await expect(filteredEmptyState).toBeVisible();
    await expect(page.locator(".no-results-default:not(.hidden)")).toHaveCount(0);
    await expect(calendarEvents).toHaveCount(0);

    // Navigate into the seeded current month.
    await waitForActionResponse(page, () => page.locator("#next-month-btn").click(), {
      method: "GET",
      urlIncludes: "/explore/events/search",
    });

    // Verify empty fallback content clears after the pinned event appears.
    const populatedRange = getMonthRange(currentMonth);
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
    const nextMonth = addMonths(getMonthStart(new Date()), 1);
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
    await waitForActionResponse(page, () => page.locator("#next-month-btn").click(), {
      method: "GET",
      urlIncludes: "/explore/events/search",
    });

    // Verify the filtered empty state appears for the empty month because the pinned event query remains active.
    const emptyRange = getMonthRange(emptyMonth);
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

  test("treats blank date filters as missing and rejects malformed ones", async ({ request }) => {
    const searchUrl = (dateFrom, dateTo = "") =>
      buildE2eUrl(
        `/explore/events/search?community[0]=${TEST_COMMUNITY_NAME}&view_mode=list` +
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

/** Deletes sort fixtures from event, event_ticket_type, and event_ticket_price_window. */
const deleteSortEvents = (slugs) => {
  if (slugs.length === 0) {
    return;
  }

  queryE2eDatabase(
    `
      delete from event_ticket_price_window
      where event_ticket_type_id in (
        select event_ticket_type_id
        from event_ticket_type
        where event_id in (
          select event_id
          from event
          where slug in (${slugs.map((slug) => `'${escapeSql(slug)}'`).join(", ")})
        )
      );
      delete from event_ticket_type
      where event_id in (
        select event_id
        from event
        where slug in (${slugs.map((slug) => `'${escapeSql(slug)}'`).join(", ")})
      );
      delete from event where slug in (${slugs.map((slug) => `'${escapeSql(slug)}'`).join(", ")});
    `,
  );
};

/** Escapes a value for embedding in E2E SQL. */
const escapeSql = (value) => value.replace(/'/g, "''");

/** Formats a date as YYYY-MM-DD using UTC components. */
const formatDate = (date) => {
  const year = date.getUTCFullYear();
  const month = String(date.getUTCMonth() + 1).padStart(2, "0");
  const day = String(date.getUTCDate()).padStart(2, "0");

  return `${year}-${month}-${day}`;
};

/** Returns the last day of the UTC month. */
const getMonthEnd = (date) => new Date(Date.UTC(date.getUTCFullYear(), date.getUTCMonth() + 1, 0));

/** Returns the inclusive date range for a UTC month. */
const getMonthRange = (date) => ({
  first: formatDate(getMonthStart(date)),
  last: formatDate(getMonthEnd(date)),
});

/** Returns the first day of the UTC month. */
const getMonthStart = (date) => new Date(Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), 1));

/** Inserts sort fixtures into event, event_ticket_type, and event_ticket_price_window. */
const insertSortEvent = ({ id, name, priceWindowId, slug, startsAt, endsAt, ticketTypeId }) => {
  queryE2eDatabase(`
    insert into event (
      event_id, name, slug, description, timezone, event_category_id,
      event_kind_id, group_id, published, starts_at, ends_at
    ) values (
      '${escapeSql(id)}',
      '${escapeSql(name)}',
      '${escapeSql(slug)}',
      '${escapeSql(`${name} generated for deterministic sorting coverage.`)}',
      'UTC',
      '${SORT_EVENT_CATEGORY_ID}',
      'in-person',
      '${TEST_GROUP_IDS.community1.alpha}',
      true,
      '${escapeSql(startsAt)}'::timestamp at time zone 'UTC',
      '${escapeSql(endsAt)}'::timestamp at time zone 'UTC'
    );
    insert into event_ticket_type (
      event_ticket_type_id, active, event_id, "order", seats_total, title, description
    ) values (
      '${escapeSql(ticketTypeId)}',
      true,
      '${escapeSql(id)}',
      1,
      30,
      'General admission',
      'Default ticket type for deterministic sorting coverage.'
    );
    insert into event_ticket_price_window (
      amount_minor, event_ticket_price_window_id, event_ticket_type_id
    ) values (
      0,
      '${escapeSql(priceWindowId)}',
      '${escapeSql(ticketTypeId)}'
    );
  `);
};

/** Builds a URL slug for deterministic sort fixture names. */
const slugify = (value) =>
  value
    .toLowerCase()
    .replace(/[^a-z0-9]+/gu, "-")
    .replace(/^-|-$/gu, "");
