import { expect, test } from "../../fixtures.js";
import { queryE2eDatabase, queryE2eDatabaseRows } from "../../database.js";
import { deleteNotifications, expectNewNotifications, snapshotNotifications } from "../../notifications.js";
import { TEST_COMMUNITY_NAME, TEST_GROUP_SLUGS, TEST_USER_IDS, TEST_WEBHOOK_EVENTS } from "../../seed.js";
import { getAttendButton, waitForAttendanceState } from "../../site/event/helpers.js";
import { navigateToEvent, navigateToPath } from "../../utils.js";
import { WEBHOOK_ENDPOINTS, WEBHOOK_SECRETS, postStripe, signStripe } from "../../webhooks.js";

const BAD_SIGNATURE_REPLACEMENT = "0";

const CONNECTED_WEBHOOK = {
  endpoint: WEBHOOK_ENDPOINTS.stripeConnected,
  secret: WEBHOOK_SECRETS.stripeConnected,
};

const EVENT_CREATED_AT = 1_700_000_000;

const MISMATCHED_CONNECTED_ACCOUNT = "acct_e2e_mismatch";

const REFUND_ATTENDEE_NAME = "E2E Member Two";

const STALE_STRIPE_TIMESTAMP = 1;

test.describe("Stripe payment webhooks", () => {
  test.describe.configure({ mode: "serial" });

  test.beforeEach(() => {
    restoreStripeWebhookFixtures();
  });

  test("expires a checkout hold and releases public ticket capacity", async ({ pending1Page, request }) => {
    try {
      // Verify the fixture starts full because one completed purchase and one active hold occupy it.
      const availability = await getAvailability(request, TEST_WEBHOOK_EVENTS.expire);
      const ticketAvailability = getTicketTypeAvailability(availability, TEST_WEBHOOK_EVENTS.expire);
      expect(ticketAvailability).toBeTruthy();
      expect(availability.remaining_capacity).toBe(0);
      expect(ticketAvailability.remaining_seats).toBe(0);

      // Verify the attendee dashboard exposes the active pending-payment entry.
      const dashboardContent = await openMyEventsDashboard(pending1Page);
      const pendingRow = getUserEventRow(dashboardContent, TEST_WEBHOOK_EVENTS.expire.name);
      await expect(pendingRow).toContainText("Payment pending");
      await pendingRow.getByLabel("Open event actions").click();
      await expect(pendingRow.getByRole("menuitem", { name: "Continue to checkout" })).toHaveAttribute(
        "href",
        "https://checkout.stripe.test/cs_e2e_webhook_expire",
      );

      // Deliver the connected-account checkout expiration webhook.
      const response = await postStripe(request, {
        ...CONNECTED_WEBHOOK,
        body: checkoutExpiredBody(),
      });
      expect(response.status()).toBe(200);
      expect(getPurchaseStatus(TEST_WEBHOOK_EVENTS.expire.pendingPurchaseId)).toBe("expired");

      // Verify the expired hold disappears from My Events and capacity is available again.
      const refreshedDashboard = await openMyEventsDashboard(pending1Page);
      await expect(getUserEventRow(refreshedDashboard, TEST_WEBHOOK_EVENTS.expire.name)).toHaveCount(0);
      const updatedAvailability = await getAvailability(request, TEST_WEBHOOK_EVENTS.expire);
      const updatedTicketAvailability = getTicketTypeAvailability(
        updatedAvailability,
        TEST_WEBHOOK_EVENTS.expire,
      );
      expect(updatedTicketAvailability).toBeTruthy();
      expect(updatedAvailability.remaining_capacity).toBe(1);
      expect(updatedTicketAvailability.remaining_seats).toBe(1);

      // Verify the public event page now exposes a fresh ticket action to the same user.
      await navigateToEvent(
        pending1Page,
        TEST_COMMUNITY_NAME,
        TEST_GROUP_SLUGS.community1.alpha,
        TEST_WEBHOOK_EVENTS.expire.slug,
      );
      await waitForAttendanceState(pending1Page);
      await expect(getAttendButton(pending1Page)).toContainText("Get ticket");
    } finally {
      // Restore the seeded Stripe expiration fixture.
      restoreStripeWebhookFixtures();
    }
  });

  test("attaches an invoice document from a connected-account invoice webhook", async ({
    pending2Page,
    request,
  }) => {
    try {
      // Deliver the invoice webhook for a completed purchase that starts without invoice fields.
      const response = await postStripe(request, {
        ...CONNECTED_WEBHOOK,
        body: invoicePaidBody(),
      });
      expect(response.status()).toBe(200);
      expect(getInvoiceState().providerInvoiceId).toBe(TEST_WEBHOOK_EVENTS.invoice.providerInvoiceId);

      // Verify the attendee purchases dashboard exposes the new invoice action.
      const dashboardContent = await openPurchasesDashboard(pending2Page);
      const purchaseRow = getPurchaseRow(dashboardContent, TEST_WEBHOOK_EVENTS.invoice.name);
      await expect(purchaseRow).toContainText("Paid");
      await purchaseRow.getByLabel(`Open document actions for ${TEST_WEBHOOK_EVENTS.invoice.name}`).click();
      await expect(purchaseRow.getByRole("menuitem", { name: "View invoice" })).toHaveAttribute(
        "href",
        `/dashboard/user/purchases/${TEST_WEBHOOK_EVENTS.invoice.purchaseId}/invoice`,
      );
    } finally {
      // Restore the seeded Stripe invoice fixture.
      restoreStripeWebhookFixtures();
    }
  });

  test("records a Stripe refund success and lets the worker finalize attendance", async ({
    member2Page,
    organizerGroupPage,
    request,
  }) => {
    const snapshot = snapshotNotifications();
    let notificationIds = [];

    try {
      // Deliver the provider success while the refund job is intentionally not yet claimable.
      const response = await postStripe(request, {
        ...CONNECTED_WEBHOOK,
        body: refundUpdatedBody(),
      });
      expect(response.status()).toBe(200);
      expect(getRefundProviderConfirmation()).toMatchObject({
        providerRefundId: TEST_WEBHOOK_EVENTS.refund.providerRefundId,
        providerRefundedAtSet: true,
      });

      // Wait for the payment worker to claim the now-due job and finalize local state.
      await expect
        .poll(getRefundWorkflowState, {
          intervals: [1_000],
          message: "refund worker finalization; received value includes payment_job diagnostics",
          timeout: 45_000,
        })
        .toMatchObject({
          attendeeStatus: "attendance-canceled",
          jobStatus: "completed",
          purchaseStatus: "refunded",
          refundStatus: "finalized",
          remainingSeats: 1,
          requestStatus: "approved",
        });

      // Verify the worker enqueued the attendee refund notification exactly once.
      notificationIds = expectNewNotifications(snapshot, [
        {
          kind: "event-refund-approved",
          templateDataContains: {
            event: { name: TEST_WEBHOOK_EVENTS.refund.name },
            external_payment: false,
          },
          userIds: [TEST_USER_IDS.member2],
        },
      ]);

      // Verify attendee-facing and organizer-facing state after local finalization.
      const availability = await getAvailability(request, TEST_WEBHOOK_EVENTS.refund);
      expect(availability.remaining_capacity).toBe(1);
      const refundsDashboard = await openRefundsDashboard(
        organizerGroupPage,
        `/dashboard/group?tab=refunds&view=completed&event_id=${TEST_WEBHOOK_EVENTS.refund.id}`,
      );
      await expect(getRefundRow(refundsDashboard, REFUND_ATTENDEE_NAME)).toContainText("Refunded");
      const myEventsDashboard = await openMyEventsDashboard(member2Page);
      await expect(getUserEventRow(myEventsDashboard, TEST_WEBHOOK_EVENTS.refund.name)).toHaveCount(0);

      // Replay the same provider event and verify idempotency leaves no duplicate rows or notices.
      const replaySnapshot = snapshotNotifications();
      const replayResponse = await postStripe(request, {
        ...CONNECTED_WEBHOOK,
        body: refundUpdatedBody(),
      });
      expect(replayResponse.status()).toBe(200);
      expect(getRefundGraphCounts()).toMatchObject({
        jobs: 1,
        refunds: 1,
        requests: 1,
      });
      expectNewNotifications(replaySnapshot, []);

      // The replay leaves the finalized refund and its completed job untouched instead of reopening them.
      expect(getRefundWorkflowState()).toMatchObject({
        jobStatus: "completed",
        purchaseStatus: "refunded",
        refundStatus: "finalized",
      });
    } finally {
      // Remove refund notifications and restore the seeded Stripe refund fixture.
      deleteNotifications(notificationIds);
      restoreStripeWebhookFixtures();
    }
  });

  test("rejects invalid connected-account Stripe webhook deliveries", async ({ request }) => {
    try {
      // Verify signature and mode failures are rejected before local reconciliation.
      const validBody = checkoutExpiredBody();
      const validPayload = JSON.stringify(validBody);
      const badSignature = corruptStripeSignature(signStripe(validPayload, WEBHOOK_SECRETS.stripeConnected));
      const badSignatureResponse = await postStripe(request, {
        body: validPayload,
        endpoint: WEBHOOK_ENDPOINTS.stripeConnected,
        secret: WEBHOOK_SECRETS.stripeConnected,
        signature: badSignature,
      });
      expect(badSignatureResponse.status()).toBe(401);

      // Verify stale timestamps are rejected.
      const staleResponse = await postStripe(request, {
        ...CONNECTED_WEBHOOK,
        body: checkoutExpiredBody(),
        timestamp: STALE_STRIPE_TIMESTAMP,
      });
      expect(staleResponse.status()).toBe(401);

      // Verify platform secrets cannot authenticate connected-account webhooks.
      const wrongSecretResponse = await postStripe(request, {
        body: checkoutExpiredBody(),
        endpoint: WEBHOOK_ENDPOINTS.stripeConnected,
        secret: WEBHOOK_SECRETS.stripePlatform,
      });
      expect(wrongSecretResponse.status()).toBe(401);

      // Verify live-mode deliveries are rejected in test fixtures.
      const liveModeResponse = await postStripe(request, {
        ...CONNECTED_WEBHOOK,
        body: checkoutExpiredBody({ livemode: true }),
      });
      expect(liveModeResponse.status()).toBe(401);

      // Verify malformed webhook payloads are rejected.
      const malformedResponse = await postStripe(request, {
        ...CONNECTED_WEBHOOK,
        body: '{"id":',
      });
      expect(malformedResponse.status()).toBe(401);

      // Verify account mismatches use the handler's real no-op/error contracts.
      const mismatchedExpireResponse = await postStripe(request, {
        ...CONNECTED_WEBHOOK,
        body: checkoutExpiredBody({ account: MISMATCHED_CONNECTED_ACCOUNT }),
      });
      expect(mismatchedExpireResponse.status()).toBe(200);
      expect(getPurchaseStatus(TEST_WEBHOOK_EVENTS.expire.pendingPurchaseId)).toBe("pending");

      // Verify account mismatches fail invoice reconciliation without mutating invoice state.
      const mismatchedInvoiceResponse = await postStripe(request, {
        ...CONNECTED_WEBHOOK,
        body: invoicePaidBody({ account: MISMATCHED_CONNECTED_ACCOUNT }),
      });
      expect(mismatchedInvoiceResponse.status()).toBe(500);
      expect(getInvoiceState().providerInvoiceId).toBeNull();
    } finally {
      // Restore all seeded Stripe webhook fixtures.
      restoreStripeWebhookFixtures();
    }
  });
});

/** Builds a checkout.session.expired webhook body for the seeded checkout. */
const checkoutExpiredBody = ({
  account = TEST_WEBHOOK_EVENTS.expire.connectedAccount,
  livemode = false,
} = {}) =>
  stripeEventBody("checkout.session.expired", {
    account,
    livemode,
    object: {
      id: TEST_WEBHOOK_EVENTS.expire.providerCheckoutSessionId,
      object: "checkout.session",
    },
  });

/** Returns a Stripe signature with a mismatched HMAC digest. */
const corruptStripeSignature = (signature) =>
  signature.replace(/v1=([0-9a-f])/u, (_match, digit) => {
    const replacement = digit === BAD_SIGNATURE_REPLACEMENT ? "1" : BAD_SIGNATURE_REPLACEMENT;

    return `v1=${replacement}`;
  });

/** Deletes Stripe refund notification rows from the notification table. */
const deleteStripeWebhookNotifications = () => {
  const notificationIds = queryE2eDatabaseRows(`
    select n.notification_id
    from notification n
    left join notification_template_data ntd using (notification_template_data_id)
    where n.kind = 'event-refund-approved'
    and n.user_id = '${TEST_USER_IDS.member2}'
    and ntd.data::text like '%${TEST_WEBHOOK_EVENTS.refund.id}%'
  `).map(([notificationId]) => notificationId);

  deleteNotifications(notificationIds);
};

/** Returns the public event availability API payload for a fixture. */
const getAvailability = async (request, event) => {
  const response = await request.get(
    `/${TEST_COMMUNITY_NAME}/group/${TEST_GROUP_SLUGS.community1.alpha}/event/${event.slug}/availability`,
  );

  expect(response.ok()).toBeTruthy();

  return response.json();
};

/** Returns invoice provider fields from event_purchase. */
const getInvoiceState = () =>
  readJson(`
    select jsonb_build_object(
      'providerInvoiceHostedUrl', provider_invoice_hosted_url,
      'providerInvoiceId', provider_invoice_id,
      'providerInvoicePdfUrl', provider_invoice_pdf_url
    )::text
    from event_purchase
    where event_purchase_id = '${TEST_WEBHOOK_EVENTS.invoice.purchaseId}'
  `);

/** Returns the purchases dashboard row for the event name. */
const getPurchaseRow = (dashboardContent, eventName) =>
  dashboardContent.locator("tbody tr", { hasText: eventName });

/** Returns the purchase status from event_purchase. */
const getPurchaseStatus = (purchaseId) =>
  queryE2eDatabase(`
    select status
    from event_purchase
    where event_purchase_id = '${purchaseId}'
  `);

/** Returns refund graph counts from payment_job and related refund tables. */
const getRefundGraphCounts = () =>
  readJson(`
    select jsonb_build_object(
      'jobs', (
        select count(*)
        from payment_job
        where payment_job_id = '${TEST_WEBHOOK_EVENTS.refund.paymentJobId}'
      ),
      'refunds', (
        select count(*)
        from event_purchase_refund
        where event_purchase_refund_id = '${TEST_WEBHOOK_EVENTS.refund.refundId}'
      ),
      'requests', (
        select count(*)
        from event_refund_request
        where event_refund_request_id = '${TEST_WEBHOOK_EVENTS.refund.refundRequestId}'
      )
    )::text
  `);

/** Returns provider refund confirmation fields from event_purchase_refund. */
const getRefundProviderConfirmation = () =>
  readJson(`
    select jsonb_build_object(
      'providerRefundId', provider_refund_id,
      'providerRefundedAtSet', provider_refunded_at is not null
    )::text
    from event_purchase_refund
    where event_purchase_refund_id = '${TEST_WEBHOOK_EVENTS.refund.refundId}'
  `);

/** Returns the refunds dashboard row for the attendee name. */
const getRefundRow = (dashboardContent, attendeeName) =>
  dashboardContent
    .getByRole("table", { name: "Refunds list" })
    .locator("tbody tr", { hasText: attendeeName });

/** Returns refund workflow state from purchase, refund, request, job, and attendee tables. */
const getRefundWorkflowState = () =>
  readJson(`
    select jsonb_build_object(
      'attendeeStatus', ea.status,
      'jobAttemptCount', pj.attempt_count,
      'jobFailureMessage', pj.failure_message,
      'jobNextAttemptAt', pj.next_attempt_at::text,
      'jobStatus', pj.status,
      'purchaseStatus', ep.status,
      'refundStatus', epr.status,
      'remainingSeats', greatest(
        ett.seats_total - get_event_ticket_type_allocated_seat_count(ep.event_id, ep.event_ticket_type_id),
        0
      ),
      'requestStatus', err.status
    )::text
    from event_purchase ep
    join event_ticket_type ett on ett.event_ticket_type_id = ep.event_ticket_type_id
    join event_purchase_refund epr on epr.event_purchase_id = ep.event_purchase_id
    join event_refund_request err on err.event_refund_request_id = epr.event_refund_request_id
    join payment_job pj on pj.payment_job_id = epr.payment_job_id
    left join event_attendee ea on ea.event_id = ep.event_id and ea.user_id = ep.user_id
    where ep.event_purchase_id = '${TEST_WEBHOOK_EVENTS.refund.purchaseId}'
  `);

/** Returns availability details for the fixture ticket type. */
const getTicketTypeAvailability = (availability, event) =>
  availability.ticket_types.find((ticketType) => ticketType.event_ticket_type_id === event.ticketTypeId);

/** Returns the user events dashboard row for the event name. */
const getUserEventRow = (dashboardContent, eventName) =>
  dashboardContent.locator("tbody tr", { hasText: eventName });

/** Builds a Stripe invoice.paid webhook body for the invoice fixture. */
const invoicePaidBody = ({ account = TEST_WEBHOOK_EVENTS.invoice.connectedAccount, livemode = false } = {}) =>
  stripeEventBody("invoice.paid", {
    account,
    livemode,
    object: {
      hosted_invoice_url: TEST_WEBHOOK_EVENTS.invoice.providerInvoiceHostedUrl,
      id: TEST_WEBHOOK_EVENTS.invoice.providerInvoiceId,
      invoice_pdf: TEST_WEBHOOK_EVENTS.invoice.providerInvoicePdfUrl,
      metadata: {
        event_purchase_id: TEST_WEBHOOK_EVENTS.invoice.purchaseId,
      },
      object: "invoice",
    },
  });

/** Opens the user events dashboard and returns its content region. */
const openMyEventsDashboard = async (page) => {
  await navigateToPath(page, "/dashboard/user?tab=events");

  const dashboardContent = page.locator("#dashboard-content");
  await expect(dashboardContent.getByText("My Events", { exact: true })).toBeVisible();

  return dashboardContent;
};

/** Opens the purchases dashboard and returns its content region. */
const openPurchasesDashboard = async (page) => {
  await navigateToPath(page, "/dashboard/user?tab=purchases");

  const dashboardContent = page.locator("#dashboard-content");
  await expect(dashboardContent.getByText("Purchases & documents", { exact: true })).toBeVisible();

  return dashboardContent;
};

/** Opens the refunds dashboard path and returns its content region. */
const openRefundsDashboard = async (page, path) => {
  await navigateToPath(page, path);

  const dashboardContent = page.locator("#dashboard-content");
  await expect(dashboardContent.getByRole("table", { name: "Refunds list" })).toBeVisible();

  return dashboardContent;
};

/** Returns parsed JSON from an E2E database query. */
const readJson = (sql) => JSON.parse(queryE2eDatabase(sql));

/** Builds a refund.updated webhook body for the seeded refund. */
const refundUpdatedBody = ({
  account = TEST_WEBHOOK_EVENTS.refund.connectedAccount,
  livemode = false,
} = {}) =>
  stripeEventBody("refund.updated", {
    account,
    livemode,
    object: {
      amount: 5000,
      currency: "usd",
      id: TEST_WEBHOOK_EVENTS.refund.providerRefundId,
      metadata: {
        event_purchase_id: TEST_WEBHOOK_EVENTS.refund.purchaseId,
      },
      object: "refund",
      payment_intent: TEST_WEBHOOK_EVENTS.refund.providerPaymentReference,
      status: "succeeded",
    },
  });

/** Restores Stripe webhook fixture rows across event_purchase and refund tables. */
const restoreStripeWebhookFixtures = () => {
  deleteStripeWebhookNotifications();

  queryE2eDatabase(`
    update event_purchase
    set
      hold_expires_at = current_timestamp + interval '2 days',
      provider_checkout_url = 'https://checkout.stripe.test/cs_e2e_webhook_expire',
      status = 'pending',
      updated_at = current_timestamp
    where event_purchase_id = '${TEST_WEBHOOK_EVENTS.expire.pendingPurchaseId}';

    update event_purchase
    set
      provider_invoice_hosted_url = null,
      provider_invoice_id = null,
      provider_invoice_pdf_url = null,
      updated_at = current_timestamp
    where event_purchase_id = '${TEST_WEBHOOK_EVENTS.invoice.purchaseId}';

    update event_purchase
    set
      refunded_at = null,
      status = 'refund-pending',
      updated_at = current_timestamp
    where event_purchase_id = '${TEST_WEBHOOK_EVENTS.refund.purchaseId}';

    update event_refund_request
    set
      review_note = 'Approved for webhook finalization.',
      reviewed_at = current_timestamp - interval '1 day',
      reviewed_by_user_id = '${TEST_USER_IDS.organizer1}',
      status = 'approving',
      updated_at = current_timestamp
    where event_refund_request_id = '${TEST_WEBHOOK_EVENTS.refund.refundRequestId}';

    update payment_job
    set
      attempt_count = 0,
      claim_id = null,
      claimed_at = null,
      completed_at = null,
      failure_message = null,
      next_attempt_at = current_timestamp + interval '1 year',
      status = 'pending',
      updated_at = current_timestamp
    where payment_job_id = '${TEST_WEBHOOK_EVENTS.refund.paymentJobId}';

    update event_purchase_refund
    set
      finalized_at = null,
      provider_refund_id = '${TEST_WEBHOOK_EVENTS.refund.providerRefundId}',
      provider_refunded_at = null,
      review_note = 'Approved for webhook finalization.',
      status = 'provider-pending',
      terminal_failure = false,
      updated_at = current_timestamp
    where event_purchase_refund_id = '${TEST_WEBHOOK_EVENTS.refund.refundId}';

    insert into event_attendee (
      event_id,
      user_id
    )
    values (
      '${TEST_WEBHOOK_EVENTS.refund.id}',
      '${TEST_USER_IDS.member2}'
    )
    on conflict (event_id, user_id) do update
    set
      attendance_canceled_at = null,
      attendance_canceled_by_user_id = null,
      checked_in = false,
      checked_in_at = null,
      status = 'confirmed';
  `);
};

/** Builds a Stripe webhook event body for the requested event type. */
const stripeEventBody = (type, { account, livemode, object }) => ({
  account,
  created: EVENT_CREATED_AT,
  data: { object },
  id: `evt_e2e_${type.replace(/\W+/gu, "_")}`,
  livemode,
  object: "event",
  type,
});
