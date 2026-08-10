import { expect, test } from "@playwright/test";

import { navigateToPath } from "../../utils.js";

const expectChartSettled = async (page, selector) => {
  const chart = page.locator(selector);

  if ((await chart.count()) === 0) {
    await expect(page.locator(".chart-empty-state").first()).toBeVisible();
    return;
  }

  await expect(chart).toBeVisible();
  await expect(chart.locator("svg-spinner")).toHaveCount(0);
};

const PUBLIC_STATS_CHART_IDS = [
  "groups-running-chart",
  "groups-monthly-chart",
  "members-running-chart",
  "members-monthly-chart",
  "events-running-chart",
  "events-monthly-chart",
  "attendees-running-chart",
  "attendees-monthly-chart",
];

test.describe("site stats page", () => {
  test("renders totals and analytics chart containers", async ({ page }) => {
    // Load the public stats page before checking analytics sections.
    await navigateToPath(page, "/stats");

    // Find the main content.
    const mainContent = page.locator("#main-content");

    // Verify renders totals and analytics chart containers.
    await expect(mainContent.getByText("Stats", { exact: true })).toBeVisible();
    await expect(
      mainContent.getByText("Global growth trends across all communities.", {
        exact: true,
      }),
    ).toBeVisible();

    // Assert each expected case.
    for (const sectionName of ["Groups", "Members", "Events", "Attendees"]) {
      await expect(mainContent.getByText(sectionName, { exact: true }).first()).toBeVisible();
    }

    // Set up groups section.
    const groupsSection = mainContent
      .getByText("Groups", { exact: true })
      .first()
      .locator("..")
      .locator("..");
    await expect(groupsSection.locator("#groups-running-chart, .chart-empty-state").first()).toBeVisible();
    await expect(groupsSection.locator("#groups-monthly-chart, .chart-empty-state").last()).toBeVisible();

    // Set up members section.
    const membersSection = mainContent
      .getByText("Members", { exact: true })
      .first()
      .locator("..")
      .locator("..");
    await expect(membersSection.locator("#members-running-chart, .chart-empty-state").first()).toBeVisible();
    await expect(membersSection.locator("#members-monthly-chart, .chart-empty-state").last()).toBeVisible();

    // Set up events section.
    const eventsSection = mainContent
      .getByText("Events", { exact: true })
      .first()
      .locator("..")
      .locator("..");
    await expect(eventsSection.locator("#events-running-chart, .chart-empty-state").first()).toBeVisible();
    await expect(eventsSection.locator("#events-monthly-chart, .chart-empty-state").last()).toBeVisible();

    // Set up attendees section.
    const attendeesSection = mainContent
      .getByText("Attendees", { exact: true })
      .first()
      .locator("..")
      .locator("..");
    await expect(
      attendeesSection.locator("#attendees-running-chart, .chart-empty-state").first(),
    ).toBeVisible();
    await expect(
      attendeesSection.locator("#attendees-monthly-chart, .chart-empty-state").last(),
    ).toBeVisible();

    // Verify representative charts finish rendering or show the empty state.
    await expectChartSettled(page, "#groups-running-chart");
    await expectChartSettled(page, "#members-running-chart");
    await expectChartSettled(page, "#events-running-chart");
    await expectChartSettled(page, "#attendees-running-chart");

    // Count rendered and empty chart slots to cover the complete page contract.
    const renderedCharts = mainContent.locator(
      PUBLIC_STATS_CHART_IDS.map((chartId) => `#${chartId}`).join(", "),
    );
    const emptyCharts = mainContent.locator(".chart-empty-state");
    await expect
      .poll(async () => (await renderedCharts.count()) + (await emptyCharts.count()))
      .toBe(PUBLIC_STATS_CHART_IDS.length);

    for (const chartId of PUBLIC_STATS_CHART_IDS) {
      const chart = mainContent.locator(`#${chartId}`);
      if ((await chart.count()) > 0) {
        await expect(chart).toBeVisible();
        await expect(chart.locator("svg-spinner")).toHaveCount(0);
      }
    }

    // Verify the embedded payload contains every public statistics area.
    // The stats payload script is rendered outside #main-content.
    const statsPayload = await page.locator("script[data-site-stats]").textContent();
    const parsedStats = JSON.parse(statsPayload);
    expect(Object.keys(parsedStats)).toEqual(
      expect.arrayContaining(["groups", "members", "events", "attendees"]),
    );
  });

  test("keeps every statistics card and chart available on mobile @mobile", async ({ page }) => {
    // Load public statistics using the mobile project viewport.
    await navigateToPath(page, "/stats");

    // Verify every summary card and chart slot remains available.
    const mainContent = page.locator("#main-content");
    await expect(mainContent.getByText("Stats", { exact: true })).toBeVisible();
    // Each total card mixes the label with its value, so match by substring.
    await expect(mainContent.getByText("Total")).toHaveCount(4);
    await expect(mainContent.locator("section")).toHaveCount(4);
    await expect(mainContent.locator(".chart-empty-state, [id$='-chart']")).toHaveCount(
      PUBLIC_STATS_CHART_IDS.length,
    );
  });
});
