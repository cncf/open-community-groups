import { expect, test } from "../../../fixtures.js";

import { navigateToPath } from "../../../utils.js";

const ANALYTICS_TABS = [
  {
    chartId: "groups-running-chart",
    chartCount: 8,
    key: "groups",
    label: "Groups",
    representativeText: "Running total",
  },
  {
    chartId: "members-running-chart",
    chartCount: 8,
    key: "members",
    label: "Members",
    representativeText: "Running total",
  },
  {
    chartId: "events-running-chart",
    chartCount: 11,
    key: "events",
    label: "Events",
    representativeText: "Running total",
  },
  {
    chartId: "attendees-running-chart",
    chartCount: 10,
    key: "attendees",
    label: "Attendees",
    representativeText: "Running total",
  },
  {
    chartId: "total-views-monthly-chart",
    chartCount: 8,
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
  test("empty community analytics settles every tab", async ({
    adminEmptyCommunityPage,
  }) => {
    // Load analytics for the dedicated community without activity records.
    await navigateToPath(
      adminEmptyCommunityPage,
      "/dashboard/community?tab=analytics",
    );
    const dashboardContent = adminEmptyCommunityPage.locator(
      "#dashboard-content",
    );

    // Verify every tab resolves each chart to an explicit empty state.
    for (const analyticsTab of ANALYTICS_TABS) {
      await dashboardContent
        .locator(`button[data-analytics-tab="${analyticsTab.key}"]`)
        .first()
        .click();
      const tabContent = dashboardContent.locator(
        `[data-analytics-content="${analyticsTab.key}"]`,
      );
      await expect(tabContent).toBeVisible();
      await expect(tabContent.locator(".chart-empty-state")).toHaveCount(
        analyticsTab.chartCount,
      );
      await expect(tabContent.locator("[id$='-chart']")).toHaveCount(0);
    }
  });

  test("admin can switch between analytics tabs and view each section", async ({ adminCommunityPage }) => {
    // Load the community analytics dashboard before switching tabs.
    await navigateToPath(adminCommunityPage, "/dashboard/community?tab=analytics");

    // Find the dashboard content.
    const dashboardContent = adminCommunityPage.locator("#dashboard-content");

    // Verify admin can switch between analytics tabs and view each section.
    await expect(dashboardContent.getByText("Analytics", { exact: true })).toBeVisible();

    // Assert each expected case.
    for (const analyticsTab of ANALYTICS_TABS) {
      const tabButton = dashboardContent.locator(`button[data-analytics-tab="${analyticsTab.key}"]`).first();
      const tabContent = dashboardContent.locator(`[data-analytics-content="${analyticsTab.key}"]`);

      // Assert the expected content is visible.
      await expect(tabButton).toBeVisible();
      await expect(tabButton).toHaveClass(/xl:hover:border-primary-300/);
      await expect(tabButton).toHaveClass(/xl:hover:shadow-sm/);
      await tabButton.click();

      // Assert the rendered attribute value.
      await expect(tabButton).toHaveAttribute("data-active", "true");
      await expect(tabButton).not.toHaveClass(/outline-primary-200/);
      await expect(tabContent).toBeVisible();
      await expect(tabContent.getByText(analyticsTab.label, { exact: true }).first()).toBeVisible();
      await expect(tabContent.getByText(analyticsTab.representativeText, { exact: true })).toBeVisible();
      await expect(tabContent.locator(".chart-empty-state, [id$='-chart']")).toHaveCount(
        analyticsTab.chartCount,
      );
      await expectChartSettled(tabContent, analyticsTab.chartId);
    }
  });

  test("tablet analytics tabs expose every section", async ({ adminCommunityPage }) => {
    // The tab list only renders below xl and the dashboard needs md or more,
    // so exercise the tabbed layout at a tablet viewport instead of mobile.
    await adminCommunityPage.setViewportSize({ width: 1024, height: 800 });
    await navigateToPath(adminCommunityPage, "/dashboard/community?tab=analytics");

    // Find the mobile tab list and verify it is available.
    const dashboardContent = adminCommunityPage.locator("#dashboard-content");
    const mobileTabList = dashboardContent.getByRole("tablist", {
      name: "Analytics tabs",
    });
    await expect(mobileTabList).toBeVisible();

    // Open every tab and verify its corresponding analytics section.
    for (const analyticsTab of ANALYTICS_TABS) {
      const tabButton = mobileTabList.getByRole("button", {
        name: analyticsTab.label,
      });
      await tabButton.click();
      await expect(tabButton).toHaveAttribute("data-active", "true");
      await expect(dashboardContent.locator(`[data-analytics-content="${analyticsTab.key}"]`)).toBeVisible();
    }
  });
});
