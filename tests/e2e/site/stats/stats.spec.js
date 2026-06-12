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
      await expect(
        mainContent.getByText(sectionName, { exact: true }).first(),
      ).toBeVisible();
    }

    // Set up groups section.
    const groupsSection = mainContent
      .getByText("Groups", { exact: true })
      .first()
      .locator("..")
      .locator("..");
    await expect(
      groupsSection
        .locator("#groups-running-chart, .chart-empty-state")
        .first(),
    ).toBeVisible();
    await expect(
      groupsSection.locator("#groups-monthly-chart, .chart-empty-state").last(),
    ).toBeVisible();

    // Set up members section.
    const membersSection = mainContent
      .getByText("Members", { exact: true })
      .first()
      .locator("..")
      .locator("..");
    await expect(
      membersSection
        .locator("#members-running-chart, .chart-empty-state")
        .first(),
    ).toBeVisible();
    await expect(
      membersSection
        .locator("#members-monthly-chart, .chart-empty-state")
        .last(),
    ).toBeVisible();

    // Set up events section.
    const eventsSection = mainContent
      .getByText("Events", { exact: true })
      .first()
      .locator("..")
      .locator("..");
    await expect(
      eventsSection
        .locator("#events-running-chart, .chart-empty-state")
        .first(),
    ).toBeVisible();
    await expect(
      eventsSection.locator("#events-monthly-chart, .chart-empty-state").last(),
    ).toBeVisible();

    // Set up attendees section.
    const attendeesSection = mainContent
      .getByText("Attendees", { exact: true })
      .first()
      .locator("..")
      .locator("..");
    await expect(
      attendeesSection
        .locator("#attendees-running-chart, .chart-empty-state")
        .first(),
    ).toBeVisible();
    await expect(
      attendeesSection
        .locator("#attendees-monthly-chart, .chart-empty-state")
        .last(),
    ).toBeVisible();

    // Verify representative charts finish rendering or show the empty state.
    await expectChartSettled(page, "#groups-running-chart");
    await expectChartSettled(page, "#members-running-chart");
    await expectChartSettled(page, "#events-running-chart");
    await expectChartSettled(page, "#attendees-running-chart");
  });
});
