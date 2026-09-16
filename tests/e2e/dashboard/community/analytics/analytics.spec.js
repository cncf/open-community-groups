import { expect, test } from "../../../fixtures.js";
import { navigateToPath } from "../../../utils.js";

const ANALYTICS_TABS = [
  {
    chartCount: 8,
    chartIds: [
      "groups-category-chart",
      "groups-region-chart",
      "groups-running-chart",
      "groups-running-category-chart",
      "groups-running-region-chart",
      "groups-monthly-chart",
      "groups-monthly-category-chart",
      "groups-monthly-region-chart",
    ],
    key: "groups",
    label: "Groups",
    representativeText: "Running total",
  },
  {
    chartCount: 8,
    chartIds: [
      "members-category-chart",
      "members-region-chart",
      "members-running-chart",
      "members-running-category-chart",
      "members-running-region-chart",
      "members-monthly-chart",
      "members-monthly-category-chart",
      "members-monthly-region-chart",
    ],
    key: "members",
    label: "Members",
    representativeText: "Running total",
  },
  {
    chartCount: 11,
    chartIds: [
      "events-group-category-chart",
      "events-region-chart",
      "events-category-chart",
      "events-running-chart",
      "events-running-group-category-chart",
      "events-running-group-region-chart",
      "events-running-event-category-chart",
      "events-monthly-chart",
      "events-monthly-group-category-chart",
      "events-monthly-group-region-chart",
      "events-monthly-event-category-chart",
    ],
    key: "events",
    label: "Events",
    representativeText: "Running total",
  },
  {
    chartCount: 10,
    chartIds: [
      "attendees-category-chart",
      "attendees-region-chart",
      "attendees-running-chart",
      "attendees-running-group-category-chart",
      "attendees-running-group-region-chart",
      "attendees-running-event-category-chart",
      "attendees-monthly-chart",
      "attendees-monthly-group-category-chart",
      "attendees-monthly-group-region-chart",
      "attendees-monthly-event-category-chart",
    ],
    key: "attendees",
    label: "Attendees",
    representativeText: "Running total",
  },
  {
    chartCount: 8,
    chartIds: [],
    key: "page-views",
    label: "Page views",
    representativeText: "Community page",
  },
];

test.describe("community dashboard analytics view", () => {
  test("empty community analytics settles every tab", async ({ adminEmptyCommunityPage }) => {
    // Load analytics for the dedicated community without activity records.
    await navigateToPath(adminEmptyCommunityPage, "/dashboard/community?tab=analytics");
    const dashboardContent = adminEmptyCommunityPage.locator("#dashboard-content");

    // Verify every tab resolves each chart to an explicit empty state.
    for (const analyticsTab of ANALYTICS_TABS) {
      await dashboardContent.locator(`button[data-analytics-tab="${analyticsTab.key}"]`).first().click();
      const tabContent = dashboardContent.locator(`[data-analytics-content="${analyticsTab.key}"]`);
      await expect(tabContent).toBeVisible();
      await expect(tabContent.locator(".chart-empty-state")).toHaveCount(analyticsTab.chartCount);
      await expect(tabContent.locator(".chart-empty-state")).toHaveText(
        Array(analyticsTab.chartCount).fill("No data available yet"),
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
      for (const chartId of analyticsTab.chartIds) {
        await expectChartRendered(tabContent, chartId);
      }
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

/** Verifies the chart slot has rendered a non-empty chart. */
const expectChartRendered = async (container, chartId) => {
  const chart = container.locator(`#${chartId}`);

  await expect(chart).toBeVisible();
  await expect(chart).not.toHaveClass(/chart-empty-state/u);
  await expect(chart.locator("svg-spinner")).toHaveCount(0);
  await expect.poll(async () => chart.locator("canvas, svg").count()).toBeGreaterThan(0);
};
