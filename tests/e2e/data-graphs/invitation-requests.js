import { queryE2eDatabase, sqlString } from "../database.js";
import {
  TEST_EVENT_IDS,
  TEST_REGISTRATION_WINDOW_EVENTS,
  TEST_TICKETING_EVENTS,
  TEST_USER_IDS,
} from "../seed.js";

// Fixed ID of the expired approval offer that `resetClosedRegistrationWindowRequests` recreates.
const CLOSED_APPROVAL_OFFER_ID = "59555555-5555-5555-5555-555555555905";

/** Removes the temporary request and offer used by disabled approval reissue coverage. */
export const cleanupDisabledApprovalExpiredOffer = () => {
  queryE2eDatabase(`
    delete from admission_offer
    where event_id = '${TEST_EVENT_IDS.alpha.one}'
    and user_id = '${TEST_USER_IDS.member2}';

    delete from event_invitation_request
    where event_id = '${TEST_EVENT_IDS.alpha.one}'
    and user_id = '${TEST_USER_IDS.member2}';
  `);
};

/** Removes the temporary request used by disabled approval tab coverage. */
export const cleanupReviewedInvitationRequest = () => {
  queryE2eDatabase(`
    delete from event_invitation_request
    where event_id = '${TEST_EVENT_IDS.alpha.one}'
    and user_id = '${TEST_USER_IDS.member2}';
  `);
};

/** Restores invitation review fixtures whose public registration window is closed. */
export const resetClosedRegistrationWindowRequests = () => {
  const eventId = TEST_REGISTRATION_WINDOW_EVENTS.approvalClosed.id;

  queryE2eDatabase(`
    delete from event_purchase
    where event_id = '${eventId}'
    and user_id in (
      '${TEST_USER_IDS.member1}',
      '${TEST_USER_IDS.pending1}',
      '${TEST_USER_IDS.pending2}'
    );

    delete from event_attendee
    where event_id = '${eventId}'
    and user_id in (
      '${TEST_USER_IDS.member1}',
      '${TEST_USER_IDS.pending1}',
      '${TEST_USER_IDS.pending2}'
    );

    delete from admission_offer
    where event_id = '${eventId}'
    and user_id in (
      '${TEST_USER_IDS.member1}',
      '${TEST_USER_IDS.pending1}',
      '${TEST_USER_IDS.pending2}'
    );

    update event_invitation_request
    set
      status = case
        when user_id = '${TEST_USER_IDS.member1}' then 'accepted'
        else 'pending'
      end,
      reviewed_at = case
        when user_id = '${TEST_USER_IDS.member1}' then current_timestamp - interval '2 days'
        else null
      end,
      reviewed_by = case
        when user_id = '${TEST_USER_IDS.member1}' then '${TEST_USER_IDS.organizer1}'::uuid
        else null
      end
    where event_id = '${eventId}'
    and user_id in (
      '${TEST_USER_IDS.member1}',
      '${TEST_USER_IDS.pending1}',
      '${TEST_USER_IDS.pending2}'
    );

    insert into admission_offer (
      admission_offer_id,
      created_at,
      amount_minor,
      currency_code,
      discount_amount_minor,
      event_id,
      event_ticket_type_id,
      expires_at,
      source,
      status,
      ticket_title,
      user_id
    ) values (
      '${CLOSED_APPROVAL_OFFER_ID}',
      current_timestamp - interval '2 days',
      null,
      null,
      null,
      '${eventId}',
      (
        select event_ticket_type_id
        from event_ticket_type
        where event_id = '${eventId}'
        order by "order"
        limit 1
      ),
      current_timestamp - interval '1 day',
      'approval',
      'expired',
      null,
      '${TEST_USER_IDS.member1}'
    );
  `);
};

/** Restores the pending approval request whose registration window opens later. */
export const resetFutureRegistrationWindowRequest = () => {
  const eventId = TEST_REGISTRATION_WINDOW_EVENTS.approvalFuture.id;

  queryE2eDatabase(`
    delete from event_purchase
    where event_id = '${eventId}'
    and user_id = '${TEST_USER_IDS.member1}';

    delete from event_attendee
    where event_id = '${eventId}'
    and user_id = '${TEST_USER_IDS.member1}';

    delete from admission_offer
    where event_id = '${eventId}'
    and user_id = '${TEST_USER_IDS.member1}';

    update event_invitation_request
    set
      status = 'pending',
      reviewed_at = null,
      reviewed_by = null
    where event_id = '${eventId}'
    and user_id = '${TEST_USER_IDS.member1}';
  `);
};

/**
 * Restores the Invitation Request Lifecycle Lab requests, offers, purchases and attendees from a
 * snapshot. Rows are deleted and re-inserted instead of updated because
 * `check_admission_offer_lifecycle` blocks backward offer status transitions.
 */
export const restoreInvitationRequestLifecycleLab = (snapshot) => {
  const eventId = TEST_TICKETING_EVENTS.invitationRequests.id;
  const snapshotRows = (table) => `${sqlString(snapshot)}::jsonb -> '${table}'`;
  const eventPurchaseIds = `select event_purchase_id from event_purchase where event_id = '${eventId}'`;

  queryE2eDatabase(`
    delete from event_purchase_credit_note
    where event_purchase_refund_id in (
      select event_purchase_refund_id
      from event_purchase_refund
      where event_purchase_id in (${eventPurchaseIds})
    );
    delete from event_purchase_application_fee_adjustment where event_purchase_id in (${eventPurchaseIds});
    delete from event_purchase_refund where event_purchase_id in (${eventPurchaseIds});
    delete from payment_job where event_purchase_id in (${eventPurchaseIds});
    delete from event_refund_request where event_purchase_id in (${eventPurchaseIds});
    delete from event_purchase where event_id = '${eventId}';
    delete from event_attendee where event_id = '${eventId}';
    delete from admission_offer where event_id = '${eventId}';
    delete from event_invitation_request where event_id = '${eventId}';

    insert into event_invitation_request
    select * from jsonb_populate_recordset(null::event_invitation_request, ${snapshotRows("event_invitation_request")});
    insert into admission_offer
    select * from jsonb_populate_recordset(null::admission_offer, ${snapshotRows("admission_offer")});
    insert into event_purchase
    select * from jsonb_populate_recordset(null::event_purchase, ${snapshotRows("event_purchase")});
    insert into event_attendee
    select * from jsonb_populate_recordset(null::event_attendee, ${snapshotRows("event_attendee")});
  `);
};

/** Records an accepted request with an expired approval offer on the Alpha event. */
export const setupDisabledApprovalExpiredOffer = () => {
  queryE2eDatabase(`
    insert into event_invitation_request (event_id, user_id, status, reviewed_at, reviewed_by)
    values (
      '${TEST_EVENT_IDS.alpha.one}',
      '${TEST_USER_IDS.member2}',
      'accepted',
      current_timestamp - interval '3 days',
      '${TEST_USER_IDS.organizer1}'
    )
    on conflict do nothing;

    insert into admission_offer (
      created_at,
      event_id,
      event_ticket_type_id,
      expires_at,
      source,
      status,
      user_id
    ) values (
      current_timestamp - interval '2 days',
      '${TEST_EVENT_IDS.alpha.one}',
      (
        select event_ticket_type_id
        from event_ticket_type
        where event_id = '${TEST_EVENT_IDS.alpha.one}'
        order by "order"
        limit 1
      ),
      current_timestamp - interval '1 day',
      'approval',
      'expired',
      '${TEST_USER_IDS.member2}'
    );
  `);
};

/** Records a rejected request on the Alpha event without enabling approval. */
export const setupReviewedInvitationRequest = () => {
  queryE2eDatabase(`
    insert into event_invitation_request (event_id, user_id, status, reviewed_at, reviewed_by)
    values (
      '${TEST_EVENT_IDS.alpha.one}',
      '${TEST_USER_IDS.member2}',
      'rejected',
      now(),
      '${TEST_USER_IDS.organizer1}'
    )
    on conflict do nothing;
  `);
};

/**
 * Captures the Invitation Request Lifecycle Lab requests, offers, purchases and attendees as JSON
 * text keyed by table, for `restoreInvitationRequestLifecycleLab`.
 */
export const snapshotInvitationRequestLifecycleLab = () => {
  const eventId = TEST_TICKETING_EVENTS.invitationRequests.id;
  const tableRows = (table) => `
    '${table}', (
      select coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb)
      from ${table} t
      where t.event_id = '${eventId}'
    )`;

  return queryE2eDatabase(`
    select jsonb_build_object(
      ${["admission_offer", "event_attendee", "event_invitation_request", "event_purchase"].map(tableRows).join(",")}
    )::text
  `);
};
