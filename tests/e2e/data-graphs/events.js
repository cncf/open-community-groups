import { randomUUID } from "node:crypto";

import { queryE2eDatabase } from "../database.js";
import { TEST_USER_IDS } from "../seed.js";

const EVENT_CATEGORY_ID = "33333333-3333-3333-3333-333333333331";

/** Builds a UUID array literal for E2E SQL cleanup queries. */
const sqlArray = (values) => `array[${values.map((value) => `'${value}'::uuid`).join(", ")}]`;

/**
 * Deletes the event graph owned by a notification scenario.
 * @param {string[]} eventIds - Exact event identifiers created by the scenario.
 */
export const cleanupEventsByIds = (eventIds) => {
  if (eventIds.length === 0) {
    return;
  }

  const eventIdArray = sqlArray(eventIds);

  queryE2eDatabase(`
    do $$
    declare
      v_event_ids uuid[] := ${eventIdArray};
      v_event_series_ids uuid[];
    begin
      select coalesce(array_agg(distinct event_series_id), '{}')
      into v_event_series_ids
      from event
      where event_id = any(v_event_ids)
      and event_series_id is not null;

      delete from event_organizer where event_id = any(v_event_ids);
      delete from event_host where event_id = any(v_event_ids);
      delete from event_sponsor where event_id = any(v_event_ids);
      delete from event_speaker where event_id = any(v_event_ids);
      delete from event_waitlist where event_id = any(v_event_ids);
      delete from event_attendee where event_id = any(v_event_ids);
      delete from event_invitation_request where event_id = any(v_event_ids);
      delete from admission_offer where event_id = any(v_event_ids);
      delete from event_cfs_label where event_id = any(v_event_ids);
      delete from meeting where event_id = any(v_event_ids);

      -- Attending a ticketed event records a purchase; remove it and its dependents before tickets.
      delete from event_purchase_credit_note
      where event_purchase_refund_id in (
        select event_purchase_refund_id
        from event_purchase_refund
        where event_purchase_id in (
          select event_purchase_id from event_purchase where event_id = any(v_event_ids)
        )
      );
      delete from event_purchase_application_fee_adjustment
      where event_purchase_id in (
        select event_purchase_id from event_purchase where event_id = any(v_event_ids)
      );
      delete from event_purchase_refund
      where event_purchase_id in (
        select event_purchase_id from event_purchase where event_id = any(v_event_ids)
      );
      delete from payment_job
      where event_purchase_id in (
        select event_purchase_id from event_purchase where event_id = any(v_event_ids)
      );
      delete from event_refund_request
      where event_purchase_id in (
        select event_purchase_id from event_purchase where event_id = any(v_event_ids)
      );
      delete from event_purchase where event_id = any(v_event_ids);

      delete from event_ticket_price_window
      where event_ticket_type_id in (
        select event_ticket_type_id from event_ticket_type where event_id = any(v_event_ids)
      );
      delete from event_ticket_type where event_id = any(v_event_ids);
      delete from event where event_id = any(v_event_ids);
      delete from event_series where event_series_id = any(v_event_series_ids);
    end $$;
  `);
};

/**
 * Creates a published future alpha-group event with the exact recipient graph needed to
 * verify event cancellation notifications.
 * @param {{ groupId: string }} options - Group that owns the event.
 * @returns {{
 *   attendeeUserIds: string[],
 *   eventId: string,
 *   name: string,
 *   recipientUserIds: string[],
 *   speakerUserIds: string[],
 *   waitlistUserIds: string[]
 * }}
 */
export const setupCancelableEvent = ({ groupId }) => {
  const eventId = randomUUID();
  const priceWindowId = randomUUID();
  const suffix = eventId.replace(/-/g, "").slice(0, 8);
  const ticketTypeId = randomUUID();
  const name = `E2E cancelable event ${suffix}`;
  const slug = `e2e-cancelable-event-${suffix}`;
  const attendeeUserIds = [TEST_USER_IDS.member1, TEST_USER_IDS.member2];
  const waitlistUserIds = [TEST_USER_IDS.pending1];
  const speakerUserIds = [TEST_USER_IDS.pending2];
  const recipientUserIds = [...new Set([...attendeeUserIds, ...waitlistUserIds, ...speakerUserIds])];

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
      capacity,
      waitlist_enabled
    ) values (
      '${eventId}',
      '${name}',
      '${slug}',
      'Owned cancellation event used by E2E notification coverage.',
      'Owned cancellation event used by E2E notification coverage.',
      'UTC',
      '${EVENT_CATEGORY_ID}',
      'virtual',
      '${groupId}',
      true,
      current_timestamp,
      '${TEST_USER_IDS.organizer1}',
      current_timestamp + interval '180 days',
      current_timestamp + interval '180 days 2 hours',
      10,
      true
    );

    insert into event_ticket_type (
      event_ticket_type_id,
      active,
      event_id,
      "order",
      seats_total,
      title,
      description
    ) values (
      '${ticketTypeId}',
      true,
      '${eventId}',
      1,
      10,
      'General admission',
      'Disposable admission used by E2E notification coverage.'
    );

    insert into event_ticket_price_window (
      event_ticket_price_window_id,
      amount_minor,
      event_ticket_type_id,
      starts_at,
      ends_at
    ) values (
      '${priceWindowId}',
      0,
      '${ticketTypeId}',
      null,
      null
    );

    insert into event_attendee (event_id, user_id, status)
    select '${eventId}', unnest(${sqlArray(attendeeUserIds)}), 'confirmed';

    insert into event_waitlist (event_id, event_ticket_type_id, user_id)
    select '${eventId}', '${ticketTypeId}', unnest(${sqlArray(waitlistUserIds)});

    insert into event_speaker (event_id, user_id, featured)
    select '${eventId}', unnest(${sqlArray(speakerUserIds)}), true;

    insert into event_organizer (event_id, user_id, "order")
    values ('${eventId}', '${TEST_USER_IDS.organizer1}', 1);
  `);

  return {
    attendeeUserIds,
    eventId,
    name,
    recipientUserIds,
    speakerUserIds,
    waitlistUserIds,
  };
};

/**
 * Creates a future event for notification suppression checks.
 * @param {{
 *   attendeeUserIds?: string[],
 *   groupId: string,
 *   published?: boolean,
 *   testEvent?: boolean
 * }} options - Event shape.
 * @returns {{ attendeeUserIds: string[], eventId: string, name: string }}
 */
export const setupNotificationEvent = ({
  attendeeUserIds = [],
  groupId,
  published = false,
  testEvent = false,
}) => {
  const eventId = randomUUID();
  const priceWindowId = randomUUID();
  const suffix = eventId.replace(/-/g, "").slice(0, 8);
  const ticketTypeId = randomUUID();
  const name = `E2E notification event ${suffix}`;
  const slug = `e2e-notification-event-${suffix}`;

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
      capacity,
      test_event
    ) values (
      '${eventId}',
      '${name}',
      '${slug}',
      'Owned notification event used by E2E coverage.',
      'Owned notification event used by E2E coverage.',
      'UTC',
      '${EVENT_CATEGORY_ID}',
      'virtual',
      '${groupId}',
      ${published},
      ${published ? "current_timestamp" : "null"},
      ${published ? `'${TEST_USER_IDS.organizer1}'` : "null"},
      current_timestamp + interval '190 days',
      current_timestamp + interval '190 days 2 hours',
      10,
      ${testEvent}
    );

    insert into event_ticket_type (
      event_ticket_type_id,
      active,
      event_id,
      "order",
      seats_total,
      title,
      description
    ) values (
      '${ticketTypeId}',
      true,
      '${eventId}',
      1,
      10,
      'General admission',
      'Disposable admission used by E2E notification coverage.'
    );

    insert into event_ticket_price_window (
      event_ticket_price_window_id,
      amount_minor,
      event_ticket_type_id,
      starts_at,
      ends_at
    ) values (
      '${priceWindowId}',
      0,
      '${ticketTypeId}',
      null,
      null
    );

    insert into event_organizer (event_id, user_id, "order")
    values ('${eventId}', '${TEST_USER_IDS.organizer1}', 1);
  `);

  if (attendeeUserIds.length > 0) {
    queryE2eDatabase(`
      insert into event_attendee (event_id, user_id, status)
      select '${eventId}', unnest(${sqlArray(attendeeUserIds)}), 'confirmed';
    `);
  }

  return { attendeeUserIds, eventId, name };
};
