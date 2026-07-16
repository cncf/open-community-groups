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
    representativeText: "Community page",
  },
];

const expectChartSettled = async (container, chartId) => {
  const chart = container.locator(`#${chartId}`);

  if ((await chart.count()) === 0) {
    await expect(container.locator(".chart-empty-state").first()).toBeVisible();
    return;
  }

  await expect(chart).toBeVisible();
  await expect(chart.locator("svg-spinner")).toHaveCount(0);
};

test.describe("community dashboard analytics view", () => {
  test("admin can switch between analytics tabs and view each section", async ({
    adminCommunityPage,
  }) => {
    // Load the community analytics dashboard before switching tabs.
    await navigateToPath(
      adminCommunityPage,
      "/dashboard/community?tab=analytics",
    );

    // Find the dashboard content.
    const dashboardContent = adminCommunityPage.locator("#dashboard-content");

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
      await expect(tabButton).toHaveClass(/xl:hover:border-primary-300/);
      await expect(tabButton).toHaveClass(/xl:hover:shadow-sm/);
      await tabButton.click();

      // Assert the rendered attribute value.
      await expect(tabButton).toHaveAttribute("data-active", "true");
      await expect(tabButton).not.toHaveClass(/outline-primary-200/);
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
