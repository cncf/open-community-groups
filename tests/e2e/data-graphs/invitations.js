import { queryCount, queryE2eDatabase, sqlString, sqlUuid } from "../database.js";
import { TEST_USER_IDS } from "../seed.js";

/**
 * Removes a pending community team invitation by exact owner identifiers.
 * @param {{ communityId: string, userId: string }} options - Invitation owner identifiers.
 */
export const cleanupCommunityTeamInvitation = ({ communityId, userId }) => {
  queryE2eDatabase(`
    delete from community_team
    where community_id = ${sqlUuid(communityId)}
    and user_id = ${sqlUuid(userId)}
    and accepted = false;
  `);
};

/**
 * Removes every attendee, purchase, offer, waitlist and invitation request row of an event-user
 * pair, leaving the pair without enrollment state. Covers event invitations and attend/leave flows,
 * where leaving keeps the attendee as canceled and the purchase as refunded.
 * @param {{ eventId: string, userId: string }} options - Event-user pair identifiers.
 */
export const cleanupEventEnrollment = ({ eventId, userId }) => {
  queryE2eDatabase(clearEventUserEnrollmentSql({ eventId, userId }));
};

/**
 * Removes a pending group team invitation by exact owner identifiers.
 * @param {{ groupId: string, userId: string }} options - Invitation owner identifiers.
 */
export const cleanupGroupTeamInvitation = ({ groupId, userId }) => {
  queryE2eDatabase(`
    delete from group_team
    where group_id = ${sqlUuid(groupId)}
    and user_id = ${sqlUuid(userId)}
    and accepted = false;
  `);
};

/**
 * Removes a group team row a test added, whether its invitation is still pending or was accepted.
 * Only for pairs without a seeded team row.
 * @param {{ groupId: string, userId: string }} options - Team member identifiers.
 */
export const cleanupGroupTeamMember = ({ groupId, userId }) => {
  queryE2eDatabase(`
    delete from group_team
    where group_id = ${sqlUuid(groupId)}
    and user_id = ${sqlUuid(userId)};
  `);
};

/**
 * Counts the team invitation audit rows of one action a user recorded in a community or group
 * scope. Audit rows are never cleaned, so compare counts before and after an action.
 * @param {{ action: string, communityId?: string, groupId?: string, userId: string }} options -
 *   Audit action, actor and exactly one scope identifier.
 * @returns {number} Matching audit row count.
 */
export const countTeamInvitationAuditLogs = ({ action, communityId, groupId, userId }) => {
  const scopeFilter = groupId
    ? `and group_id = ${sqlUuid(groupId)}`
    : `and community_id = ${sqlUuid(communityId)}`;

  return queryCount(`
    select count(*)
    from audit_log
    where action = ${sqlString(action)}
    and actor_user_id = ${sqlUuid(userId)}
    ${scopeFilter};
  `);
};

/**
 * Creates or resets a pending community team invitation with the given role. Enqueues no
 * notification or audit row.
 * @param {{ communityId: string, role: string, userId: string }} options - Invitation shape.
 */
export const setupCommunityTeamInvitation = ({ communityId, role, userId }) => {
  queryE2eDatabase(`
    insert into community_team (accepted, community_id, role, user_id)
    values (false, ${sqlUuid(communityId)}, ${sqlString(role)}, ${sqlUuid(userId)})
    on conflict (community_id, user_id) do update
    set accepted = false, role = excluded.role;
  `);
};

/**
 * Creates a pending organizer invitation offer for an event-user pair after clearing the pair's
 * enrollment state. The offer is issued by organizer1 for the event's first ticket type at its
 * current price and expires in 7 days. Enqueues no notification or audit row.
 * @param {{ eventId: string, userId: string }} options - Event-user pair identifiers.
 */
export const setupEventInvitation = ({ eventId, userId }) => {
  queryE2eDatabase(`
    ${clearEventUserEnrollmentSql({ eventId, userId })}

    insert into admission_offer (
      amount_minor,
      currency_code,
      discount_amount_minor,
      event_id,
      event_ticket_type_id,
      expires_at,
      organizer_user_id,
      source,
      status,
      ticket_title,
      user_id
    )
    select
      offer.amount_minor,
      case when offer.amount_minor > 0 then e.payment_currency_code end,
      0,
      e.event_id,
      ett.event_ticket_type_id,
      current_timestamp + interval '7 days',
      ${sqlUuid(TEST_USER_IDS.organizer1)},
      'organizer_invitation',
      'pending',
      ett.title,
      ${sqlUuid(userId)}
    from event e
    join lateral (
      select ett.*
      from event_ticket_type ett
      where ett.event_id = e.event_id
      order by ett."order", ett.event_ticket_type_id
      limit 1
    ) ett on true
    cross join lateral (
      select event_ticket_type_current_price(ett.event_ticket_type_id) as amount_minor
    ) offer
    where e.event_id = ${sqlUuid(eventId)};
  `);
};

/**
 * Creates or resets a pending group team invitation with the given role. Enqueues no notification
 * or audit row.
 * @param {{ groupId: string, role: string, userId: string }} options - Invitation shape.
 */
export const setupGroupTeamInvitation = ({ groupId, role, userId }) => {
  queryE2eDatabase(`
    insert into group_team (accepted, group_id, role, user_id)
    values (false, ${sqlUuid(groupId)}, ${sqlString(role)}, ${sqlUuid(userId)})
    on conflict (group_id, user_id) do update
    set accepted = false, role = excluded.role;
  `);
};

/**
 * Builds SQL that deletes the enrollment state of an event-user pair, purchase dependents first.
 * @param {{ eventId: string, userId: string }} options - Event-user pair identifiers.
 * @returns {string} SQL statements.
 */
const clearEventUserEnrollmentSql = ({ eventId, userId }) => {
  const pairPurchaseIds = `
    select event_purchase_id
    from event_purchase
    where event_id = ${sqlUuid(eventId)}
    and user_id = ${sqlUuid(userId)}
  `;

  return `
    delete from event_purchase_credit_note
    where event_purchase_refund_id in (
      select event_purchase_refund_id
      from event_purchase_refund
      where event_purchase_id in (${pairPurchaseIds})
    );
    delete from event_purchase_application_fee_adjustment
    where event_purchase_id in (${pairPurchaseIds});
    delete from event_purchase_refund where event_purchase_id in (${pairPurchaseIds});
    delete from payment_job where event_purchase_id in (${pairPurchaseIds});
    delete from event_refund_request where event_purchase_id in (${pairPurchaseIds});
    delete from event_purchase
    where event_id = ${sqlUuid(eventId)}
    and user_id = ${sqlUuid(userId)};

    delete from admission_offer
    where event_id = ${sqlUuid(eventId)}
    and user_id = ${sqlUuid(userId)};
    delete from event_waitlist
    where event_id = ${sqlUuid(eventId)}
    and user_id = ${sqlUuid(userId)};
    delete from event_invitation_request
    where event_id = ${sqlUuid(eventId)}
    and user_id = ${sqlUuid(userId)};
    delete from event_attendee
    where event_id = ${sqlUuid(eventId)}
    and user_id = ${sqlUuid(userId)};
  `;
};
