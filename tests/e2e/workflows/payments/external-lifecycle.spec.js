import { expect, test } from "../../fixtures.js";
import { queryE2eDatabase } from "../../database.js";
import { deleteNotifications, expectNewNotifications, snapshotNotifications } from "../../notifications.js";
import { TEST_COMMUNITY_NAME, TEST_EXTERNAL_PAYMENT_EVENTS, TEST_USER_IDS } from "../../seed.js";
import { getAttendanceContainer, getAttendButton, getLeaveButton } from "../../site/event/helpers.js";
import { navigateToPath, waitForActionResponse } from "../../utils.js";
import {
  EXTERNAL_GROUP_SLUG,
  dismissAlert,
  getCheckoutButton,
  getRefundButton,
  getTicketModal,
  openAttendeesTab,
  openExternalEvent,
  openMarkPaidDialog,
  resetExternalPaymentFixtures,
  startExternalCheckout,
} from "./external-helpers.js";

const INVITATION_OFFER_ID = "59555555-5555-5555-5555-555555555926";

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
    let notificationIds = [];

    // Reserve the external ticket without leaving the event page.
    const pendingPaymentSnapshot = snapshotNotifications();
    try {
      // Start checkout and assert the pending payment notification.
      await startExternalCheckout(member1Page, event);
      const hostBox = member1Page.locator("[data-event-host]");
      await expect(hostBox).toContainText("Host");
      await expect(hostBox).toContainText("This event is hosted by E2E External Payee Co");
      notificationIds = expectNewNotifications(pendingPaymentSnapshot, [
        { kind: "event-external-payment-pending", userIds: [TEST_USER_IDS.member1] },
      ]);
    } finally {
      // Remove pending payment notifications from the reservation.
      deleteNotifications(notificationIds);
    }
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

    // Enter the organizer's reconciliation note.
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

    // Submit the delayed failure and verify duplicate clicks are ignored.
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
    const welcomeSnapshot = snapshotNotifications();
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
    deleteNotificationsSince(welcomeSnapshot, "event-welcome", [TEST_USER_IDS.member1]);
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

    // Define the mark-paid failure responses and the messages each must surface.
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

    // Exercise each failure response and keep the organizer note retryable.
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

    // Hold the first mark-paid response until a second attendee opens.
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

    // Release the older response after the second attendee owns the modal.
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

    // Mock checkout setup unavailability for the selected ticket.
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

    // Confirm the invitation claim through the external checkout endpoint.
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
    await referenceValue.evaluate((referenceElement, paymentReference) => {
      referenceElement.textContent = paymentReference;
    }, longPaymentReference);
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

/** Deletes matching notification table rows created after the snapshot. */
const deleteNotificationsSince = (snapshot, kind, userIds) => {
  queryE2eDatabase(`
    delete from notification
    where created_at >= '${snapshot.createdAfter}'::timestamptz
    and kind = '${kind}'
    and user_id in (${userIds.map((userId) => `'${userId}'::uuid`).join(", ")});
  `);
};

/** Reads the purchase identifier created for one attendee and event. */
const getExternalPurchaseId = (eventId, userId) =>
  queryE2eDatabase(`
    select event_purchase_id from event_purchase
    where event_id = '${eventId}' and user_id = '${userId}';
  `);
