import { expect, test } from "../../../fixtures.js";

import { navigateToPath } from "../../../utils.js";

const ANALYTICS_TABS = [
  {
    key: "groups",
    label: "Groups",
    representativeText: "Running total",
  },
  {
    key: "members",
    label: "Members",
    representativeText: "Running total",
  },
  {
    key: "events",
    label: "Events",
    representativeText: "Running total",
  },
  {
    key: "attendees",
    label: "Attendees",
    representativeText: "Running total",
  },
  {
    key: "page-views",
    label: "Page views",
    representativeText: "Community page",
  },
];

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
    }
  });
});
