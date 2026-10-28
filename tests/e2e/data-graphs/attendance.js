import { queryE2eDatabase, sqlString } from "../database.js";
import { setupCompletedFreePurchases } from "./events.js";

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

/**
 * Creates one confirmed attendee holding a free ticket tier through a completed zero-amount
 * purchase, as attending a ticketed event does. Create the event with `owned.event`, whose
 * cleanup removes the attendee and purchase rows.
 * @param {{ checkedIn?: boolean, eventId: string, ticketTypeId: string, userId: string }} input -
 *   Attendee fields and the free tier the attendee holds.
 * @returns {{ eventId: string, ticketTypeId: string, userId: string }}
 */
export const setupOwnedTicketedAttendee = ({ checkedIn = false, eventId, ticketTypeId, userId }) => {
  setupOwnedAttendee({ checkedIn, eventId, userId });
  setupCompletedFreePurchases({ eventId, ticketTypeId, userIds: [userId] });

  return { eventId, ticketTypeId, userId };
};
