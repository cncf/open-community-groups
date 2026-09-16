import { randomUUID } from "node:crypto";

import { queryE2eDatabase, queryE2eDatabaseRows } from "../database.js";

const DEFAULT_BADGE_ARTWORK_FILE_NAME = "e2e-disposable-badge.png";

/**
 * Deletes badge award jobs owned by a disposable badge definition.
 * @param {{ badgeId?: string, badgeAwardJobIds?: string[] }} ids - Owned job selectors.
 * @returns {void}
 */
export const cleanupBadgeAwardJobs = ({ badgeId, badgeAwardJobIds = [] }) => {
  const predicates = [
    badgeId ? `badge_id = ${sqlString(badgeId)}::uuid` : "",
    badgeAwardJobIds.length > 0
      ? `badge_award_job_id in (${badgeAwardJobIds.map((id) => `${sqlString(id)}::uuid`).join(", ")})`
      : "",
  ].filter(Boolean);

  if (predicates.length === 0) {
    return;
  }

  queryE2eDatabase(`
    delete from badge_award_job_recipient
    where badge_award_job_id in (
      select badge_award_job_id
      from badge_award_job
      where ${predicates.join(" or ")}
    );

    delete from badge_award_job
    where ${predicates.join(" or ")};
  `);
};

/**
 * Deletes a disposable badge definition and its owned status list or credential rows.
 * @param {{
 *   badgeCreated?: boolean,
 *   badgeId?: string,
 *   badgeStatusListId?: string,
 *   userBadgeId?: string
 * }} ids - Owned IDs.
 * @returns {void}
 */
export const cleanupCredential = ({ badgeCreated = true, badgeId, badgeStatusListId, userBadgeId }) => {
  if (userBadgeId) {
    queryE2eDatabase(`delete from user_badge where user_badge_id = ${sqlString(userBadgeId)}::uuid;`);
  } else if (badgeCreated && badgeId) {
    queryE2eDatabase(`delete from user_badge where badge_id = ${sqlString(badgeId)}::uuid;`);
  }

  if (badgeCreated && badgeId) {
    cleanupBadgeDefinition({ badgeId });
  }

  if (badgeStatusListId) {
    queryE2eDatabase(`
      delete from badge_status_list
      where badge_status_list_id = ${sqlString(badgeStatusListId)}::uuid;
    `);
  }
};

/**
 * Deletes a disposable badge definition.
 * @param {{ badgeId?: string }} ids - Owned definition ID.
 * @returns {void}
 */
export const cleanupBadgeDefinition = ({ badgeId }) => {
  if (!badgeId) {
    return;
  }

  queryE2eDatabase(`delete from badge where badge_id = ${sqlString(badgeId)}::uuid;`);
};

/**
 * Deletes an owned badge status list after any credentials using it have been removed.
 * @param {{ badgeStatusListId?: string }} ids - Owned status-list ID.
 * @returns {void}
 */
export const cleanupBadgeStatusList = ({ badgeStatusListId }) => {
  if (!badgeStatusListId) {
    return;
  }

  queryE2eDatabase(`
    delete from badge_status_list
    where badge_status_list_id = ${sqlString(badgeStatusListId)}::uuid;
  `);
};

/**
 * Creates a disposable badge definition for one group.
 * @param {{
 *   criteria?: string,
 *   description?: string,
 *   groupId: string,
 *   imageFileName?: string,
 *   name?: string
 * }} input - Definition fields.
 * @returns {{
 *   badgeCreated: boolean,
 *   badgeId: string,
 *   badgeName: string,
 *   groupId: string,
 *   imageFileName: string
 * }}
 */
export const setupBadgeDefinition = ({
  criteria = "Complete the disposable E2E badge scenario.",
  description = "Disposable badge definition created by an E2E scenario.",
  groupId,
  imageFileName = DEFAULT_BADGE_ARTWORK_FILE_NAME,
  name = uniqueBadgeName("Disposable Badge"),
}) => {
  const badgeId = randomUUID();

  queryE2eDatabase(`
    insert into badge (
      badge_id,
      criteria,
      description,
      group_id,
      image_file_name,
      name
    ) values (
      ${sqlString(badgeId)}::uuid,
      ${sqlString(criteria)},
      ${sqlString(description)},
      ${sqlString(groupId)}::uuid,
      ${sqlString(imageFileName)},
      ${sqlString(name)}
    );
  `);

  return {
    badgeId,
    badgeName: name,
    badgeCreated: true,
    groupId,
    imageFileName,
  };
};

/**
 * Creates an empty status list that the badge award worker will prefer for this group.
 * @param {{ groupId: string }} input - Status list group owner.
 * @returns {{ badgeStatusListId: string, groupId: string }}
 */
export const setupBadgeStatusList = ({ groupId }) => {
  const badgeStatusListId = randomUUID();

  queryE2eDatabase(`
    insert into badge_status_list (
      badge_status_list_id,
      allocation_offset,
      allocation_position,
      allocation_stride,
      group_id
    ) values (
      ${sqlString(badgeStatusListId)}::uuid,
      0,
      0,
      1,
      ${sqlString(groupId)}::uuid
    );
  `);

  return { badgeStatusListId, groupId };
};

/**
 * Creates a disposable active credential that can be permanently revoked and deleted.
 * @param {{ badgeId?: string, eventId?: string, groupId: string, userId: string }} input - Credential owner.
 * @returns {{
 *   badgeCreated: boolean,
 *   badgeId: string,
 *   badgeName: string,
 *   badgeStatusListId: string,
 *   groupId: string,
 *   userBadgeId: string,
 *   userId: string
 * }}
 */
export const setupRevocableCredential = ({ badgeId, eventId, groupId, userId }) => {
  const badge = badgeId
    ? { ...getBadgeDefinition({ badgeId, groupId }), badgeCreated: false }
    : setupBadgeDefinition({ groupId });
  const badgeStatusListId = randomUUID();
  const userBadgeId = randomUUID();

  queryE2eDatabase(`
    begin;

    insert into badge_status_list (
      badge_status_list_id,
      allocation_offset,
      allocation_position,
      allocation_stride,
      group_id
    ) values (
      ${sqlString(badgeStatusListId)}::uuid,
      0,
      1,
      1,
      ${sqlString(groupId)}::uuid
    );

    insert into user_badge (
      badge_status_list_id,
      display_order,
      group_id,
      is_listed,
      snapshot,
      status_list_index,
      user_badge_id,

      badge_id,
      event_id,
      user_id
    )
    select
      ${sqlString(badgeStatusListId)}::uuid,
      (
        select coalesce(max(existing.display_order) + 1, 0)
        from user_badge existing
        where existing.revoked_at is null
        and existing.user_id = ${sqlString(userId)}::uuid
      ),
      b.group_id,
      true,
      jsonb_build_object(
        'criteria', b.criteria,
        'description', b.description,
        'image_file_name', b.image_file_name,
        'issuer', jsonb_build_object(
          'community_id', c.community_id,
          'community_name', c.display_name,
          'group_id', g.group_id,
          'group_name', g.name
        ),
        'name', b.name
      ),
      0,
      ${sqlString(userBadgeId)}::uuid,

      b.badge_id,
      ${eventId ? `${sqlString(eventId)}::uuid` : "null::uuid"},
      ${sqlString(userId)}::uuid
    from badge b
    join "group" g on g.group_id = b.group_id
    join community c on c.community_id = g.community_id
    where b.badge_id = ${sqlString(badge.badgeId)}::uuid
    and b.group_id = ${sqlString(groupId)}::uuid;

    commit;
  `);

  return {
    ...badge,
    badgeStatusListId,
    eventId,
    userBadgeId,
    userId,
  };
};

/** Returns a badge row from the badge table for the seeded group. */
const getBadgeDefinition = ({ badgeId, groupId }) => {
  const [row] = queryE2eDatabaseRows(`
    select badge_id, name, image_file_name
    from badge
    where badge_id = ${sqlString(badgeId)}::uuid
    and group_id = ${sqlString(groupId)}::uuid
  `);

  if (!row) {
    throw new Error(`Badge ${badgeId} was not found in group ${groupId}`);
  }

  const [resolvedBadgeId, badgeName, imageFileName] = row;

  return {
    badgeId: resolvedBadgeId,
    badgeName,
    badgeCreated: false,
    groupId,
    imageFileName,
  };
};

/** Escapes a value for embedding in E2E SQL. */
const sqlString = (value) => `'${String(value).replaceAll("'", "''")}'`;

/** Builds a unique badge name for badge scenario fixtures. */
const uniqueBadgeName = (label) => `E2E ${label} ${randomUUID().replace(/-/g, "").slice(0, 8)}`;
