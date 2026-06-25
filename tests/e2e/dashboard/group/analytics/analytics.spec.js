import { expect, test } from "../../../fixtures.js";

import { navigateToPath } from "../../../utils.js";

const expectChartSettled = async (container, chartId) => {
  const chart = container.locator(`#${chartId}`);

  if ((await chart.count()) === 0) {
    await expect(container).toBeVisible();
    return;
  }

  await expect(chart).toBeVisible();
  await expect(chart.locator("svg-spinner")).toHaveCount(0);
};

test.describe("group dashboard analytics view", () => {
  test("organizer can view analytics summary cards and chart sections", async ({
    organizerGroupPage,
  }) => {
    // Load the group analytics dashboard before checking chart sections.
    await navigateToPath(organizerGroupPage, "/dashboard/group?tab=analytics");

    // Find the dashboard content.
    const dashboardContent = organizerGroupPage.locator("#dashboard-content");

    // Verify organizer can view analytics summary cards and chart sections.
    await expect(
      dashboardContent.getByText("Analytics", { exact: true }),
    ).toBeVisible();

    // Assert each expected case.
    for (const label of ["Members", "Events", "Attendees", "Page views"]) {
      await expect(
        dashboardContent.getByText(label, { exact: true }).first(),
      ).toBeVisible();
    }

    await expect(
      dashboardContent.getByText("Running total", { exact: true }).first(),
    ).toBeVisible();

    // Set up page views section.
    const pageViewsSection = dashboardContent.getByText("Page views", {
      exact: true,
    });
    await expect(pageViewsSection.first()).toBeVisible();
    await expect(
      dashboardContent.getByText("Group page", { exact: true }),
    ).toBeVisible();
    await expect(
      dashboardContent.getByText("Event pages", { exact: true }),
    ).toBeVisible();

    // Verify representative charts finish rendering or show the empty state.
    await expectChartSettled(dashboardContent, "members-running-chart");
    await expectChartSettled(dashboardContent, "events-running-chart");
    await expectChartSettled(dashboardContent, "attendees-running-chart");
    await expectChartSettled(dashboardContent, "group-views-monthly-chart");
  });
});
