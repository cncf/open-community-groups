import { randomUUID } from "node:crypto";

import { queryE2eDatabase, queryE2eDatabaseRows } from "../database.js";
import { TEST_EVENT_CATEGORY_IDS, TEST_GROUP_IDS, TEST_USER_IDS } from "../seed.js";
import { cleanupEventsByIds, insertOwnedEvent } from "./events.js";

// Event categories of each seeded community, keyed like `TEST_GROUP_IDS`.
const COMMUNITY_EVENT_CATEGORY_IDS = {
  community1: TEST_EVENT_CATEGORY_IDS.general,
  community2: TEST_EVENT_CATEGORY_IDS.meetups,
};

/**
 * Deletes co-hosted events plus their co-host rows. The notifications they produced are left to
 * the `notifications` fixture, which also deletes their template data.
 * @param {string[]} eventIds - Exact event identifiers created by the scenario.
 */
export const cleanupCohostEvents = (eventIds) => {
  const ids = eventIds.filter(Boolean);
  if (ids.length === 0) {
    return;
  }

  const eventIdArray = `array[${ids.map((eventId) => `'${eventId}'::uuid`).join(", ")}]`;

  queryE2eDatabase(`delete from event_cohost where event_id = any(${eventIdArray});`);
  cleanupEventsByIds(ids);
};

/**
 * Returns the co-host audit actions recorded for one event in one group scope.
 * @param {string} eventId - Event identifier.
 * @param {string} groupId - Group whose audit scope is read.
 * @returns {string[]} Audit actions ordered by creation time.
 */
export const listCohostAuditActions = (eventId, groupId) =>
  queryE2eDatabaseRows(`
    select action
    from audit_log
    where event_id = '${eventId}'::uuid
    and group_id = '${groupId}'::uuid
    and action like 'event_cohost_%'
    order by created_at, audit_log_id
  `).map(([action]) => action);

/**
 * Returns the stored co-hosts revision for one event.
 * @param {string} eventId - Co-hosted event identifier.
 * @returns {string} Revision number as returned by psql.
 */
export const readCohostsRevision = (eventId) =>
  queryE2eDatabase(`select cohosts_revision from event where event_id = '${eventId}'::uuid`);

/**
 * Returns the stored co-host status for one event and group.
 * @param {string} eventId - Co-hosted event identifier.
 * @param {string} groupId - Co-host group identifier.
 * @returns {string} Co-host status identifier, or an empty string when absent.
 */
export const readCohostStatus = (eventId, groupId) =>
  queryE2eDatabase(`
    select coalesce(
      (
        select event_cohost_status_id
        from event_cohost
        where event_id = '${eventId}'::uuid
        and group_id = '${groupId}'::uuid
      ),
      ''
    )
  `);

/**
 * Creates a future virtual event owned by one group with co-host invitations in given states.
 * @param {{
 *   attendeeUserIds?: string[],
 *   cohosts?: Array<{ groupId: string, status?: "approved"|"canceled"|"pending"|"rejected" }>,
 *   days?: number,
 *   ownerGroupId?: string,
 *   published?: boolean
 * }} [options] - Event shape.
 * @returns {{ eventId: string, invitationIds: Record<string, string>, name: string, slug: string }}
 */
export const setupCohostEvent = ({
  attendeeUserIds = [],
  cohosts = [],
  days = 200,
  ownerGroupId = TEST_GROUP_IDS.community1.alpha,
  published = false,
} = {}) => {
  const eventId = randomUUID();
  const suffix = eventId.replace(/-/g, "").slice(0, 8);
  const name = `E2E co-hosted event ${suffix}`;
  const slug = `e2e-cohosted-event-${suffix}`;
  const invitationIds = Object.fromEntries(cohosts.map(({ groupId }) => [groupId, randomUUID()]));
  const cohostValues = cohosts.map(
    ({ groupId, status = "pending" }) => `(
      '${eventId}',
      '${groupId}',
      '${status}',
      '${invitationIds[groupId]}',
      '${TEST_USER_IDS.organizer1}',
      ${status === "approved" || status === "canceled" ? "current_timestamp" : "null"},
      ${status === "pending" ? "null" : "current_timestamp"}
    )`,
  );

  insertOwnedEvent({
    attendeeUserIds,
    categoryId: getOwnerEventCategoryId(ownerGroupId),
    description: "Disposable event used by E2E co-hosting coverage.",
    descriptionShort: "Disposable co-hosting coverage.",
    eventId,
    groupId: ownerGroupId,
    meetingJoinUrl: "https://meet.example.com/e2e-cohosted-event",
    name,
    organizerUserIds: [],
    published,
    slug,
    startsIn: `${days} days`,
    tiers: [{ key: "general", seats: 100, title: "General admission" }],
  });

  if (cohostValues.length > 0) {
    try {
      queryE2eDatabase(`
        insert into event_cohost (
          event_id, group_id, event_cohost_status_id, invitation_id, invited_by, approved_at, responded_at
        ) values ${cohostValues.join(", ")};
      `);
    } catch (error) {
      cleanupEventsByIds([eventId]);
      throw error;
    }
  }

  return { eventId, invitationIds, name, slug };
};

/**
 * Returns the event category of the seeded community that owns a seeded group.
 * @param {string} groupId - Seeded group identifier.
 * @returns {string} Event category identifier.
 */
const getOwnerEventCategoryId = (groupId) => {
  const community = Object.keys(TEST_GROUP_IDS).find((key) =>
    Object.values(TEST_GROUP_IDS[key]).includes(groupId),
  );
  if (community === undefined) {
    throw new Error(`setupCohostEvent: ${groupId} is not a seeded group`);
  }

  return COMMUNITY_EVENT_CATEGORY_IDS[community];
};
