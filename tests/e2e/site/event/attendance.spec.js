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
  TEST_REGISTRATION_QUESTIONS_EVENT,
  TEST_TICKETING_EVENTS,
  buildE2eUrl,
  getAttendanceContainer,
  getAttendButton,
  getLeaveButton,
  navigateToEvent,
  navigateToPath,
  waitForAttendanceState,
} from "../../utils.js";

// Dismiss the optional profile completion prompt shown after successful attendance.
const dismissProfileCompletionPrompt = async (page) => {
  const maybeLaterButton = page.getByRole("button", { name: "Maybe later" });
  if (await maybeLaterButton.isVisible()) {
    await maybeLaterButton.click();
    await expect(page.locator(".swal2-popup")).toBeHidden();
  }
};

// Cancel attendance when the current user is already registered.
const cancelAttendance = async (page, eventId) => {
  await dismissProfileCompletionPrompt(page);

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
    page.waitForResponse(
      (response) =>
        response.request().method() === "GET" &&
        response.url().includes(`/event/${eventId}/enrollment`) &&
        response.ok(),
    ),
    confirmButton.click(),
  ]);

  // Verify the attend action returns after cancellation.
  await waitForAttendanceState(page);
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

    // Leave any existing attendance before continuing.
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

  test("member answers registration questions before attending", async ({
    pending2Page,
  }) => {
    // Load the event page before changing attendance state.
    await navigateToEvent(
      pending2Page,
      TEST_COMMUNITY_NAME,
      TEST_GROUP_SLUGS.community1.alpha,
      TEST_REGISTRATION_QUESTIONS_EVENT.slug,
    );

    // Verify the public event page is ready.
    await expect(
      pending2Page.getByRole("heading", {
        level: 1,
        name: TEST_REGISTRATION_QUESTIONS_EVENT.name,
      }),
    ).toBeVisible();

    // Resolve current attendance before resetting the member state.
    await waitForAttendanceState(pending2Page);

    // Leave any existing attendance before continuing.
    if (await getLeaveButton(pending2Page).isVisible()) {
      await cancelAttendance(
        pending2Page,
        TEST_REGISTRATION_QUESTIONS_EVENT.id,
      );
    }

    // Open the required registration questions modal.
    await getAttendButton(pending2Page).click();

    // Find the registration modal.
    const registrationModal = pending2Page.locator(
      '[data-attendance-role="registration-modal"]',
    );
    await expect(registrationModal).toBeVisible();
    await expect(
      registrationModal.getByRole("heading", {
        name: "Registration questions",
      }),
    ).toBeVisible();
    await expect(registrationModal).toContainText(
      "What are you hoping to learn from this event?",
    );
    await expect(registrationModal).toContainText("Preferred session format");
    await expect(registrationModal).toContainText("Topics you want covered");
    await expect(registrationModal).toContainText(
      "Anything the organizers should know?",
    );

    // Fill all question types before submitting the registration.
    await registrationModal
      .locator("fieldset", {
        hasText: "What are you hoping to learn from this event?",
      })
      .locator("textarea")
      .fill("I want to compare live platform practices.");
    await registrationModal
      .locator("label", { hasText: "Panel discussion" })
      .click();
    await registrationModal
      .locator("label", { hasText: "Developer experience" })
      .click();
    await registrationModal
      .locator("label", { hasText: "Security and compliance" })
      .click();
    await registrationModal
      .locator("fieldset", {
        hasText: "Anything the organizers should know?",
      })
      .locator("textarea")
      .fill("Please share slides afterward.");

    // Submit the answers and wait for attendance to be created.
    await Promise.all([
      pending2Page.waitForResponse(
        (response) =>
          response.request().method() === "POST" &&
          response
            .url()
            .includes(
              `/event/${TEST_REGISTRATION_QUESTIONS_EVENT.id}/attend`,
            ) &&
          response.ok(),
      ),
      registrationModal
        .locator('[data-attendance-role="registration-modal-submit"]')
        .click(),
    ]);

    // Verify the member can now cancel attendance.
    await expect(registrationModal).toBeHidden();
    await expect(getLeaveButton(pending2Page)).toContainText(
      "Cancel attendance",
    );

    // Restore the reusable attendance state.
    await cancelAttendance(pending2Page, TEST_REGISTRATION_QUESTIONS_EVENT.id);
  });

  test("signed-out event calls to action match each enrollment model", async ({
    page,
  }) => {
    // Simple public RSVP events invite guests to sign in and attend.
    await navigateToEvent(
      page,
      TEST_COMMUNITY_NAME,
      TEST_GROUP_SLUGS.community1.alpha,
      TEST_EVENT_SLUGS.alpha[0],
    );
    await expect(getSignInButton(page)).toContainText("Attend event");

    // Approval-required RSVP events use invitation-request wording.
    await navigateToEvent(
      page,
      TEST_COMMUNITY_NAME,
      TEST_GROUP_SLUGS.community1.alpha,
      "alpha-registration-window-approval-closed",
    );
    await expect(getSignInButton(page)).toContainText("Request invitation");

    // Sold-out RSVP events with a waiting list expose the waitlist action.
    await navigateToEvent(
      page,
      TEST_COMMUNITY_NAME,
      TEST_GROUP_SLUGS.community1.alpha,
      "alpha-waitlist-lab",
    );
    await expect(getSignInButton(page)).toContainText("Join waiting list");

    // Events with no public tiers stay informational rather than prompting login.
    if (E2E_PAYMENTS_ENABLED) {
      await navigateToEvent(
        page,
        TEST_COMMUNITY_NAME,
        TEST_GROUP_SLUGS.community1.alpha,
        TEST_TICKETING_EVENTS.paidOffers.slug,
      );
      await expect(getSignInButton(page)).toBeHidden();
      await expect(getAttendButton(page)).toContainText("Invitation only");
      await expect(getAttendButton(page)).toBeDisabled();
    }
  });

  test.describe("payment-enabled attendance flows", () => {
    test.skip(
      !E2E_PAYMENTS_ENABLED,
      "Payments are disabled in this environment.",
    );

    test("canceled payment returns keep the active checkout resumable and clean the URL", async ({
      pending2Page,
    }) => {
      const event = TEST_TICKETING_EVENTS.paymentReturn;

      // Return from checkout with a canceled outcome and an active payment hold.
      await navigateToPath(
        pending2Page,
        `/${TEST_COMMUNITY_NAME}/group/${TEST_GROUP_SLUGS.community1.alpha}/event/${event.slug}` +
          "?source=e2e&payment=canceled#attendance",
      );

      // Verify the return message explains that checkout can still be resumed.
      await expect(pending2Page.locator(".swal2-popup")).toContainText(
        "Checkout was canceled. You can resume payment while your ticket hold is still active.",
      );
      await expect(getAttendButton(pending2Page)).toContainText(
        "Continue to checkout",
      );

      // Keep unrelated URL state while removing the one-time payment outcome.
      await expect
        .poll(() => pending2Page.url())
        .toContain("?source=e2e#attendance");
      expect(new URL(pending2Page.url()).searchParams.has("payment")).toBe(
        false,
      );
    });

    test("confirmed payment returns show registration success and clean the URL", async ({
      eventsManagerGroupPage,
    }) => {
      const event = TEST_TICKETING_EVENTS.paymentReturn;

      // Return from checkout for a user whose purchase is already confirmed.
      await navigateToPath(
        eventsManagerGroupPage,
        `/${TEST_COMMUNITY_NAME}/group/${TEST_GROUP_SLUGS.community1.alpha}/event/${event.slug}` +
          "?payment=success",
      );

      // Verify the terminal success state and registered attendee controls.
      await expect(
        eventsManagerGroupPage.locator(".swal2-popup"),
      ).toContainText(
        "Your payment is complete. You're registered for this event.",
      );
      await expect(getRefundButton(eventsManagerGroupPage)).toContainText(
        "Request refund",
      );
      await expect
        .poll(() =>
          new URL(eventsManagerGroupPage.url()).searchParams.has("payment"),
        )
        .toBe(false);
    });

    test("successful payment returns poll pending checkout until attendance is confirmed", async ({
      pending2Page,
    }) => {
      test.setTimeout(30_000);

      const event = TEST_TICKETING_EVENTS.paymentReturn;
      const enrollmentUrl = `**/event/${event.id}/enrollment`;
      let allowAttendanceConfirmation = false;
      let paymentReturnRequests = 0;

      // Keep payment-return requests pending until the interim feedback is observable.
      await pending2Page.route(enrollmentUrl, async (route) => {
        const isHtmxRequest =
          route.request().headers()["hx-request"] === "true";
        if (!isHtmxRequest) {
          paymentReturnRequests += 1;
        }

        const status = allowAttendanceConfirmation
          ? "attendee"
          : "pending-payment";
        await route.fulfill({
          body: JSON.stringify({ status }),
          contentType: "application/json",
          status: 200,
        });
      });

      try {
        // Return before webhook reconciliation has confirmed the purchase.
        await navigateToPath(
          pending2Page,
          `/${TEST_COMMUNITY_NAME}/group/${TEST_GROUP_SLUGS.community1.alpha}/event/${event.slug}` +
            "?payment=success",
        );

        // Verify pending feedback is replaced after the follow-up poll confirms attendance.
        await expect(pending2Page.locator(".swal2-popup")).toContainText(
          "Confirming your payment. This can take a few seconds.",
        );
        allowAttendanceConfirmation = true;
        await expect(pending2Page.locator(".swal2-popup")).toContainText(
          "Your payment is complete. You're registered for this event.",
          { timeout: 10_000 },
        );
        expect(paymentReturnRequests).toBeGreaterThanOrEqual(2);
        await expect
          .poll(() => new URL(pending2Page.url()).searchParams.has("payment"))
          .toBe(false);
      } finally {
        await pending2Page.unroute(enrollmentUrl);
      }
    });

    test("guest sees the get ticket CTA on a paid event", async ({ page }) => {
      // Load the paid event as a guest.
      await navigateToEvent(
        page,
        TEST_COMMUNITY_NAME,
        TEST_GROUP_SLUGS.community1.alpha,
        TEST_PAYMENT_EVENT_SLUGS.draft,
      );

      // Assert the expected content is visible.
      await expect(
        page.getByRole("heading", {
          level: 1,
          name: TEST_PAYMENT_EVENT_NAMES.draft,
        }),
      ).toBeVisible();

      // Verify guests see the sign-in CTA for ticket checkout.
      await expect(getSignInButton(page)).toContainText("Get ticket");
    });

    test("member requests a public ticket while private tiers stay organizer-only", async ({
      member1Page,
    }) => {
      const event = TEST_TICKETING_EVENTS.ticketRequest;

      try {
        // Open the approval-required ticketed event as an authenticated member.
        await navigateToEvent(
          member1Page,
          TEST_COMMUNITY_NAME,
          TEST_GROUP_SLUGS.community1.alpha,
          event.slug,
        );
        await waitForAttendanceState(member1Page);
        await expect(getAttendButton(member1Page)).toContainText(
          "Request ticket",
        );
        await getAttendButton(member1Page).click();

        // Verify only the public requested tier appears in the attendee modal.
        const ticketModal = getTicketModal(member1Page);
        await expect(ticketModal).toBeVisible();
        await expect(ticketModal).toContainText("Requested conference pass");
        await expect(ticketModal).not.toContainText("Private supporter pass");
        await ticketModal
          .locator("label", { hasText: "Requested conference pass" })
          .click();
        await ticketModal
          .locator('[data-attendance-role="discount-code-input"]')
          .evaluate((input) => {
            input.disabled = false;
            input.value = "OFFER25";
          });

        // Continue through required registration questions before submitting.
        await getCheckoutButton(member1Page).click();
        const registrationModal = member1Page.locator(
          '[data-attendance-role="registration-modal"]',
        );
        await expect(registrationModal).toBeVisible();
        await registrationModal
          .getByRole("textbox")
          .fill("I would like to join the attendee program.");

        // Submit the request and inspect the attendee-facing form contract.
        const requestPromise = member1Page.waitForRequest(
          (request) =>
            request.method() === "POST" &&
            request.url().includes(`/event/${event.id}/attend`),
        );
        await Promise.all([
          member1Page.waitForResponse(
            (response) =>
              response.request().method() === "POST" &&
              response.url().includes(`/event/${event.id}/attend`) &&
              response.ok(),
          ),
          registrationModal
            .locator('[data-attendance-role="registration-modal-submit"]')
            .click(),
        ]);
        const request = await requestPromise;
        const requestData = new URLSearchParams(request.postData() ?? "");
        const answers = JSON.parse(
          requestData.get("registration_answers") ?? "{}",
        );

        // Approval requests retain answers and the requested public tier only.
        expect(requestData.get("event_ticket_type_id")).toBe(
          "56555555-5555-5555-5555-555555555913",
        );
        expect(requestData.has("discount_code")).toBe(false);
        expect(answers.answers?.[0]?.value).toBe(
          "I would like to join the attendee program.",
        );
        await expect(getLeaveButton(member1Page)).toContainText(
          "Request pending",
        );
        await dismissProfileCompletionPrompt(member1Page);
        await expect(getLeaveButton(member1Page)).toHaveAccessibleName(
          "Request pending – cancel request",
        );
      } finally {
        // Restore the reusable member and request fixture.
        await member1Page.request.delete(
          buildE2eUrl(`/${TEST_COMMUNITY_NAME}/event/${event.id}/leave`),
        );
      }
    });

    test("paid checkout retains registration answers before the provider redirect", async ({
      member1Page,
    }) => {
      const event = TEST_TICKETING_EVENTS.paidQuestions;
      const checkoutUrl = `**/event/${event.id}/checkout`;

      // Keep the provider handoff local while exercising the public paid form.
      await member1Page.route(checkoutUrl, async (route) => {
        await route.fulfill({
          body: JSON.stringify({
            redirect_url:
              `/${TEST_COMMUNITY_NAME}/group/${TEST_GROUP_SLUGS.community1.alpha}/event/${event.slug}` +
              "?questions-checkout=redirected",
          }),
          contentType: "application/json",
          status: 200,
        });
      });

      try {
        await navigateToEvent(
          member1Page,
          TEST_COMMUNITY_NAME,
          TEST_GROUP_SLUGS.community1.alpha,
          event.slug,
        );
        await waitForAttendanceState(member1Page);
        await getAttendButton(member1Page).click();
        const ticketModal = getTicketModal(member1Page);
        await ticketModal
          .locator("label", { hasText: "Questions conference pass" })
          .click();
        await getCheckoutButton(member1Page).click();

        const registrationModal = member1Page.locator(
          '[data-attendance-role="registration-modal"]',
        );
        await registrationModal
          .getByRole("textbox")
          .fill("Please reserve captions for the paid workshop.");
        const checkoutRequest = member1Page.waitForRequest(
          (request) =>
            request.method() === "POST" &&
            request.url().includes(`/event/${event.id}/checkout`),
        );
        await Promise.all([
          member1Page.waitForURL(/questions-checkout=redirected/u),
          registrationModal
            .locator('[data-attendance-role="registration-modal-submit"]')
            .click(),
        ]);
        const requestData = new URLSearchParams(
          (await checkoutRequest).postData() ?? "",
        );
        const answers = JSON.parse(
          requestData.get("registration_answers") ?? "{}",
        );

        // Paid provider checkout keeps the selected tier and validated answers.
        expect(requestData.get("event_ticket_type_id")).toBe(
          "56555555-5555-5555-5555-555555555917",
        );
        expect(requestData.has("discount_code")).toBe(false);
        expect(answers.answers?.[0]?.value).toBe(
          "Please reserve captions for the paid workshop.",
        );
      } finally {
        await member1Page.unroute(checkoutUrl);
      }
    });

    test("member sees checkout validation and only sellable tickets in the ticket modal", async ({
      member1Page,
    }) => {
      // Load the paid event before opening ticket choices.
      await navigateToEvent(
        member1Page,
        TEST_COMMUNITY_NAME,
        TEST_GROUP_SLUGS.community1.alpha,
        TEST_PAYMENT_EVENT_SLUGS.draft,
      );

      // Resolve the current ticket attendance state.
      await waitForAttendanceState(member1Page);

      // Verify ticket selection is required before checkout.
      await expect(getAttendButton(member1Page)).toContainText("Get ticket");

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
      await expect(getAttendButton(member1Page)).toContainText("Get ticket");
    });

    test("member can complete a free ticket checkout without a discount code", async ({
      member2Page,
    }) => {
      // Load the multi-tier event before selecting a free ticket.
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

    test("sold-out waitlist submissions omit discounts and stale answers", async ({
      pending1Page,
    }) => {
      const event = TEST_TICKETING_EVENTS.soldOut;

      try {
        // Open the sold-out paid tier and verify its exact ticket-card state.
        await navigateToEvent(
          pending1Page,
          TEST_COMMUNITY_NAME,
          TEST_GROUP_SLUGS.community1.alpha,
          event.slug,
        );
        await waitForAttendanceState(pending1Page);
        await expect(getAttendButton(pending1Page)).toContainText(
          "Join waiting list",
        );
        await getAttendButton(pending1Page).click();
        const ticketModal = getTicketModal(pending1Page);
        const soldOutCard = ticketModal.locator(
          '[data-attendance-role="ticket-type-card"]',
          {
            hasText: "Limited conference pass",
          },
        );
        await expect(soldOutCard).toContainText("Sold out");
        await soldOutCard.click();

        // Seed stale client values that must not cross the waitlist boundary.
        await ticketModal
          .locator('[data-attendance-role="discount-code-input"]')
          .evaluate((input) => {
            input.disabled = false;
            input.value = "FULLCOMP";
          });
        await ticketModal
          .locator(
            '[data-attendance-role="checkout-registration-answers-input"]',
          )
          .evaluate((input) => {
            input.value = JSON.stringify({
              answers: [{ question_id: "stale", value: "stale answer" }],
            });
          });

        // Join the waiting list and inspect the final request payload.
        const waitlistRequest = pending1Page.waitForRequest(
          (request) =>
            request.method() === "POST" &&
            request.url().includes(`/event/${event.id}/attend`),
        );
        await Promise.all([
          pending1Page.waitForResponse(
            (response) =>
              response.request().method() === "POST" &&
              response.url().includes(`/event/${event.id}/attend`) &&
              response.ok(),
          ),
          getCheckoutButton(pending1Page).click(),
        ]);
        const requestData = new URLSearchParams(
          (await waitlistRequest).postData() ?? "",
        );

        // Waiting-list requests carry only their selected tier.
        expect(requestData.get("event_ticket_type_id")).toBe(
          "56555555-5555-5555-5555-555555555918",
        );
        expect(requestData.has("discount_code")).toBe(false);
        expect(requestData.has("registration_answers")).toBe(false);
        await expect(getLeaveButton(pending1Page)).toContainText(
          "Leave waiting list",
        );
      } finally {
        await pending1Page.request.delete(
          buildE2eUrl(`/${TEST_COMMUNITY_NAME}/event/${event.id}/leave`),
        );
      }
    });

    test("a finalized refund releases sold-out ticket capacity", async ({
      pending1Page,
    }) => {
      const event = TEST_TICKETING_EVENTS.refundedCapacity;

      await navigateToEvent(
        pending1Page,
        TEST_COMMUNITY_NAME,
        TEST_GROUP_SLUGS.community1.alpha,
        event.slug,
      );
      await waitForAttendanceState(pending1Page);

      // The refunded purchase no longer occupies the event's only seat.
      await expect(
        pending1Page.locator("[data-availability-sold-out-ribbon]"),
      ).toBeHidden();
      await expect(getAttendButton(pending1Page)).toContainText("Get ticket");
      await getAttendButton(pending1Page).click();

      const refundedTierCard = getTicketModal(pending1Page).locator(
        '[data-attendance-role="ticket-type-card"]',
        { hasText: "Refunded conference pass" },
      );
      await expect(refundedTierCard).toContainText("Available now");
      await expect(
        refundedTierCard.locator('[data-attendance-role="ticket-type-option"]'),
      ).toBeEnabled();
    });

    test("ticket cards show the not-on-sale state from refreshed availability", async ({
      member1Page,
    }) => {
      const event = TEST_PAYMENT_EVENT_SLUGS.draft;
      const availabilityUrl = `**/event/${event}/availability`;

      // Expose the scheduled tier during hydration while keeping it unavailable.
      await member1Page.route(availabilityUrl, async (route) => {
        await route.fulfill({
          body: JSON.stringify({
            attendee_approval_required: false,
            canceled: false,
            capacity: 42,
            has_only_free_ticket_types: false,
            has_sellable_ticket_types: true,
            has_sold_out_ticket_types: false,
            has_visible_ticket_types: true,
            is_live: false,
            is_past: false,
            is_simple_rsvp: false,
            paid_capable: true,
            registration_window_open: true,
            remaining_capacity: 42,
            ticket_types: [
              {
                active: true,
                current_price_label: "USD 25.00",
                current_price_minor: 2500,
                event_ticket_type_id: "56555555-5555-5555-5555-555555555521",
                is_sellable_now: false,
                sold_out: false,
                title: "General admission",
              },
              {
                active: true,
                current_price_label: "Free",
                current_price_minor: 0,
                event_ticket_type_id: "56555555-5555-5555-5555-555555555522",
                is_sellable_now: true,
                sold_out: false,
                title: "Community ticket",
              },
            ],
            waitlist_count: 0,
            waitlist_enabled: false,
          }),
          contentType: "application/json",
          status: 200,
        });
      });

      try {
        await navigateToEvent(
          member1Page,
          TEST_COMMUNITY_NAME,
          TEST_GROUP_SLUGS.community1.alpha,
          event,
        );
        await waitForAttendanceState(member1Page);
        await getAttendButton(member1Page).click();
        const unavailableCard = getTicketModal(member1Page).locator(
          '[data-attendance-role="ticket-type-card"]',
          { hasText: "General admission" },
        );
        await expect(unavailableCard).toContainText("Not on sale");
        await expect(
          unavailableCard.locator('[data-attendance-role="ticket-type-option"]'),
        ).toBeDisabled();
      } finally {
        await member1Page.unroute(availabilityUrl);
      }
    });

    test("member trims the discount code before a paid ticket checkout", async ({
      pending1Page,
    }) => {
      // Load the paid event before entering a spaced discount code.
      await navigateToEvent(
        pending1Page,
        TEST_COMMUNITY_NAME,
        TEST_GROUP_SLUGS.community1.alpha,
        TEST_PAYMENT_EVENT_SLUGS.draft,
      );

      // Open the ticket modal before entering the discount.
      await waitForAttendanceState(pending1Page);
      await getAttendButton(pending1Page).click();

      // Verify the discount code field accepts the spaced input for a paid tier.
      const ticketModal = getTicketModal(pending1Page);
      await expect(ticketModal).toBeVisible();
      await ticketModal
        .locator("label", { hasText: "General admission" })
        .click();
      await ticketModal
        .locator('[data-attendance-role="discount-code-input"]')
        .fill("  SAVE10  ");

      // Intercept checkout so request normalization is tested without calling Stripe.
      const checkoutUrl = `**/event/${TEST_PAYMENT_EVENT_IDS.draft}/checkout`;
      await pending1Page.route(checkoutUrl, async (route) => {
        await route.fulfill({
          body: "checkout intercepted by e2e test",
          contentType: "text/plain",
          status: 422,
        });
      });
      const checkoutRequest = pending1Page.waitForRequest(
        (request) =>
          request.method() === "POST" &&
          request
            .url()
            .includes(`/event/${TEST_PAYMENT_EVENT_IDS.draft}/checkout`),
      );
      try {
        // Submit checkout with the spaced discount code.
        await getCheckoutButton(pending1Page).click();

        // Wait for checkout request details.
        const request = await checkoutRequest;
        const postData = request.postData() ?? "";

        // Verify checkout submits the trimmed discount code.
        expect(postData).toContain("discount_code=SAVE10");
        expect(postData).not.toContain("discount_code=%20%20SAVE10%20%20");
      } finally {
        await pending1Page.unroute(checkoutUrl);
      }
    });

    test("member sees an error for expired discount codes during checkout", async ({
      member1Page,
    }) => {
      // Load the paid event before submitting an expired discount.
      await navigateToEvent(
        member1Page,
        TEST_COMMUNITY_NAME,
        TEST_GROUP_SLUGS.community1.alpha,
        TEST_PAYMENT_EVENT_SLUGS.draft,
      );

      // Open the ticket modal before entering the expired discount.
      await waitForAttendanceState(member1Page);
      await getAttendButton(member1Page).click();

      // Set up ticket modal.
      const ticketModal = getTicketModal(member1Page);

      // Select a ticket and enter an expired discount code.
      await ticketModal
        .locator("label", { hasText: "General admission" })
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
      // Load the paid event before submitting an unavailable discount.
      await navigateToEvent(
        member1Page,
        TEST_COMMUNITY_NAME,
        TEST_GROUP_SLUGS.community1.alpha,
        TEST_PAYMENT_EVENT_SLUGS.draft,
      );

      // Open the ticket modal before entering the unavailable discount.
      await waitForAttendanceState(member1Page);
      await getAttendButton(member1Page).click();

      // Set up ticket modal.
      const ticketModal = getTicketModal(member1Page);

      // Select a ticket and enter an exhausted discount code.
      await ticketModal
        .locator("label", { hasText: "General admission" })
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

    test("member can resume and cancel a pending checkout from the event page", async ({
      pending2Page,
    }) => {
      test.setTimeout(90_000);

      // Load the paid event before starting checkout.
      await navigateToEvent(
        pending2Page,
        TEST_COMMUNITY_NAME,
        TEST_GROUP_SLUGS.community1.alpha,
        TEST_PAYMENT_EVENT_SLUGS.draft,
      );

      // Resolve the current ticket attendance state.
      await waitForAttendanceState(pending2Page);
      // Verify the seeded pending payment exposes resume controls.
      await expect(getAttendButton(pending2Page)).toContainText(
        "Continue to checkout",
      );
      const resumeCheckoutUrl =
        await getAttendButton(pending2Page).getAttribute("data-resume-url");
      if (resumeCheckoutUrl !== null) {
        expect(resumeCheckoutUrl).not.toEqual("");
      }

      // Open the event-page actions and cancel the active checkout hold.
      const attendanceContainer = getAttendanceContainer(pending2Page);
      const actionsMenu = attendanceContainer.locator(
        '[data-attendance-role="actions-menu"]',
      );
      await expect(actionsMenu).toBeVisible();
      await actionsMenu.locator("summary").click();
      await attendanceContainer
        .locator('[data-attendance-role="checkout-cancel-btn"]')
        .click();
      await expect(pending2Page.locator(".swal2-popup")).toContainText(
        "Are you sure you want to cancel this checkout?",
      );

      // Confirm checkout cancellation and verify ticket selection is restored.
      await Promise.all([
        pending2Page.waitForResponse(
          (response) =>
            response.request().method() === "DELETE" &&
            response
              .url()
              .includes(`/event/${TEST_PAYMENT_EVENT_IDS.draft}/checkout`) &&
            response.ok(),
        ),
        pending2Page.getByRole("button", { name: "Yes" }).click(),
      ]);
      await expect(pending2Page.locator(".swal2-popup")).toContainText(
        "Your checkout has been canceled. You can choose a different ticket.",
      );
      await expect(getAttendButton(pending2Page)).toContainText("Get ticket");
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

      // Set up refund button.
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

      // Set up refund button.
      const refundButton = getRefundButton(member2Page);

      // Verify the processing refund state disables attendee cancellation.
      await expect(refundButton).toBeVisible();
      await expect(refundButton).toContainText("Refund processing");
      await expect(refundButton).toBeDisabled();
      await expect(getLeaveButton(member2Page)).toBeHidden();
    });

    test("paid attendee sees the reason when a refund request was rejected", async ({
      pending1Page,
    }) => {
      // Load the refund-ready event with a rejected refund.
      await navigateToEvent(
        pending1Page,
        TEST_COMMUNITY_NAME,
        TEST_GROUP_SLUGS.community1.alpha,
        TEST_PAYMENT_EVENT_SLUGS.refunds,
      );

      // Set up refund button.
      const refundButton = getRefundButton(pending1Page);
      const rejectionReason = pending1Page.locator(
        '[data-attendance-role="refund-rejection-reason"]',
      );

      // Assert the rejected state and its persisted organizer reason.
      await expect(refundButton).toBeVisible();
      await expect(refundButton).toContainText("Refund rejected");
      await expect(refundButton).toBeDisabled();
      await expect(rejectionReason).toHaveText(
        "Reason: The request falls outside the refund policy window.",
      );
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

      // Set up refund button.
      const refundButton = getRefundButton(pending2Page);

      // Verify the attendee can request a refund instead of canceling.
      await expect(refundButton).toBeVisible();
      if ((await refundButton.innerText()).includes("Refund requested")) {
        await expect(refundButton).toBeDisabled();
        await expect(getLeaveButton(pending2Page)).toBeHidden();
        return;
      }
      await expect(refundButton).toContainText("Request refund");
      await expect(refundButton).toBeEnabled();
      await expect(getLeaveButton(pending2Page)).toBeHidden();

      // Open the refund request modal and provide an optional reason.
      await refundButton.click();
      const refundModal = pending2Page.getByRole("dialog", {
        name: "Request a refund",
      });
      await expect(refundModal).toBeVisible();
      await refundModal
        .getByRole("textbox", { name: "Reason (optional)" })
        .fill("Unable to attend");

      // Submit the request and verify the reason reaches the refund endpoint.
      const [refundResponse] = await Promise.all([
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
        refundModal.getByRole("button", { name: "Request refund" }).click(),
      ]);
      const refundRequestData = new URLSearchParams(
        refundResponse.request().postData(),
      );
      expect(refundRequestData.get("requested_reason")).toBe(
        "Unable to attend",
      );

      // Verify the event page updates to the pending refund request state.
      await expect(pending2Page.locator(".swal2-popup")).toContainText(
        "Your refund request has been sent to the organizers.",
      );
      await expect(refundButton).toContainText("Refund requested");
      await expect(refundButton).toBeDisabled();
    });
  });
});
