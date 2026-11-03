import { queryE2eDatabase, sqlUuid } from "../database.js";
import { TEST_EVENT_IDS, TEST_USER_IDS } from "../seed.js";

/**
 * Resets the seeded waitlist lab event to its seeded shape: one seat held by organizer1 through a
 * confirmed attendee row and a completed zero-value purchase of the first ticket type, with no
 * waitlist entries, admission offers or invitation requests. Every other attendee, purchase and
 * purchase dependent of the event is deleted. The re-inserted attendee gets a new check-in code.
 * @returns {void}
 */
export const resetWaitlistLab = () => {
  queryE2eDatabase(`
    do $$
    declare
      v_event_id uuid := ${sqlUuid(TEST_EVENT_IDS.alpha.waitlistLab)};
      v_organizer_id uuid := ${sqlUuid(TEST_USER_IDS.organizer1)};
    begin
      -- Remove purchases and their dependents before the offers they reference.
      delete from event_purchase_credit_note
      where event_purchase_refund_id in (
        select event_purchase_refund_id
        from event_purchase_refund
        where event_purchase_id in (
          select event_purchase_id from event_purchase where event_id = v_event_id
        )
      );
      delete from event_purchase_application_fee_adjustment
      where event_purchase_id in (
        select event_purchase_id from event_purchase where event_id = v_event_id
      );
      delete from event_purchase_refund
      where event_purchase_id in (
        select event_purchase_id from event_purchase where event_id = v_event_id
      );
      delete from payment_job
      where event_purchase_id in (
        select event_purchase_id from event_purchase where event_id = v_event_id
      );
      delete from event_refund_request
      where event_purchase_id in (
        select event_purchase_id from event_purchase where event_id = v_event_id
      );
      delete from event_purchase where event_id = v_event_id;

      -- Remove queue, offer, request and attendance state.
      delete from event_waitlist where event_id = v_event_id;
      delete from admission_offer where event_id = v_event_id;
      delete from event_invitation_request where event_id = v_event_id;
      delete from event_attendee where event_id = v_event_id;

      -- Restore the seeded organizer seat that keeps the one-seat event full.
      insert into event_attendee (event_id, user_id)
      values (v_event_id, v_organizer_id);

      insert into event_purchase (
        amount_minor,
        currency_code,
        discount_amount_minor,
        event_id,
        event_ticket_type_id,
        status,
        ticket_title,
        user_id
      )
      select
        0,
        null,
        0,
        v_event_id,
        ett.event_ticket_type_id,
        'completed',
        ett.title,
        v_organizer_id
      from event_ticket_type ett
      where ett.event_id = v_event_id
      order by ett."order", ett.event_ticket_type_id
      limit 1;
    end $$;
  `);
};
