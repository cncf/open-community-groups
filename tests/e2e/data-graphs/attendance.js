import { queryE2eDatabase } from "../database.js";

/**
 * Deletes one owned attendee row.
 * @param {{ eventId?: string, userId?: string }} ids - Owned attendee identity.
 * @returns {void}
 */
export const cleanupOwnedAttendee = ({ eventId, userId }) => {
  if (!eventId || !userId) {
    return;
  }

  queryE2eDatabase(`
    delete from event_attendee
    where event_id = ${sqlString(eventId)}::uuid
    and user_id = ${sqlString(userId)}::uuid;
  `);
};

/**
 * Creates one confirmed attendee row owned by an E2E scenario.
 * @param {{ checkedIn?: boolean, eventId: string, userId: string }} input - Attendee fields.
 * @returns {{ eventId: string, userId: string }}
 */
export const setupOwnedAttendee = ({ checkedIn = false, eventId, userId }) => {
  cleanupOwnedAttendee({ eventId, userId });

  queryE2eDatabase(`
    insert into event_attendee (
      event_id,
      user_id,
      checked_in,
      checked_in_at,
      manually_invited,
      status
    ) values (
      ${sqlString(eventId)}::uuid,
      ${sqlString(userId)}::uuid,
      ${checkedIn ? "true" : "false"},
      ${checkedIn ? "current_timestamp - interval '15 minutes'" : "null"},
      false,
      'confirmed'
    );
  `);

  return { eventId, userId };
};

/** Escapes a value for embedding in E2E SQL. */
const sqlString = (value) => `'${String(value).replaceAll("'", "''")}'`;
