import { expect } from "../fixtures.js";
import { expectPageLayout } from "../snapshots.js";
import { navigateToPath } from "../utils.js";

// Shown instead of the dashboard content on mobile, except on the Check-In tabs.
export const MOBILE_NOTICE = "This dashboard is not optimized yet for mobile devices";

/**
 * Returns the dashboard menu, a navigation landmark on every viewport.
 * @param {import("@playwright/test").Page} page - Dashboard page.
 * @returns {import("@playwright/test").Locator}
 */
export const getDashboardMenu = (page) => page.getByRole("navigation", { name: "Dashboard navigation" });

/**
 * Returns the box of the mobile notice that replaces the dashboard content.
 * @param {import("@playwright/test").Page} page - Dashboard page.
 * @returns {import("@playwright/test").Locator}
 */
export const getMobileNotice = (page) => page.getByText(MOBILE_NOTICE, { exact: true }).locator("..");

/**
 * Opens the row actions dropdown whose trigger has the given accessible name, checks the layout
 * with the dropdown as a key region and returns it.
 * @param {import("@playwright/test").Page} page - Page showing the row.
 * @param {string} label - Accessible name of the trigger, unique on the page, such as
 *   `Open actions for <event>`.
 * @returns {Promise<import("@playwright/test").Locator>}
 */
export const openActionsMenu = async (page, label) => {
  const trigger = page.locator(`[aria-label="${label}"]`);
  const dropdown = trigger.locator("xpath=..").locator(".dropdown");
  await trigger.click();
  await expect(dropdown).toBeVisible();
  await expectPageLayout(page, { regions: [dropdown] });
  return dropdown;
};

/**
 * Opens a dashboard view, checks its layout with the header, the menu, the main content area and
 * the given regions as key regions, and returns the dashboard content. The main area is checked
 * instead of the content, which the group and community dashboards lay out with `display: contents`.
 * @param {import("@playwright/test").Page} page - Page of the user who sees the view.
 * @param {string} path - Dashboard path with its query, such as `/dashboard/user?tab=events`.
 * @param {{ menu?: boolean, regions?: import("@playwright/test").Locator[] }} [options] - Extra key
 *   regions; `menu: false` leaves out the menu, which is a closed drawer in the mobile layout.
 * @returns {Promise<import("@playwright/test").Locator>}
 */
export const openDashboardView = async (page, path, { menu = true, regions = [] } = {}) => {
  const content = page.locator("#dashboard-content");
  await navigateToPath(page, path);
  await expect(content).toBeVisible();
  await expectPageLayout(page, {
    regions: [
      page.locator("#dashboard-header"),
      ...(menu ? [getDashboardMenu(page)] : []),
      page.locator("#dashboard-main-content"),
      ...regions,
    ],
  });
  return content;
};
