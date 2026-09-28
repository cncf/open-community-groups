import { randomUUID } from "node:crypto";

import { queryE2eDatabase, queryE2eDatabaseRows } from "../database.js";
import { TEST_GROUP_IDS, TEST_USER_IDS } from "../seed.js";
import { cleanupEventsByIds } from "./events.js";

/**
 * Deletes co-hosted events plus the co-host rows and notifications they produced.
 * @param {string[]} eventIds - Exact event identifiers created by the scenario.
 */
export const cleanupCohostEvents = (eventIds) => {
  const ids = eventIds.filter(Boolean);
  if (ids.length === 0) {
    return;
  }

  const eventIdArray = `array[${ids.map((eventId) => `'${eventId}'::uuid`).join(", ")}]`;

  // Co-host emails only carry event names, so match both identifiers and unique names.
  queryE2eDatabase(`
    delete from notification n
    using notification_template_data ntd, event e
    where n.notification_template_data_id = ntd.notification_template_data_id
    and e.event_id = any(${eventIdArray})
    and (
      strpos(ntd.data::text, e.event_id::text) > 0
      or strpos(ntd.data::text, e.name) > 0
    );

    delete from event_cohost where event_id = any(${eventIdArray});
  `);
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
 *   cohosts?: Array<{ groupId: string, status?: "approved"|"canceled"|"pending"|"rejected" }>,
 *   days?: number,
 *   ownerGroupId?: string,
 *   published?: boolean
 * }} [options] - Event shape.
 * @returns {{ eventId: string, invitationIds: Record<string, string>, name: string, slug: string }}
 */
export const setupCohostEvent = ({
  cohosts = [],
  days = 200,
  ownerGroupId = TEST_GROUP_IDS.community1.alpha,
  published = false,
} = {}) => {
  const eventId = randomUUID();
  const suffix = eventId.replace(/-/g, "").slice(0, 8);
  const name = `E2E co-hosted event ${suffix}`;
  const slug = `e2e-cohosted-event-${suffix}`;
  const ticketTypeId = randomUUID();
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
  const cohostInsert =
    cohostValues.length > 0
      ? `insert into event_cohost (
           event_id, group_id, event_cohost_status_id, invitation_id, invited_by, approved_at, responded_at
         ) values ${cohostValues.join(", ")};`
      : "";

  queryE2eDatabase(`
    insert into event (
      event_id,
      name,
      slug,
      description,
      description_short,
      timezone,
      event_category_id,
      event_kind_id,
      group_id,
      published,
      published_at,
      published_by,
      starts_at,
      ends_at,
      meeting_join_url
    ) values (
      '${eventId}',
      '${name}',
      '${slug}',
      'Disposable event used by E2E co-hosting coverage.',
      'Disposable co-hosting coverage.',
      'UTC',
      (
        select ec.event_category_id
        from event_category ec
        join "group" g on g.community_id = ec.community_id
        where g.group_id = '${ownerGroupId}'::uuid
        order by ec.event_category_id
        limit 1
      ),
      'virtual',
      '${ownerGroupId}',
      ${published},
      ${published ? "current_timestamp" : "null"},
      ${published ? `'${TEST_USER_IDS.organizer1}'::uuid` : "null"},
      current_timestamp + interval '${days} days',
      current_timestamp + interval '${days} days 2 hours',
      'https://meet.example.com/e2e-cohosted-event'
    );

    insert into event_ticket_type (event_ticket_type_id, active, event_id, "order", seats_total, title)
    values ('${ticketTypeId}', true, '${eventId}', 1, 100, 'General admission');

    insert into event_ticket_price_window (event_ticket_price_window_id, amount_minor, event_ticket_type_id)
    values ('${randomUUID()}', 0, '${ticketTypeId}');

    ${cohostInsert}
  `);

  return { eventId, invitationIds, name, slug };
};
