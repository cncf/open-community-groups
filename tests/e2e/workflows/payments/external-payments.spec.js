import { expect, test } from "../../fixtures.js";

import { queryE2eDatabase } from "../../database.js";
import {
  TEST_COMMUNITY_NAME,
  TEST_EXTERNAL_PAYMENT_EVENTS,
  TEST_GROUP_SLUGS,
  TEST_USER_IDS,
  getAttendanceContainer,
  getAttendButton,
  getLeaveButton,
  navigateToEvent,
  navigateToPath,
  waitForActionResponse,
  waitForAttendanceState,
} from "../../utils.js";

const EXTERNAL_GROUP_ID = "44444444-4444-4444-4444-444444444448";
const EXTERNAL_GROUP_SLUG = TEST_GROUP_SLUGS.community1.externalPayments;
const EXTERNAL_EVENT_IDS = Object.values(TEST_EXTERNAL_PAYMENT_EVENTS).map(({ id }) => id);
const INVITATION_OFFER_ID = "59555555-5555-5555-5555-555555555926";

// Locate the shared controls used by public external-payment flows.
const getTicketModal = (page) => page.locator('[data-attendance-role="ticket-modal"]');
const getCheckoutButton = (page) => page.locator('[data-attendance-role="checkout-btn"]');
const getRefundButton = (page) => page.locator('[data-attendance-role="refund-btn"]');

// Dismiss a visible SweetAlert and wait until it no longer blocks the page.
const dismissAlert = async (page) => {
  const confirmButton = page.locator(".swal2-confirm");
  if (await confirmButton.isVisible()) {
    await confirmButton.click();
    await expect(page.locator(".swal2-popup")).toBeHidden();
  }
};

// Restore the external-payment configuration and clear mutable journey state.
const resetExternalPaymentFixtures = () => {
  const eventIds = EXTERNAL_EVENT_IDS.map((eventId) => `'${eventId}'`).join(", ");

  queryE2eDatabase(`
    select sync_external_payments_config(array['US']::text[], 72, 336);

    delete from event_purchase_refund
    where event_purchase_id in (
      select event_purchase_id from event_purchase where event_id in (${eventIds})
    );

    delete from event_refund_request
    where event_purchase_id in (
      select event_purchase_id from event_purchase where event_id in (${eventIds})
    );

    delete from event_attendee where event_id in (${eventIds});
    delete from event_purchase where event_id in (${eventIds});
    delete from admission_offer where event_id in (${eventIds});
    delete from event_invitation_request where event_id in (${eventIds});

    update "group"
    set
      active = true,
      city = 'New York',
      country_code = 'US',
      country_name = 'United States',
      external_payments_enabled = true,
      payment_recipient = null
    where group_id = '${EXTERNAL_GROUP_ID}';

    update event
    set
      canceled = false,
      deleted = false,
      published = true
    where event_id in (${eventIds});

    update event
    set
      external_payment_url = case event_id
        when '${TEST_EXTERNAL_PAYMENT_EVENTS.lifecycle.id}'
          then 'https://payments.example.com/external-lifecycle'
        when '${TEST_EXTERNAL_PAYMENT_EVENTS.capacity.id}'
          then 'https://payments.example.com/external-capacity'
        when '${TEST_EXTERNAL_PAYMENT_EVENTS.invitation.id}'
          then 'https://payments.example.com/external-invitation'
        else null
      end,
      external_payment_instructions = case event_id
        when '${TEST_EXTERNAL_PAYMENT_EVENTS.lifecycle.id}'
          then 'Include the reservation reference with the bank transfer.'
        when '${TEST_EXTERNAL_PAYMENT_EVENTS.capacity.id}'
          then 'Complete payment before the reservation expires.'
        when '${TEST_EXTERNAL_PAYMENT_EVENTS.invitation.id}'
          then 'Use the invitation reference when sending payment.'
        else null
      end,
      external_payment_window_hours = case event_id
        when '${TEST_EXTERNAL_PAYMENT_EVENTS.lifecycle.id}' then 72
        when '${TEST_EXTERNAL_PAYMENT_EVENTS.capacity.id}' then 24
        when '${TEST_EXTERNAL_PAYMENT_EVENTS.invitation.id}' then 48
        else null
      end
    where event_id in (${eventIds});

    update event_discount_code
    set available = null, available_override_active = false
    where event_id = '${TEST_EXTERNAL_PAYMENT_EVENTS.lifecycle.id}';
  `);
};

// Read the purchase identifier created for one attendee and event.
const getExternalPurchaseId = (eventId, userId) =>
  queryE2eDatabase(`
    select event_purchase_id from event_purchase
    where event_id = '${eventId}' and user_id = '${userId}';
  `);

// Open a seeded external-payment event and wait for its attendance controls.
const openExternalEvent = async (page, event) => {
  await navigateToEvent(page, TEST_COMMUNITY_NAME, EXTERNAL_GROUP_SLUG, event.slug);
  await waitForAttendanceState(page);
};

// Reserve a ticket through external checkout and return the server response.
const startExternalCheckout = async (page, event, discountCode = "") => {
  await openExternalEvent(page, event);
  await expect(getAttendButton(page)).toContainText("Get ticket");
  await getAttendButton(page).click();

  const ticketModal = getTicketModal(page);
  await expect(ticketModal).toBeVisible();
  const ticketOptionSelector = `[data-attendance-role="ticket-type-option"][value="${event.ticketTypeId}"]`;
  await ticketModal.locator(ticketOptionSelector).locator("..").click();
  await expect(ticketModal.locator(ticketOptionSelector)).toBeChecked();

  if (discountCode) {
    await ticketModal.locator('[data-attendance-role="discount-code-input"]').fill(discountCode);
  }

  const response = await waitForActionResponse(page, () => getCheckoutButton(page).click(), {
    method: "POST",
    urlIncludes: `/event/${event.id}/checkout`,
  });
  await expect(ticketModal).toBeHidden();

  return response;
};

// Open an event's attendees section from the desktop group dashboard.
const openAttendeesTab = async (page, event) => {
  await navigateToPath(page, "/dashboard/group?tab=events");
  const eventRow = page.locator("#dashboard-content tbody tr", {
    hasText: event.name,
  });
  await expect(eventRow).toBeVisible();
  await waitForActionResponse(page, () => eventRow.locator('button[aria-label^="Edit event:"]').click(), {
    method: "GET",
    urlIncludes: `/dashboard/group/events/${event.id}/update`,
  });
  const attendeesTab = page.locator('button[data-section="attendees"]');
  const openAttendeesSection = async () => {
    if (await attendeesTab.isVisible()) {
      await attendeesTab.click();
      return;
    }

    await page.locator("[data-section-select]").selectOption("attendees");
  };
  await waitForActionResponse(page, openAttendeesSection, {
    method: "GET",
    urlIncludes: `/dashboard/group/events/${event.id}/attendees`,
  });

  const attendeesContent = page.locator("#attendees-content");
  await expect(attendeesContent.getByRole("table", { name: "Attendees list" })).toBeVisible();
  return attendeesContent;
};

// Open the mark-paid dialog for one attendee row.
const openMarkPaidDialog = async (page, attendeesContent, attendeeName) => {
  const attendeeRow = attendeesContent.locator("tbody tr", {
    hasText: attendeeName,
  });
  const actionsMenu = attendeeRow.locator("[data-actions-menu]");
  await actionsMenu.locator("summary").click();
  await actionsMenu.getByRole("menuitem", { name: "Mark payment received" }).click();

  const dialog = page.getByRole("dialog", { name: "Mark payment received" });
  await expect(dialog).toBeVisible();
  return { attendeeRow, dialog };
};

// Complete an external purchase from the organizer attendee table.
const markExternalPurchasePaid = async (page, event, attendeeName, note) => {
  const attendeesContent = await openAttendeesTab(page, event);
  const { dialog } = await openMarkPaidDialog(page, attendeesContent, attendeeName);
  await dialog.getByLabel("Payment details").fill(note);
  await Promise.all([
    page.waitForResponse(
      (response) =>
        response.request().method() === "POST" &&
        response.url().includes("/external-payment") &&
        response.ok(),
    ),
    page.waitForResponse(
      (response) =>
        response.request().method() === "GET" &&
        response.url().includes(`/events/${event.id}/attendees`) &&
        response.ok(),
    ),
    dialog.getByRole("button", { name: "Mark paid" }).click(),
  ]);
  await expect(dialog).toBeHidden();
};

// Submit an attendee refund request for a completed external purchase.
const requestExternalRefund = async (page, event, reason) => {
  await openExternalEvent(page, event);
  await getRefundButton(page).click();
  const requestDialog = page.getByRole("dialog", {
    name: "Request a refund",
  });
  await requestDialog.getByLabel("Reason (optional)").fill(reason);
  await waitForActionResponse(
    page,
    () => requestDialog.getByRole("button", { name: "Request refund" }).click(),
    {
      method: "POST",
      urlIncludes: `/event/${event.id}/refund-request`,
    },
  );
  await expect(page.locator(".swal2-popup")).toContainText(
    "Your refund request has been sent to the organizers.",
  );
  await dismissAlert(page);
};

test.describe("external payment journeys", () => {
  test.describe.configure({ mode: "serial" });

  test.beforeEach(() => {
    resetExternalPaymentFixtures();
  });

  test("registers externally and recovers a failed mark-paid request", async ({
    member1Page,
    organizerExternalGroupPage,
  }) => {
    const event = TEST_EXTERNAL_PAYMENT_EVENTS.lifecycle;
    const eventUrlPath = `/${TEST_COMMUNITY_NAME}/group/${EXTERNAL_GROUP_SLUG}/event/${event.slug}`;

    // Reserve the external ticket without leaving the event page.
    await startExternalCheckout(member1Page, event);
    expect(new URL(member1Page.url()).pathname).toBe(eventUrlPath);
    await expect(getAttendButton(member1Page)).toContainText("Open payment page");

    // Verify the payment trigger exposes the pending purchase details.
    const paymentDetailsTrigger = getAttendButton(member1Page);
    await paymentDetailsTrigger.focus();
    const paymentDetails = getAttendanceContainer(member1Page).getByText("Payment details", {
      exact: true,
    });
    await expect(paymentDetails).toBeVisible();
    await expect(getAttendanceContainer(member1Page)).toContainText("Awaiting organizer confirmation");
    await expect(getAttendanceContainer(member1Page)).toContainText("$12.34");
    await expect(getAttendanceContainer(member1Page)).toContainText("Confirm by");
    await expect(getAttendanceContainer(member1Page)).toContainText(/\bE(?:S|D)T\b/u);
    await expect(getAttendanceContainer(member1Page)).toContainText(
      "Include the reservation reference with the bank transfer.",
    );

    // Confirm the reservation is stored as a pending external purchase.
    const purchaseRecord = queryE2eDatabase(`
      select event_purchase_id || '|' ||
        coalesce(provider_payment_reference, event_purchase_id::text) || '|' ||
        status || '|' || charge_model
      from event_purchase
      where event_id = '${event.id}' and user_id = '${TEST_USER_IDS.member1}';
    `);
    const [purchaseId, reference, status, chargeModel] = purchaseRecord.split("|");
    expect(purchaseId).toBeTruthy();
    expect(reference).toBeTruthy();
    expect(status).toBe("pending");
    expect(chargeModel).toBe("external");

    // Open the organizer action and verify it retains the external reference.
    const attendeesContent = await openAttendeesTab(organizerExternalGroupPage, event);
    const { attendeeRow, dialog } = await openMarkPaidDialog(
      organizerExternalGroupPage,
      attendeesContent,
      "E2E Member One",
    );
    await expect(attendeeRow).toContainText("Payment pending");
    await expect(attendeeRow).toContainText(reference);
    await expect(attendeeRow).toContainText(/\bUTC\b/u);
    await expect(dialog).toContainText("External admission");
    await expect(dialog).toContainText(/(?:US)?\$12\.34/u);
    await expect(dialog).toContainText(reference);

    const paymentNote = "Bank transfer reconciled by the organizer";
    const detailsInput = dialog.getByLabel("Payment details");
    const submitButton = dialog.getByRole("button", { name: "Mark paid" });
    await detailsInput.fill(paymentNote);

    // Delay a failed request so duplicate submission protection is observable.
    let releaseFailedResponse;
    const failedResponseGate = new Promise((resolve) => {
      releaseFailedResponse = resolve;
    });
    let requestCount = 0;
    await organizerExternalGroupPage.route(
      `**/dashboard/group/events/${event.id}/purchases/${purchaseId}/external-payment`,
      async (route) => {
        requestCount += 1;
        await failedResponseGate;
        await route.fulfill({ status: 409 });
      },
    );

    const failedResponse = organizerExternalGroupPage.waitForResponse(
      (response) =>
        response.request().method() === "POST" &&
        response.url().endsWith(`/purchases/${purchaseId}/external-payment`),
    );
    await submitButton.click();
    await expect(submitButton).toBeDisabled();
    await submitButton.evaluate((button) => button.click());
    expect(requestCount).toBe(1);
    releaseFailedResponse();
    await failedResponse;

    // Keep the dialog and organizer note available after visible error feedback.
    await expect(organizerExternalGroupPage.locator(".swal2-popup")).toContainText(
      "Payment could not be marked as received. Check its status and try again.",
    );
    await dismissAlert(organizerExternalGroupPage);
    await expect(dialog).toBeVisible();
    await expect(detailsInput).toHaveValue(paymentNote);
    await expect(submitButton).toBeEnabled();
    await organizerExternalGroupPage.unroute(
      `**/dashboard/group/events/${event.id}/purchases/${purchaseId}/external-payment`,
    );

    // Retry against the real endpoint and wait for the attendee table refresh.
    await Promise.all([
      organizerExternalGroupPage.waitForResponse(
        (response) =>
          response.request().method() === "POST" &&
          response.url().endsWith(`/purchases/${purchaseId}/external-payment`) &&
          response.ok(),
      ),
      organizerExternalGroupPage.waitForResponse(
        (response) =>
          response.request().method() === "GET" &&
          response.url().includes(`/events/${event.id}/attendees`) &&
          response.ok(),
      ),
      submitButton.click(),
    ]);
    await expect(dialog).toBeHidden();
    await expect(attendeesContent).toContainText("Active");

    // Verify the successful retry persists the organizer's reconciliation note.
    const completedPurchase = queryE2eDatabase(`
      select status || '|' || external_payment_details
      from event_purchase where event_purchase_id = '${purchaseId}';
    `);
    expect(completedPurchase).toBe(`completed|${paymentNote}`);

    // Confirm the attendee now sees refund controls instead of registration.
    await openExternalEvent(member1Page, event);
    await expect(getRefundButton(member1Page)).toContainText("Request refund");
    await expect(getAttendButton(member1Page)).toBeHidden();
  });

  test("shows each mark-paid error without losing the organizer note", async ({
    member1Page,
    organizerExternalGroupPage,
  }) => {
    const event = TEST_EXTERNAL_PAYMENT_EVENTS.lifecycle;
    const paymentNote = "Bank transfer still needs organizer review";

    // Create one pending purchase and open its organizer action.
    await startExternalCheckout(member1Page, event);
    const purchaseId = getExternalPurchaseId(event.id, TEST_USER_IDS.member1);
    const attendeesContent = await openAttendeesTab(organizerExternalGroupPage, event);
    const { dialog } = await openMarkPaidDialog(
      organizerExternalGroupPage,
      attendeesContent,
      "E2E Member One",
    );
    const detailsInput = dialog.getByLabel("Payment details");
    const submitButton = dialog.getByRole("button", { name: "Mark paid" });
    await detailsInput.fill(paymentNote);

    const requestUrl = `**/dashboard/group/events/${event.id}/purchases/${purchaseId}/external-payment`;
    const failureCases = [
      {
        body: "The payment reservation expired before it was confirmed.",
        expectedMessage: "The payment reservation expired before it was confirmed.",
        status: 422,
      },
      {
        body: "Forbidden",
        expectedMessage: "It looks like you don't have permission to perform this operation.",
        status: 403,
      },
      {
        body: "Not found",
        expectedMessage: "Payment could not be marked as received. Check its status and try again.",
        status: 404,
      },
      {
        body: "Unexpected server failure",
        expectedMessage: "Payment could not be marked as received. Check its status and try again.",
        status: 500,
      },
    ];

    for (const failureCase of failureCases) {
      await organizerExternalGroupPage.route(requestUrl, (route) =>
        route.fulfill({
          body: failureCase.body,
          contentType: "text/plain",
          status: failureCase.status,
        }),
      );

      // Submit each failure and keep the modal ready for a later retry.
      await waitForActionResponse(organizerExternalGroupPage, () => submitButton.click(), {
        method: "POST",
        status: failureCase.status,
        urlIncludes: `/purchases/${purchaseId}/external-payment`,
      });
      await expect(organizerExternalGroupPage.locator(".swal2-popup")).toContainText(
        failureCase.expectedMessage,
      );
      await dismissAlert(organizerExternalGroupPage);
      await expect(dialog).toBeVisible();
      await expect(detailsInput).toHaveValue(paymentNote);
      await expect(submitButton).toBeEnabled();
      await organizerExternalGroupPage.unroute(requestUrl);
    }
  });

  test("ignores an older mark-paid response after another attendee opens", async ({
    member1Page,
    member2Page,
    organizerExternalGroupPage,
  }) => {
    const event = TEST_EXTERNAL_PAYMENT_EVENTS.lifecycle;

    // Create two purchases that share the organizer's mark-paid modal.
    await startExternalCheckout(member1Page, event);
    await startExternalCheckout(member2Page, event);
    const firstPurchaseId = getExternalPurchaseId(event.id, TEST_USER_IDS.member1);
    const secondPurchaseId = getExternalPurchaseId(event.id, TEST_USER_IDS.member2);
    const attendeesContent = await openAttendeesTab(organizerExternalGroupPage, event);
    const { dialog: firstDialog } = await openMarkPaidDialog(
      organizerExternalGroupPage,
      attendeesContent,
      "E2E Member One",
    );

    let releaseFirstResponse;
    let markFirstRequestStarted;
    const firstRequestStarted = new Promise((resolve) => {
      markFirstRequestStarted = resolve;
    });
    const firstResponseGate = new Promise((resolve) => {
      releaseFirstResponse = resolve;
    });
    const firstRequestUrl = `**/dashboard/group/events/${event.id}/purchases/${firstPurchaseId}/external-payment`;
    await organizerExternalGroupPage.route(firstRequestUrl, async (route) => {
      markFirstRequestStarted();
      await firstResponseGate;
      await route.fulfill({ status: 204 });
    });

    // Leave the first response pending, then reuse the modal for another attendee.
    await firstDialog.getByRole("button", { name: "Mark paid" }).click();
    await firstRequestStarted;
    await firstDialog.getByRole("button", { name: "Cancel" }).click();
    const { dialog: secondDialog } = await openMarkPaidDialog(
      organizerExternalGroupPage,
      attendeesContent,
      "E2E Member Two",
    );
    await expect(secondDialog).toContainText("E2E Member Two");

    const firstResponse = organizerExternalGroupPage.waitForResponse(
      (response) =>
        response.request().method() === "POST" &&
        response.url().endsWith(`/purchases/${firstPurchaseId}/external-payment`),
    );
    releaseFirstResponse();
    await firstResponse;

    // The older success cannot close or retarget the newer attendee's modal.
    await expect(secondDialog).toBeVisible();
    await expect(secondDialog).toContainText("E2E Member Two");
    await expect(secondDialog.locator("#attendee-external-payment-form")).toHaveAttribute(
      "hx-post",
      `/dashboard/group/events/${event.id}/purchases/${secondPurchaseId}/external-payment`,
    );
    await organizerExternalGroupPage.unroute(firstRequestUrl);
  });

  test("completes a fully discounted ticket without external payment", async ({ member2Page }) => {
    const event = TEST_EXTERNAL_PAYMENT_EVENTS.lifecycle;

    // Redeem a full discount and complete the ticket without external payment.
    await startExternalCheckout(member2Page, event, event.discountCode);
    await expect(member2Page.locator(".swal2-popup")).toContainText(
      "You have successfully registered for this event.",
    );
    await dismissAlert(member2Page);
    await expect(getLeaveButton(member2Page)).toContainText("Cancel attendance");
    await expect(getRefundButton(member2Page)).toBeHidden();
    await expect(getAttendButton(member2Page)).toBeHidden();

    // Verify the zero-total purchase uses the provider-free charge model.
    const purchaseRecord = queryE2eDatabase(`
      select status || '|' || charge_model || '|' || amount_minor
      from event_purchase
      where event_id = '${event.id}' and user_id = '${TEST_USER_IDS.member2}';
    `);
    expect(purchaseRecord).toBe("completed|ocg-free|0");
  });

  test("refreshes stale capacity and releases canceled and expired holds", async ({
    member1Page,
    member2Page,
  }) => {
    const event = TEST_EXTERNAL_PAYMENT_EVENTS.capacity;

    // Keep one ticket modal stale while another member reserves the final seat.
    await openExternalEvent(member1Page, event);
    await openExternalEvent(member2Page, event);

    await getAttendButton(member2Page).click();
    const staleTicketModal = getTicketModal(member2Page);
    const staleTicketOptionSelector = `[data-attendance-role="ticket-type-option"][value="${event.ticketTypeId}"]`;
    await staleTicketModal.locator(staleTicketOptionSelector).locator("..").click();
    await expect(staleTicketModal.locator(staleTicketOptionSelector)).toBeChecked();

    // Reserve the only seat from the first member's current event page.
    await getAttendButton(member1Page).click();
    const member1TicketOption = getTicketModal(member1Page).locator(
      `[data-attendance-role="ticket-type-option"][value="${event.ticketTypeId}"]`,
    );
    await member1TicketOption.locator("..").click();
    await expect(
      getTicketModal(member1Page).locator(
        `[data-attendance-role="ticket-type-option"][value="${event.ticketTypeId}"]`,
      ),
    ).toBeChecked();
    await waitForActionResponse(member1Page, () => getCheckoutButton(member1Page).click(), {
      method: "POST",
      urlIncludes: `/event/${event.id}/checkout`,
    });

    // Submit the stale modal and verify its conflict refreshes availability.
    const [soldOutResponse] = await Promise.all([
      member2Page.waitForResponse(
        (response) =>
          response.request().method() === "POST" &&
          response.url().includes(`/event/${event.id}/checkout`) &&
          response.status() === 409,
      ),
      getCheckoutButton(member2Page).click(),
    ]);
    expect(await soldOutResponse.json()).toMatchObject({
      conflict: "ticket-type-sold-out",
    });
    await expect(staleTicketModal).toBeHidden();
    await expect(member2Page.locator(".swal2-popup")).toContainText(
      "This ticket has just sold out. Event availability has been updated.",
    );
    await dismissAlert(member2Page);
    await expect(getAttendButton(member2Page)).toBeVisible();
    await expect(getAttendButton(member2Page)).toBeDisabled();
    await expect(getAttendButton(member2Page)).toHaveAccessibleName("Tickets unavailable");
    await expect(member2Page.getByText("Sold out", { exact: true }).first()).toBeVisible();

    // Cancel the first hold and verify the released seat becomes available.
    const cancelCheckoutButton = getAttendanceContainer(member1Page).locator(
      '[data-attendance-role="checkout-cancel-btn"]',
    );
    await getAttendanceContainer(member1Page)
      .locator('[data-attendance-role="actions-menu"] summary')
      .click();
    await cancelCheckoutButton.click();
    const confirmCancellation = member1Page.getByRole("button", {
      name: "Yes",
    });
    await waitForActionResponse(member1Page, () => confirmCancellation.click(), {
      method: "DELETE",
      urlIncludes: `/event/${event.id}/checkout`,
    });
    await dismissAlert(member1Page);

    await openExternalEvent(member2Page, event);
    await expect(getAttendButton(member2Page)).toContainText("Get ticket");

    // Expire the replacement hold and verify the public page releases it.
    await startExternalCheckout(member2Page, event);
    queryE2eDatabase(`
      update event_purchase
      set hold_expires_at = current_timestamp - interval '1 minute'
      where event_id = '${event.id}' and user_id = '${TEST_USER_IDS.member2}';
    `);

    await openExternalEvent(member2Page, event);
    await expect(getAttendButton(member2Page)).toContainText("Get ticket");
    await expect
      .poll(
        () =>
          queryE2eDatabase(`
        select status from event_purchase
        where event_id = '${event.id}' and user_id = '${TEST_USER_IDS.member2}';
      `),
        { timeout: 20_000 },
      )
      .toBe("expired");
  });

  test("keeps checkout retryable when payment setup is unavailable", async ({ member1Page }) => {
    const event = TEST_EXTERNAL_PAYMENT_EVENTS.lifecycle;

    // Open checkout and select the external paid ticket.
    await openExternalEvent(member1Page, event);
    await getAttendButton(member1Page).click();
    const ticketModal = getTicketModal(member1Page);
    const ticketOptionSelector = `[data-attendance-role="ticket-type-option"][value="${event.ticketTypeId}"]`;
    await ticketModal.locator(ticketOptionSelector).locator("..").click();
    await expect(ticketModal.locator(ticketOptionSelector)).toBeChecked();

    const checkoutUrl = `**/event/${event.id}/checkout`;
    await member1Page.route(checkoutUrl, (route) =>
      route.fulfill({
        body: JSON.stringify({ conflict: "payment-setup-unavailable" }),
        contentType: "application/json",
        status: 409,
      }),
    );

    // Reject checkout with the typed conflict and keep a useful retry path.
    await waitForActionResponse(member1Page, () => getCheckoutButton(member1Page).click(), {
      method: "POST",
      status: 409,
      urlIncludes: `/event/${event.id}/checkout`,
    });
    await expect(ticketModal).toBeHidden();
    await expect(member1Page.locator(".swal2-popup")).toContainText(
      "Payment is temporarily unavailable for this ticket. Try again later or contact the organizer.",
    );
    await dismissAlert(member1Page);
    await expect(getAttendButton(member1Page)).toContainText("Get ticket");
    await expect(getAttendButton(member1Page)).toBeEnabled();
    await member1Page.unroute(checkoutUrl);
  });

  test("claims an invitation into an external pending payment", async ({ pending1Page }) => {
    const event = TEST_EXTERNAL_PAYMENT_EVENTS.invitation;

    // Seed a pending organizer invitation for the dedicated external event.
    queryE2eDatabase(`
      insert into admission_offer (
        admission_offer_id,
        event_id,
        event_ticket_type_id,
        expires_at,
        organizer_user_id,
        source,
        status,
        user_id
      ) values (
        '${INVITATION_OFFER_ID}',
        '${event.id}',
        '${event.ticketTypeId}',
        current_timestamp + interval '5 days',
        '${TEST_USER_IDS.organizer1}',
        'organizer_invitation',
        'pending',
        '${TEST_USER_IDS.pending1}'
      );
    `);

    // Claim the offer from the attendee dashboard through external checkout.
    await navigateToPath(pending1Page, "/dashboard/user?tab=invitations");
    const offerRow = pending1Page.locator("#dashboard-content tbody tr", {
      hasText: event.name,
    });
    await expect(offerRow).toContainText("External invited admission");
    const actionsMenu = offerRow.locator("[data-actions-menu]");
    await actionsMenu.locator("summary").click();
    await actionsMenu.getByRole("menuitem", { name: "Claim offer" }).click();

    const claimDialog = pending1Page.getByRole("dialog", {
      name: "Claim offer",
    });
    await expect(claimDialog).toBeVisible();
    await waitForActionResponse(
      pending1Page,
      () => claimDialog.getByRole("button", { name: "Claim offer", exact: true }).click(),
      {
        method: "POST",
        urlIncludes: `/event/${event.id}/checkout`,
      },
    );
    await expect(pending1Page.locator(".swal2-popup")).toContainText(
      "Your reservation is awaiting organizer confirmation.",
    );
    await dismissAlert(pending1Page);

    // Verify payment details and the external link remain on the invitation row.
    await expect(offerRow).toContainText("Confirm by");
    await expect(offerRow).toContainText("Reference:");
    await expect(offerRow).toContainText("Use the invitation reference when sending payment.");
    await actionsMenu.locator("summary").click();
    await expect(actionsMenu.getByRole("menuitem", { name: "Open payment page" })).toHaveAttribute(
      "target",
      "_blank",
    );
    await expect(pending1Page).toHaveURL(/\/dashboard\/user\?tab=invitations/u);

    // Confirm the claimed offer created a pending external purchase.
    expect(
      queryE2eDatabase(`
        select status || '|' || charge_model
        from event_purchase
        where event_id = '${event.id}' and user_id = '${TEST_USER_IDS.pending1}';
      `),
    ).toBe("pending|external");
  });

  test("records an external refund and cancels attendance immediately", async ({
    member1Page,
    organizerExternalGroupPage,
  }) => {
    const event = TEST_EXTERNAL_PAYMENT_EVENTS.lifecycle;

    // Complete an external purchase and submit its attendee refund request.
    await startExternalCheckout(member1Page, event);
    await markExternalPurchasePaid(
      organizerExternalGroupPage,
      event,
      "E2E Member One",
      "Payment confirmed before refund",
    );

    await requestExternalRefund(member1Page, event, "Unable to attend");

    // Open the group refund action and verify its external context contract.
    await navigateToPath(organizerExternalGroupPage, "/dashboard/group?tab=refunds");
    const refundRow = organizerExternalGroupPage.locator("#dashboard-content tbody tr", {
      hasText: "E2E Member One",
    });
    await expect(refundRow).toContainText(event.name);
    const refundAmountCell = refundRow.locator("td").nth(2);
    const refundStatusCell = refundRow.locator("td").nth(3);
    await expect(refundAmountCell).toContainText(/(?:US)?\$12\.34/u);
    await expect(refundAmountCell).toContainText("External");
    await expect(refundStatusCell).toContainText("Needs review");
    await expect(refundStatusCell).not.toContainText("External");
    await expect(
      organizerExternalGroupPage.getByText(
        /external refunds can still be recorded after the money is returned outside OCG/u,
      ),
    ).toBeVisible();
    const actionsMenu = refundRow.locator("[data-actions-menu]");
    await actionsMenu.locator("summary").click();
    const approveButton = actionsMenu.getByRole("button", {
      name: "Approve refund",
    });
    await expect(approveButton).toHaveAttribute("data-refund-external", "true");
    await approveButton.click();

    const approveDialog = organizerExternalGroupPage.getByRole("dialog", {
      name: "Approve refund request",
    });
    await expect(approveDialog).toContainText("This payment was collected outside this platform.");
    await expect(approveDialog).toContainText("Unable to attend");
    await approveDialog.getByLabel("Review note (optional)").fill("Refund confirmed externally");

    // Record the external refund and verify the organizer success feedback.
    await waitForActionResponse(
      organizerExternalGroupPage,
      () => approveDialog.getByRole("button", { name: "Approve refund" }).click(),
      {
        method: "PUT",
        urlIncludes: "/dashboard/group/refunds/",
        urlEndsWith: "/approve",
      },
    );
    await expect(organizerExternalGroupPage.locator(".swal2-popup")).toContainText(
      "Refund recorded. Attendance canceled.",
    );
    await dismissAlert(organizerExternalGroupPage);

    // Verify external approval cancels attendance without a provider refund row.
    expect(
      queryE2eDatabase(`
        select ep.status || '|' || err.status || '|' || coalesce(ea.status, '')
        from event_purchase ep
        join event_refund_request err using (event_purchase_id)
        left join event_attendee ea
          on ea.event_id = ep.event_id and ea.user_id = ep.user_id
        where ep.event_id = '${event.id}' and ep.user_id = '${TEST_USER_IDS.member1}';
      `),
    ).toBe("refunded|approved|attendance-canceled");
    expect(
      queryE2eDatabase(`
        select count(*) from event_purchase_refund epr
        join event_purchase ep using (event_purchase_id)
        where ep.event_id = '${event.id}';
      `),
    ).toBe("0");
  });

  test("preserves external context when rejecting a refund", async ({
    member2Page,
    organizerExternalGroupPage,
  }) => {
    const event = TEST_EXTERNAL_PAYMENT_EVENTS.lifecycle;

    // Complete another external purchase and request a refund for rejection.
    await startExternalCheckout(member2Page, event);
    await markExternalPurchasePaid(
      organizerExternalGroupPage,
      event,
      "E2E Member Two",
      "Payment confirmed before rejection",
    );
    await requestExternalRefund(member2Page, event, "Duplicate reservation");

    // Open rejection from the production refund row and retain external context.
    await navigateToPath(organizerExternalGroupPage, "/dashboard/group?tab=refunds");
    const refundRow = organizerExternalGroupPage.locator("#dashboard-content tbody tr", {
      hasText: "E2E Member Two",
    });
    const actionsMenu = refundRow.locator("[data-actions-menu]");
    await actionsMenu.locator("summary").click();
    const rejectButton = actionsMenu.getByRole("button", {
      name: "Reject refund",
    });
    await expect(rejectButton).toHaveAttribute("data-refund-external", "true");
    await rejectButton.click();

    const rejectDialog = organizerExternalGroupPage.getByRole("dialog", {
      name: "Reject refund request",
    });
    await expect(rejectDialog).toContainText("This payment was collected outside this platform.");
    await expect(rejectDialog).toContainText("Duplicate reservation");
    const rejectionReason = "The reservation is outside the refund policy";
    await rejectDialog.getByLabel("Reason shown to attendee").fill(rejectionReason);

    // Reject the request and verify the organizer receives specific feedback.
    await waitForActionResponse(
      organizerExternalGroupPage,
      () => rejectDialog.getByRole("button", { name: "Reject refund" }).click(),
      {
        method: "PUT",
        urlIncludes: "/dashboard/group/refunds/",
        urlEndsWith: "/reject",
      },
    );
    await expect(organizerExternalGroupPage.locator(".swal2-popup")).toContainText(
      "Refund request rejected.",
    );
    await dismissAlert(organizerExternalGroupPage);

    // Verify the attendee sees the preserved rejection reason on the event.
    await openExternalEvent(member2Page, event);
    await expect(getRefundButton(member2Page)).toContainText("Refund rejected");
    await getAttendanceContainer(member2Page)
      .locator('[data-attendance-role="refund-rejection-trigger"]')
      .focus();
    await expect(getAttendanceContainer(member2Page)).toContainText(rejectionReason);

    // Confirm rejection keeps the purchase completed and stores its review note.
    expect(
      queryE2eDatabase(`
        select ep.status || '|' || err.status || '|' || err.review_note
        from event_purchase ep
        join event_refund_request err using (event_purchase_id)
        where ep.event_id = '${event.id}' and ep.user_id = '${TEST_USER_IDS.member2}';
      `),
    ).toBe(`completed|rejected|${rejectionReason}`);
  });

  test("stops new sales after eligibility loss and preserves existing holds", async ({
    member1Page,
    member2Page,
    organizerExternalGroupPage,
  }) => {
    const event = TEST_EXTERNAL_PAYMENT_EVENTS.lifecycle;

    // Create a valid hold before removing the group's country from the allowlist.
    await startExternalCheckout(member1Page, event);
    queryE2eDatabase("select sync_external_payments_config(array['CA']::text[], 72, 336);");

    try {
      // Verify eligibility loss disables only new paid registrations.
      await openExternalEvent(member2Page, event);
      await expect(getAttendButton(member2Page)).toContainText("Tickets unavailable");
      await expect(getAttendButton(member2Page)).toBeDisabled();

      await navigateToPath(organizerExternalGroupPage, "/dashboard/group?tab=settings");
      await expect(organizerExternalGroupPage.locator("#dashboard-content")).toContainText(
        "This group's country is no longer on the operator allowlist.",
      );

      // Confirm an existing external hold remains recoverable by the organizer.
      await markExternalPurchasePaid(
        organizerExternalGroupPage,
        event,
        "E2E Member One",
        "Existing hold confirmed after eligibility loss",
      );
      expect(
        queryE2eDatabase(`
          select status from event_purchase
          where event_id = '${event.id}' and user_id = '${TEST_USER_IDS.member1}';
        `),
      ).toBe("completed");
    } finally {
      // Restore operator eligibility for the remaining serial journeys.
      queryE2eDatabase("select sync_external_payments_config(array['US']::text[], 72, 336);");
    }
  });

  test("shows external payment eligibility through the settings toggle", async ({
    organizerExternalGroupPage,
  }) => {
    const settingsPath = "/dashboard/group?tab=settings";
    const toggleName = "Collect ticket payments outside this platform";

    try {
      // Eligible groups receive the active toggle and its visual switch track.
      await navigateToPath(organizerExternalGroupPage, settingsPath);
      const enabledToggle = organizerExternalGroupPage.getByRole("checkbox", {
        name: toggleName,
      });
      await expect(enabledToggle).toBeChecked();
      await expect(enabledToggle).toBeEnabled();
      await expect(enabledToggle).toHaveClass(/\bsr-only\b.*\bpeer\b/u);
      await expect(enabledToggle.locator("xpath=following-sibling::div[1]")).toBeVisible();

      // Removing the country from the allowlist leaves the toggle visible but inert.
      queryE2eDatabase("select sync_external_payments_config(array['CA']::text[], 72, 336);");
      await navigateToPath(organizerExternalGroupPage, settingsPath);
      const ineligibleToggle = organizerExternalGroupPage.getByRole("checkbox", { name: toggleName });
      await expect(ineligibleToggle).toHaveCount(1);
      await expect(ineligibleToggle).toBeChecked();
      await expect(ineligibleToggle).toBeDisabled();
      await expect(ineligibleToggle.locator("xpath=following-sibling::div[1]")).toBeVisible();
      const eligibilityWarning = organizerExternalGroupPage.getByRole("alert");
      await expect(eligibilityWarning).toContainText(
        "External payments are not available for groups located in United States.",
      );
      await expect(eligibilityWarning).toHaveClass(/border-amber-200/u);
      await expect(eligibilityWarning).toHaveClass(/bg-amber-50/u);

      // A missing country explains that the location must be saved first.
      queryE2eDatabase(`
        update "group"
        set country_code = null, country_name = null
        where group_id = '${EXTERNAL_GROUP_ID}';
      `);
      await navigateToPath(organizerExternalGroupPage, settingsPath);
      await expect(
        organizerExternalGroupPage.getByRole("checkbox", {
          name: toggleName,
        }),
      ).toBeDisabled();
      await expect(organizerExternalGroupPage.getByRole("alert")).toContainText(
        "Set the group's location above and save the settings to determine eligibility.",
      );
    } finally {
      queryE2eDatabase(`
        select sync_external_payments_config(array['US']::text[], 72, 336);
        update "group"
        set country_code = 'US', country_name = 'United States'
        where group_id = '${EXTERNAL_GROUP_ID}';
      `);
    }
  });

  test("warns before settings invalidate published external events", async ({
    organizerExternalGroupPage,
  }) => {
    const settingsPath = "/dashboard/group?tab=settings";
    const updateSettingsButton = organizerExternalGroupPage.getByRole("button", { name: "Update Group" });

    try {
      // Published external events prevent organizers from disabling the rail.
      await navigateToPath(organizerExternalGroupPage, settingsPath);
      await organizerExternalGroupPage
        .getByRole("checkbox", {
          name: "Collect ticket payments outside this platform",
        })
        .uncheck({ force: true });
      await waitForActionResponse(organizerExternalGroupPage, () => updateSettingsButton.click(), {
        method: "PUT",
        status: 422,
        urlIncludes: "/dashboard/group/settings/update",
      });
      await expect(organizerExternalGroupPage.locator(".swal2-popup")).toContainText(
        "external payments cannot be disabled while published external paid events are upcoming",
      );
      await dismissAlert(organizerExternalGroupPage);

      // An eligible country change still cannot strand events in another country.
      queryE2eDatabase("select sync_external_payments_config(array['US', 'CA']::text[], 72, 336);");
      await navigateToPath(organizerExternalGroupPage, settingsPath);
      for (const [fieldId, value] of [
        ["group-location-search-country_code", "CA"],
        ["group-location-search-country_name", "Canada"],
      ]) {
        await organizerExternalGroupPage.locator(`#${fieldId}`).evaluate((field, nextValue) => {
          field.value = nextValue;
          field.dispatchEvent(new Event("input", { bubbles: true }));
        }, value);
      }
      await waitForActionResponse(organizerExternalGroupPage, () => updateSettingsButton.click(), {
        method: "PUT",
        status: 422,
        urlIncludes: "/dashboard/group/settings/update",
      });
      await expect(organizerExternalGroupPage.locator(".swal2-popup")).toContainText(
        "published external paid events require a venue in the group country",
      );
      await dismissAlert(organizerExternalGroupPage);
    } finally {
      queryE2eDatabase("select sync_external_payments_config(array['US']::text[], 72, 336);");
    }
  });

  test("explains external cancellation and unpublish consequences", async ({
    organizerExternalGroupPage,
  }) => {
    const event = TEST_EXTERNAL_PAYMENT_EVENTS.lifecycle;

    // Open the external event actions without changing its durable state.
    await navigateToPath(organizerExternalGroupPage, "/dashboard/group?tab=events");
    const eventRow = organizerExternalGroupPage.locator("#dashboard-content tbody tr", {
      hasText: event.name,
    });
    const actionsButton = eventRow.locator(".btn-actions");

    // Cancellation directs the organizer to return external money outside OCG.
    await actionsButton.click();
    await eventRow.locator('button[id^="cancel-event-"]').click();
    const cancellationAlert = organizerExternalGroupPage.locator(".swal2-popup");
    await expect(cancellationAlert).toContainText(
      "Any external payments already received must be returned by an organizer outside OCG.",
    );
    await cancellationAlert.getByRole("button", { name: "Keep event" }).click();
    await expect(cancellationAlert).toBeHidden();

    // Unpublishing distinguishes expiring reservations from confirmed attendees.
    await actionsButton.click();
    await eventRow.locator('button[id^="unpublish-event-"]').click();
    const unpublishAlert = organizerExternalGroupPage.locator(".swal2-popup");
    await expect(unpublishAlert).toContainText(/pending reservations?.*expire/iu);
    await expect(unpublishAlert).toContainText(/confirmed attendees?.*remain/iu);
    await unpublishAlert.getByRole("button", { name: "No" }).click();
    await expect(unpublishAlert).toBeHidden();
  });

  test("copies and clears external payment form values as one unit", async ({
    organizerExternalGroupPage,
  }) => {
    // Open a blank event form in the external-payment test group.
    await organizerExternalGroupPage.setViewportSize({
      height: 900,
      width: 1600,
    });
    await navigateToPath(organizerExternalGroupPage, "/dashboard/group?tab=events");
    await organizerExternalGroupPage.getByRole("button", { name: "Add Event" }).click();
    await expect(organizerExternalGroupPage.locator('[data-event-page="add"]')).toBeVisible();
    await organizerExternalGroupPage.locator('button[data-section="payments"]').click();
    await expect(organizerExternalGroupPage.locator('[data-content="payments"]')).toBeVisible();

    // Select a source event through the reusable event-copy control.
    const copyEvent = async (eventName) => {
      const selector = organizerExternalGroupPage.locator("event-selector");
      await selector.getByRole("button", { name: "Select event" }).click();
      await selector.getByPlaceholder("Search events").fill(eventName);
      const eventOption = selector.getByRole("button", {
        name: new RegExp(eventName, "u"),
      });
      await expect(eventOption).toBeVisible();
      await eventOption.click();
      await expect(selector.getByRole("button", { name: "Select event" })).toContainText(eventName);
    };

    const externalUrl = organizerExternalGroupPage.locator("#external_payment_url");
    const externalInstructions = organizerExternalGroupPage.locator("#external_payment_instructions");
    const externalWindow = organizerExternalGroupPage.locator("#external_payment_window_hours");
    const paymentCurrency = organizerExternalGroupPage.locator("#payment_currency_code");

    // Verify the destination form starts without external-payment values.
    await expect(externalUrl).toHaveValue("");
    await expect(externalInstructions).toHaveValue("");
    await expect(externalWindow).toHaveValue("");
    await expect(externalInstructions).toHaveCSS("resize", "vertical");

    await externalUrl.fill("https://payments.example.com/stale");
    await externalInstructions.fill("Stale instructions");
    await externalWindow.fill("96");

    // Copy an external event and replace every stale destination value.
    await copyEvent(TEST_EXTERNAL_PAYMENT_EVENTS.lifecycle.name);
    await expect(externalUrl).toHaveValue("https://payments.example.com/external-lifecycle");
    await expect(externalInstructions).toHaveValue(
      "Include the reservation reference with the bank transfer.",
    );
    await expect(externalWindow).toHaveValue("72");
    await expect(externalWindow).toHaveAttribute("min", "1");
    await expect(externalWindow).toHaveAttribute("max", "336");
    await expect(externalUrl).toHaveJSProperty("required", true);

    // Keep the currency first, URL and window together, and instructions below.
    const [currencyBox, urlBox, windowBox, instructionsBox] = await Promise.all([
      paymentCurrency.boundingBox(),
      externalUrl.boundingBox(),
      externalWindow.boundingBox(),
      externalInstructions.boundingBox(),
    ]);
    expect(currencyBox).not.toBeNull();
    expect(urlBox).not.toBeNull();
    expect(windowBox).not.toBeNull();
    expect(instructionsBox).not.toBeNull();
    expect(currencyBox.y).toBeLessThan(urlBox.y);
    expect(Math.abs(urlBox.y - windowBox.y)).toBeLessThanOrEqual(2);
    expect(instructionsBox.y).toBeGreaterThan(urlBox.y);
    expect(instructionsBox.width).toBeGreaterThan(urlBox.width);

    // A positive copied price makes the external URL actionable validation.
    await externalUrl.fill("");
    await expect(externalUrl).toHaveJSProperty(
      "validationMessage",
      "Paid tickets require an external payment URL.",
    );
    await externalUrl.fill("https://payments.example.com/external-lifecycle");

    // Verify the values that the payments form would submit.
    const submittedExternalValues = await organizerExternalGroupPage
      .locator("#payments-form")
      .evaluate((form) => Object.fromEntries(new FormData(form)));
    expect(submittedExternalValues).toMatchObject({
      external_payment_instructions: "Include the reservation reference with the bank transfer.",
      external_payment_url: "https://payments.example.com/external-lifecycle",
      external_payment_window_hours: "72",
    });

    // Copy another external event and update all three values together.
    await copyEvent(TEST_EXTERNAL_PAYMENT_EVENTS.capacity.name);
    await expect(externalUrl).toHaveValue("https://payments.example.com/external-capacity");
    await expect(externalInstructions).toHaveValue("Complete payment before the reservation expires.");
    await expect(externalWindow).toHaveValue("24");

    // Copy a free event and clear the complete external-payment field set.
    await copyEvent(TEST_EXTERNAL_PAYMENT_EVENTS.copyFree.name);
    await expect(externalUrl).toHaveValue("");
    await expect(externalInstructions).toHaveValue("");
    await expect(externalWindow).toHaveValue("");
    await expect(externalUrl).toHaveJSProperty("required", false);
    await expect(externalUrl).toHaveJSProperty("validationMessage", "");
  });

  test("keeps mark-paid modal focus contained and restores page state", async ({
    member1Page,
    organizerExternalGroupPage,
  }) => {
    const event = TEST_EXTERNAL_PAYMENT_EVENTS.lifecycle;

    // Create the pending purchase required by the organizer action.
    await startExternalCheckout(member1Page, event);

    // Open the organizer dialog and verify focus stays contained.
    const attendeesContent = await openAttendeesTab(organizerExternalGroupPage, event);
    const { attendeeRow, dialog } = await openMarkPaidDialog(
      organizerExternalGroupPage,
      attendeesContent,
      "E2E Member One",
    );
    await expect(organizerExternalGroupPage.locator("body")).toHaveCSS("overflow", "hidden");
    await dialog.getByRole("button", { name: "Mark paid" }).focus();
    await organizerExternalGroupPage.keyboard.press("Tab");
    expect(await dialog.evaluate((modal) => modal.contains(document.activeElement))).toBe(true);

    // Dismiss with Escape and restore scroll and focus to the attendee action.
    await organizerExternalGroupPage.keyboard.press("Escape");
    await expect(dialog).toBeHidden();
    await expect(organizerExternalGroupPage.locator("body")).not.toHaveCSS("overflow", "hidden");
    await expect(attendeeRow.locator("[data-actions-menu] summary")).toBeFocused();
  });

  test("@mobile keeps pending payment details within the viewport", async ({ member1Page }) => {
    const event = TEST_EXTERNAL_PAYMENT_EVENTS.lifecycle;
    const longInstructionToken = `BANK-${"I".repeat(96)}`;
    const longPaymentReference = `REFERENCE-${"R".repeat(96)}`;

    // Store multiline instructions before checkout snapshots the payment details.
    queryE2eDatabase(`
      update event
      set external_payment_instructions = $$Transfer to account 1234
Use this unbroken bank code: ${longInstructionToken}$$
      where event_id = '${event.id}';
    `);

    // Create a pending purchase and inspect its compact payment details.
    await startExternalCheckout(member1Page, event);
    queryE2eDatabase(`
      update event_purchase
      set provider_payment_reference = '${longPaymentReference}'
      where event_id = '${event.id}' and user_id = '${TEST_USER_IDS.member1}';
    `);
    await openExternalEvent(member1Page, event);
    const attendanceContainer = getAttendanceContainer(member1Page);
    const paymentButton = getAttendButton(member1Page);
    await paymentButton.focus();
    await expect(attendanceContainer.getByText("Payment details", { exact: true })).toBeVisible();
    const instructionsValue = attendanceContainer.locator(
      '[data-attendance-role="external-payment-instructions"] [data-attendance-detail-value]',
    );
    const referenceValue = attendanceContainer.locator(
      '[data-attendance-role="external-payment-reference"] [data-attendance-detail-value]',
    );
    await expect(instructionsValue).toHaveText(
      `Transfer to account 1234\nUse this unbroken bank code: ${longInstructionToken}`,
    );
    await expect(instructionsValue).toHaveCSS("white-space", "pre-wrap");
    await expect(referenceValue).toHaveText(longPaymentReference);
    const paymentDetailsPanel = attendanceContainer.locator(
      '[data-attendance-role="external-payment-details"] [role="tooltip"]',
    );
    const paymentDetailsBox = await paymentDetailsPanel.boundingBox();
    const viewportSize = member1Page.viewportSize();
    expect(paymentDetailsBox).not.toBeNull();
    expect(viewportSize).not.toBeNull();
    expect(paymentDetailsBox.x).toBeGreaterThanOrEqual(0);
    expect(paymentDetailsBox.x + paymentDetailsBox.width).toBeLessThanOrEqual(viewportSize.width);
    expect(await paymentDetailsPanel.evaluate((panel) => panel.scrollWidth <= panel.clientWidth + 1)).toBe(
      true,
    );
  });
});
