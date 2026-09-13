import { randomUUID } from "node:crypto";

import { queryE2eDatabase } from "../database.js";

const PAYMENT_SELLER_SNAPSHOT =
  '{"connected_account_id":"acct_e2e_alpha","display_name":"E2E Alpha Fiscal Sponsor","provider":"stripe"}';
const PAYMENT_VENUE_SNAPSHOT =
  '{"address":"123 Payment Way","city":"New York","country_code":"US","name":"E2E Admission Hall","state_code":"NY","state_name":"New York","zip_code":"10001"}';

/**
 * Deletes an owned purchase graph in foreign-key order.
 * @param {{ eventId?: string, purchaseId?: string, userId?: string }} ids - Owned payment graph IDs.
 * @returns {void}
 */
export const cleanupOwnedPaymentPurchase = ({ eventId, purchaseId, userId }) => {
  const purchasePredicate = purchaseId
    ? `event_purchase_id = ${sqlString(purchaseId)}::uuid`
    : eventId && userId
      ? `event_id = ${sqlString(eventId)}::uuid and user_id = ${sqlString(userId)}::uuid`
      : "";

  if (!purchasePredicate) {
    return;
  }

  const eventAttendeeDelete =
    eventId && userId
      ? `
    delete from event_attendee
    where event_id = ${sqlString(eventId)}::uuid
    and user_id = ${sqlString(userId)}::uuid;
  `
      : "";

  queryE2eDatabase(`
    delete from event_purchase_credit_note
    where event_purchase_refund_id in (
      select event_purchase_refund_id
      from event_purchase_refund
      where event_purchase_id in (
        select event_purchase_id from event_purchase where ${purchasePredicate}
      )
    );

    delete from event_purchase_application_fee_adjustment
    where event_purchase_id in (
      select event_purchase_id from event_purchase where ${purchasePredicate}
    );

    delete from event_purchase_refund
    where event_purchase_id in (
      select event_purchase_id from event_purchase where ${purchasePredicate}
    );

    delete from payment_job
    where event_purchase_id in (
      select event_purchase_id from event_purchase where ${purchasePredicate}
    );

    delete from event_refund_request
    where event_purchase_id in (
      select event_purchase_id from event_purchase where ${purchasePredicate}
    );

    delete from event_purchase
    where ${purchasePredicate};

    ${eventAttendeeDelete}
  `);
};

/**
 * Creates a completed direct-charge purchase ready for an attendee refund request.
 * @param {{ eventId: string, userId: string }} input - Purchase owner.
 * @returns {{ eventId: string, purchaseId: string, userId: string }}
 */
export const setupOwnedCompletedRefundPurchase = ({ eventId, userId }) => {
  const purchaseId = randomUUID();
  const checkoutSessionId = `cs_e2e_owned_refund_request_${shortId(purchaseId)}`;
  const paymentReference = `pi_e2e_owned_refund_request_${shortId(purchaseId)}`;
  const providerChargeId = `ch_e2e_owned_refund_request_${shortId(purchaseId)}`;

  cleanupOwnedPaymentPurchase({ eventId, userId });

  queryE2eDatabase(`
    insert into event_attendee (
      event_id,
      user_id,
      manually_invited,
      status
    ) values (
      ${sqlString(eventId)}::uuid,
      ${sqlString(userId)}::uuid,
      false,
      'confirmed'
    );

    insert into event_purchase (
      event_purchase_id,
      amount_minor,
      completed_at,
      currency_code,
      discount_amount_minor,
      event_id,
      event_ticket_type_id,
      payment_provider_id,
      provider_checkout_session_id,
      provider_checkout_url,
      provider_payment_reference,
      status,
      ticket_title,
      user_id,

      charge_model,
      connected_seller_id,
      provider_object_account_id,
      seller_snapshot,
      tax_behavior,
      tax_calculation_mode,
      tax_classification,
      venue_snapshot,
      final_platform_fee_amount_minor,
      provider_charge_id,
      provider_total_minor,
      subtotal_excluding_tax_minor,
      tax_amount_minor
    ) values (
      ${sqlString(purchaseId)}::uuid,
      5000,
      current_timestamp - interval '1 day',
      'USD',
      0,
      ${sqlString(eventId)}::uuid,
      ${firstTicketTypeSql(eventId)},
      'stripe',
      ${sqlString(checkoutSessionId)},
      ${sqlString(`https://checkout.stripe.test/${checkoutSessionId}`)},
      ${sqlString(paymentReference)},
      'completed',
      'VIP pass',
      ${sqlString(userId)}::uuid,

      'direct-charge',
      'acct_e2e_alpha',
      'acct_e2e_alpha',
      ${sqlString(PAYMENT_SELLER_SNAPSHOT)}::jsonb,
      'inclusive',
      'manual',
      'professional-event-admission',
      ${sqlString(PAYMENT_VENUE_SNAPSHOT)}::jsonb,
      0,
      ${sqlString(providerChargeId)},
      5000,
      5000,
      0
    );
  `);

  return { eventId, purchaseId, userId };
};

/**
 * Creates an exhausted provider refund graph that is eligible for an organizer retry.
 * @param {{ eventId: string, userId: string }} input - Refund graph owner.
 * @returns {{
 *   attendeeName: string,
 *   eventId: string,
 *   paymentJobId: string,
 *   purchaseId: string,
 *   refundId: string,
 *   userId: string
 * }}
 */
export const setupExhaustedRefundGraph = ({ eventId, userId }) => {
  const graph = baseDirectRefundGraph({ eventId, userId });

  // Match by event/user so stale purchases from interrupted runs are removed.
  cleanupOwnedPaymentPurchase({ eventId, userId });

  queryE2eDatabase(`
    ${insertConfirmedAttendeeSql(graph)}
    ${insertDirectRefundPurchaseSql(graph, {
      checkoutLabel: "exhausted_refund",
      purchaseStatus: "refund-pending",
    })}

    insert into payment_job (
      attempt_count,
      completed_at,
      event_purchase_id,
      failure_message,
      idempotency_key,
      kind,
      next_attempt_at,
      payment_job_id,
      payment_provider_id,
      status
    ) values (
      10,
      null,
      ${sqlString(graph.purchaseId)}::uuid,
      'Provider refund attempts exhausted',
      ${sqlString(`event-purchase-refund-${graph.purchaseId}`)},
      'event-purchase-refund',
      current_timestamp - interval '1 minute',
      ${sqlString(graph.paymentJobId)}::uuid,
      'stripe',
      'failed'
    );

    insert into event_purchase_refund (
      amount_minor,
      currency_code,
      event_purchase_id,
      event_purchase_refund_id,
      kind,
      payment_job_id,
      payment_provider_id,
      status,
      terminal_failure,

      event_refund_request_id,
      finalized_at,
      provider_refund_id
    ) values (
      5000,
      'USD',
      ${sqlString(graph.purchaseId)}::uuid,
      ${sqlString(graph.refundId)}::uuid,
      'event-cancellation',
      ${sqlString(graph.paymentJobId)}::uuid,
      'stripe',
      'provider-failed',
      false,

      null,
      null,
      null
    );
  `);

  return graph;
};

/**
 * Creates a pending external refund request that can be approved or rejected locally.
 * @param {{ eventId: string, requestedReason?: string, userId: string }} input - Request owner.
 * @returns {{
 *   attendeeName: string,
 *   eventId: string,
 *   purchaseId: string,
 *   refundRequestId: string,
 *   userId: string
 * }}
 */
export const setupExternalRefundRequestGraph = ({
  eventId,
  requestedReason = "E2E external refund request",
  userId,
}) => {
  const purchaseId = randomUUID();
  const refundRequestId = randomUUID();
  const attendeeName = getUserName(userId);

  cleanupOwnedPaymentPurchase({ eventId, userId });

  queryE2eDatabase(`
    insert into event_attendee (
      event_id,
      user_id,
      manually_invited,
      status
    ) values (
      ${sqlString(eventId)}::uuid,
      ${sqlString(userId)}::uuid,
      false,
      'confirmed'
    );

    insert into event_purchase (
      event_purchase_id,
      amount_minor,
      completed_at,
      currency_code,
      discount_amount_minor,
      event_id,
      event_ticket_type_id,
      provider_payment_reference,
      status,
      ticket_title,
      user_id,

      charge_model,
      external_payment_details,
      external_payment_marked_by_user_id
    ) values (
      ${sqlString(purchaseId)}::uuid,
      1234,
      current_timestamp - interval '1 day',
      'USD',
      0,
      ${sqlString(eventId)}::uuid,
      ${firstTicketTypeSql(eventId)},
      ${sqlString(`external-ref-${shortId(purchaseId)}`)},
      'refund-requested',
      'External admission',
      ${sqlString(userId)}::uuid,

      'external',
      'Bank transfer received',
      ${sqlString(userId)}::uuid
    );

    insert into event_refund_request (
      event_refund_request_id,
      event_purchase_id,
      requested_by_user_id,
      status,

      requested_reason,
      review_note,
      reviewed_at,
      reviewed_by_user_id
    ) values (
      ${sqlString(refundRequestId)}::uuid,
      ${sqlString(purchaseId)}::uuid,
      ${sqlString(userId)}::uuid,
      'pending',

      ${sqlString(requestedReason)},
      null,
      null,
      null
    );
  `);

  return { attendeeName, eventId, purchaseId, refundRequestId, userId };
};

/**
 * Creates a terminal provider-refund failure that organizer recovery can complete.
 * @param {{ eventId: string, userId: string }} input - Refund graph owner.
 * @returns {{
 *   attendeeName: string,
 *   eventId: string,
 *   paymentJobId: string,
 *   purchaseId: string,
 *   refundId: string,
 *   refundRequestId: string,
 *   userId: string
 * }}
 */
export const setupRecoverableRefundGraph = ({ eventId, userId }) => {
  const graph = {
    ...baseDirectRefundGraph({ eventId, userId }),
    refundRequestId: randomUUID(),
  };

  // Match by event/user so stale purchases from interrupted runs are removed.
  cleanupOwnedPaymentPurchase({ eventId, userId });

  queryE2eDatabase(`
    ${insertConfirmedAttendeeSql(graph)}
    ${insertDirectRefundPurchaseSql(graph, {
      checkoutLabel: "recoverable_refund",
      purchaseStatus: "refund-requested",
    })}

    insert into event_refund_request (
      event_refund_request_id,
      event_purchase_id,
      requested_by_user_id,
      status,

      requested_reason,
      review_note,
      reviewed_at,
      reviewed_by_user_id
    ) values (
      ${sqlString(graph.refundRequestId)}::uuid,
      ${sqlString(graph.purchaseId)}::uuid,
      ${sqlString(userId)}::uuid,
      'approving',

      'Provider completed the refund outside OCG',
      'Approved by the organizer',
      current_timestamp - interval '10 days',
      ${sqlString(userId)}::uuid
    );

    insert into payment_job (
      attempt_count,
      completed_at,
      event_purchase_id,
      failure_message,
      idempotency_key,
      kind,
      next_attempt_at,
      payment_job_id,
      payment_provider_id,
      status
    ) values (
      10,
      null,
      ${sqlString(graph.purchaseId)}::uuid,
      'Provider refund requires external recovery',
      ${sqlString(`event-purchase-refund-${graph.purchaseId}`)},
      'event-purchase-refund',
      current_timestamp + interval '1 year',
      ${sqlString(graph.paymentJobId)}::uuid,
      'stripe',
      'failed'
    );

    insert into event_purchase_refund (
      amount_minor,
      currency_code,
      event_purchase_id,
      event_purchase_refund_id,
      kind,
      payment_job_id,
      payment_provider_id,
      status,
      terminal_failure,

      event_refund_request_id,
      finalized_at,
      provider_refund_id
    ) values (
      5000,
      'USD',
      ${sqlString(graph.purchaseId)}::uuid,
      ${sqlString(graph.refundId)}::uuid,
      'refund-request-approval',
      ${sqlString(graph.paymentJobId)}::uuid,
      'stripe',
      'provider-failed',
      true,

      ${sqlString(graph.refundRequestId)}::uuid,
      null,
      ${sqlString(`re_e2e_refund_recovery_${shortId(graph.refundId)}`)}
    );
  `);

  return graph;
};

/**
 * Creates a pending direct-charge checkout hold for one attendee.
 * @param {{
 *   eventId: string,
 *   providerCheckoutSessionId?: string,
 *   providerCheckoutUrl?: string,
 *   userId: string
 * }} input - Checkout owner and optional provider fields.
 * @returns {{
 *   eventId: string,
 *   providerCheckoutSessionId: string,
 *   providerCheckoutUrl: string,
 *   purchaseId: string,
 *   userId: string
 * }}
 */
export const setupOwnedPendingCheckout = ({
  eventId,
  providerCheckoutSessionId,
  providerCheckoutUrl,
  userId,
}) => {
  const purchaseId = randomUUID();
  const checkoutSessionId = providerCheckoutSessionId ?? `cs_e2e_owned_checkout_${shortId(purchaseId)}`;
  const checkoutUrl = providerCheckoutUrl ?? `https://example.test/checkout/e2e-owned-${shortId(purchaseId)}`;

  cleanupOwnedPaymentPurchase({ eventId, userId });

  queryE2eDatabase(`
    insert into event_purchase (
      event_purchase_id,
      amount_minor,
      currency_code,
      discount_amount_minor,
      event_id,
      event_ticket_type_id,
      hold_expires_at,
      payment_provider_id,
      provider_checkout_session_id,
      provider_checkout_url,
      status,
      ticket_title,
      user_id,

      charge_model,
      connected_seller_id,
      provider_object_account_id,
      seller_snapshot,
      tax_behavior,
      tax_calculation_mode,
      tax_classification,
      venue_snapshot
    ) values (
      ${sqlString(purchaseId)}::uuid,
      2500,
      'USD',
      0,
      ${sqlString(eventId)}::uuid,
      ${firstTicketTypeSql(eventId)},
      current_timestamp + interval '2 days',
      'stripe',
      ${sqlString(checkoutSessionId)},
      ${sqlString(checkoutUrl)},
      'pending',
      'General admission',
      ${sqlString(userId)}::uuid,

      'direct-charge',
      'acct_e2e_alpha',
      'acct_e2e_alpha',
      ${sqlString(PAYMENT_SELLER_SNAPSHOT)}::jsonb,
      'inclusive',
      'manual',
      'professional-event-admission',
      ${sqlString(PAYMENT_VENUE_SNAPSHOT)}::jsonb
    );
  `);

  return {
    eventId,
    providerCheckoutSessionId: checkoutSessionId,
    providerCheckoutUrl: checkoutUrl,
    purchaseId,
    userId,
  };
};

/** Builds the direct-refund fixture graph identifiers for a user and event. */
const baseDirectRefundGraph = ({ eventId, userId }) => ({
  attendeeName: getUserName(userId),
  eventId,
  paymentJobId: randomUUID(),
  purchaseId: randomUUID(),
  refundId: randomUUID(),
  userId,
});

/** Builds an event_ticket_type subquery for the event's first ticket type. */
const firstTicketTypeSql = (eventId) => `(
        select event_ticket_type_id
        from event_ticket_type
        where event_id = ${sqlString(eventId)}::uuid
        order by "order", event_ticket_type_id
        limit 1
      )`;

/** Returns the user's name from the user table. */
const getUserName = (userId) =>
  queryE2eDatabase(`
    select name
    from "user"
    where user_id = ${sqlString(userId)}::uuid;
  `);

/** Builds event_attendee insert SQL for a confirmed attendee. */
const insertConfirmedAttendeeSql = ({ eventId, userId }) => `
    insert into event_attendee (
      event_id,
      user_id,
      manually_invited,
      status
    ) values (
      ${sqlString(eventId)}::uuid,
      ${sqlString(userId)}::uuid,
      false,
      'confirmed'
    );
`;

/** Builds the insert statement for a purchase that a refund can target directly. */
const insertDirectRefundPurchaseSql = (
  { eventId, purchaseId, userId },
  { checkoutLabel, purchaseStatus },
) => `
    insert into event_purchase (
      event_purchase_id,
      amount_minor,
      completed_at,
      currency_code,
      discount_amount_minor,
      event_id,
      event_ticket_type_id,
      payment_provider_id,
      provider_checkout_session_id,
      provider_checkout_url,
      provider_payment_reference,
      refunded_at,
      status,
      ticket_title,
      user_id,

      charge_model,
      connected_seller_id,
      provider_object_account_id,
      seller_snapshot,
      tax_behavior,
      tax_calculation_mode,
      tax_classification,
      venue_snapshot,
      final_platform_fee_amount_minor,
      provider_charge_id,
      provider_invoice_id,
      provider_total_minor,
      subtotal_excluding_tax_minor,
      tax_amount_minor
    ) values (
      ${sqlString(purchaseId)}::uuid,
      5000,
      current_timestamp - interval '7 days',
      'USD',
      0,
      ${sqlString(eventId)}::uuid,
      ${firstTicketTypeSql(eventId)},
      'stripe',
      ${sqlString(`cs_e2e_${checkoutLabel}_${shortId(purchaseId)}`)},
      ${sqlString(`https://checkout.stripe.test/cs_e2e_${checkoutLabel}_${shortId(purchaseId)}`)},
      ${sqlString(`pi_e2e_${checkoutLabel}_${shortId(purchaseId)}`)},
      null,
      ${sqlString(purchaseStatus)},
      'VIP pass',
      ${sqlString(userId)}::uuid,

      'direct-charge',
      'acct_e2e_alpha',
      'acct_e2e_alpha',
      ${sqlString(PAYMENT_SELLER_SNAPSHOT)}::jsonb,
      'inclusive',
      'manual',
      'professional-event-admission',
      ${sqlString(PAYMENT_VENUE_SNAPSHOT)}::jsonb,
      0,
      ${sqlString(`ch_e2e_${checkoutLabel}_${shortId(purchaseId)}`)},
      null,
      5000,
      5000,
      0
    );
`;

/** Returns a shortened identifier for readable E2E labels. */
const shortId = (id) => id.replaceAll("-", "").slice(0, 12);

/** Escapes a value for embedding in E2E SQL. */
const sqlString = (value) => `'${String(value).replaceAll("'", "''")}'`;
