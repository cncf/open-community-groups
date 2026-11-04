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
      await expect(tabButton).toHaveAttribute("aria-selected", "true");
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

    // Verify the summary cards are plain stat cards while the tab list is shown.
    await expect(dashboardContent.getByRole("tablist")).toHaveCount(1);
    await expect(dashboardContent.getByRole("group", { name: "Analytics summary" })).toBeVisible();
    await expect(dashboardContent.getByRole("tab")).toHaveCount(ANALYTICS_TABS.length);

    // Open every tab and verify its corresponding analytics section.
    for (const analyticsTab of ANALYTICS_TABS) {
      const tabButton = mobileTabList.getByRole("tab", {
        name: analyticsTab.label,
      });
      await tabButton.click();
      await expect(tabButton).toHaveAttribute("aria-selected", "true");
      await expect(dashboardContent.getByRole("tabpanel", { name: analyticsTab.label })).toBeVisible();
    }

    // Verify the tab list fits without scrolling and shows the full active underline.
    await expectTabListFits(mobileTabList);

    // Move between the tabs with the arrow, Home and End keys.
    await mobileTabList.getByRole("tab", { exact: true, name: "Groups" }).click();
    await adminCommunityPage.keyboard.press("ArrowRight");
    await expectKeyboardSelectedTab(dashboardContent, mobileTabList, "Members");
    await adminCommunityPage.keyboard.press("End");
    await expectKeyboardSelectedTab(dashboardContent, mobileTabList, "Page views");
    await adminCommunityPage.keyboard.press("Home");
    await expectKeyboardSelectedTab(dashboardContent, mobileTabList, "Groups");
    await adminCommunityPage.keyboard.press("ArrowLeft");
    await expectKeyboardSelectedTab(dashboardContent, mobileTabList, "Page views");

    // Verify the narrowest md viewport also fits the tab list with the last tab active.
    await adminCommunityPage.setViewportSize({ width: 768, height: 800 });
    await expect(mobileTabList).toBeVisible();
    await expectTabListFits(mobileTabList);
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

/**
 * Verifies a keyboard-selected analytics tab is focused, selected, in the tab order and showing its panel.
 * @param {import("@playwright/test").Locator} dashboardContent - Dashboard content region.
 * @param {import("@playwright/test").Locator} tabList - Analytics tab list.
 * @param {string} name - Accessible name of the expected tab.
 * @returns {Promise<void>}
 */
const expectKeyboardSelectedTab = async (dashboardContent, tabList, name) => {
  const tab = tabList.getByRole("tab", { exact: true, name });

  await expect(tab).toBeFocused();
  await expect(tab).toHaveAttribute("aria-selected", "true");
  await expect(tab).toHaveAttribute("tabindex", "0");
  await expect(tabList.locator('[role="tab"][tabindex="0"]')).toHaveCount(1);
  await expect(dashboardContent.getByRole("tabpanel", { exact: true, name })).toBeVisible();
};

/**
 * Verifies the analytics tab list wrapper does not scroll and does not clip the active tab underline.
 * @param {import("@playwright/test").Locator} tabList - Analytics tab list.
 * @returns {Promise<void>}
 */
const expectTabListFits = async (tabList) => {
  await expect
    .poll(() =>
      tabList.evaluate((list) => {
        const wrapper = list.parentElement;
        const activeTab = list.querySelector('[role="tab"][aria-selected="true"]');
        const wrapperBottom = wrapper.getBoundingClientRect().top + wrapper.clientTop + wrapper.clientHeight;

        return {
          scrollsHorizontally: wrapper.scrollWidth > wrapper.clientWidth,
          underlineClipped: activeTab.getBoundingClientRect().bottom > wrapperBottom + 0.5,
        };
      }),
    )
    .toEqual({ scrollsHorizontally: false, underlineClipped: false });
};
