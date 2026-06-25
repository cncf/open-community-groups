import { expect, test } from "../../../fixtures.js";

import { navigateToPath } from "../../../utils.js";

const ANALYTICS_TABS = [
  {
    chartId: "groups-running-chart",
    key: "groups",
    label: "Groups",
    representativeText: "Running total",
  },
  {
    chartId: "members-running-chart",
    key: "members",
    label: "Members",
    representativeText: "Running total",
  },
  {
    chartId: "events-running-chart",
    key: "events",
    label: "Events",
    representativeText: "Running total",
  },
  {
    chartId: "attendees-running-chart",
    key: "attendees",
    label: "Attendees",
    representativeText: "Running total",
  },
  {
    chartId: "total-views-monthly-chart",
    key: "page-views",
    label: "Page views",
    representativeText: "Alliance page",
  },
];

const expectChartSettled = async (container, chartId) => {
  const chart = container.locator(`#${chartId}`);

  if ((await chart.count()) === 0) {
    await expect(container).toBeVisible();
    return;
  }

  await expect(chart).toBeVisible();
  await expect(chart.locator("svg-spinner")).toHaveCount(0);
};

test.describe("alliance dashboard analytics view", () => {
  test("admin can switch between analytics tabs and view each section", async ({
    adminAlliancePage,
  }) => {
    // Load the alliance analytics dashboard before switching tabs.
    await navigateToPath(
      adminAlliancePage,
      "/dashboard/alliance?tab=analytics",
    );

    // Find the dashboard content.
    const dashboardContent = adminAlliancePage.locator("#dashboard-content");

    // Verify admin can switch between analytics tabs and view each section.
    await expect(
      dashboardContent.getByText("Analytics", { exact: true }),
    ).toBeVisible();

    // Assert each expected case.
    for (const analyticsTab of ANALYTICS_TABS) {
      const tabButton = dashboardContent
        .locator(`button[data-analytics-tab="${analyticsTab.key}"]`)
        .first();
      const tabContent = dashboardContent.locator(
        `[data-analytics-content="${analyticsTab.key}"]`,
      );

      // Assert the expected content is visible.
      await expect(tabButton).toBeVisible();
      await tabButton.click();

      // Assert the rendered attribute value.
      await expect(tabButton).toHaveAttribute("data-active", "true");
      await expect(tabContent).toBeVisible();
      await expect(
        tabContent.getByText(analyticsTab.label, { exact: true }).first(),
      ).toBeVisible();
      await expect(
        tabContent.getByText(analyticsTab.representativeText, { exact: true }),
      ).toBeVisible();
      await expectChartSettled(tabContent, analyticsTab.chartId);
    }
  });
});
