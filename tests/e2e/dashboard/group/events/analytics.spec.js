import { expect, test } from "../../../fixtures.js";
import { TEST_EVENT_ANALYTICS, TEST_UNPUBLISHED_EVENT } from "../../../seed.js";
import { openEventUpdateFormByName } from "./helpers.js";

/**
 * Opens the analytics section of the loaded event editor and waits for its charts.
 * @param {import("@playwright/test").Page} page - Playwright page.
 * @param {string} eventId - Event whose analytics load.
 * @param {(page: import("@playwright/test").Page) => Promise<void>} activate - Section activation.
 * @returns {Promise<import("@playwright/test").Locator>} Analytics content locator.
 */
const openAnalyticsSection = async (page, eventId, activate) => {
  const [response] = await Promise.all([
    page.waitForResponse(
      (candidate) =>
        candidate.request().method() === "GET" &&
        candidate.url().includes(`/dashboard/group/events/${eventId}/analytics`),
    ),
    activate(page),
  ]);
  expect(response.ok()).toBe(true);

  const content = page.locator("#analytics-content");
  await expect(content).toHaveAttribute("data-analytics-state", "loaded");
  await expect(content.locator("[data-event-analytics]")).toHaveAttribute(
    "data-event-analytics-ready",
    "true",
  );
  return content;
};

/** Activates the analytics section from the desktop tab list. */
const clickAnalyticsTab = (page) => page.locator('button[data-section="analytics"]').click();

test.describe("group dashboard event analytics tab", () => {
  test("organizer views traffic, registrations, tickets and check-ins of a past paid event", async ({
    organizerGroupPage,
  }) => {
    // Open the past paid event and its analytics tab.
    const { id, name } = TEST_EVENT_ANALYTICS.pastPaid;
    await openEventUpdateFormByName(organizerGroupPage, name, id, { eventsTab: "past" });
    const content = await openAnalyticsSection(organizerGroupPage, id, clickAnalyticsTab);

    // Verify the summary cards and rendered charts.
    await expect(content.getByText("Conversion", { exact: true })).toBeVisible();
    await expect(content.getByText("Check-in rate", { exact: true })).toBeVisible();
    for (const chartId of [
      "event-views-daily-chart",
      "event-registrations-daily-chart",
      "event-registration-paths-chart",
      "event-check-ins-chart",
    ]) {
      await expect(content.locator(`#${chartId}`)).toHaveAttribute("_echarts_instance_", /.+/);
    }

    // Verify the paid ticket usage and the check-in section.
    await expect(content.locator("[data-event-analytics-tickets]")).toContainText(
      "2 sold · 0 reserved · 18 remaining of 20",
    );
    await expect(content.getByRole("progressbar", { name: "Analytics pass seats" })).toHaveAttribute(
      "aria-valuenow",
      "2",
    );
    await expect(content.locator("[data-event-analytics-check-ins]")).toBeVisible();
    await expect(content.getByText(/revenue/i)).toHaveCount(0);
  });

  test("organizer switches UTM dimensions and sorts combinations", async ({ organizerGroupPage }) => {
    // Open the past paid event analytics.
    const { id, name } = TEST_EVENT_ANALYTICS.pastPaid;
    await openEventUpdateFormByName(organizerGroupPage, name, id, { eventsTab: "past" });
    const content = await openAnalyticsSection(organizerGroupPage, id, clickAnalyticsTab);

    // Switch the values chart to mediums.
    const dimensionSwitch = content.getByRole("group", { name: "UTM parameter" });
    const mediumButton = dimensionSwitch.getByRole("button", { name: "Medium", exact: true });
    await mediumButton.click();
    await expect(mediumButton).toHaveAttribute("aria-pressed", "true");
    await expect(dimensionSwitch.getByRole("button", { name: "Source", exact: true })).toHaveAttribute(
      "aria-pressed",
      "false",
    );

    // Sort the combinations by source.
    const table = content.locator("table[data-utm-combinations]");
    const sourceHeader = table.locator("th", { has: organizerGroupPage.locator('[data-utm-sort="source"]') });
    await table.locator('[data-utm-sort="source"]').click();
    await expect(sourceHeader).toHaveAttribute("aria-sort", "ascending");
    await expect(table.locator("tbody tr td:first-child")).toHaveText([
      "mastodon",
      "newsletter",
      "Not specified",
    ]);
  });

  test("organizer sees no tickets or check-ins for a future free event", async ({ organizerGroupPage }) => {
    // Open the future free event analytics.
    const { id, name } = TEST_EVENT_ANALYTICS.futureFree;
    await openEventUpdateFormByName(organizerGroupPage, name, id);
    const content = await openAnalyticsSection(organizerGroupPage, id, clickAnalyticsTab);

    // Verify paid and post-event sections are omitted.
    await expect(content.getByText("Fill rate", { exact: true })).toBeVisible();
    await expect(content.locator("[data-event-analytics-tickets]")).toHaveCount(0);
    await expect(content.locator("[data-event-analytics-check-ins]")).toHaveCount(0);
    await expect(content.getByText("Check-in rate", { exact: true })).toHaveCount(0);
    await expect(content.getByText(/revenue/i)).toHaveCount(0);
  });

  test("organizer sees why daily charts are missing for an unpublished event", async ({
    organizerGroupPage,
  }) => {
    // Open the unpublished event analytics.
    const { id, name } = TEST_UNPUBLISHED_EVENT;
    await openEventUpdateFormByName(organizerGroupPage, name, id);
    const content = await openAnalyticsSection(organizerGroupPage, id, clickAnalyticsTab);

    // Verify the explanation replaces the daily charts.
    await expect(content.locator("[data-event-analytics-range-unavailable]").first()).toContainText(
      "this event is not published",
    );
    await expect(content.locator("#event-views-daily-chart")).toHaveCount(0);
  });

  test("group viewer can open the analytics tab", async ({ groupViewerPage }) => {
    // Open the past paid event as a read-only group viewer.
    const { id, name } = TEST_EVENT_ANALYTICS.pastPaid;
    await openEventUpdateFormByName(groupViewerPage, name, id, { eventsTab: "past" });
    const content = await openAnalyticsSection(groupViewerPage, id, clickAnalyticsTab);

    // Verify the analytics render for read-only roles.
    await expect(content.getByText("Page views", { exact: true }).first()).toBeVisible();
  });

  test("organizer opens analytics from the compact section select", async ({ organizerGroupPage }) => {
    // Open the past paid event and narrow the viewport to show the section select.
    const { id, name } = TEST_EVENT_ANALYTICS.pastPaid;
    await openEventUpdateFormByName(organizerGroupPage, name, id, { eventsTab: "past" });
    await organizerGroupPage.setViewportSize({ width: 1024, height: 900 });

    // Choose analytics from the section select.
    const content = await openAnalyticsSection(organizerGroupPage, id, (page) =>
      page.locator("#update-event-section-select").selectOption("analytics"),
    );

    // Verify the charts render.
    await expect(content.locator("#event-views-daily-chart")).toHaveAttribute("_echarts_instance_", /.+/);
  });
});
