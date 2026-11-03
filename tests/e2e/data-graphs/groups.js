import { randomUUID } from "node:crypto";

import { queryE2eDatabase, queryE2eDatabaseRows, sqlString, sqlUuid } from "../database.js";
import { TEST_COMMUNITY_IDS, TEST_GROUP_CATEGORY_IDS } from "../seed.js";
import { shortId, uniqueName } from "../utils.js";
import { cleanupEventsByIds } from "./events.js";

/** Badge artwork file name registered by `setupTemporaryGroup({ withArtwork: true })`. */
export const BADGE_ARTWORK_FILE_NAME = "e2e-disposable-badge.png";

/** Logo of sponsors created by `setupGroupSponsor`, served from the e2e static images. */
const SPONSOR_LOGO_URL = "/static/images/e2e/sponsor-logo.svg";

/**
 * Deletes custom notifications with an exact subject.
 * @param {string} subject - Unique subject sent by the test.
 */
export const cleanupGroupCustomNotificationsBySubject = (subject) => {
  queryE2eDatabase(`delete from custom_notification where subject = ${sqlString(subject)};`);
};

/**
 * Deletes a group membership a test created, for user-group pairs without a seeded membership.
 * @param {{ groupId: string, userId: string }} options - Membership identifiers.
 */
export const cleanupGroupMember = ({ groupId, userId }) => {
  queryE2eDatabase(`
    delete from group_member
    where group_id = ${sqlUuid(groupId)}
    and user_id = ${sqlUuid(userId)};
  `);
};

/**
 * Deletes a group sponsor a test created with `setupGroupSponsor`.
 * @param {{ sponsorId: string }} sponsor - Sponsor identifier.
 */
export const cleanupGroupSponsor = ({ sponsorId }) => {
  queryE2eDatabase(`delete from group_sponsor where group_sponsor_id = ${sqlUuid(sponsorId)};`);
};

/**
 * Deletes a temporary group, its inbox conversations and events, and its badge, sponsor,
 * notification, member and team rows.
 * @param {string} groupId - Group created by `setupTemporaryGroup` or through the dashboard.
 */
export const cleanupTemporaryGroup = (groupId) => {
  queryE2eDatabase(`
    delete from inbox_message
    where inbox_conversation_id in (
      select inbox_conversation_id from inbox_conversation where group_id = ${sqlUuid(groupId)}
    );
    delete from inbox_conversation where group_id = ${sqlUuid(groupId)};
  `);
  cleanupEventsByIds(eventIdsByGroup(groupId));

  queryE2eDatabase(`
    delete from badge where group_id = ${sqlUuid(groupId)};
    delete from badge_artwork where group_id = ${sqlUuid(groupId)};
    delete from group_sponsor where group_id = ${sqlUuid(groupId)};
    delete from custom_notification where group_id = ${sqlUuid(groupId)};
    delete from group_member where group_id = ${sqlUuid(groupId)};
    delete from group_team where group_id = ${sqlUuid(groupId)};
    delete from "group" where group_id = ${sqlUuid(groupId)};
  `);
};

/**
 * Returns the IDs of every event, deleted or not, that belongs to a group.
 * @param {string} groupId - Group identifier.
 * @returns {string[]}
 */
export const eventIdsByGroup = (groupId) =>
  queryE2eDatabaseRows(`select event_id from event where group_id = ${sqlUuid(groupId)};`).map(
    ([eventId]) => eventId,
  );

/**
 * Creates a featured sponsor in a group. Release it with `cleanupGroupSponsor`.
 * @param {{ groupId: string }} options - Group that owns the sponsor.
 * @returns {{ name: string, sponsorId: string }}
 */
export const setupGroupSponsor = ({ groupId }) => {
  const sponsorId = randomUUID();
  const name = uniqueName("sponsor");

  queryE2eDatabase(`
    insert into group_sponsor (group_sponsor_id, group_id, name, logo_url, featured)
    values (
      ${sqlUuid(sponsorId)},
      ${sqlUuid(groupId)},
      ${sqlString(name)},
      ${sqlString(SPONSOR_LOGO_URL)},
      true
    );
  `);

  return { name, sponsorId };
};

/**
 * Creates a temporary group, active and in the primary community unless told otherwise, with
 * optional region, team member, group member and badge artwork rows. Release it with
 * `cleanupTemporaryGroup`.
 * @param {{
 *   active?: boolean,
 *   communityId?: string,
 *   groupCategoryId?: string,
 *   memberUserId?: string,
 *   regionId?: string,
 *   teamRole?: string,
 *   teamUserId?: string,
 *   withArtwork?: boolean
 * }} [options] - Status, community with one of its group categories, region, accepted team row
 *   (`teamRole` for `teamUserId`), group member and artwork.
 * @returns {{ groupId: string, groupName: string, slug: string }}
 */
export const setupTemporaryGroup = ({
  active = true,
  communityId = TEST_COMMUNITY_IDS.community1,
  groupCategoryId = TEST_GROUP_CATEGORY_IDS.one,
  memberUserId,
  regionId = null,
  teamRole,
  teamUserId,
  withArtwork = false,
} = {}) => {
  const groupId = randomUUID();
  const groupName = uniqueName("temporary group");
  const slug = `e2e-temporary-group-${shortId(groupId)}`;
  const teamInsert = teamRole
    ? `insert into group_team (group_id, user_id, accepted, role, "order")
       values (${sqlUuid(groupId)}, ${sqlUuid(teamUserId)}, true, ${sqlString(teamRole)}, 1);`
    : "";
  const memberInsert = memberUserId
    ? `insert into group_member (group_id, user_id) values (${sqlUuid(groupId)}, ${sqlUuid(memberUserId)});`
    : "";
  const artworkInsert = withArtwork
    ? `insert into badge_artwork (badge_artwork_id, file_name, group_id)
       values (${sqlUuid(randomUUID())}, ${sqlString(BADGE_ARTWORK_FILE_NAME)}, ${sqlUuid(groupId)});`
    : "";

  queryE2eDatabase(`
    insert into "group" (
      group_id,
      community_id,
      group_category_id,
      name,
      slug,
      description,
      active,
      region_id
    ) values (
      ${sqlUuid(groupId)},
      ${sqlUuid(communityId)},
      ${sqlUuid(groupCategoryId)},
      ${sqlString(groupName)},
      ${sqlString(slug)},
      'Temporary group owned by E2E coverage.',
      ${active},
      ${regionId ? sqlUuid(regionId) : "null"}
    );

    ${teamInsert}
    ${memberInsert}
    ${artworkInsert}
  `);

  return { groupId, groupName, slug };
};
