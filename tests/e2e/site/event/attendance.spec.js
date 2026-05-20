import { expect, test } from "../../fixtures.js";

import {
  E2E_PAYMENTS_ENABLED,
  TEST_COMMUNITY_NAME,
  TEST_EVENT_IDS,
  TEST_EVENT_NAMES,
  TEST_EVENT_SLUGS,
  TEST_GROUP_SLUGS,
  TEST_PAYMENT_EVENT_IDS,
  TEST_PAYMENT_EVENT_NAMES,
  TEST_PAYMENT_EVENT_SLUGS,
  getAttendButton,
  getLeaveButton,
  navigateToEvent,
  waitForAttendanceState,
} from "../../utils.js";

// Cancel attendance when the current user is already registered.
const cancelAttendance = async (page, eventId) => {
  const leaveButton = getLeaveButton(page);
  await expect(leaveButton).toBeVisible();

  // Request attendance cancellation before confirming the dialog.
  await leaveButton.click();
  const confirmButton = page.getByRole("button", { name: "Yes" });
  await expect(confirmButton).toBeVisible();

  // Confirm cancellation and wait for the attendance record to be removed.
  await Promise.all([
    page.waitForResponse(
      (response) =>
        response.request().method() === "DELETE" &&
        response.url().includes(`/event/${eventId}/leave`) &&
        response.ok(),
    ),
    confirmButton.click(),
  ]);

  // Verify the attend action returns after cancellation.
  await expect(getAttendButton(page)).toBeVisible();
};

// Return the ticket selection modal.
const getTicketModal = (page) =>
  page.locator('[data-attendance-role="ticket-modal"]');

// Return the checkout action inside the ticket modal.
const getCheckoutButton = (page) =>
  page.locator('[data-attendance-role="checkout-btn"]');

// Return the refund action for a paid attendee.
const getRefundButton = (page) =>
  page.locator('[data-attendance-role="refund-btn"]');

// Return the sign-in action shown to anonymous users.
const getSignInButton = (page) =>
  page.locator('[data-attendance-role="signin-btn"]');

test.describe("event attendance", () => {
  test("member can attend and cancel from the public event page", async ({
    member2Page,
  }) => {
    // Load the event page before changing attendance state.
    await navigateToEvent(
      member2Page,
      TEST_COMMUNITY_NAME,
      TEST_GROUP_SLUGS.community1.alpha,
      TEST_EVENT_SLUGS.alpha[0],
    );

    // Verify the public event page is ready.
    await expect(
      member2Page.getByRole("heading", {
        level: 1,
        name: TEST_EVENT_NAMES.alpha[0],
      }),
    ).toBeVisible();

    // Resolve current attendance before resetting the member state.
    await waitForAttendanceState(member2Page);

    if (await getLeaveButton(member2Page).isVisible()) {
      await cancelAttendance(member2Page, TEST_EVENT_IDS.alpha.one);
    }

    // Target the public attend action.
    const attendButton = getAttendButton(member2Page);
    await expect(attendButton).toBeVisible();

    // Attend the event and wait for attendance to be created.
    await Promise.all([
      member2Page.waitForResponse(
        (response) =>
          response.request().method() === "POST" &&
          response
            .url()
            .includes(`/event/${TEST_EVENT_IDS.alpha.one}/attend`) &&
          response.ok(),
      ),
      attendButton.click(),
    ]);

    // Verify the member can now cancel attendance.
    await expect(getLeaveButton(member2Page)).toBeVisible();

    // Restore the reusable attendance state.
    await cancelAttendance(member2Page, TEST_EVENT_IDS.alpha.one);
  });

  test.describe("payment-enabled attendance flows", () => {
    test.skip(
      !E2E_PAYMENTS_ENABLED,
      "Payments are disabled in this environment.",
    );

    test("guest sees the buy ticket CTA on a ticketed event", async ({
      page,
    }) => {
      // Load the ticketed event as a guest.
      await navigateToEvent(
        page,
        TEST_COMMUNITY_NAME,
        TEST_GROUP_SLUGS.community1.alpha,
        TEST_PAYMENT_EVENT_SLUGS.draft,
      );

      await expect(
        page.getByRole("heading", {
          level: 1,
          name: TEST_PAYMENT_EVENT_NAMES.draft,
        }),
      ).toBeVisible();

      // Verify guests see the sign-in CTA for ticket checkout.
      await expect(getSignInButton(page)).toContainText("Buy ticket");
    });

    test("member sees checkout validation and only sellable tickets in the ticket modal", async ({
      member1Page,
    }) => {
      // Load the ticketed event before opening ticket choices.
      await navigateToEvent(
        member1Page,
        TEST_COMMUNITY_NAME,
        TEST_GROUP_SLUGS.community1.alpha,
        TEST_PAYMENT_EVENT_SLUGS.draft,
      );

      // Resolve the current ticket attendance state.
      await waitForAttendanceState(member1Page);

      // Verify ticket selection is required before checkout.
      await expect(getAttendButton(member1Page)).toContainText("Buy ticket");

      // Open the ticket modal without selecting a ticket.
      await getAttendButton(member1Page).click();

      // Verify checkout is blocked until a sellable ticket is selected.
      const ticketModal = getTicketModal(member1Page);
      await expect(ticketModal).toBeVisible();
      await expect(getCheckoutButton(member1Page)).toBeDisabled();
      await expect(getCheckoutButton(member1Page)).toHaveAttribute(
        "title",
        "Choose a ticket to continue.",
      );
      await expect(ticketModal).not.toContainText("Backstage pass");

      // Close the ticket modal without registering.
      await ticketModal
        .locator('[data-attendance-role="ticket-modal-cancel"]')
        .click();

      // Verify closing the modal leaves the member unregistered.
      await expect(ticketModal).toBeHidden();
      await expect(getLeaveButton(member1Page)).toBeHidden();
      await expect(getAttendButton(member1Page)).toContainText("Buy ticket");
    });

    test("member can complete a free ticket checkout without a discount code", async ({
      member2Page,
    }) => {
      // Load the ticketed event before selecting a free ticket.
      await navigateToEvent(
        member2Page,
        TEST_COMMUNITY_NAME,
        TEST_GROUP_SLUGS.community1.alpha,
        TEST_PAYMENT_EVENT_SLUGS.draft,
      );

      // Open the ticket modal for the member checkout.
      await waitForAttendanceState(member2Page);
      await getAttendButton(member2Page).click();

      // Verify the free ticket can be selected for checkout.
      const ticketModal = getTicketModal(member2Page);
      await expect(ticketModal).toBeVisible();
      await ticketModal
        .locator("label", { hasText: "Community ticket" })
        .click();

      // Watch checkout request payload and response after submitting.
      const checkoutRequest = member2Page.waitForRequest(
        (request) =>
          request.method() === "POST" &&
          request
            .url()
            .includes(`/event/${TEST_PAYMENT_EVENT_IDS.draft}/checkout`),
      );
      const checkoutResponse = member2Page.waitForResponse(
        (response) =>
          response.request().method() === "POST" &&
          response
            .url()
            .includes(`/event/${TEST_PAYMENT_EVENT_IDS.draft}/checkout`) &&
          response.ok(),
      );

      // Submit checkout for the selected free ticket.
      await getCheckoutButton(member2Page).click();

      // Wait for checkout request details and the successful response.
      const [request] = await Promise.all([checkoutRequest, checkoutResponse]);
      const postData = request.postData() ?? "";

      // Verify checkout does not send a discount code.
      expect(postData).not.toContain("discount_code=");

      // Verify successful checkout registers the member.
      await expect(member2Page).toHaveURL(
        new RegExp(TEST_PAYMENT_EVENT_SLUGS.draft),
      );
      await expect(getLeaveButton(member2Page)).toContainText(
        "Cancel attendance",
      );
      await expect(member2Page.locator(".swal2-popup")).toContainText(
        "You have successfully registered for this event.",
      );

      // Restore the reusable ticket attendance state.
      await cancelAttendance(member2Page, TEST_PAYMENT_EVENT_IDS.draft);
    });

    test("member trims the discount code before a free ticket checkout", async ({
      pending1Page,
    }) => {
      // Load the ticketed event before entering a spaced discount code.
      await navigateToEvent(
        pending1Page,
        TEST_COMMUNITY_NAME,
        TEST_GROUP_SLUGS.community1.alpha,
        TEST_PAYMENT_EVENT_SLUGS.draft,
      );

      // Open the ticket modal before entering the discount.
      await waitForAttendanceState(pending1Page);
      await getAttendButton(pending1Page).click();

      // Verify the discount code field accepts the spaced input.
      const ticketModal = getTicketModal(pending1Page);
      await expect(ticketModal).toBeVisible();
      await ticketModal
        .locator("label", { hasText: "Community ticket" })
        .click();
      await ticketModal
        .locator('[data-attendance-role="discount-code-input"]')
        .fill("  SAVE10  ");

      // Watch checkout request payload and response after submitting.
      const checkoutRequest = pending1Page.waitForRequest(
        (request) =>
          request.method() === "POST" &&
          request
            .url()
            .includes(`/event/${TEST_PAYMENT_EVENT_IDS.draft}/checkout`),
      );
      const checkoutResponse = pending1Page.waitForResponse(
        (response) =>
          response.request().method() === "POST" &&
          response
            .url()
            .includes(`/event/${TEST_PAYMENT_EVENT_IDS.draft}/checkout`) &&
          response.ok(),
      );

      // Submit checkout with the spaced discount code.
      await getCheckoutButton(pending1Page).click();

      // Wait for checkout request details and the successful response.
      const [request] = await Promise.all([checkoutRequest, checkoutResponse]);
      const postData = request.postData() ?? "";

      // Verify checkout submits the trimmed discount code.
      expect(postData).toContain("discount_code=SAVE10");
      expect(postData).not.toContain("discount_code=%20%20SAVE10%20%20");

      // Verify successful checkout registers the member.
      await expect(getLeaveButton(pending1Page)).toContainText(
        "Cancel attendance",
      );

      // Restore the reusable ticket attendance state.
      await cancelAttendance(pending1Page, TEST_PAYMENT_EVENT_IDS.draft);
    });

    test("member sees an error for expired discount codes during checkout", async ({
      member1Page,
    }) => {
      // Load the ticketed event before submitting an expired discount.
      await navigateToEvent(
        member1Page,
        TEST_COMMUNITY_NAME,
        TEST_GROUP_SLUGS.community1.alpha,
        TEST_PAYMENT_EVENT_SLUGS.draft,
      );

      // Open the ticket modal before entering the expired discount.
      await waitForAttendanceState(member1Page);
      await getAttendButton(member1Page).click();

      const ticketModal = getTicketModal(member1Page);

      // Select a ticket and enter an expired discount code.
      await ticketModal
        .locator("label", { hasText: "Community ticket" })
        .click();
      await ticketModal
        .locator('[data-attendance-role="discount-code-input"]')
        .fill("EXPIRED15");

      // Submit checkout with an expired discount and wait for validation.
      await Promise.all([
        member1Page.waitForResponse(
          (response) =>
            response.request().method() === "POST" &&
            response
              .url()
              .includes(`/event/${TEST_PAYMENT_EVENT_IDS.draft}/checkout`) &&
            response.status() === 422,
        ),
        getCheckoutButton(member1Page).click(),
      ]);

      // Verify the expired discount keeps the ticket modal open.
      await expect(member1Page.locator(".swal2-popup")).toContainText(
        "discount code is not available",
      );
      await expect(ticketModal).toBeVisible();
    });

    test("member sees an error for unavailable discount codes during checkout", async ({
      member1Page,
    }) => {
      // Load the ticketed event before submitting an unavailable discount.
      await navigateToEvent(
        member1Page,
        TEST_COMMUNITY_NAME,
        TEST_GROUP_SLUGS.community1.alpha,
        TEST_PAYMENT_EVENT_SLUGS.draft,
      );

      // Open the ticket modal before entering the unavailable discount.
      await waitForAttendanceState(member1Page);
      await getAttendButton(member1Page).click();

      const ticketModal = getTicketModal(member1Page);

      // Select a ticket and enter an exhausted discount code.
      await ticketModal
        .locator("label", { hasText: "Community ticket" })
        .click();
      await ticketModal
        .locator('[data-attendance-role="discount-code-input"]')
        .fill("LIMIT5");

      // Submit checkout with an exhausted discount and wait for validation.
      await Promise.all([
        member1Page.waitForResponse(
          (response) =>
            response.request().method() === "POST" &&
            response
              .url()
              .includes(`/event/${TEST_PAYMENT_EVENT_IDS.draft}/checkout`) &&
            response.status() === 422,
        ),
        getCheckoutButton(member1Page).click(),
      ]);

      // Verify the exhausted discount keeps the ticket modal open.
      await expect(member1Page.locator(".swal2-popup")).toContainText(
        "discount code is not available",
      );
      await expect(ticketModal).toBeVisible();
    });

    test("paid attendee sees a pending refund request on the event page", async ({
      member1Page,
    }) => {
      // Load the refund-ready event with a pending request.
      await navigateToEvent(
        member1Page,
        TEST_COMMUNITY_NAME,
        TEST_GROUP_SLUGS.community1.alpha,
        TEST_PAYMENT_EVENT_SLUGS.refunds,
      );

      const refundButton = getRefundButton(member1Page);

      // Verify the pending refund state disables attendee cancellation.
      await expect(refundButton).toBeVisible();
      await expect(refundButton).toContainText("Refund requested");
      await expect(refundButton).toBeDisabled();
      await expect(getLeaveButton(member1Page)).toBeHidden();
    });

    test("paid attendee sees refund processing on the event page", async ({
      member2Page,
    }) => {
      // Load the refund-ready event with a processing refund.
      await navigateToEvent(
        member2Page,
        TEST_COMMUNITY_NAME,
        TEST_GROUP_SLUGS.community1.alpha,
        TEST_PAYMENT_EVENT_SLUGS.refunds,
      );

      const refundButton = getRefundButton(member2Page);

      // Verify the processing refund state disables attendee cancellation.
      await expect(refundButton).toBeVisible();
      await expect(refundButton).toContainText("Refund processing");
      await expect(refundButton).toBeDisabled();
      await expect(getLeaveButton(member2Page)).toBeHidden();
    });

    test("paid attendee sees refund unavailable when a request was rejected", async ({
      pending1Page,
    }) => {
      // Load the refund-ready event with a rejected refund.
      await navigateToEvent(
        pending1Page,
        TEST_COMMUNITY_NAME,
        TEST_GROUP_SLUGS.community1.alpha,
        TEST_PAYMENT_EVENT_SLUGS.refunds,
      );

      const refundButton = getRefundButton(pending1Page);

      // Verify rejected refunds cannot be requested again.
      await expect(refundButton).toBeVisible();
      await expect(refundButton).toContainText("Refund unavailable");
      await expect(refundButton).toBeDisabled();
      await expect(getLeaveButton(pending1Page)).toBeHidden();
    });

    test("paid attendee can request a refund before the event starts", async ({
      pending2Page,
    }) => {
      // Load the refund-ready event before requesting a refund.
      await navigateToEvent(
        pending2Page,
        TEST_COMMUNITY_NAME,
        TEST_GROUP_SLUGS.community1.alpha,
        TEST_PAYMENT_EVENT_SLUGS.refunds,
      );

      const refundButton = getRefundButton(pending2Page);

      // Verify the attendee can request a refund instead of canceling.
      await expect(refundButton).toBeVisible();
      await expect(refundButton).toContainText("Request refund");
      await expect(refundButton).toBeEnabled();
      await expect(getLeaveButton(pending2Page)).toBeHidden();

      // Request a refund and confirm the organizer-facing workflow.
      await refundButton.click();
      const confirmButton = pending2Page.getByRole("button", { name: "Yes" });
      await expect(confirmButton).toBeVisible();

      await Promise.all([
        pending2Page.waitForResponse(
          (response) =>
            response.request().method() === "POST" &&
            response
              .url()
              .includes(
                `/event/${TEST_PAYMENT_EVENT_IDS.refunds}/refund-request`,
              ) &&
            response.ok(),
        ),
        confirmButton.click(),
      ]);

      // Verify the event page updates to the pending refund request state.
      await expect(pending2Page.locator(".swal2-popup")).toContainText(
        "Your refund request has been sent to the organizers.",
      );
      await expect(refundButton).toContainText("Refund requested");
      await expect(refundButton).toBeDisabled();
    });
  });
});
