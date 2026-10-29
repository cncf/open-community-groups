import { cleanupTemporaryCommunity, setupTemporaryCommunity } from "../../data-graphs/communities.js";
import { TEST_USER_IDS } from "../../seed.js";
import { selectCommunityContext } from "../../utils.js";
import { openDashboardView } from "../aria-helpers.js";

export { getDashboardMenu, getMobileNotice, openActionsMenu } from "../aria-helpers.js";

/**
 * Opens a community dashboard view, checks its layout with the header, the menu, the main content
 * area and the given regions as key regions, and returns the dashboard content.
 * @param {import("@playwright/test").Page} page - Page of the team member who sees the view.
 * @param {string} query - Query string after `/dashboard/community?`, such as `tab=groups`.
 * @param {{ menu?: boolean, regions?: import("@playwright/test").Locator[] }} [options] - Extra key
 *   regions; `menu: false` leaves out the menu, which is a closed drawer in the mobile layout.
 * @returns {Promise<import("@playwright/test").Locator>}
 */
export const openCommunityDashboardView = (page, query, options) =>
  openDashboardView(page, `/dashboard/community?${query}`, options);

/**
 * Creates a temporary community with the first admin as admin, removed when the test ends, and
 * selects it on the admin's page. Its views hold only the rows the test adds, so other tests never
 * change them; the community name ends in a random suffix the snapshots match with a regex.
 * @param {{ owned: object, page: import("@playwright/test").Page }} options - Owned data fixture
 *   and the first admin's page.
 * @returns {Promise<{ communityId: string, displayName: string, groupCategoryId: string }>}
 */
export const setupAriaCommunity = async ({ owned, page }) => {
  const community = owned.track(
    setupTemporaryCommunity({ label: "aria community", teamRole: "admin", userId: TEST_USER_IDS.admin1 }),
    ({ communityId }) => cleanupTemporaryCommunity(communityId),
  );
  await selectCommunityContext(page, community.communityId);
  return community;
};
