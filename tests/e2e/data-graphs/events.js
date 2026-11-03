import { randomUUID } from "node:crypto";

import { queryE2eDatabase, sqlString, sqlUuid, sqlUuidArray } from "../database.js";
import { TEST_EVENT_CATEGORY_IDS, TEST_USER_IDS } from "../seed.js";
import { shortId, uniqueName } from "../utils.js";
import { setupTemporaryUser } from "./users.js";

/**
 * Deletes the event graph owned by a notification scenario.
 * @param {string[]} eventIds - Exact event identifiers created by the scenario.
 */
export const cleanupEventsByIds = (eventIds) => {
  if (eventIds.length === 0) {
    return;
  }

  const eventIdArray = sqlUuidArray(eventIds);

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
      delete from event_label where event_id = any(v_event_ids);
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
      -- Claimed offers are referenced by their purchase.
      delete from admission_offer where event_id = any(v_event_ids);

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
 * Inserts an owned event graph in one transaction: the event, its ticket tiers and their price
 * windows, organizers, confirmed attendees, waitlist entries and featured speakers. Event
 * capacity is the sum of the tier seats. Every other event insert in the suite goes through this
 * primitive. Remove the graph with `cleanupEventsByIds([eventId])` or create it with `owned.event`.
 * @param {{
 *   approvalRequired?: boolean,
 *   attendeeUserIds?: string[],
 *   capacity?: number,
 *   categoryId?: string,
 *   description?: string,
 *   descriptionShort?: string | null,
 *   duration?: string,
 *   endsAt?: string,
 *   eventId?: string,
 *   groupId: string,
 *   kind?: "hybrid" | "in-person" | "virtual",
 *   meetingJoinUrl?: string | null,
 *   name?: string,
 *   organizerUserIds?: string[],
 *   paymentCurrencyCode?: string | null,
 *   published?: boolean,
 *   publishedAgo?: string | null,
 *   publishedBy?: string | null,
 *   registrationEndsAt?: string,
 *   registrationStartsAt?: string,
 *   slug?: string,
 *   speakerUserIds?: string[],
 *   startsAt?: string,
 *   startsIn?: string,
 *   testEvent?: boolean,
 *   tiers?: { amountMinor?: number, description?: string, key: string, seats: number, title: string }[],
 *   timezone?: string,
 *   waitlist?: string[],
 *   waitlistEnabled?: boolean
 * }} options - Event shape. `capacity` sizes the single default tier (key `general`) used when
 * `tiers` is omitted. Tiers are free unless `amountMinor` is positive; positive amounts require
 * `paymentCurrencyCode` (such as `USD`) and a currency requires a positive amount.
 * `startsAt`/`endsAt` and `registrationStartsAt`/`registrationEndsAt` are local timestamps
 * (`YYYY-MM-DD HH:MM`) in `timezone`; without `startsAt` the event starts `startsIn` (a SQL interval)
 * from now. A missing end is `duration` (a SQL interval) after the start. Registration is open
 * without a window when both registration bounds are omitted. A published event was published `publishedAgo` (a SQL
 * interval) before now, now when omitted, and has no `published_at` when it is null. `publishedBy`
 * defaults to organizer1 when published.
 * `waitlist` lists user IDs queued for the first tier, oldest first.
 * @returns {{ eventId: string, name: string, slug: string, ticketTypeIds: Record<string, string> }}
 */
export const insertOwnedEvent = ({
  approvalRequired = false,
  attendeeUserIds = [],
  capacity = 10,
  categoryId = TEST_EVENT_CATEGORY_IDS.general,
  description = "Owned event used by E2E coverage.",
  descriptionShort = description,
  duration = "2 hours",
  endsAt,
  eventId = randomUUID(),
  groupId,
  kind = "virtual",
  meetingJoinUrl = null,
  name,
  organizerUserIds = [TEST_USER_IDS.organizer1],
  paymentCurrencyCode = null,
  published = true,
  publishedAgo,
  publishedBy = published ? TEST_USER_IDS.organizer1 : null,
  registrationEndsAt,
  registrationStartsAt,
  slug,
  speakerUserIds = [],
  startsAt,
  startsIn = "30 days",
  testEvent = false,
  tiers = [{ key: "general", seats: capacity, title: "General admission" }],
  timezone = "UTC",
  waitlist = [],
  waitlistEnabled = false,
}) => {
  const identity = buildOwnedEventIdentity("owned event", eventId);
  const eventName = name ?? identity.name;
  const eventSlug = slug ?? identity.slug;
  const ownedTiers = tiers.map((tier, index) => ({
    amountMinor: 0,
    ...tier,
    order: index + 1,
    priceWindowId: randomUUID(),
    ticketTypeId: randomUUID(),
  }));
  const ticketTypeIds = Object.fromEntries(ownedTiers.map((tier) => [tier.key, tier.ticketTypeId]));

  if (ownedTiers.length === 0) {
    throw new Error("insertOwnedEvent: events require at least one ticket tier");
  }
  if (Object.keys(ticketTypeIds).length !== ownedTiers.length) {
    throw new Error("insertOwnedEvent: tier keys must be unique");
  }
  // Mirrors check_event_ticketing_consistency so a bad shape fails before the deferred trigger.
  if (ownedTiers.some((tier) => tier.amountMinor > 0) !== (paymentCurrencyCode !== null)) {
    throw new Error("insertOwnedEvent: positive tier amounts and paymentCurrencyCode go together");
  }

  const eventUuid = sqlUuid(eventId);
  const localTimestampSql = (value) =>
    value === undefined ? "null" : `(${sqlString(value)}::timestamp at time zone ${sqlString(timezone)})`;
  const startsAtSql = startsAt
    ? localTimestampSql(startsAt)
    : `(current_timestamp + ${sqlString(startsIn)}::interval)`;
  const endsAtSql = endsAt ? localTimestampSql(endsAt) : `${startsAtSql} + ${sqlString(duration)}::interval`;
  let publishedAtSql = "null";
  if (published && publishedAgo === undefined) {
    publishedAtSql = "current_timestamp";
  } else if (published && publishedAgo !== null) {
    publishedAtSql = `(current_timestamp - ${sqlString(publishedAgo)}::interval)`;
  }

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
      meeting_join_url,
      payment_currency_code,
      published,
      published_at,
      published_by,
      registration_starts_at,
      registration_ends_at,
      starts_at,
      ends_at,
      capacity,
      attendee_approval_required,
      test_event,
      waitlist_enabled
    ) values (
      ${eventUuid},
      ${sqlString(eventName)},
      ${sqlString(eventSlug)},
      ${sqlString(description)},
      ${descriptionShort === null ? "null" : sqlString(descriptionShort)},
      ${sqlString(timezone)},
      ${sqlUuid(categoryId)},
      ${sqlString(kind)},
      ${sqlUuid(groupId)},
      ${meetingJoinUrl === null ? "null" : sqlString(meetingJoinUrl)},
      ${paymentCurrencyCode === null ? "null" : sqlString(paymentCurrencyCode)},
      ${published},
      ${publishedAtSql},
      ${publishedBy === null ? "null" : sqlUuid(publishedBy)},
      ${localTimestampSql(registrationStartsAt)},
      ${localTimestampSql(registrationEndsAt)},
      ${startsAtSql},
      ${endsAtSql},
      ${ownedTiers.reduce((total, tier) => total + tier.seats, 0)},
      ${approvalRequired},
      ${testEvent},
      ${waitlistEnabled}
    );

    insert into event_ticket_type (
      event_ticket_type_id,
      active,
      event_id,
      "order",
      seats_total,
      title,
      description
    ) values ${ownedTiers
      .map(
        (tier) => `(
          ${sqlUuid(tier.ticketTypeId)},
          true,
          ${eventUuid},
          ${tier.order},
          ${tier.seats},
          ${sqlString(tier.title)},
          ${tier.description === undefined ? "null" : sqlString(tier.description)}
        )`,
      )
      .join(", ")};

    insert into event_ticket_price_window (event_ticket_price_window_id, amount_minor, event_ticket_type_id)
    values ${ownedTiers
      .map(
        (tier) =>
          `(${sqlUuid(tier.priceWindowId)}, ${Number(tier.amountMinor)}, ${sqlUuid(tier.ticketTypeId)})`,
      )
      .join(", ")};

    insert into event_organizer (event_id, user_id, "order")
    select ${eventUuid}, organizer.user_id, organizer.position::int
    from unnest(${sqlUuidArray(organizerUserIds)}) with ordinality as organizer(user_id, position);

    insert into event_attendee (event_id, user_id, status)
    select ${eventUuid}, user_id, 'confirmed'
    from unnest(${sqlUuidArray(attendeeUserIds)}) as user_id;

    -- Entries are a second apart in list order, so promotion order is deterministic.
    insert into event_waitlist (event_id, event_ticket_type_id, user_id, created_at)
    select
      ${eventUuid},
      ${sqlUuid(ownedTiers[0].ticketTypeId)},
      entry.user_id,
      current_timestamp - (${waitlist.length} - entry.position) * interval '1 second'
    from unnest(${sqlUuidArray(waitlist)}) with ordinality as entry(user_id, position);

    insert into event_speaker (event_id, user_id, featured)
    select ${eventUuid}, user_id, true
    from unnest(${sqlUuidArray(speakerUserIds)}) as user_id;
  `);

  return { eventId, name: eventName, slug: eventSlug, ticketTypeIds };
};

/**
 * Creates a published free virtual event 70 days ahead that requires organizer approval for
 * attendees, with only the default free tier. Inserting it published sends no notifications.
 * Release it with `cleanupEventsByIds([eventId])`.
 * @param {{ groupId: string, name: string }} options - Group that owns the event and its name.
 * @returns {{ eventId: string, name: string, slug: string, ticketTypeIds: Record<string, string> }}
 */
export const setupApprovalRequiredEvent = ({ groupId, name }) =>
  insertOwnedEvent({
    approvalRequired: true,
    description: "Owned approval-required event used by E2E invitation request coverage.",
    groupId,
    meetingJoinUrl: "https://meet.example.com/e2e-invitation-requests",
    name,
    startsIn: "70 days",
  });

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
  const attendeeUserIds = [TEST_USER_IDS.member1, TEST_USER_IDS.member2];
  const waitlistUserIds = [TEST_USER_IDS.pending1];
  const speakerUserIds = [TEST_USER_IDS.pending2];
  const recipientUserIds = [...new Set([...attendeeUserIds, ...waitlistUserIds, ...speakerUserIds])];
  const eventId = randomUUID();
  const { name, slug } = buildOwnedEventIdentity("cancelable event", eventId);

  // The full tier keeps the enrollment worker from promoting the queued user
  // into an admission offer before the test cancels the event.
  insertOwnedEvent({
    attendeeUserIds,
    description: "Owned cancellation event used by E2E notification coverage.",
    eventId,
    groupId,
    name,
    slug,
    speakerUserIds,
    startsIn: "180 days",
    tiers: [
      {
        description: "Disposable admission used by E2E notification coverage.",
        key: "general",
        seats: 0,
        title: "General admission",
      },
    ],
    waitlist: waitlistUserIds,
    waitlistEnabled: true,
  });

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
 * Creates a published free event starting tomorrow with one confirmed, not checked-in temporary
 * attendee. Release it with `cleanupEventsByIds([eventId])` and `cleanupTemporaryUser(userId)`.
 * @param {{ groupId: string }} options - Group that owns the event.
 * @returns {{ eventId: string, userId: string }}
 */
export const setupCheckInEventGraph = ({ groupId }) => {
  const eventId = randomUUID();
  const { userId } = setupTemporaryUser({ label: "check-in-attendee" });

  insertOwnedEvent({
    attendeeUserIds: [userId],
    description: "Temporary event owned by E2E check-in coverage.",
    eventId,
    groupId,
    name: uniqueName("check-in event"),
    organizerUserIds: [],
    publishedBy: null,
    slug: `e2e-check-in-event-${shortId(eventId)}`,
    startsIn: "1 day",
    tiers: [
      {
        description: "Temporary free admission used by E2E check-in coverage.",
        key: "general",
        seats: 500,
        title: "General Admission",
      },
    ],
  });

  return { eventId, userId };
};

/**
 * Records completed zero-value purchases of a free tier, as attending one does, so the attendees
 * hold its seats and a full tier stops waitlist promotion. `cleanupEventsByIds` removes them.
 * @param {{ eventId: string, ticketTypeId: string, userIds: string[] }} options - Seat holders.
 */
export const setupCompletedFreePurchases = ({ eventId, ticketTypeId, userIds }) => {
  queryE2eDatabase(`
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
      ett.event_id,
      ett.event_ticket_type_id,
      'completed',
      ett.title,
      buyer.user_id
    from event_ticket_type ett
    cross join unnest(${sqlUuidArray(userIds)}) as buyer(user_id)
    where ett.event_id = ${sqlUuid(eventId)}
    and ett.event_ticket_type_id = ${sqlUuid(ticketTypeId)};
  `);
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
  const { name, slug } = buildOwnedEventIdentity("notification event", eventId);

  insertOwnedEvent({
    attendeeUserIds,
    description: "Owned notification event used by E2E coverage.",
    eventId,
    groupId,
    name,
    published,
    slug,
    startsIn: "190 days",
    testEvent,
    tiers: [
      {
        description: "Disposable admission used by E2E notification coverage.",
        key: "general",
        seats: 10,
        title: "General admission",
      },
    ],
  });

  return { attendeeUserIds, eventId, name };
};

/**
 * Creates a future event whose only participants are the supplied organizers, confirmed attendees
 * and, when given, speakers and waitlisted users, so organizer badge awards and My Events roles stay
 * isolated. It is published unless `published` is false and starts in 20 days unless `startsAt` is
 * given. Its single tier (key `general`, 10 seats) is free unless `amountMinor` is positive, which
 * requires `paymentCurrencyCode`.
 * @param {{
 *   amountMinor?: number,
 *   attendeeUserIds?: string[],
 *   endsAt?: string,
 *   groupId: string,
 *   organizerUserIds: string[],
 *   paymentCurrencyCode?: string | null,
 *   published?: boolean,
 *   speakerUserIds?: string[],
 *   startsAt?: string,
 *   timezone?: string,
 *   waitlist?: string[],
 *   waitlistEnabled?: boolean
 * }} options - Event participants in organizer display order and `insertOwnedEvent` options.
 * @returns {{ eventId: string, name: string, slug: string, ticketTypeIds: Record<string, string> }}
 */
export const setupOrganizerEvent = ({
  amountMinor = 0,
  attendeeUserIds = [],
  endsAt,
  groupId,
  organizerUserIds,
  paymentCurrencyCode = null,
  published = true,
  speakerUserIds = [],
  startsAt,
  timezone = "UTC",
  waitlist = [],
  waitlistEnabled = false,
}) => {
  const eventId = randomUUID();
  const { name, slug } = buildOwnedEventIdentity("organizer event", eventId);

  return insertOwnedEvent({
    attendeeUserIds,
    description: "Owned organizer event used by E2E contributor coverage.",
    endsAt,
    eventId,
    groupId,
    meetingJoinUrl: `https://meet.example.com/${slug}`,
    name,
    organizerUserIds,
    paymentCurrencyCode,
    published,
    slug,
    speakerUserIds,
    startsAt,
    startsIn: "20 days",
    tiers: [
      {
        amountMinor,
        description: "Disposable admission used by E2E contributor coverage.",
        key: "general",
        seats: 10,
        title: "General admission",
      },
    ],
    timezone,
    waitlist,
    waitlistEnabled,
  });
};

/**
 * Creates a future event with ticket tiers for allocation conflict checks. It is published unless
 * `published` is false and starts in 200 days unless `startsAt` is given. Tiers are free unless
 * `amountMinor` is positive, which requires `paymentCurrencyCode`; `waitlist` queues users for the
 * first tier.
 * @param {{
 *   approvalRequired?: boolean,
 *   endsAt?: string,
 *   groupId: string,
 *   paymentCurrencyCode?: string | null,
 *   published?: boolean,
 *   speakerUserIds?: string[],
 *   startsAt?: string,
 *   ticketTypes: { amountMinor?: number, key: string, seats: number, title: string }[],
 *   timezone?: string,
 *   waitlist?: string[],
 *   waitlistEnabled?: boolean
 * }} options - Event shape and `insertOwnedEvent` options.
 * @returns {{ eventId: string, name: string, slug: string, ticketTypeIds: Record<string, string> }}
 */
export const setupTicketAllocationEvent = ({
  approvalRequired = false,
  endsAt,
  groupId,
  paymentCurrencyCode = null,
  published = true,
  speakerUserIds = [],
  startsAt,
  ticketTypes,
  timezone = "UTC",
  waitlist = [],
  waitlistEnabled = false,
}) => {
  const eventId = randomUUID();
  const { name, slug } = buildOwnedEventIdentity("ticket allocation event", eventId);

  return insertOwnedEvent({
    approvalRequired,
    description: "Owned ticket allocation event used by E2E coverage.",
    endsAt,
    eventId,
    groupId,
    name,
    paymentCurrencyCode,
    published,
    slug,
    speakerUserIds,
    startsAt,
    startsIn: "200 days",
    tiers: ticketTypes.map(({ amountMinor = 0, key, seats, title }) => ({ amountMinor, key, seats, title })),
    timezone,
    waitlist,
    waitlistEnabled,
  });
};

/**
 * Records one invitation request for a ticket allocation event.
 * @param {{
 *   eventId: string,
 *   status?: "accepted" | "pending",
 *   ticketTypeId: string,
 *   userId: string
 * }} options - Request fields.
 */
export const setupTicketInvitationRequest = ({ eventId, status = "pending", ticketTypeId, userId }) => {
  const reviewed = status === "accepted";

  queryE2eDatabase(`
    insert into event_invitation_request (
      event_id,
      event_ticket_type_id,
      reviewed_at,
      reviewed_by,
      status,
      user_id
    ) values (
      '${eventId}',
      '${ticketTypeId}',
      ${reviewed ? "current_timestamp - interval '2 days'" : "null"},
      ${reviewed ? `'${TEST_USER_IDS.organizer1}'` : "null"},
      '${status}',
      '${userId}'
    );
  `);
};

/**
 * Records one admission offer for a ticket allocation event.
 * Pending and checkout pending offers reserve a seat; expired offers can be
 * reissued. Completed and declined offers keep a future deadline to cover
 * closed offers before expiry.
 * @param {{
 *   eventId: string,
 *   source: "approval" | "organizer_invitation",
 *   status: "checkout_pending" | "completed" | "declined" | "expired" | "pending",
 *   ticketTypeId: string,
 *   userId: string
 * }} options - Offer fields.
 */
export const setupTicketOffer = ({ eventId, source, status, ticketTypeId, userId }) => {
  const expired = status === "expired";
  const snapshot = status === "checkout_pending" || status === "completed";

  // Checkout pending and completed offers require a free ticket snapshot.
  queryE2eDatabase(`
    insert into admission_offer (
      amount_minor,
      created_at,
      discount_amount_minor,
      event_id,
      event_ticket_type_id,
      expires_at,
      organizer_user_id,
      source,
      status,
      ticket_title,
      user_id
    ) values (
      ${snapshot ? "0" : "null"},
      current_timestamp - interval '${expired ? "2 days" : "1 minute"}',
      ${snapshot ? "0" : "null"},
      '${eventId}',
      '${ticketTypeId}',
      current_timestamp ${expired ? "- interval '1 day'" : "+ interval '1 day'"},
      '${TEST_USER_IDS.organizer1}',
      '${source}',
      '${status}',
      ${snapshot ? `(select title from event_ticket_type where event_ticket_type_id = '${ticketTypeId}')` : "null"},
      '${userId}'
    );
  `);
};

/**
 * Queues one user for a ticket tier on a ticket allocation event.
 * @param {{ eventId: string, ticketTypeId: string, userId: string }} options - Waitlist entry fields.
 */
export const setupTicketWaitlistEntry = ({ eventId, ticketTypeId, userId }) => {
  queryE2eDatabase(`
    insert into event_waitlist (event_id, event_ticket_type_id, user_id)
    values ('${eventId}', '${ticketTypeId}', '${userId}');
  `);
};

/**
 * Builds the name and slug of an owned event from a label and the event ID, such as
 * `E2E cancelable event 1a2b3c4d` and `e2e-cancelable-event-1a2b3c4d`.
 * @param {string} label - Lowercase words naming the event kind.
 * @param {string} eventId - Event identifier whose first 8 hex digits suffix the name.
 * @returns {{ name: string, slug: string }}
 */
const buildOwnedEventIdentity = (label, eventId) => {
  const suffix = eventId.replace(/-/g, "").slice(0, 8);

  return { name: `E2E ${label} ${suffix}`, slug: `e2e-${label.replaceAll(" ", "-")}-${suffix}` };
};
