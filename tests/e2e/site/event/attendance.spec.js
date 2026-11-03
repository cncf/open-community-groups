import { expect, test } from "../../fixtures.js";
import { queryE2eDatabase } from "../../database.js";
import { setupTicketOffer } from "../../data-graphs/events.js";
import { cleanupEventEnrollment } from "../../data-graphs/invitations.js";
import {
  cleanupOwnedPaymentPurchase,
  setupOwnedCompletedRefundPurchase,
  setupOwnedPendingCheckout,
} from "../../data-graphs/payments.js";
import {
  TEST_APPROVAL_REQUIRED_EVENT,
  TEST_COMMUNITY_NAME,
  TEST_EVENT_IDS,
  TEST_EVENT_NAMES,
  TEST_EVENT_SLUGS,
  TEST_GROUP_IDS,
  TEST_GROUP_SLUGS,
  TEST_OPEN_CHECK_IN_EVENT,
  TEST_PAYMENT_EVENT_IDS,
  TEST_PAYMENT_EVENT_NAMES,
  TEST_PAYMENT_EVENT_SLUGS,
  TEST_REGISTRATION_QUESTIONS_EVENT,
  TEST_TICKETING_EVENTS,
  TEST_USER_IDS,
} from "../../seed.js";
import {
  cancelAttendance,
  dismissProfileCompletionPrompt,
  getAttendanceContainer,
  getAttendButton,
  getCheckoutButton,
  getLeaveButton,
  getRefundButton,
  getTicketModal,
  waitForAttendanceState,
} from "./helpers.js";
import {
  buildE2eUrl,
  confirmAlert,
  navigateToEvent,
  navigateToPath,
  waitForActionResponse,
} from "../../utils.js";

const OWNED_CHECKOUT_CANCEL_URL = "https://example.test/checkout/e2e-owned-cancel";

const OWNED_CHECKOUT_RESUME_URL = "https://example.test/checkout/e2e-owned-resume";

const EVENT_REFUND_REQUESTED_RECIPIENT_IDS = [
  TEST_USER_IDS.admin1,
  TEST_USER_IDS.organizer1,
  TEST_USER_IDS.groupsManager1,
  TEST_USER_IDS.eventsManager1,
];

const UNAVAILABLE_DISCOUNT_CASES = [
  { code: "EXPIRED15", name: "expired" },
  { code: "LIMIT5", name: "unavailable" },
];

test.describe("event attendance", () => {
  test("guest attendance action links to sign in with the event return URL", async ({ page }) => {
    // Load the public event as a guest.
    await navigateToEvent(
      page,
      TEST_COMMUNITY_NAME,
      TEST_GROUP_SLUGS.community1.alpha,
      TEST_EVENT_SLUGS.alpha[0],
    );

    // Find the attendance sign-in action and verify its event return URL.
    const signInButton = getSignInButton(page);
    await expect(signInButton).toContainText("Attend event");
    // The action is a button that navigates through its data-path value.
    await expect(signInButton).toHaveAttribute(
      "data-path",
      `/${TEST_COMMUNITY_NAME}/group/${TEST_GROUP_SLUGS.community1.alpha}/event/${TEST_EVENT_SLUGS.alpha[0]}`,
    );
  });

  test("member can attend and cancel from the public event page @smoke", async ({
    member2Page,
    notifications,
    owned,
  }) => {
    // Cancelling keeps the attendee and a refunded purchase, so remove the pair's enrollment rows.
    owned.defer(() =>
      cleanupEventEnrollment({ eventId: TEST_EVENT_IDS.alpha.one, userId: TEST_USER_IDS.member2 }),
    );

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

    // Resolve the attendance state before attending.
    await waitForAttendanceState(member2Page);

    // Target the public attend action.
    const attendButton = getAttendButton(member2Page);
    await expect(attendButton).toBeVisible();

    // Attend the event and verify its welcome notification.
    const attendCheckpoint = notifications.checkpoint();
    await waitForActionResponse(member2Page, () => attendButton.click(), {
      method: "POST",
      urlIncludes: `/event/${TEST_EVENT_IDS.alpha.one}/attend`,
    });
    notifications.expectNew([{ kind: "event-welcome", userIds: [TEST_USER_IDS.member2] }], {
      since: attendCheckpoint,
    });

    // Verify the member can now cancel attendance.
    await expect(getLeaveButton(member2Page)).toBeVisible();

    // Cancel attendance and verify its cancellation notification.
    const cancellationCheckpoint = notifications.checkpoint();
    await cancelAttendance(member2Page, TEST_EVENT_IDS.alpha.one);
    notifications.expectNew([{ kind: "event-attendance-canceled", userIds: [TEST_USER_IDS.member2] }], {
      since: cancellationCheckpoint,
    });
  });

  test("failed attendance changes preserve the current action for retry", async ({ member2Page, owned }) => {
    // Remove the attendance and purchase the successful registration creates.
    owned.defer(() =>
      cleanupEventEnrollment({ eventId: TEST_EVENT_IDS.alpha.one, userId: TEST_USER_IDS.member2 }),
    );

    // Load a reusable event before intercepting attendance changes.
    const attendPath = `**/${TEST_COMMUNITY_NAME}/event/${TEST_EVENT_IDS.alpha.one}/attend`;
    const leavePath = `**/${TEST_COMMUNITY_NAME}/event/${TEST_EVENT_IDS.alpha.one}/leave`;
    await navigateToEvent(
      member2Page,
      TEST_COMMUNITY_NAME,
      TEST_GROUP_SLUGS.community1.alpha,
      TEST_EVENT_SLUGS.alpha[0],
    );
    await waitForAttendanceState(member2Page);

    try {
      // Fail registration and verify the attend action returns with explicit feedback.
      await member2Page.route(attendPath, (route) =>
        route.fulfill({
          body: "Temporary attendance failure",
          contentType: "text/plain",
          status: 500,
        }),
      );
      await waitForActionResponse(member2Page, () => getAttendButton(member2Page).click(), {
        method: "POST",
        status: 500,
        urlIncludes: `/event/${TEST_EVENT_IDS.alpha.one}/attend`,
      });
      await expect(member2Page.locator(".swal2-popup")).toContainText(
        "Something went wrong registering for this event. Please try again later.",
      );
      await expect(getAttendButton(member2Page)).toBeVisible();
      await expect(getAttendButton(member2Page)).toBeEnabled();
      await member2Page.getByRole("button", { name: "OK" }).click();

      // Register successfully before exercising failed cancellation.
      await member2Page.unroute(attendPath);
      await waitForActionResponse(member2Page, () => getAttendButton(member2Page).click(), {
        method: "POST",
        urlIncludes: `/event/${TEST_EVENT_IDS.alpha.one}/attend`,
      });
      await expect(getLeaveButton(member2Page)).toBeVisible();
      await dismissProfileCompletionPrompt(member2Page);

      // Fail cancellation and verify the durable attendance action is preserved.
      await member2Page.route(leavePath, (route) =>
        route.fulfill({
          body: "Temporary cancellation failure",
          contentType: "text/plain",
          status: 500,
        }),
      );
      await getLeaveButton(member2Page).click();
      await expect(member2Page.getByRole("button", { name: "Yes" })).toBeVisible();
      await waitForActionResponse(
        member2Page,
        () => confirmAlert(member2Page, { message: "Are you sure you want to cancel your attendance?" }),
        {
          method: "DELETE",
          status: 500,
          urlIncludes: `/event/${TEST_EVENT_IDS.alpha.one}/leave`,
        },
      );
      await expect(member2Page.locator(".swal2-popup")).toContainText(
        "Something went wrong canceling your attendance. Please try again later.",
      );
      await expect(getLeaveButton(member2Page)).toBeVisible();
      await expect(getLeaveButton(member2Page)).toBeEnabled();
    } finally {
      // Remove the failure routes.
      await member2Page.unroute(attendPath);
      await member2Page.unroute(leavePath);
    }
  });

  test("member answers registration questions before attending", async ({ owned, pending2Page }) => {
    // Cancelling keeps the attendee and a refunded purchase, so remove the pair's enrollment rows.
    owned.defer(() =>
      cleanupEventEnrollment({
        eventId: TEST_REGISTRATION_QUESTIONS_EVENT.id,
        userId: TEST_USER_IDS.pending2,
      }),
    );

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

    // Resolve the attendance state before attending.
    await waitForAttendanceState(pending2Page);

    // Open the required registration questions modal.
    await getAttendButton(pending2Page).click();

    // Find the registration modal.
    const registrationModal = pending2Page.locator('[data-attendance-role="registration-modal"]');
    await expect(registrationModal).toBeVisible();
    await expect(
      registrationModal.getByRole("heading", {
        name: "Registration questions",
      }),
    ).toBeVisible();
    await expect(registrationModal).toContainText("What are you hoping to learn from this event?");
    await expect(registrationModal).toContainText("Preferred session format");
    await expect(registrationModal).toContainText("Topics you want covered");
    await expect(registrationModal).toContainText("Anything the organizers should know?");

    // Fill all question types before submitting the registration.
    await registrationModal
      .locator("fieldset", {
        hasText: "What are you hoping to learn from this event?",
      })
      .locator("textarea")
      .fill("I want to compare live platform practices.");
    await registrationModal.locator("label", { hasText: "Panel discussion" }).click();
    await registrationModal.locator("label", { hasText: "Developer experience" }).click();
    await registrationModal.locator("label", { hasText: "Security and compliance" }).click();
    await registrationModal
      .locator("fieldset", {
        hasText: "Anything the organizers should know?",
      })
      .locator("textarea")
      .fill("Please share slides afterward.");

    // Submit the answers and wait for attendance to be created.
    await waitForActionResponse(
      pending2Page,
      () => registrationModal.locator('[data-attendance-role="registration-modal-submit"]').click(),
      {
        method: "POST",
        urlIncludes: `/event/${TEST_REGISTRATION_QUESTIONS_EVENT.id}/attend`,
      },
    );

    // Verify the member can now cancel attendance.
    await expect(registrationModal).toBeHidden();
    await expect(getLeaveButton(pending2Page)).toContainText("Cancel attendance");

    // Cancel attendance from the event page.
    await cancelAttendance(pending2Page, TEST_REGISTRATION_QUESTIONS_EVENT.id);
  });

  test("signed-out event calls to action match each enrollment model", async ({ page }) => {
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
    await navigateToEvent(page, TEST_COMMUNITY_NAME, TEST_GROUP_SLUGS.community1.alpha, "alpha-waitlist-lab");
    await expect(getSignInButton(page)).toContainText("Join waiting list");

    // Events with no public tiers stay informational rather than prompting login.
    await navigateToEvent(
      page,
      TEST_COMMUNITY_NAME,
      TEST_GROUP_SLUGS.community1.alpha,
      TEST_TICKETING_EVENTS.paidOffers.slug,
    );
    await expect(getSignInButton(page)).toBeHidden();
    await expect(getAttendButton(page)).toContainText("Invitation only");
    await expect(getAttendButton(page)).toBeDisabled();
  });

  test("required registration questions block an empty submission", async ({ pending2Page }) => {
    // Load the event with required registration questions.
    await navigateToEvent(
      pending2Page,
      TEST_COMMUNITY_NAME,
      TEST_GROUP_SLUGS.community1.alpha,
      TEST_REGISTRATION_QUESTIONS_EVENT.slug,
    );
    await waitForAttendanceState(pending2Page);

    // Track attendance requests so browser validation can be verified.
    let attendanceRequests = 0;
    pending2Page.on("request", (request) => {
      if (
        request.method() === "POST" &&
        request.url().includes(`/event/${TEST_REGISTRATION_QUESTIONS_EVENT.id}/attend`)
      ) {
        attendanceRequests += 1;
      }
    });

    // Open the questions modal and submit it without required answers.
    await getAttendButton(pending2Page).click();
    const registrationModal = pending2Page.locator('[data-attendance-role="registration-modal"]');
    const requiredAnswer = registrationModal
      .locator("fieldset", {
        hasText: "What are you hoping to learn from this event?",
      })
      .locator("textarea");
    await registrationModal.locator('[data-attendance-role="registration-modal-submit"]').click();

    // Verify the form remains open and no attendance request is sent.
    await expect(registrationModal).toBeVisible();
    // Native required validation blocks the submit before any request fires.
    await expect.poll(() => requiredAnswer.evaluate((input) => input.validity.valueMissing)).toBe(true);
    await expect
      .poll(() => requiredAnswer.evaluate((input) => input.validationMessage.length))
      .toBeGreaterThan(0);
    expect(attendanceRequests).toBe(0);

    // Close the invalid form and verify the modal is dismissed.
    await registrationModal.locator('[data-attendance-role="registration-modal-cancel"]').click();
    await expect(registrationModal).toBeHidden();
  });

  test("member can request and cancel approval-required attendance", async ({ owned, pending1Page }) => {
    // Remove the invitation request even if the flow fails before cancelling it.
    owned.defer(() =>
      cleanupEventEnrollment({ eventId: TEST_APPROVAL_REQUIRED_EVENT.id, userId: TEST_USER_IDS.pending1 }),
    );

    // Load the seeded approval-required event and resolve the current state.
    await navigateToEvent(
      pending1Page,
      TEST_COMMUNITY_NAME,
      TEST_GROUP_SLUGS.community1.alpha,
      TEST_APPROVAL_REQUIRED_EVENT.slug,
    );
    await waitForAttendanceState(pending1Page);

    // Verify the event labels the approval action before submission.
    const requestInvitationButton = getAttendButton(pending1Page);
    await expect(requestInvitationButton).toContainText("Request invitation");

    // Submit the invitation request and wait for its pending state.
    await waitForActionResponse(pending1Page, () => requestInvitationButton.click(), {
      method: "POST",
      urlIncludes: `/event/${TEST_APPROVAL_REQUIRED_EVENT.id}/attend`,
    });

    // Verify the public action explains the organizer-review state.
    const cancelRequestButton = getLeaveButton(pending1Page);
    await expect(cancelRequestButton).toContainText("Request pending");
    await expect(cancelRequestButton).toHaveAttribute(
      "title",
      "Your invitation request is waiting for organizer review.",
    );

    // Cancel the request and verify the action returns.
    await cancelAttendance(pending1Page, TEST_APPROVAL_REQUIRED_EVENT.id);
    await expect(getAttendButton(pending1Page)).toContainText("Request invitation");
  });

  test("rejected approval request remains disabled with recovery copy", async ({ pending2Page }) => {
    // Load the approval event with a seeded rejected request.
    await navigateToEvent(
      pending2Page,
      TEST_COMMUNITY_NAME,
      TEST_GROUP_SLUGS.community1.alpha,
      TEST_APPROVAL_REQUIRED_EVENT.slug,
    );
    await waitForAttendanceState(pending2Page);

    // Verify rejected users cannot submit another invitation request.
    const rejectedRequestButton = getAttendButton(pending2Page);
    await expect(rejectedRequestButton).toContainText("Request rejected");
    await expect(rejectedRequestButton).toBeDisabled();
    await expect(rejectedRequestButton).toHaveAttribute("title", "Your invitation request was rejected.");
  });

  test("accepted approval request surfaces the offer claim state", async ({ member1Page }) => {
    // Load the approval event with a seeded accepted request and offer.
    await navigateToEvent(
      member1Page,
      TEST_COMMUNITY_NAME,
      TEST_GROUP_SLUGS.community1.alpha,
      TEST_APPROVAL_REQUIRED_EVENT.slug,
    );
    await waitForAttendanceState(member1Page);

    // Verify the approved offer routes claiming through the dashboard.
    const attendButton = getAttendButton(member1Page);
    await expect(attendButton).toContainText("Confirm RSVP");
    await expect(attendButton).toHaveAttribute(
      "data-resume-url",
      `/dashboard/user?tab=invitations#event-offer-${TEST_APPROVAL_REQUIRED_EVENT.offerId}`,
    );
  });

  test("members whose latest ticket offer expired see the expired state", async ({ member1Page, owned }) => {
    // Record an expired organizer invitation for the member on an owned event.
    const event = owned.event({ groupId: TEST_GROUP_IDS.community1.alpha });
    setupTicketOffer({
      eventId: event.eventId,
      source: "organizer_invitation",
      status: "expired",
      ticketTypeId: event.ticketTypeIds.general,
      userId: TEST_USER_IDS.member1,
    });

    // Load the event and resolve the member's attendance state.
    await navigateToEvent(member1Page, TEST_COMMUNITY_NAME, TEST_GROUP_SLUGS.community1.alpha, event.slug);
    await waitForAttendanceState(member1Page);

    // Verify the expired offer blocks attending.
    const attendButton = getAttendButton(member1Page);
    await expect(attendButton).toContainText("Ticket offer expired");
    await expect(attendButton).toBeDisabled();
  });

  test("attending twice through the API is rejected", async ({ member1Page, owned }) => {
    // Seat the member on an owned event.
    const event = owned.event({
      attendeeUserIds: [TEST_USER_IDS.member1],
      groupId: TEST_GROUP_IDS.community1.alpha,
    });

    // Post a second attendance directly, bypassing the event page.
    const response = await member1Page.request.post(
      buildE2eUrl(`/${TEST_COMMUNITY_NAME}/event/${event.eventId}/attend`),
      { form: {} },
    );

    // Verify the enrollment guard rejects it and keeps a single attendee row.
    expect(response.status()).toBe(422);
    expect(await response.text()).toContain("user is already attending this event");
    expect(
      queryE2eDatabase(`
        select count(*)
        from event_attendee
        where event_id = '${event.eventId}'
        and user_id = '${TEST_USER_IDS.member1}';
      `),
    ).toBe("1");
  });

  test("attendee sees the meeting link while the event is live", async ({ pending2Page }) => {
    // Load the live event where the user is a seeded attendee.
    await navigateToEvent(
      pending2Page,
      TEST_COMMUNITY_NAME,
      TEST_GROUP_SLUGS.community1.alpha,
      TEST_OPEN_CHECK_IN_EVENT.slug,
    );
    await waitForAttendanceState(pending2Page);

    // Verify the meeting details reveal the seeded join instructions.
    const meetingDetails = pending2Page.locator("[data-meeting-details]").first();
    await expect(meetingDetails).toBeVisible();
    await expect(
      meetingDetails.getByText("Use the passcode shared with attendees to join the room."),
    ).toBeVisible();

    // Verify the meeting link exposes the seeded join destination.
    const meetingLink = meetingDetails.getByRole("link", {
      name: "Meeting link",
    });
    await expect(meetingLink).toBeVisible();
    await expect(meetingLink).toHaveAttribute("href", "https://meet.example.com/e2e-open-check-in");

    // Verify the agenda session exposes its attendee-only join link.
    const sessionItem = pending2Page.locator("li", {
      hasText: "Live Check-In Briefing",
    });
    const sessionJoinLink = sessionItem.getByRole("link", {
      name: "Join session",
    });
    await expect(sessionJoinLink).toBeVisible();
    await expect(sessionJoinLink).toHaveAttribute("href", "https://meet.example.com/e2e-live-briefing");
  });

  test.describe("payment-enabled attendance flows", () => {
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
      await expect(getAttendButton(pending2Page)).toContainText("Continue to checkout");

      // Keep unrelated URL state while removing the one-time payment outcome.
      await expect.poll(() => pending2Page.url()).toContain("?source=e2e#attendance");
      expect(new URL(pending2Page.url()).searchParams.has("payment")).toBe(false);
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
      await expect(eventsManagerGroupPage.locator(".swal2-popup")).toContainText(
        "Your payment is complete. You're registered for this event.",
      );
      await expect(getRefundButton(eventsManagerGroupPage)).toContainText("Request refund");
      await expect.poll(() => new URL(eventsManagerGroupPage.url()).searchParams.has("payment")).toBe(false);
    });

    test("successful payment returns poll pending checkout until attendance is confirmed", async ({
      pending2Page,
    }) => {
      const event = TEST_TICKETING_EVENTS.paymentReturn;
      const enrollmentUrl = `**/event/${event.id}/enrollment`;
      let allowAttendanceConfirmation = false;
      let paymentReturnRequests = 0;

      // Keep payment-return requests pending until the interim feedback is observable.
      await pending2Page.route(enrollmentUrl, async (route) => {
        const isHtmxRequest = route.request().headers()["hx-request"] === "true";
        if (!isHtmxRequest) {
          paymentReturnRequests += 1;
        }

        const status = allowAttendanceConfirmation ? "attendee" : "pending-payment";
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
        await expect.poll(() => new URL(pending2Page.url()).searchParams.has("payment")).toBe(false);
      } finally {
        // Restore the real enrollment endpoint.
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
      owned,
    }) => {
      const event = TEST_TICKETING_EVENTS.ticketRequest;
      owned.defer(() => cleanupEventEnrollment({ eventId: event.id, userId: TEST_USER_IDS.member1 }));

      // Open the approval-required ticketed event as an authenticated member.
      await navigateToEvent(member1Page, TEST_COMMUNITY_NAME, TEST_GROUP_SLUGS.community1.alpha, event.slug);
      await waitForAttendanceState(member1Page);
      await expect(getAttendButton(member1Page)).toContainText("Request ticket");
      await getAttendButton(member1Page).click();

      // Verify only the public requested tier appears in the attendee modal.
      const ticketModal = getTicketModal(member1Page);
      await expect(ticketModal).toBeVisible();
      await expect(ticketModal).toContainText("Requested conference pass");
      await expect(ticketModal).not.toContainText("Private supporter pass");
      await ticketModal.locator("label", { hasText: "Requested conference pass" }).click();
      await ticketModal.locator('[data-attendance-role="discount-code-input"]').evaluate((input) => {
        input.disabled = false;
        input.value = "OFFER25";
      });

      // Continue through required registration questions before submitting.
      await getCheckoutButton(member1Page).click();
      const registrationModal = member1Page.locator('[data-attendance-role="registration-modal"]');
      await expect(registrationModal).toBeVisible();
      await registrationModal.getByRole("textbox").fill("I would like to join the attendee program.");

      // Submit the request and inspect the attendee-facing form contract.
      const requestPromise = member1Page.waitForRequest(
        (request) => request.method() === "POST" && request.url().includes(`/event/${event.id}/attend`),
      );
      await waitForActionResponse(
        member1Page,
        () => registrationModal.locator('[data-attendance-role="registration-modal-submit"]').click(),
        {
          method: "POST",
          urlIncludes: `/event/${event.id}/attend`,
        },
      );
      const request = await requestPromise;
      const requestData = new URLSearchParams(request.postData() ?? "");
      const answers = JSON.parse(requestData.get("registration_answers") ?? "{}");

      // Approval requests retain answers and the requested public tier only.
      expect(requestData.get("event_ticket_type_id")).toBe("56555555-5555-5555-5555-555555555913");
      expect(requestData.has("discount_code")).toBe(false);
      expect(answers.answers?.[0]?.value).toBe("I would like to join the attendee program.");
      await expect(getLeaveButton(member1Page)).toContainText("Request pending");
      await dismissProfileCompletionPrompt(member1Page);
      await expect(getLeaveButton(member1Page)).toHaveAccessibleName("Request pending – cancel request");
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
        // Open the paid questions checkout flow.
        await navigateToEvent(
          member1Page,
          TEST_COMMUNITY_NAME,
          TEST_GROUP_SLUGS.community1.alpha,
          event.slug,
        );
        await waitForAttendanceState(member1Page);
        await getAttendButton(member1Page).click();
        const ticketModal = getTicketModal(member1Page);
        await ticketModal.locator("label", { hasText: "Questions conference pass" }).click();
        await getCheckoutButton(member1Page).click();

        // Submit registration answers and capture the checkout request.
        const registrationModal = member1Page.locator('[data-attendance-role="registration-modal"]');
        await registrationModal.getByRole("textbox").fill("Please reserve captions for the paid workshop.");
        const checkoutRequest = member1Page.waitForRequest(
          (request) => request.method() === "POST" && request.url().includes(`/event/${event.id}/checkout`),
        );
        await Promise.all([
          member1Page.waitForURL(/questions-checkout=redirected/u),
          registrationModal.locator('[data-attendance-role="registration-modal-submit"]').click(),
        ]);
        const requestData = new URLSearchParams((await checkoutRequest).postData() ?? "");
        const answers = JSON.parse(requestData.get("registration_answers") ?? "{}");

        // Paid provider checkout keeps the selected tier and validated answers.
        expect(requestData.get("event_ticket_type_id")).toBe("56555555-5555-5555-5555-555555555917");
        expect(requestData.has("discount_code")).toBe(false);
        expect(answers.answers?.[0]?.value).toBe("Please reserve captions for the paid workshop.");
      } finally {
        // Restore the real checkout endpoint.
        await member1Page.unroute(checkoutUrl);
      }
    });

    test("member sees checkout validation and only sellable tickets in the ticket modal @smoke", async ({
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
      await expect(getCheckoutButton(member1Page)).toHaveAttribute("title", "Choose a ticket to continue.");
      await expect(ticketModal).not.toContainText("Backstage pass");

      // Close the ticket modal without registering.
      await ticketModal.locator('[data-attendance-role="ticket-modal-cancel"]').click();

      // Verify closing the modal leaves the member unregistered.
      await expect(ticketModal).toBeHidden();
      await expect(getLeaveButton(member1Page)).toBeHidden();
      await expect(getAttendButton(member1Page)).toContainText("Get ticket");
    });

    test("member can complete a free ticket checkout without a discount code", async ({
      member2Page,
      owned,
    }) => {
      // Cancelling keeps the attendee and a refunded purchase, so remove the pair's enrollment rows.
      owned.defer(() =>
        cleanupEventEnrollment({ eventId: TEST_PAYMENT_EVENT_IDS.draft, userId: TEST_USER_IDS.member2 }),
      );

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
      await ticketModal.locator("label", { hasText: "Community ticket" }).click();

      // Watch checkout request payload and response after submitting.
      const checkoutRequest = member2Page.waitForRequest(
        (request) =>
          request.method() === "POST" &&
          request.url().includes(`/event/${TEST_PAYMENT_EVENT_IDS.draft}/checkout`),
      );

      // Submit checkout for the selected free ticket.
      await waitForActionResponse(member2Page, () => getCheckoutButton(member2Page).click(), {
        method: "POST",
        urlIncludes: `/event/${TEST_PAYMENT_EVENT_IDS.draft}/checkout`,
      });

      // Wait for checkout request details and the successful response.
      const request = await checkoutRequest;
      const postData = request.postData() ?? "";

      // Verify checkout does not send a discount code.
      expect(postData).not.toContain("discount_code=");

      // Verify successful checkout registers the member.
      await expect(member2Page).toHaveURL(new RegExp(TEST_PAYMENT_EVENT_SLUGS.draft));
      await expect(getLeaveButton(member2Page)).toContainText("Cancel attendance");
      await expect(member2Page.locator(".swal2-popup")).toContainText(
        "You have successfully registered for this event.",
      );

      // Cancel the ticket attendance from the event page.
      await cancelAttendance(member2Page, TEST_PAYMENT_EVENT_IDS.draft);
    });

    test("sold-out waitlist submissions omit discounts and stale answers", async ({
      owned,
      pending1Page,
    }) => {
      const event = TEST_TICKETING_EVENTS.soldOut;
      owned.defer(() => cleanupEventEnrollment({ eventId: event.id, userId: TEST_USER_IDS.pending1 }));

      // Open the sold-out paid tier and verify its exact ticket-card state.
      await navigateToEvent(pending1Page, TEST_COMMUNITY_NAME, TEST_GROUP_SLUGS.community1.alpha, event.slug);
      await waitForAttendanceState(pending1Page);
      await expect(getAttendButton(pending1Page)).toContainText("Join waiting list");
      await getAttendButton(pending1Page).click();
      const ticketModal = getTicketModal(pending1Page);
      const soldOutCard = ticketModal.locator('[data-attendance-role="ticket-type-card"]', {
        hasText: "Limited conference pass",
      });
      await expect(soldOutCard.locator('[data-attendance-role="ticket-type-status-label"]')).toHaveText(
        "Sold out (you can join the waiting list)",
      );
      await soldOutCard.click();

      // Seed stale client values that must not cross the waitlist boundary.
      await ticketModal.locator('[data-attendance-role="discount-code-input"]').evaluate((input) => {
        input.disabled = false;
        input.value = "FULLCOMP";
      });
      await ticketModal
        .locator('[data-attendance-role="checkout-registration-answers-input"]')
        .evaluate((input) => {
          input.value = JSON.stringify({
            answers: [{ question_id: "stale", value: "stale answer" }],
          });
        });

      // Join the waiting list and inspect the final request payload.
      const waitlistRequest = pending1Page.waitForRequest(
        (request) => request.method() === "POST" && request.url().includes(`/event/${event.id}/attend`),
      );
      await waitForActionResponse(pending1Page, () => getCheckoutButton(pending1Page).click(), {
        method: "POST",
        urlIncludes: `/event/${event.id}/attend`,
      });
      const requestData = new URLSearchParams((await waitlistRequest).postData() ?? "");

      // Waiting-list requests carry only their selected tier.
      expect(requestData.get("event_ticket_type_id")).toBe("56555555-5555-5555-5555-555555555918");
      expect(requestData.has("discount_code")).toBe(false);
      expect(requestData.has("registration_answers")).toBe(false);
      await expect(getLeaveButton(pending1Page)).toContainText("Leave waiting list");
    });

    test("a finalized refund releases sold-out ticket capacity", async ({ pending1Page }) => {
      const event = TEST_TICKETING_EVENTS.refundedCapacity;

      // Load the refunded-capacity event before opening ticket choices.
      await navigateToEvent(pending1Page, TEST_COMMUNITY_NAME, TEST_GROUP_SLUGS.community1.alpha, event.slug);
      await waitForAttendanceState(pending1Page);

      // The refunded purchase no longer occupies the event's only seat.
      await expect(pending1Page.locator("[data-availability-sold-out-ribbon]")).toBeHidden();
      await expect(getAttendButton(pending1Page)).toContainText("Get ticket");
      await getAttendButton(pending1Page).click();

      // Verify the refunded tier is available for selection.
      const refundedTierCard = getTicketModal(pending1Page).locator(
        '[data-attendance-role="ticket-type-card"]',
        { hasText: "Refunded conference pass" },
      );
      await expect(refundedTierCard).toContainText("Available now");
      await expect(refundedTierCard.locator('[data-attendance-role="ticket-type-option"]')).toBeEnabled();
    });

    test("mixed tiers show remaining seats and the waitlist hint on the sold-out tier", async ({
      member1Page,
    }) => {
      const event = TEST_TICKETING_EVENTS.mixedTierWaitlist;

      // Load the mixed-tier event whose waiting list is enabled.
      await navigateToEvent(member1Page, TEST_COMMUNITY_NAME, TEST_GROUP_SLUGS.community1.alpha, event.slug);
      await waitForAttendanceState(member1Page);

      // The open tier keeps remaining seats visible despite the waiting list.
      await expect(member1Page.locator("[data-availability-capacity]")).toHaveText("4");
      await expect(member1Page.locator('[data-availability-caption="remaining"]')).toBeVisible();
      await expect(member1Page.locator("[data-availability-remaining]")).toHaveText("3");
      await expect(member1Page.locator("[data-availability-sold-out-ribbon]")).toBeHidden();

      // Open ticket choices and verify each tier status.
      await getAttendButton(member1Page).click();
      const ticketModal = getTicketModal(member1Page);
      await expect(ticketModal).toBeVisible();
      const soldOutCard = getTicketTypeCard(ticketModal, "Early pass");
      const openCard = getTicketTypeCard(ticketModal, "Standard pass");
      await expect(soldOutCard.locator('[data-attendance-role="ticket-type-status-label"]')).toHaveText(
        "Sold out (you can join the waiting list)",
      );
      await expect(soldOutCard.locator('[data-attendance-role="ticket-type-option"]')).toBeEnabled();
      await expect(openCard.locator('[data-attendance-role="ticket-type-status-label"]')).toHaveText(
        "Available now",
      );
      await expect(openCard.locator('[data-attendance-role="ticket-type-option"]')).toBeEnabled();

      // Selecting each tier switches between the waitlist and ticket actions.
      await soldOutCard.click();
      await expect(getCheckoutButton(member1Page)).toContainText("Join waiting list");
      await openCard.click();
      await expect(getCheckoutButton(member1Page)).toContainText("Get free ticket");

      // Close the ticket modal without registering.
      await ticketModal.locator('[data-attendance-role="ticket-modal-cancel"]').click();
      await expect(ticketModal).toBeHidden();
    });

    test("mixed tiers keep the sold-out tier closed without a waiting list", async ({ member1Page }) => {
      const event = TEST_TICKETING_EVENTS.mixedTierNoWaitlist;

      // Load the mixed-tier event whose waiting list is disabled.
      await navigateToEvent(member1Page, TEST_COMMUNITY_NAME, TEST_GROUP_SLUGS.community1.alpha, event.slug);
      await waitForAttendanceState(member1Page);

      // The open tier keeps remaining seats visible.
      await expect(member1Page.locator('[data-availability-caption="remaining"]')).toBeVisible();
      await expect(member1Page.locator("[data-availability-remaining]")).toHaveText("3");

      // Open ticket choices and verify the sold-out tier omits the waitlist hint.
      await getAttendButton(member1Page).click();
      const ticketModal = getTicketModal(member1Page);
      await expect(ticketModal).toBeVisible();
      const soldOutCard = getTicketTypeCard(ticketModal, "Early pass");
      const openCard = getTicketTypeCard(ticketModal, "Standard pass");
      await expect(soldOutCard.locator('[data-attendance-role="ticket-type-status-label"]')).toHaveText(
        "Sold out",
      );
      await expect(soldOutCard.locator('[data-attendance-role="ticket-type-option"]')).toBeDisabled();
      await expect(openCard.locator('[data-attendance-role="ticket-type-status-label"]')).toHaveText(
        "Available now",
      );
      await expect(openCard.locator('[data-attendance-role="ticket-type-option"]')).toBeEnabled();

      // Close the ticket modal without registering.
      await ticketModal.locator('[data-attendance-role="ticket-modal-cancel"]').click();
      await expect(ticketModal).toBeHidden();
    });

    test("ticket cards show the not-on-sale state from refreshed availability", async ({ member1Page }) => {
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
        // Open ticket choices from refreshed availability data.
        await navigateToEvent(member1Page, TEST_COMMUNITY_NAME, TEST_GROUP_SLUGS.community1.alpha, event);
        await waitForAttendanceState(member1Page);
        await getAttendButton(member1Page).click();
        const unavailableCard = getTicketModal(member1Page).locator(
          '[data-attendance-role="ticket-type-card"]',
          { hasText: "General admission" },
        );
        await expect(unavailableCard).toContainText("Not on sale");
        await expect(unavailableCard.locator('[data-attendance-role="ticket-type-option"]')).toBeDisabled();
      } finally {
        // Restore the real availability endpoint.
        await member1Page.unroute(availabilityUrl);
      }
    });

    test("member trims the discount code before a paid ticket checkout", async ({ pending1Page }) => {
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
      await ticketModal.locator("label", { hasText: "General admission" }).click();
      await ticketModal.locator('[data-attendance-role="discount-code-input"]').fill("  SAVE10  ");

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
          request.url().includes(`/event/${TEST_PAYMENT_EVENT_IDS.draft}/checkout`),
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
        // Restore the real checkout endpoint.
        await pending1Page.unroute(checkoutUrl);
      }
    });

    for (const discountCase of UNAVAILABLE_DISCOUNT_CASES) {
      test(`member sees an error for ${discountCase.name} discount codes during checkout`, async ({
        member1Page,
      }) => {
        // Load the paid event before submitting the unavailable discount.
        await navigateToEvent(
          member1Page,
          TEST_COMMUNITY_NAME,
          TEST_GROUP_SLUGS.community1.alpha,
          TEST_PAYMENT_EVENT_SLUGS.draft,
        );

        // Open the ticket modal before entering the discount.
        await waitForAttendanceState(member1Page);
        await getAttendButton(member1Page).click();

        // Select a ticket and enter the unavailable discount code.
        const ticketModal = getTicketModal(member1Page);
        await ticketModal.locator("label", { hasText: "General admission" }).click();
        await ticketModal.locator('[data-attendance-role="discount-code-input"]').fill(discountCase.code);

        // Submit checkout and wait for discount validation.
        await waitForActionResponse(member1Page, () => getCheckoutButton(member1Page).click(), {
          method: "POST",
          status: 422,
          urlIncludes: `/event/${TEST_PAYMENT_EVENT_IDS.draft}/checkout`,
        });

        // Verify the rejected discount keeps the ticket modal open.
        await expect(member1Page.locator(".swal2-popup")).toContainText("discount code is not available");
        await expect(ticketModal).toBeVisible();
      });
    }

    test("member can resume a pending checkout from the event page", async ({ emptyUserPage, owned }) => {
      // Create an owned active checkout hold before loading the paid event.
      owned.track(
        setupOwnedPendingCheckout({
          eventId: TEST_PAYMENT_EVENT_IDS.draft,
          providerCheckoutSessionId: "cs_e2e_owned_resume_checkout",
          providerCheckoutUrl: OWNED_CHECKOUT_RESUME_URL,
          userId: TEST_USER_IDS.empty,
        }),
        cleanupOwnedPaymentPurchase,
      );

      // Resolve the current ticket attendance state.
      await navigateToEvent(
        emptyUserPage,
        TEST_COMMUNITY_NAME,
        TEST_GROUP_SLUGS.community1.alpha,
        TEST_PAYMENT_EVENT_SLUGS.draft,
      );
      await waitForAttendanceState(emptyUserPage);

      // Verify the owned pending payment exposes a non-empty provider resume URL.
      const attendButton = getAttendButton(emptyUserPage);
      await expect(attendButton).toContainText("Continue to checkout");
      await expect(attendButton).toHaveAttribute("data-resume-url", OWNED_CHECKOUT_RESUME_URL);
      const resumeCheckoutUrl = await attendButton.getAttribute("data-resume-url");
      expect(resumeCheckoutUrl).toBe(OWNED_CHECKOUT_RESUME_URL);
      expect(new URL(resumeCheckoutUrl).origin).toBe("https://example.test");
    });

    test("member can cancel a pending checkout from the event page", async ({ emptyUserPage, owned }) => {
      // Create an owned active checkout hold before loading the paid event.
      const purchase = owned.track(
        setupOwnedPendingCheckout({
          eventId: TEST_PAYMENT_EVENT_IDS.draft,
          providerCheckoutSessionId: "cs_e2e_owned_cancel_checkout",
          providerCheckoutUrl: OWNED_CHECKOUT_CANCEL_URL,
          userId: TEST_USER_IDS.empty,
        }),
        cleanupOwnedPaymentPurchase,
      );

      // Resolve the current ticket attendance state.
      await navigateToEvent(
        emptyUserPage,
        TEST_COMMUNITY_NAME,
        TEST_GROUP_SLUGS.community1.alpha,
        TEST_PAYMENT_EVENT_SLUGS.draft,
      );
      await waitForAttendanceState(emptyUserPage);
      await expect(getAttendButton(emptyUserPage)).toContainText("Continue to checkout");
      expect(
        queryE2eDatabase(`
            select status
            from event_purchase
            where event_purchase_id = '${purchase.purchaseId}';
          `),
      ).toBe("pending");

      // Open the event-page actions and cancel the active checkout hold.
      const attendanceContainer = getAttendanceContainer(emptyUserPage);
      const actionsMenu = attendanceContainer.locator('[data-attendance-role="actions-menu"]');
      await expect(actionsMenu).toBeVisible();
      await actionsMenu.locator("summary").click();
      await attendanceContainer.locator('[data-attendance-role="checkout-cancel-btn"]').click();

      // Confirm checkout cancellation and verify the ticket hold is released.
      await waitForActionResponse(
        emptyUserPage,
        () => confirmAlert(emptyUserPage, { message: "Are you sure you want to cancel this checkout?" }),
        {
          method: "DELETE",
          urlIncludes: `/event/${TEST_PAYMENT_EVENT_IDS.draft}/checkout`,
        },
      );
      await expect(emptyUserPage.locator(".swal2-popup")).toContainText(
        "Your checkout has been canceled. You can choose a different ticket.",
      );
      expect(
        queryE2eDatabase(`
            select status || '|' || (hold_expires_at <= current_timestamp)::text
            from event_purchase
            where event_purchase_id = '${purchase.purchaseId}';
          `),
      ).toBe("expired|true");
      await expect(getAttendButton(emptyUserPage)).toContainText("Get ticket");
    });

    test("paid attendee sees a pending refund request on the event page", async ({ member1Page }) => {
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

    test("paid attendee sees refund processing on the event page", async ({ member2Page }) => {
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

    test("paid attendee sees the reason when a refund request was rejected", async ({ pending1Page }) => {
      // Load the refund-ready event with a rejected refund.
      await navigateToEvent(
        pending1Page,
        TEST_COMMUNITY_NAME,
        TEST_GROUP_SLUGS.community1.alpha,
        TEST_PAYMENT_EVENT_SLUGS.refunds,
      );

      // Set up refund button.
      const refundButton = getRefundButton(pending1Page);
      const rejectionReason = pending1Page.locator('[data-attendance-role="refund-rejection-reason"]');

      // Assert the rejected state and its persisted organizer reason.
      await expect(refundButton).toBeVisible();
      await expect(refundButton).toContainText("Refund rejected");
      await expect(refundButton).toBeDisabled();
      await expect(rejectionReason).toHaveText("The request falls outside the refund policy window.");
      await expect(getLeaveButton(pending1Page)).toBeHidden();
    });

    test("paid attendee can request a refund before the event starts", async ({
      emptyUserPage,
      notifications,
      owned,
    }) => {
      // Create an owned completed purchase so the request starts from an exact state.
      const purchase = owned.track(
        setupOwnedCompletedRefundPurchase({
          eventId: TEST_PAYMENT_EVENT_IDS.refunds,
          userId: TEST_USER_IDS.empty,
        }),
        cleanupOwnedPaymentPurchase,
      );

      // Load the refund-ready event before requesting a refund.
      await navigateToEvent(
        emptyUserPage,
        TEST_COMMUNITY_NAME,
        TEST_GROUP_SLUGS.community1.alpha,
        TEST_PAYMENT_EVENT_SLUGS.refunds,
      );

      // Set up refund button.
      const refundButton = getRefundButton(emptyUserPage);

      // Verify the attendee can request a refund instead of canceling.
      await expect(refundButton).toBeVisible();
      await expect(refundButton).toContainText("Request refund");
      await expect(refundButton).toBeEnabled();
      await expect(getLeaveButton(emptyUserPage)).toBeHidden();

      // Open the refund request modal and provide an optional reason.
      await refundButton.click();
      const refundModal = emptyUserPage.getByRole("dialog", {
        name: "Request a refund",
      });
      await expect(refundModal).toBeVisible();
      await refundModal.getByRole("textbox", { name: "Reason (optional)" }).fill("Unable to attend");

      // Submit the request and verify the reason reaches the refund endpoint.
      const refundResponse = await waitForActionResponse(
        emptyUserPage,
        () => refundModal.getByRole("button", { name: "Request refund" }).click(),
        {
          method: "POST",
          urlIncludes: `/event/${TEST_PAYMENT_EVENT_IDS.refunds}/refund-request`,
        },
      );
      notifications.expectNew([
        {
          kind: "event-refund-requested",
          userIds: EVENT_REFUND_REQUESTED_RECIPIENT_IDS,
        },
      ]);
      const refundRequestData = new URLSearchParams(refundResponse.request().postData());
      expect(refundRequestData.get("requested_reason")).toBe("Unable to attend");

      // Verify exactly one durable refund request is created for the owned purchase.
      expect(
        queryE2eDatabase(`
            select count(*) || '|' || max(status) || '|' || max(requested_reason)
            from event_refund_request
            where event_purchase_id = '${purchase.purchaseId}';
          `),
      ).toBe("1|pending|Unable to attend");

      // Verify the event page updates to the pending refund request state.
      await expect(emptyUserPage.locator(".swal2-popup")).toContainText(
        "Your refund request has been sent to the organizers.",
      );
      await expect(refundButton).toContainText("Refund requested");
      await expect(refundButton).toBeDisabled();
    });
  });
});

/** Returns the sign-in action shown to anonymous users. */
const getSignInButton = (page) => page.locator('[data-attendance-role="signin-btn"]');

/** Returns the ticket type card matching a tier title inside the ticket modal. */
const getTicketTypeCard = (ticketModal, title) =>
  ticketModal.locator('[data-attendance-role="ticket-type-card"]', {
    has: ticketModal.page().locator('[data-attendance-role="ticket-type-title"]', {
      hasText: title,
    }),
  });
