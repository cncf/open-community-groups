import { expect, test } from "@playwright/test";
import type { Page } from "@playwright/test";

import {
  TEST_COMMUNITY_NAME,
  TEST_EVENT_NAMES,
  navigateToPath,
} from "../../utils";

/**
 * Formats a date as YYYY-MM-DD using UTC components.
 * @param {Date} date - Month date to format
 * @returns {string} Formatted date string
 */
const formatDate = (date: Date) => {
  const year = date.getUTCFullYear();
  const month = String(date.getUTCMonth() + 1).padStart(2, "0");
  const day = String(date.getUTCDate()).padStart(2, "0");

  return `${year}-${month}-${day}`;
};

/**
 * Returns the first day of the UTC month.
 * @param {Date} date - Month date to normalize
 * @returns {Date} Month start date
 */
const getMonthStart = (date: Date) =>
  new Date(Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), 1));

/**
 * Returns the last day of the UTC month.
 * @param {Date} date - Month date to normalize
 * @returns {Date} Month end date
 */
const getMonthEnd = (date: Date) =>
  new Date(Date.UTC(date.getUTCFullYear(), date.getUTCMonth() + 1, 0));

/**
 * Adds months to a UTC month date.
 * @param {Date} date - Base month date
 * @param {number} delta - Number of months to add
 * @returns {Date} Shifted month date
 */
const addMonths = (date: Date, delta: number) =>
  new Date(Date.UTC(date.getUTCFullYear(), date.getUTCMonth() + delta, 1));

/**
 * Returns a stable key for a UTC month.
 * @param {Date} date - Month date to convert
 * @returns {string} YYYY-MM key
 */
const getMonthKey = (date: Date) => formatDate(getMonthStart(date)).slice(0, 7);

/**
 * Returns the inclusive date range for a UTC month.
 * @param {Date} date - Month date to convert
 * @returns {{ first: string; last: string }} Month range
 */
const getMonthRange = (date: Date) => ({
  first: formatDate(getMonthStart(date)),
  last: formatDate(getMonthEnd(date)),
});

/**
 * Returns the distance in whole months between two UTC month dates.
 * @param {Date} from - Start month
 * @param {Date} to - End month
 * @returns {number} Month distance
 */
const getMonthDistance = (from: Date, to: Date) =>
  (to.getUTCFullYear() - from.getUTCFullYear()) * 12 + (to.getUTCMonth() - from.getUTCMonth());

/**
 * Finds a populated month with an adjacent empty month for navigation coverage.
 * @param {Page} page - Page fixture
 * @returns {Promise<{ emptyMonth: Date; populatedMonth: Date; direction: "next" | "previous" } | null>}
 */
const findCalendarNavigationScenario = async (page: Page) => {
  const data = await page.evaluate(async (communityName) => {
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

    return response.json();
  }, TEST_COMMUNITY_NAME);

  const populatedMonths = new Set(
    data.events.map((event: { starts_at: number }) => getMonthKey(new Date(event.starts_at * 1000))),
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

  throw new Error("Could not find an empty month adjacent to populated calendar data");
};

test.describe("site explore events page", () => {
  test("supports kind filtering and switching to calendar view", async ({ page }) => {
    await navigateToPath(
      page,
      `/explore?entity=events&community[0]=${TEST_COMMUNITY_NAME}`,
    );

    await expect(page.getByPlaceholder("Search events")).toBeVisible();
    await expect(page.getByText(TEST_EVENT_NAMES.alpha[0], { exact: true })).toBeVisible();
    await expect(page.getByText(TEST_EVENT_NAMES.alpha[1], { exact: true })).toBeVisible();

    const inPersonFilter = page.locator('input[name="kind[]"][value="in-person"]').first();
    await inPersonFilter.evaluate((input) => {
      if (!(input instanceof HTMLInputElement)) {
        throw new Error("in-person filter input not found");
      }

      input.checked = true;
      input.dispatchEvent(new Event("change", { bubbles: true }));
    });

    await expect(page.getByText(TEST_EVENT_NAMES.alpha[0], { exact: true })).toBeVisible();
    await expect(page.getByText(TEST_EVENT_NAMES.alpha[1], { exact: true })).toHaveCount(0);

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

    await expect(page.locator("#calendar-box")).toBeVisible();
    await expect(page.locator("#calendar-date")).toBeVisible();
    await expect(page.locator("#current-month-btn")).toBeVisible();
    await expect(page.locator("#sort_selector")).toHaveCount(0);
  });

  test("shows a filtered empty state when no events match the search", async ({
    page,
  }) => {
    await navigateToPath(
      page,
      `/explore?entity=events&community[0]=${TEST_COMMUNITY_NAME}`,
    );

    const searchInput = page.getByPlaceholder("Search events");
    await expect(searchInput).toBeVisible();

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

    const filteredEmptyState = page.locator(".no-results-filtered:not(.hidden)");

    await expect(filteredEmptyState).toBeVisible();
    await expect(
      filteredEmptyState.getByText("No events found", { exact: true }),
    ).toBeVisible();
    await expect(
      filteredEmptyState.getByText(
        "We can't seem to find any events that match your search criteria. You can reset your filters or try a different search.",
      ),
    ).toBeVisible();

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

    await expect(page.locator("#calendar-box")).toBeVisible();
    await expect(page.locator(".no-results-filtered:not(.hidden)")).toBeVisible();
    await expect(page.locator(".no-results-default:not(.hidden)")).toHaveCount(0);
  });

  test("hides the empty state after navigating from an empty month to one with events", async ({
    page,
  }) => {
    await navigateToPath(
      page,
      `/explore?entity=events&community[0]=${TEST_COMMUNITY_NAME}`,
    );

    const scenario = await findCalendarNavigationScenario(page);
    test.skip(!scenario, "Requires seeded calendar event data");

    const { emptyMonth, populatedMonth, direction } = scenario;
    const emptyRange = getMonthRange(emptyMonth);

    await navigateToPath(
      page,
      `/explore?entity=events&community[0]=${TEST_COMMUNITY_NAME}` +
        `&view_mode=calendar&date_from=${emptyRange.first}&date_to=${emptyRange.last}`,
    );

    await expect(page.locator("#calendar-box")).toBeVisible();

    const filteredEmptyState = page.locator(".no-results-filtered:not(.hidden)");
    const navigationButton =
      direction === "next"
        ? page.locator("#next-month-btn")
        : page.locator("#prev-month-btn");
    const calendarEvents = page.locator(".fc-daygrid-event");
    await expect(filteredEmptyState).toBeVisible();
    await expect(page.locator(".no-results-default:not(.hidden)")).toHaveCount(0);
    await expect(calendarEvents).toHaveCount(0);

    const monthSteps = Math.abs(getMonthDistance(emptyMonth, populatedMonth));
    expect(monthSteps).toBeGreaterThan(0);

    for (let step = 0; step < monthSteps; step += 1) {
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

    const populatedRange = getMonthRange(populatedMonth);
    await expect(page.locator(".no-results-filtered:not(.hidden)")).toHaveCount(0);
    await expect(page.locator(".no-results-default:not(.hidden)")).toHaveCount(0);
    await expect(filteredEmptyState).toHaveCount(0);
    await expect(calendarEvents.first()).toBeVisible();
    await expect
      .poll(async () =>
        page.evaluate(() => {
          const params = new URLSearchParams(window.location.search);

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
    await navigateToPath(
      page,
      `/explore?entity=events&community[0]=${TEST_COMMUNITY_NAME}`,
    );

    const scenario = await findCalendarNavigationScenario(page);
    test.skip(!scenario, "Requires seeded calendar event data");

    const { emptyMonth, populatedMonth } = scenario;
    const populatedRange = getMonthRange(populatedMonth);

    await navigateToPath(
      page,
      `/explore?entity=events&community[0]=${TEST_COMMUNITY_NAME}` +
        `&view_mode=calendar&date_from=${populatedRange.first}&date_to=${populatedRange.last}`,
    );

    await expect(page.locator("#calendar-box")).toBeVisible();

    const calendarEvents = page.locator(".fc-daygrid-event");
    await expect(calendarEvents.first()).toBeVisible();
    await expect(page.locator(".no-results-filtered:not(.hidden)")).toHaveCount(0);
    await expect(page.locator(".no-results-default:not(.hidden)")).toHaveCount(0);

    const monthDistance = getMonthDistance(populatedMonth, emptyMonth);
    expect(monthDistance).not.toBe(0);

    const navigationButton =
      monthDistance > 0 ? page.locator("#next-month-btn") : page.locator("#prev-month-btn");

    for (let step = 0; step < Math.abs(monthDistance); step += 1) {
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

    const emptyRange = getMonthRange(emptyMonth);
    const filteredEmptyState = page.locator(".no-results-filtered:not(.hidden)");
    await expect(filteredEmptyState).toBeVisible();
    await expect(page.locator(".no-results-default:not(.hidden)")).toHaveCount(0);
    await expect(calendarEvents).toHaveCount(0);
    await expect
      .poll(async () =>
        page.evaluate(() => {
          const params = new URLSearchParams(window.location.search);

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
