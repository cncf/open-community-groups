import { cleanupTemporaryGroup, setupTemporaryGroup } from "../../data-graphs/groups.js";
import { TEST_COMMUNITY_IDS, TEST_USER_IDS } from "../../seed.js";
import { selectGroupContext } from "../../utils.js";
import { openDashboardView } from "../aria-helpers.js";

export { getDashboardMenu, getMobileNotice, openActionsMenu } from "../aria-helpers.js";

/** Name, slug and fixed start (UTC) of the owned event `setupAriaEvent` adds to a temporary group. */
export const ARIA_EVENT = {
  name: "E2E ARIA event",
  slug: "e2e-aria-event",
  startsAt: "2035-06-15 18:00",
};

/**
 * Opens a group dashboard view, checks its layout with the header, the menu, the content and the
 * given regions as key regions, and returns the dashboard content.
 * @param {import("@playwright/test").Page} page - Page of the team member who sees the view.
 * @param {string} query - Query string after `/dashboard/group?`, such as `tab=events`.
 * @param {{ menu?: boolean, regions?: import("@playwright/test").Locator[] }} [options] - Extra key
 *   regions; `menu: false` leaves out the menu, which is a closed drawer in the mobile layout.
 * @returns {Promise<import("@playwright/test").Locator>}
 */
export const openGroupDashboardView = (page, query, options) =>
  openDashboardView(page, `/dashboard/group?${query}`, options);

/**
 * Adds a published virtual event to a temporary group, removed when the test ends. It starts on a
 * fixed far date, so rows and headers show no date that changes with the test day.
 * @param {{ groupId: string, owned: object } & Record<string, unknown>} options - Temporary group,
 *   owned data fixture, and other `insertOwnedEvent` options that replace the defaults.
 * @returns {{ eventId: string, name: string, slug: string, ticketTypeIds: Record<string, string> }}
 */
export const setupAriaEvent = ({ groupId, owned, ...options }) =>
  owned.event({
    groupId,
    name: ARIA_EVENT.name,
    slug: ARIA_EVENT.slug,
    startsAt: ARIA_EVENT.startsAt,
    ...options,
  });

/**
 * Creates a temporary group with the first organizer as admin, removed when the test ends, and
 * selects it on the organizer's page. Its views hold only the rows the test adds, so other tests
 * never change them; the group name ends in a random suffix the snapshots match with a regex.
 * @param {{
 *   memberUserId?: string,
 *   owned: object,
 *   page: import("@playwright/test").Page,
 *   withArtwork?: boolean
 * }} options - Owned data fixture, the first organizer's page, and an optional member and badge
 *   artwork.
 * @returns {Promise<{ groupId: string, groupName: string }>}
 */
export const setupAriaGroup = async ({ memberUserId, owned, page, withArtwork = false }) => {
  const group = owned.track(
    setupTemporaryGroup({
      memberUserId,
      teamRole: "admin",
      teamUserId: TEST_USER_IDS.organizer1,
      withArtwork,
    }),
    ({ groupId }) => cleanupTemporaryGroup(groupId),
  );
  await selectGroupContext(page, TEST_COMMUNITY_IDS.community1, group.groupId);
  return group;
};
