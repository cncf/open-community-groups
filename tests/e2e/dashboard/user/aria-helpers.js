import { openDashboardView } from "../aria-helpers.js";

export { getDashboardMenu, getMobileNotice, MOBILE_NOTICE } from "../aria-helpers.js";

/**
 * Opens a user dashboard view, checks its layout with the header, the menu, the main content area
 * and the given regions as key regions, and returns the dashboard content.
 * @param {import("@playwright/test").Page} page - Page of the user who sees the view.
 * @param {string} query - Query string after `/dashboard/user?`, such as `tab=events`.
 * @param {{ menu?: boolean, regions?: import("@playwright/test").Locator[] }} [options] - Extra key
 *   regions; `menu: false` leaves out the menu, which is a closed drawer in the mobile layout.
 * @returns {Promise<import("@playwright/test").Locator>}
 */
export const openUserDashboardView = (page, query, options) =>
  openDashboardView(page, `/dashboard/user?${query}`, options);
