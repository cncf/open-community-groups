import { expect } from "@open-wc/testing";

import "/static/js/event/attendance.js";
import { getAttendanceMeta } from "/static/js/event/attendance-dom.js";
import {
  showRegistrationQuestionsPendingState,
  showSignedOutAttendanceState,
} from "/static/js/event/attendance-view.js";
import { waitForMicrotask } from "/tests/unit/test-utils/async.js";
import { useDashboardTestEnv } from "/tests/unit/test-utils/env.js";
import { dispatchHtmxAfterRequest, dispatchHtmxBeforeRequest } from "/tests/unit/test-utils/htmx.js";
import { mockFetch } from "/tests/unit/test-utils/network.js";

// Initialize attendance dom for the test.
const initializeAttendanceDom = async () => {
  document.body.dataset.attendanceListenersReady = "true";
  await import(`/static/js/event/attendance.js?test=${Date.now()}`);
};

const renderAttendanceDom = ({
  starts = "2099-05-10T10:00:00Z",
  capacity = "10",
  remainingCapacity = "5",
  waitlistEnabled = "false",
  attendeeMeetingAccessOpen = "false",
  canceled = "false",
  availabilityUrl = "",
  attendeeApprovalRequired = "false",
  includeRegistrationQuestions = false,
  registrationWindowOpen = "true",
  registrationWindowUnavailableTitle = "",
  isSimpleRsvp = "true",
} = {}) => {
  document.body.innerHTML = `
    <div
      data-attendance-container
      data-starts="${starts}"
      data-capacity="${capacity}"
      data-remaining-capacity="${remainingCapacity}"
      data-waitlist-enabled="${waitlistEnabled}"
      data-canceled="${canceled}"
      ${availabilityUrl ? `data-availability-url="${availabilityUrl}"` : ""}
      data-registration-window-open="${registrationWindowOpen}"
      ${
        registrationWindowUnavailableTitle
          ? `data-registration-window-unavailable-title="${registrationWindowUnavailableTitle}"`
          : ""
      }
      data-attendee-meeting-access-open="${attendeeMeetingAccessOpen}"
      data-attendee-approval-required="${attendeeApprovalRequired}"
      data-is-simple-rsvp="${isSimpleRsvp}"
    >
      <button data-attendance-role="attendance-checker"></button>
      <button
        data-attendance-role="loading-btn"
        role="status"
        aria-live="polite"
        class="hidden"
      >
        <span data-attendance-label>Loading</span>
      </button>
      <button
        id="signin-btn"
        data-attendance-role="signin-btn"
        class="hidden"
        data-path="/events/test-event"
      >
        <div class="svg-icon icon-user-plus" data-attendance-icon></div>
        <span data-attendance-label>Attend event</span>
      </button>
      <button
        id="attend-btn"
        data-attendance-role="attend-btn"
        class="hidden"
      >
        <div class="svg-icon icon-user-plus" data-attendance-icon></div>
        <span data-attendance-label>Attend event</span>
      </button>
      <button
        id="leave-btn"
        data-attendance-role="leave-btn"
        class="hidden"
      >
        <div class="svg-icon icon-cancel" data-attendance-icon></div>
        <span data-attendance-label>Cancel attendance</span>
      </button>
      <button
        id="refund-btn"
        data-attendance-role="refund-btn"
        class="hidden"
      >
        <div class="svg-icon icon-refund" data-attendance-icon></div>
        <span data-attendance-label>Request refund</span>
      </button>
      <p data-attendance-role="refund-rejection-reason" class="hidden"></p>
      ${
        includeRegistrationQuestions
          ? `
      <div
        id="questions-modal"
        data-attendance-role="registration-modal"
        class="hidden"
      >
        <form data-attendance-role="registration-form">
          <fieldset
            data-question-id="question-1"
            data-question-kind="free-text"
            data-question-required="true"
          >
            <textarea data-question-answer required></textarea>
          </fieldset>
          <input
            type="hidden"
            data-attendance-role="registration-answers-input"
            name="registration_answers"
          >
        </form>
      </div>`
          : ""
      }
    </div>
    <div data-meeting-details class="hidden">
      <a data-join-link-always class="hidden"></a>
    </div>
    <div data-meeting-details data-has-recording="true" class="hidden"></div>
    <a data-join-link class="hidden"></a>
    <a data-join-link-menu class="hidden xl:hidden"></a>
    <span data-availability-caption="capacity">
      Capacity:
      <span data-availability-capacity>
        <span data-availability-spinner></span>
      </span>
    </span>
    <span data-availability-caption="remaining" class="hidden">
      (Remaining: <span data-availability-remaining></span>)
    </span>
    <span data-availability-caption="waitlist" class="hidden">
      (Waitlist: <span data-availability-waitlist></span>)
    </span>
    <span data-availability-caption="attendees" class="hidden">
      Attendees:
      <span data-availability-attendee-count>
        <span data-availability-spinner></span>
      </span>
    </span>
    <div data-availability-sold-out-ribbon class="hidden"></div>
  `;

  return {
    container: document.querySelector("[data-attendance-container]"),
    checker: document.querySelector('[data-attendance-role="attendance-checker"]'),
    loadingButton: document.querySelector('[data-attendance-role="loading-btn"]'),
    signinButton: document.querySelector('[data-attendance-role="signin-btn"]'),
    attendButton: document.querySelector('[data-attendance-role="attend-btn"]'),
    leaveButton: document.querySelector('[data-attendance-role="leave-btn"]'),
    refundButton: document.querySelector('[data-attendance-role="refund-btn"]'),
    refundRejectionReason: document.querySelector('[data-attendance-role="refund-rejection-reason"]'),
    questionsModal: document.querySelector('[data-attendance-role="registration-modal"]'),
    meetingDetails: Array.from(document.querySelectorAll("[data-meeting-details]")),
    alwaysJoinLink: document.querySelector("[data-join-link-always]"),
    liveJoinLink: document.querySelector("[data-join-link]"),
    menuJoinLink: document.querySelector("[data-join-link-menu]"),
    availabilityCaptions: {
      capacity: document.querySelector('[data-availability-caption="capacity"]'),
      attendees: document.querySelector('[data-availability-caption="attendees"]'),
      remaining: document.querySelector('[data-availability-caption="remaining"]'),
      waitlist: document.querySelector('[data-availability-caption="waitlist"]'),
    },
    availabilityAttendeeCount: document.querySelector("[data-availability-attendee-count]"),
    availabilityCapacity: document.querySelector("[data-availability-capacity]"),
    soldOutRibbon: document.querySelector("[data-availability-sold-out-ribbon]"),
  };
};

describe("event attendance", () => {
  const env = useDashboardTestEnv({
    path: "/events/test-event",
    withHtmx: true,
    withScroll: true,
    withSwal: true,
    bodyDatasetKeysToClear: ["attendanceListenersReady"],
  });

  it("shows attendee controls and meeting details after a successful attendance check", () => {
    // Keep references to the fixture controls under assertion.
    const { checker, leaveButton, alwaysJoinLink, liveJoinLink, meetingDetails } = renderAttendanceDom({
      attendeeMeetingAccessOpen: "true",
    });

    // Dispatch the HTMX after-request event.
    dispatchHtmxAfterRequest(checker, {
      responseText: JSON.stringify({ status: "attendee" }),
    });

    // Confirm a successful attendance check reveals attendee-only controls.
    expect(leaveButton.classList.contains("hidden")).to.equal(false);
    expect(leaveButton.querySelector("[data-attendance-label]")?.textContent).to.equal("Cancel attendance");
    expect(leaveButton.querySelector("[data-attendance-icon]")?.classList.contains("icon-cancel")).to.equal(
      true,
    );
    expect(alwaysJoinLink.classList.contains("hidden")).to.equal(false);
    expect(liveJoinLink.classList.contains("hidden")).to.equal(false);
    expect(liveJoinLink.classList.contains("xl:flex")).to.equal(true);
    expect(meetingDetails[0].classList.contains("hidden")).to.equal(false);
    expect(meetingDetails[1].classList.contains("hidden")).to.equal(false);
  });

  it("shows the join meeting link when attendee meeting access is open", () => {
    // Read controls for the attendee meeting-access state.
    const { checker, alwaysJoinLink, liveJoinLink, menuJoinLink, meetingDetails } = renderAttendanceDom({
      attendeeMeetingAccessOpen: "true",
    });

    // Dispatch the HTMX after-request event.
    dispatchHtmxAfterRequest(checker, {
      responseText: JSON.stringify({ status: "attendee" }),
    });

    // Verify shows the join meeting link when attendee meeting access is open.
    expect(alwaysJoinLink.classList.contains("hidden")).to.equal(false);
    expect(liveJoinLink.classList.contains("hidden")).to.equal(false);
    expect(liveJoinLink.classList.contains("xl:flex")).to.equal(true);
    expect(menuJoinLink.classList.contains("hidden")).to.equal(false);
    expect(menuJoinLink.classList.contains("max-xl:flex")).to.equal(true);
    expect(meetingDetails[0].classList.contains("hidden")).to.equal(false);
  });

  it("allows manually invited users to complete registration questions after the window closes", () => {
    // Render an event after the public registration window closed.
    const { attendButton, container } = renderAttendanceDom({
      registrationWindowOpen: "false",
      registrationWindowUnavailableTitle: "Registration closed May 1, 2099.",
    });
    const meta = getAttendanceMeta(container);

    // Non-manual pending registrations are blocked by the closed window.
    showRegistrationQuestionsPendingState(container, meta, {
      manually_invited: false,
    });
    expect(attendButton.disabled).to.equal(true);
    expect(attendButton.title).to.equal("Registration closed May 1, 2099.");

    // Organizer-created invitations can still answer the required questions.
    showRegistrationQuestionsPendingState(container, meta, {
      manually_invited: true,
    });
    expect(attendButton.disabled).to.equal(false);
    expect(attendButton.hasAttribute("title")).to.equal(false);
  });

  it("handles attendance clicks after the page body is swapped", () => {
    // Prepare replacement body for handling attendance clicks after the page body.
    const replacementBody = document.createElement("body");
    document.documentElement.replaceChild(replacementBody, document.body);
    const { signinButton } = renderAttendanceDom();

    // Attendance clicks still work after the page body is swapped.
    signinButton.click();

    // Verify attendance clicks work after the page body is swapped.
    expect(env.current.swal.calls[0].icon).to.equal("info");
    expect(env.current.swal.calls[0].html).to.include("/log-in?next_url=%2Fevents%2Ftest-event");
  });

  it("keeps the join meeting link hidden when the event is canceled", () => {
    // Read controls for canceled meeting-access state.
    const { checker, alwaysJoinLink, liveJoinLink, menuJoinLink, meetingDetails } = renderAttendanceDom({
      attendeeMeetingAccessOpen: "true",
      canceled: "true",
    });

    // Dispatch the HTMX after-request event.
    dispatchHtmxAfterRequest(checker, {
      responseText: JSON.stringify({ status: "attendee" }),
    });

    // Verify keeps the join meeting link hidden when the event is canceled.
    expect(alwaysJoinLink.classList.contains("hidden")).to.equal(true);
    expect(liveJoinLink.classList.contains("hidden")).to.equal(true);
    expect(liveJoinLink.classList.contains("xl:flex")).to.equal(false);
    expect(menuJoinLink.classList.contains("hidden")).to.equal(true);
    expect(menuJoinLink.classList.contains("max-xl:flex")).to.equal(false);
    expect(meetingDetails[0].classList.contains("hidden")).to.equal(true);
  });

  it("keeps the join meeting link hidden before attendee meeting access opens", () => {
    // Read controls for meeting access before it opens.
    const { checker, alwaysJoinLink, liveJoinLink, menuJoinLink, meetingDetails } = renderAttendanceDom({
      attendeeMeetingAccessOpen: "false",
    });

    // Dispatch the HTMX after-request event.
    dispatchHtmxAfterRequest(checker, {
      responseText: JSON.stringify({ status: "attendee" }),
    });

    // Verify keeps the join meeting link hidden before attendee meeting access opens.
    expect(alwaysJoinLink.classList.contains("hidden")).to.equal(true);
    expect(liveJoinLink.classList.contains("hidden")).to.equal(true);
    expect(liveJoinLink.classList.contains("xl:flex")).to.equal(false);
    expect(menuJoinLink.classList.contains("hidden")).to.equal(true);
    expect(menuJoinLink.classList.contains("max-xl:flex")).to.equal(false);
    expect(meetingDetails[0].classList.contains("hidden")).to.equal(true);
  });

  it("falls back to the waitlist sign-in state when the check response cannot be parsed", () => {
    // Keep references to the fixture controls under assertion.
    const { checker, signinButton, attendButton, leaveButton } = renderAttendanceDom({
      capacity: "10",
      remainingCapacity: "0",
      waitlistEnabled: "true",
    });

    // Dispatch the HTMX after-request event.
    dispatchHtmxAfterRequest(checker, {
      responseText: "{invalid json}",
    });

    // Confirm an unparseable response falls back to the waitlist sign-in state.
    expect(signinButton.classList.contains("hidden")).to.equal(false);
    expect(signinButton.querySelector("[data-attendance-label]")?.textContent).to.equal("Join waiting list");
    expect(attendButton.classList.contains("hidden")).to.equal(true);
    expect(leaveButton.classList.contains("hidden")).to.equal(true);
  });

  it("joins the simple RSVP waitlist when only private capacity remains", () => {
    // Render aggregate capacity with a sold-out sole public RSVP tier
    const { checker, container, attendButton } = renderAttendanceDom({
      capacity: "2",
      remainingCapacity: "1",
      waitlistEnabled: "true",
    });
    container.dataset.hasSoldOutTicketTypes = "true";
    container.dataset.ticketPurchaseAvailable = "false";

    // Apply the authenticated guest state
    dispatchHtmxAfterRequest(checker, {
      responseText: JSON.stringify({ status: "guest" }),
    });

    // Check the public tier controls the simple RSVP action
    expect(attendButton.classList.contains("hidden")).to.equal(false);
    expect(attendButton.disabled).to.equal(false);
    expect(attendButton.querySelector("[data-attendance-label]")?.textContent).to.equal("Join waiting list");
  });

  it("uses the request invitation icon for approval-required sign-in state", () => {
    // Render the attendance fixture.
    const { checker, signinButton } = renderAttendanceDom({
      attendeeApprovalRequired: "true",
    });

    // Dispatch the HTMX after-request event.
    dispatchHtmxAfterRequest(checker, {
      responseText: "{invalid json}",
    });

    // Verify uses the request invitation icon for approval-required sign-in state.
    expect(signinButton.querySelector("[data-attendance-label]")?.textContent).to.equal("Request invitation");
    expect(
      signinButton.querySelector("[data-attendance-icon]")?.classList.contains("icon-request-invitation"),
    ).to.equal(true);
    expect(
      signinButton.querySelector("[data-attendance-icon]")?.classList.contains("icon-user-plus"),
    ).to.equal(false);
  });

  it("keeps sign-in available after the registration window closes", () => {
    // Render a signed-out fixture after the public registration window closed.
    const { attendButton, container, signinButton } = renderAttendanceDom({
      registrationWindowOpen: "false",
      registrationWindowUnavailableTitle: "Registration closed May 1, 2099.",
    });

    // Apply the signed-out state before the user-specific attendance check can run.
    showSignedOutAttendanceState(container, getAttendanceMeta(container));

    // Anonymous users may need to sign in before manual invitation status is known.
    expect(signinButton.classList.contains("hidden")).to.equal(false);
    expect(signinButton.disabled).to.equal(false);
    expect(signinButton.hasAttribute("title")).to.equal(false);
    expect(signinButton.querySelector("[data-attendance-label]")?.textContent).to.equal("Attend event");
    expect(attendButton.classList.contains("hidden")).to.equal(true);
  });

  it("keeps no-capacity events behind sign-in when signed out", () => {
    // Render the signed-out fixture for a no-capacity event.
    const { attendButton, container, signinButton } = renderAttendanceDom({
      capacity: "0",
      remainingCapacity: "0",
    });

    // Apply the signed-out state using the no-capacity event metadata.
    showSignedOutAttendanceState(container, getAttendanceMeta(container));

    // Verify keeps no-capacity events behind sign-in when signed out.
    expect(signinButton.classList.contains("hidden")).to.equal(false);
    expect(signinButton.querySelector("[data-attendance-label]")?.textContent).to.equal("Attend event");
    expect(attendButton.classList.contains("hidden")).to.equal(true);
  });

  it("keeps approval-required no-capacity events behind sign-in when signed out", () => {
    // Render the attendance fixture.
    const { attendButton, container, signinButton } = renderAttendanceDom({
      attendeeApprovalRequired: "true",
      capacity: "0",
      remainingCapacity: "0",
    });

    // Verify keeps approval-required no-capacity events behind.
    showSignedOutAttendanceState(container, getAttendanceMeta(container));

    // Confirm approval-required no-capacity events stay behind sign-in.
    expect(signinButton.classList.contains("hidden")).to.equal(false);
    expect(signinButton.querySelector("[data-attendance-label]")?.textContent).to.equal("Request invitation");
    expect(attendButton.classList.contains("hidden")).to.equal(true);
  });

  it("shows loading state before attending and emits a waitlist success message", () => {
    // Render the attendance fixture.
    const { attendButton, loadingButton } = renderAttendanceDom();
    let changedEvents = 0;
    document.body.addEventListener("attendance-changed", () => {
      changedEvents += 1;
    });

    // Dispatch the HTMX before-request event.
    const beforeRequestEvent = dispatchHtmxBeforeRequest(attendButton, {}, { cancelable: true });

    // Verify shows loading state before attending and emits a waitlist success.
    expect(beforeRequestEvent.defaultPrevented).to.equal(false);
    expect(attendButton.classList.contains("hidden")).to.equal(true);
    expect(loadingButton.classList.contains("hidden")).to.equal(false);
    expect(loadingButton.getAttribute("role")).to.equal("status");
    expect(loadingButton.getAttribute("aria-live")).to.equal("polite");

    // Dispatch the HTMX after-request event.
    dispatchHtmxAfterRequest(attendButton, {
      responseText: JSON.stringify({ status: "waitlisted" }),
    });

    // Verify shows loading state before attending and emits a waitlist success.
    expect(changedEvents).to.equal(1);
    expect(env.current.swal.calls.at(-1)).to.include({
      text: "You have joined the waiting list for this event.",
      icon: "info",
    });
  });

  it("blocks the attend request until registration questions are answered", () => {
    // Render attendance controls with registration questions.
    const { attendButton, container, loadingButton, questionsModal } = renderAttendanceDom({
      includeRegistrationQuestions: true,
    });

    // Expose the attend button before dispatching the event.
    attendButton.classList.remove("hidden");
    const event = dispatchHtmxBeforeRequest(attendButton, {}, { cancelable: true });

    // Verify blocks the attend request until registration questions are answered.
    expect(event.defaultPrevented).to.equal(true);
    expect(container.dataset.questionsContinueAction).to.equal("attend");
    expect(questionsModal.classList.contains("hidden")).to.equal(false);
    expect(attendButton.classList.contains("hidden")).to.equal(false);
    expect(loadingButton.classList.contains("hidden")).to.equal(true);
  });

  it("allows answered registration question requests to continue", () => {
    // Render attendance controls with registration questions.
    const { attendButton, container, loadingButton, questionsModal } = renderAttendanceDom({
      includeRegistrationQuestions: true,
    });
    const registrationAnswer = questionsModal.querySelector("[data-question-answer]");
    const registrationForm = questionsModal.querySelector('[data-attendance-role="registration-form"]');

    // First request opens the questions modal instead of submitting.
    attendButton.classList.remove("hidden");
    const blockedEvent = dispatchHtmxBeforeRequest(attendButton, {}, { cancelable: true });
    expect(blockedEvent.defaultPrevented).to.equal(true);

    // Submit valid answers through the same modal flow used by the page.
    registrationAnswer.value = "Vegetarian lunch";
    registrationForm.dispatchEvent(new Event("submit", { bubbles: true, cancelable: true }));

    // The resumed attend request is no longer blocked by question gating.
    const resumedEvent = dispatchHtmxBeforeRequest(attendButton, {}, { cancelable: true });
    expect(resumedEvent.defaultPrevented).to.equal(false);
    expect(container.dataset.questionsContinueAction).to.equal(undefined);
    expect(attendButton.classList.contains("hidden")).to.equal(true);
    expect(loadingButton.classList.contains("hidden")).to.equal(false);
  });

  it("combines attendance success with the profile completion prompt", () => {
    // Render an opted-in attendance action for an incomplete profile.
    const { attendButton, container } = renderAttendanceDom();
    container.dataset.profileComplete = "false";
    env.current.swal.setNextResult({ isConfirmed: false });

    // Dispatch a successful attend response.
    dispatchHtmxAfterRequest(attendButton, {
      responseText: JSON.stringify({ status: "attendee" }),
    });

    // Verify the success message is shown inside the profile completion prompt.
    expect(env.current.swal.calls.at(-1)).to.include({
      title: "You have successfully registered for this event.",
      confirmButtonText: "Complete profile",
      cancelButtonText: "Maybe later",
    });
  });

  it("allows waitlist joins before registration questions are answered", () => {
    // Render full-event attendance controls with waitlist enabled.
    const { attendButton, container, loadingButton, questionsModal } = renderAttendanceDom({
      capacity: "10",
      includeRegistrationQuestions: true,
      remainingCapacity: "0",
      waitlistEnabled: "true",
    });
    const event = new CustomEvent("htmx:beforeRequest", {
      bubbles: true,
      cancelable: true,
    });
    container.dataset.hasSoldOutTicketTypes = "true";

    // Expose the attend button before dispatching the event.
    attendButton.classList.remove("hidden");
    attendButton.click();

    // Verify allows waitlist joins before registration questions are answered.
    expect(questionsModal.classList.contains("hidden")).to.equal(true);
    expect(attendButton.classList.contains("hidden")).to.equal(false);

    // Dispatch the form event.
    attendButton.dispatchEvent(event);

    // Assert whether the event was prevented.
    expect(event.defaultPrevented).to.equal(false);
    expect(questionsModal.classList.contains("hidden")).to.equal(true);
    expect(attendButton.classList.contains("hidden")).to.equal(true);
    expect(loadingButton.classList.contains("hidden")).to.equal(false);
  });

  it("reopens questions when a simple waitlist ticket becomes available", () => {
    // Render a simple sold-out flow that initially defers registration questions.
    const { attendButton, container, loadingButton, questionsModal } = renderAttendanceDom({
      includeRegistrationQuestions: true,
      remainingCapacity: "0",
      waitlistEnabled: "true",
    });
    container.dataset.hasSoldOutTicketTypes = "true";
    container.dataset.ticketPurchaseAvailable = "false";
    attendButton.classList.remove("hidden");

    // Submit the waitlist action and receive authoritative seat availability.
    dispatchHtmxBeforeRequest(attendButton);
    dispatchHtmxAfterRequest(attendButton, {
      status: 409,
      responseText: JSON.stringify({
        conflict: "registration-answers-required",
      }),
    });

    // Restore the action and collect answers before retrying it.
    expect(container.dataset.questionsContinueAction).to.equal("attend");
    expect(questionsModal.classList.contains("hidden")).to.equal(false);
    expect(attendButton.classList.contains("hidden")).to.equal(false);
    expect(loadingButton.classList.contains("hidden")).to.equal(true);
    expect(env.current.swal.calls).to.have.length(0);
  });

  it("shows invitation guidance when attendance requires a pending offer", () => {
    // Render simple attendance controls before submitting the attend action.
    const { attendButton, loadingButton } = renderAttendanceDom();

    // Submit the attend action and return the admission offer conflict.
    dispatchHtmxBeforeRequest(attendButton);
    dispatchHtmxAfterRequest(attendButton, {
      status: 409,
      responseText: JSON.stringify({ conflict: "admission-offer-required" }),
    });

    // Restore the action and point the attendee to their pending invitation.
    expect(attendButton.classList.contains("hidden")).to.equal(false);
    expect(loadingButton.classList.contains("hidden")).to.equal(true);
    expect(env.current.swal.calls.at(-1)).to.include({
      icon: "error",
      text: "You have a pending invitation for this event. Please claim it from the Event Invitations section in your dashboard to register.",
    });
  });

  it("defers mixed-tier waitlist questions until an offer is claimed", () => {
    // Render ticketed controls where one tier remains purchasable.
    const { attendButton, container, questionsModal } = renderAttendanceDom({
      includeRegistrationQuestions: true,
      waitlistEnabled: "true",
    });
    container.dataset.hasSoldOutTicketTypes = "true";
    container.dataset.hasVisibleTicketTypes = "true";
    container.dataset.isSimpleRsvp = "false";
    container.dataset.ticketPurchaseAvailable = "true";
    container.insertAdjacentHTML(
      "beforeend",
      `
        <div id="ticket-modal" data-attendance-role="ticket-modal" class="hidden">
          <form
            data-attendance-role="checkout-form"
            data-attend-url="/attend"
            data-checkout-url="/checkout"
          >
            <input
              data-attendance-role="ticket-type-option"
              data-ticket-sold-out="true"
              name="event_ticket_type_id"
              type="radio"
              value="sold-out-tier"
              checked
            >
            <input
              data-attendance-role="checkout-registration-answers-input"
              name="registration_answers"
              value='{"answers":[{"question_id":"question-1","value":"early"}]}'
            >
          </form>
        </div>
      `,
    );
    const ticketModal = container.querySelector('[data-attendance-role="ticket-modal"]');
    const checkoutForm = container.querySelector('[data-attendance-role="checkout-form"]');

    // Choosing a tier comes before collecting registration answers.
    attendButton.classList.remove("hidden");
    attendButton.click();
    expect(ticketModal.classList.contains("hidden")).to.equal(false);
    expect(questionsModal.classList.contains("hidden")).to.equal(true);

    // Joining the sold-out tier does not open questions or submit stale answers.
    const parameters = {
      event_ticket_type_id: "sold-out-tier",
      registration_answers: '{"answers":[{"question_id":"question-1","value":"early"}]}',
    };
    const event = new CustomEvent("htmx:configRequest", {
      bubbles: true,
      detail: {
        parameters,
        path: "/checkout",
        unfilteredParameters: { ...parameters },
      },
    });
    checkoutForm.dispatchEvent(event);
    expect(event.detail.path).to.equal("/attend");
    expect(parameters).to.not.have.property("registration_answers");
    expect(questionsModal.classList.contains("hidden")).to.equal(true);
  });

  it("omits a disabled discount when claiming an intrinsically free tier", () => {
    // Prepare a free-tier checkout with a stale discount from a prior selection.
    const { container } = renderAttendanceDom();
    container.insertAdjacentHTML(
      "beforeend",
      `
        <form
          data-attendance-role="checkout-form"
          data-attend-url="/attend"
          data-checkout-url="/checkout"
        >
          <input
            data-attendance-role="ticket-type-option"
            data-ticket-sold-out="false"
            name="event_ticket_type_id"
            type="radio"
            value="free-tier"
            checked
          >
          <input data-attendance-role="discount-code-input" value="SAVE" disabled>
        </form>
      `,
    );
    const checkoutForm = container.querySelector('[data-attendance-role="checkout-form"]');
    const parameters = {
      discount_code: "SAVE",
      event_ticket_type_id: "free-tier",
    };

    // Disabled discount fields are omitted from both HTMX parameter collections.
    const event = new CustomEvent("htmx:configRequest", {
      bubbles: true,
      detail: {
        parameters,
        path: "/checkout",
        unfilteredParameters: { ...parameters },
      },
    });
    checkoutForm.dispatchEvent(event);
    expect(parameters).to.not.have.property("discount_code");
    expect(event.detail.unfilteredParameters).to.not.have.property("discount_code");
  });

  it("opens registration questions for promoted waitlist attendees", () => {
    // Render waitlist controls with registration questions.
    const { attendButton, checker, container, loadingButton, questionsModal } = renderAttendanceDom({
      capacity: "10",
      includeRegistrationQuestions: true,
      remainingCapacity: "0",
      waitlistEnabled: "true",
    });

    // Apply the promoted waitlist state from the attendance check.
    dispatchHtmxAfterRequest(checker, {
      responseText: JSON.stringify({
        status: "registration-questions-pending",
      }),
    });

    // Verify opens registration questions for promoted waitlist attendees.
    expect(attendButton.classList.contains("hidden")).to.equal(false);
    expect(attendButton.querySelector("[data-attendance-label]")?.textContent).to.equal(
      "Complete registration",
    );
    expect(
      attendButton.querySelector("[data-attendance-icon]")?.classList.contains("icon-list-check"),
    ).to.equal(true);

    // Click the attend button.
    attendButton.click();

    // Assert the stored follow-up action.
    expect(container.dataset.questionsContinueAction).to.equal("attend");
    expect(questionsModal.classList.contains("hidden")).to.equal(false);
    expect(attendButton.classList.contains("hidden")).to.equal(false);
    expect(loadingButton.classList.contains("hidden")).to.equal(true);
  });

  it("blocks promoted waitlist completion until registration questions are answered", () => {
    // Render waitlist controls before the attendee is promoted.
    const { attendButton, checker, questionsModal } = renderAttendanceDom({
      capacity: "10",
      includeRegistrationQuestions: true,
      remainingCapacity: "0",
      waitlistEnabled: "true",
    });
    const event = new CustomEvent("htmx:beforeRequest", {
      bubbles: true,
      cancelable: true,
    });

    dispatchHtmxAfterRequest(checker, {
      responseText: JSON.stringify({
        status: "registration-questions-pending",
      }),
    });
    attendButton.dispatchEvent(event);

    // Assert whether the event was prevented.
    expect(event.defaultPrevented).to.equal(true);
    expect(questionsModal.classList.contains("hidden")).to.equal(false);
  });

  it("completes ticketed pending questions without reopening ticket selection", () => {
    // Render a ticketed promoted-attendee state with required questions.
    const { attendButton, checker, container, loadingButton, questionsModal } = renderAttendanceDom({
      includeRegistrationQuestions: true,
    });
    container.dataset.hasVisibleTicketTypes = "true";
    container.dataset.isSimpleRsvp = "false";
    container.insertAdjacentHTML(
      "beforeend",
      `
        <div id="ticket-modal" data-attendance-role="ticket-modal" class="hidden">
          <input data-attendance-role="ticket-type-option" type="radio" value="ticket-1" />
        </div>
      `,
    );
    const ticketModal = container.querySelector('[data-attendance-role="ticket-modal"]');
    const registrationAnswer = questionsModal.querySelector("[data-question-answer]");
    const registrationForm = questionsModal.querySelector('[data-attendance-role="registration-form"]');

    dispatchHtmxAfterRequest(checker, {
      responseText: JSON.stringify({
        status: "registration-questions-pending",
      }),
    });
    const unansweredEvent = dispatchHtmxBeforeRequest(attendButton, {}, { cancelable: true });
    expect(unansweredEvent.defaultPrevented).to.equal(true);
    attendButton.click();
    registrationAnswer.value = "Vegetarian lunch";
    registrationForm.dispatchEvent(new Event("submit", { bubbles: true, cancelable: true }));

    // Valid answers resume the attendance request without looping through ticket choice.
    expect(questionsModal.classList.contains("hidden")).to.equal(true);
    expect(ticketModal.classList.contains("hidden")).to.equal(true);
    const resumedEvent = dispatchHtmxBeforeRequest(attendButton, {}, { cancelable: true });
    expect(resumedEvent.defaultPrevented).to.equal(false);
    expect(attendButton.classList.contains("hidden")).to.equal(true);
    expect(loadingButton.classList.contains("hidden")).to.equal(false);
  });

  it("shows sign-in info for waitlists and confirms leaving the waitlist", async () => {
    // Render the attendance fixture.
    const { signinButton, leaveButton } = renderAttendanceDom();

    // Keep a reference to the attendance label element.
    signinButton.querySelector("[data-attendance-label]").textContent = "Join waiting list";
    signinButton.click();

    // Verify shows sign-in info for waitlists and confirms leaving the waitlist.
    expect(env.current.swal.calls[0].icon).to.equal("info");
    expect(env.current.swal.calls[0].html).to.include("join the waiting list");
    expect(env.current.swal.calls[0].html).to.include("/log-in?next_url=%2Fevents%2Ftest-event");

    // Keep a reference to the attendance label element.
    leaveButton.querySelector("[data-attendance-label]").textContent = "Leave waiting list";
    env.current.swal.setNextResult({ isConfirmed: true });
    leaveButton.click();
    await waitForMicrotask();

    // Verify shows sign-in info for waitlists and confirms leaving the waitlist.
    expect(env.current.swal.calls[1]).to.include({
      text: "Are you sure you want to leave the waiting list?",
      icon: "warning",
    });
    expect(env.current.htmx.triggerCalls).to.deep.equal([["#leave-btn", "confirmed"]]);
  });

  it("escapes the sign-in return path in attendance alerts", () => {
    // Render the attendance fixture with a path that has query delimiters.
    const { signinButton } = renderAttendanceDom();
    signinButton.dataset.path = "/events/test-event?ticket=early&ref=home";

    // Open the attendance sign-in alert.
    signinButton.click();

    // The sign-in link keeps the full return path inside the next_url value.
    expect(env.current.swal.calls[0].html).to.include(
      "/log-in?next_url=%2Fevents%2Ftest-event%3Fticket%3Dearly%26ref%3Dhome",
    );
  });

  it("confirms canceling a pending invitation request with request-specific copy", async () => {
    // Render the attendance fixture.
    const { leaveButton } = renderAttendanceDom();

    // Keep a reference to the attendance label element.
    leaveButton.querySelector("[data-attendance-label]").textContent = "Request pending";
    leaveButton.setAttribute("aria-label", "Request pending – cancel request");
    env.current.swal.setNextResult({ isConfirmed: true });
    leaveButton.click();
    await waitForMicrotask();

    // Verify confirms canceling a pending invitation request with request-specific.
    expect(env.current.swal.calls[0]).to.include({
      text: "Are you sure you want to cancel your invitation request?",
      icon: "warning",
    });
    expect(env.current.htmx.triggerCalls).to.deep.equal([["#leave-btn", "confirmed"]]);
  });

  it("uses cancel icons for waitlist and pending invitation cancellation", () => {
    // Render the attendance fixture.
    const { checker, leaveButton } = renderAttendanceDom();

    // Dispatch the HTMX after-request event.
    dispatchHtmxAfterRequest(checker, {
      responseText: JSON.stringify({ status: "waitlisted" }),
    });

    // Verify uses cancel icons for waitlist and pending invitation cancellation.
    expect(leaveButton.querySelector("[data-attendance-label]")?.textContent).to.equal("Leave waiting list");
    expect(leaveButton.hasAttribute("aria-label")).to.equal(false);
    expect(leaveButton.querySelector("[data-attendance-icon]")?.classList.contains("icon-cancel")).to.equal(
      true,
    );

    // Dispatch the HTMX after-request event.
    dispatchHtmxAfterRequest(checker, {
      responseText: JSON.stringify({ status: "pending-approval" }),
    });

    // Verify uses cancel icons for waitlist and pending invitation cancellation.
    expect(leaveButton.querySelector("[data-attendance-label]")?.textContent).to.equal("Request pending");
    expect(leaveButton.getAttribute("aria-label")).to.equal("Request pending – cancel request");
    expect(leaveButton.querySelector("[data-attendance-icon]")?.classList.contains("icon-cancel")).to.equal(
      true,
    );
  });

  it("disables attendance changes for past events", () => {
    // Render the attendance fixture.
    const { checker, attendButton } = renderAttendanceDom({
      starts: "2000-05-10T10:00:00Z",
      capacity: "10",
      remainingCapacity: "5",
    });

    // Dispatch the HTMX after-request event.
    dispatchHtmxAfterRequest(checker, {
      responseText: JSON.stringify({ status: "guest" }),
    });

    // Verify disables attendance changes for past events.
    expect(attendButton.classList.contains("hidden")).to.equal(false);
    expect(attendButton.disabled).to.equal(true);
    expect(attendButton.title).to.equal(
      "You cannot change attendance because the event has already started.",
    );
  });

  it("uses the request invitation icon for approval-required guest state", () => {
    // Render the attendance fixture.
    const { checker, attendButton } = renderAttendanceDom({
      attendeeApprovalRequired: "true",
    });

    // Dispatch the HTMX after-request event.
    dispatchHtmxAfterRequest(checker, {
      responseText: JSON.stringify({ status: "guest" }),
    });

    // Verify uses the request invitation icon for approval-required guest state.
    expect(attendButton.querySelector("[data-attendance-label]")?.textContent).to.equal("Request invitation");
    expect(
      attendButton.querySelector("[data-attendance-icon]")?.classList.contains("icon-request-invitation"),
    ).to.equal(true);
    expect(
      attendButton.querySelector("[data-attendance-icon]")?.classList.contains("icon-user-plus"),
    ).to.equal(false);
  });

  it("disables approved invitation rejoin when the event is sold out", () => {
    // Render the attendance fixture.
    const { checker, attendButton } = renderAttendanceDom({
      attendeeApprovalRequired: "true",
      capacity: "10",
      remainingCapacity: "0",
    });

    // Dispatch the HTMX after-request event.
    dispatchHtmxAfterRequest(checker, {
      responseText: JSON.stringify({ status: "invitation-approved" }),
    });

    // Verify disables approved invitation rejoin when the event is sold out.
    expect(attendButton.classList.contains("hidden")).to.equal(false);
    expect(attendButton.disabled).to.equal(true);
    expect(attendButton.title).to.equal("This event is sold out.");
    expect(attendButton.querySelector("[data-attendance-label]")?.textContent).to.equal("Attend event");
    expect(
      attendButton.querySelector("[data-attendance-icon]")?.classList.contains("icon-user-plus"),
    ).to.equal(true);
  });

  it("routes owned ticket offers to the dashboard claim surface", () => {
    // Render a ticketed attendance control for an owned pending offer.
    const { attendButton, checker } = renderAttendanceDom({
      isSimpleRsvp: "false",
    });

    // Apply the owned ticket offer returned by the attendance endpoint.
    dispatchHtmxAfterRequest(checker, {
      responseText: JSON.stringify({
        admission_offer_id: "offer-1",
        event_ticket_type_id: "ticket-1",
        status: "invitation-approved",
      }),
    });

    // The event page identifies the claim action without describing the user as an attendee.
    expect(attendButton.querySelector("[data-attendance-label]")?.textContent).to.equal("Claim ticket");
    expect(attendButton.dataset.resumeUrl).to.equal("/dashboard/user?tab=invitations#event-offer-offer-1");
    expect(dispatchHtmxBeforeRequest(attendButton, {}, { cancelable: true }).defaultPrevented).to.equal(true);
  });

  it("clears a cached offer action when the offer is no longer claimable", () => {
    // Render an owned offer before the server hides it during refund processing.
    const { attendButton, checker } = renderAttendanceDom();
    dispatchHtmxAfterRequest(checker, {
      responseText: JSON.stringify({
        admission_offer_id: "offer-1",
        event_ticket_type_id: "ticket-1",
        status: "invitation-approved",
      }),
    });
    expect(attendButton.dataset.resumeUrl).to.equal("/dashboard/user?tab=invitations#event-offer-offer-1");

    // A non-claimable response restores the normal event action without a stale link.
    dispatchHtmxAfterRequest(checker, {
      responseText: JSON.stringify({ status: "none" }),
    });
    expect(attendButton.querySelector("[data-attendance-label]")?.textContent).to.equal("Attend event");
    expect(attendButton.hasAttribute("data-resume-url")).to.equal(false);
    expect(dispatchHtmxBeforeRequest(attendButton, {}, { cancelable: true }).defaultPrevented).to.equal(
      false,
    );
  });

  it("routes owned simple RSVP offers with questions to the dashboard claim surface", () => {
    // Render simple RSVP controls with registration questions.
    const { attendButton, checker, questionsModal } = renderAttendanceDom({
      includeRegistrationQuestions: true,
    });

    // Apply an organizer offer that still needs claim-time answers.
    dispatchHtmxAfterRequest(checker, {
      responseText: JSON.stringify({
        admission_offer_id: "offer-2",
        event_ticket_type_id: "ticket-1",
        status: "registration-questions-pending",
      }),
    });

    // The dashboard owns offer acceptance and its registration question flow.
    expect(attendButton.querySelector("[data-attendance-label]")?.textContent).to.equal("Confirm RSVP");
    expect(attendButton.dataset.resumeUrl).to.equal("/dashboard/user?tab=invitations#event-offer-offer-2");
    expect(questionsModal.classList.contains("hidden")).to.equal(true);
    expect(dispatchHtmxBeforeRequest(attendButton, {}, { cancelable: true }).defaultPrevented).to.equal(true);
  });

  it("shows an expired ticket offer as a disabled terminal state", () => {
    // Render the public event action before applying the terminal offer status.
    const { attendButton, checker } = renderAttendanceDom();

    // Apply the latest expired offer state from the attendance check.
    dispatchHtmxAfterRequest(checker, {
      responseText: JSON.stringify({
        status: "offer-expired",
      }),
    });

    // The user sees the exact terminal state and cannot retry the expired offer.
    expect(attendButton.querySelector("[data-attendance-label]")?.textContent).to.equal(
      "Ticket offer expired",
    );
    expect(attendButton.disabled).to.equal(true);
  });

  it("shows canceled state for approved invitations when a no-capacity event is canceled", () => {
    // Render the attendance fixture.
    const { checker, attendButton } = renderAttendanceDom({
      attendeeApprovalRequired: "true",
      canceled: "true",
      capacity: "0",
      remainingCapacity: "0",
    });

    // Dispatch the HTMX after-request event.
    dispatchHtmxAfterRequest(checker, {
      responseText: JSON.stringify({ status: "invitation-approved" }),
    });

    // Verify shows canceled state for approved invitations when a no-capacity event.
    expect(attendButton.classList.contains("hidden")).to.equal(false);
    expect(attendButton.disabled).to.equal(true);
    expect(attendButton.title).to.equal("This event has been canceled.");
    expect(attendButton.querySelector("[data-attendance-label]")?.textContent).to.equal("Attend event");
  });

  it("shows a sold-out attend button when no waitlist is available", () => {
    // Render the attendance fixture.
    const { checker, attendButton, signinButton } = renderAttendanceDom({
      capacity: "10",
      remainingCapacity: "0",
      waitlistEnabled: "false",
    });

    // Dispatch the HTMX after-request event.
    dispatchHtmxAfterRequest(checker, {
      responseText: JSON.stringify({ status: "guest" }),
    });

    // Verify shows a sold-out attend button when no waitlist is available.
    expect(attendButton.classList.contains("hidden")).to.equal(false);
    expect(attendButton.disabled).to.equal(true);
    expect(attendButton.title).to.equal("This event is sold out.");
    expect(signinButton.classList.contains("hidden")).to.equal(true);
  });

  it("shows a no-capacity attend button when event capacity is zero", () => {
    // Render the attendance fixture.
    const { checker, attendButton } = renderAttendanceDom({
      capacity: "0",
      remainingCapacity: "0",
      waitlistEnabled: "false",
    });

    // Dispatch the HTMX after-request event.
    dispatchHtmxAfterRequest(checker, {
      responseText: JSON.stringify({ status: "guest" }),
    });

    // Verify shows a no-capacity attend button when event capacity is zero.
    expect(attendButton.classList.contains("hidden")).to.equal(false);
    expect(attendButton.disabled).to.equal(true);
    expect(attendButton.title).to.equal("This event has no attendee capacity.");
  });

  it("allows zero-capacity events to use an enabled waitlist", () => {
    // Render a deliberately closed simple RSVP tier with a waitlist.
    const { checker, attendButton } = renderAttendanceDom({
      capacity: "0",
      remainingCapacity: "0",
      waitlistEnabled: "true",
    });

    // Apply the authenticated guest state.
    dispatchHtmxAfterRequest(checker, {
      responseText: JSON.stringify({ status: "guest" }),
    });

    // Verify the backend-supported waitlist action remains available.
    expect(attendButton.classList.contains("hidden")).to.equal(false);
    expect(attendButton.disabled).to.equal(false);
    expect(attendButton.title).to.equal("");
    expect(attendButton.querySelector("[data-attendance-label]")?.textContent).to.equal("Join waiting list");
  });

  it("allows approval requests when event capacity is zero", () => {
    // Render the attendance fixture.
    const { checker, attendButton } = renderAttendanceDom({
      attendeeApprovalRequired: "true",
      capacity: "0",
      remainingCapacity: "0",
    });

    // Dispatch the HTMX after-request event.
    dispatchHtmxAfterRequest(checker, {
      responseText: JSON.stringify({ status: "guest" }),
    });

    // Verify approval remains available before capacity allocation.
    expect(attendButton.classList.contains("hidden")).to.equal(false);
    expect(attendButton.disabled).to.equal(false);
    expect(attendButton.title).to.equal("");
    expect(attendButton.querySelector("[data-attendance-label]")?.textContent).to.equal("Request invitation");
  });

  it("clears the availability spinner when refreshed capacity is zero", async () => {
    // Render capacity availability with the initial server placeholder.
    const { availabilityCapacity } = renderAttendanceDom({
      availabilityUrl: "/events/test-event/availability",
    });
    // Mock refreshed availability for an event with no attendee capacity.
    const fetchMock = mockFetch({
      response: {
        ok: true,
        json: async () => ({
          attendee_approval_required: false,
          capacity: 0,
          canceled: false,
          has_sellable_ticket_types: false,
          is_live: false,
          is_past: false,
          is_simple_rsvp: true,
          remaining_capacity: 0,
          ticket_types: [],
          waitlist_count: 0,
          waitlist_enabled: false,
        }),
      },
    });

    try {
      // Initialize attendance behavior and wait for availability hydration.
      await initializeAttendanceDom();
      await waitForMicrotask();

      // Verify hydration replaces the spinner with the resolved zero capacity.
      expect(availabilityCapacity.textContent.trim()).to.equal("0");
      expect(availabilityCapacity.querySelector("[data-availability-spinner]")).to.equal(null);
    } finally {
      fetchMock.restore();
    }
  });

  it("shows remaining seats instead of waitlist while capacity is still available", async () => {
    // Render the attendance fixture.
    const { availabilityCapacity, availabilityCaptions } = renderAttendanceDom({
      availabilityUrl: "/events/test-event/availability",
    });
    const fetchMock = mockFetch({
      response: {
        ok: true,
        json: async () => ({
          attendee_approval_required: false,
          capacity: 2,
          canceled: false,
          has_sellable_ticket_types: false,
          is_live: false,
          is_past: false,
          is_simple_rsvp: true,
          remaining_capacity: 1,
          ticket_types: [],
          waitlist_count: 1,
          waitlist_enabled: true,
        }),
      },
    });

    // Verify shows remaining seats instead of waitlist.
    try {
      await initializeAttendanceDom();
      await waitForMicrotask();

      // Verify shows remaining seats instead of waitlist while capacity is still.
      expect(availabilityCaptions.attendees.classList.contains("hidden")).to.equal(true);
      expect(availabilityCaptions.capacity.classList.contains("hidden")).to.equal(false);
      expect(availabilityCapacity.textContent.trim()).to.equal("2");
      expect(availabilityCaptions.remaining.classList.contains("hidden")).to.equal(false);
      expect(availabilityCaptions.remaining.classList.contains("inline")).to.equal(true);
      expect(availabilityCaptions.remaining.textContent).to.include("1");
      expect(availabilityCaptions.waitlist.classList.contains("hidden")).to.equal(true);
      expect(availabilityCaptions.waitlist.classList.contains("inline")).to.equal(false);
      expect(availabilityCaptions.waitlist.textContent).to.not.include("1");
    } finally {
      fetchMock.restore();
    }
  });

  it("waits for refreshed availability before rendering attendance actions", async () => {
    // Render the attendance fixture.
    const { attendButton, checker } = renderAttendanceDom({
      availabilityUrl: "/events/test-event/availability",
    });
    let resolveAvailability;
    const availabilityResponse = new Promise((resolve) => {
      resolveAvailability = resolve;
    });
    const fetchMock = mockFetch({
      impl: async () => availabilityResponse,
    });

    // Verify waits for refreshed availability before rendering.
    try {
      await initializeAttendanceDom();

      // Dispatch the HTMX after-request event.
      dispatchHtmxAfterRequest(checker, {
        responseText: JSON.stringify({ status: "guest" }),
      });

      // Verify waits for refreshed availability before rendering attendance actions.
      expect(attendButton.classList.contains("hidden")).to.equal(true);

      // Verify waits for refreshed availability before rendering.
      resolveAvailability({
        ok: true,
        json: async () => ({
          attendee_approval_required: false,
          capacity: 2,
          canceled: false,
          has_sellable_ticket_types: false,
          is_live: false,
          is_past: false,
          is_simple_rsvp: true,
          remaining_capacity: 1,
          ticket_types: [],
          waitlist_count: 0,
          waitlist_enabled: false,
        }),
      });
      await waitForMicrotask();

      // Dispatch the HTMX after-request event.
      dispatchHtmxAfterRequest(checker, {
        responseText: JSON.stringify({ status: "guest" }),
      });

      // Verify waits for refreshed availability before rendering attendance actions.
      expect(attendButton.classList.contains("hidden")).to.equal(false);
    } finally {
      fetchMock.restore();
    }
  });

  it("falls back to cached attendance metadata when availability fails", async () => {
    // Render the attendance fixture.
    const { attendButton, checker, container } = renderAttendanceDom({
      availabilityUrl: "/events/test-event/availability",
    });
    const fetchMock = mockFetch({
      response: {
        ok: false,
      },
    });

    // Verify falls back to cached attendance metadata.
    try {
      await initializeAttendanceDom();
      await waitForMicrotask();

      // Assert the container state.
      expect(container.dataset.availabilityHydrated).to.equal("true");

      // Dispatch the HTMX after-request event.
      dispatchHtmxAfterRequest(checker, {
        responseText: JSON.stringify({ status: "guest" }),
      });

      // Assert the expected visibility state.
      expect(attendButton.classList.contains("hidden")).to.equal(false);
      expect(attendButton.disabled).to.equal(false);
      expect(env.current.swal.calls.at(-1)).to.include({
        icon: "error",
        text: "Something went wrong loading event availability. The page is showing the last available event details.",
      });
    } finally {
      fetchMock.restore();
    }
  });

  it("hydrates attendee meeting access from refreshed availability", async () => {
    // Render the attendance fixture.
    const { container } = renderAttendanceDom({
      availabilityUrl: "/events/test-event/availability",
      attendeeMeetingAccessOpen: "false",
    });
    let changedEvents = 0;
    document.body.addEventListener("attendance-changed", () => {
      changedEvents += 1;
    });
    const fetchMock = mockFetch({
      response: {
        ok: true,
        json: async () => ({
          attendee_approval_required: false,
          capacity: 2,
          canceled: false,
          has_sellable_ticket_types: false,
          is_live: true,
          is_past: false,
          is_simple_rsvp: true,
          remaining_capacity: 1,
          ticket_types: [],
          waitlist_count: 0,
          waitlist_enabled: false,
        }),
      },
    });

    // Verify hydrates attendee meeting access from refreshed.
    try {
      await initializeAttendanceDom();
      await waitForMicrotask();

      // Verify hydrates attendee meeting access from refreshed availability.
      expect(container.dataset.attendeeMeetingAccessOpen).to.equal("true");
      expect(changedEvents).to.equal(1);
    } finally {
      fetchMock.restore();
    }
  });

  it("shows waitlist count after refreshing availability", async () => {
    // Render the attendance fixture.
    const { availabilityCapacity, availabilityCaptions } = renderAttendanceDom({
      availabilityUrl: "/events/test-event/availability",
    });
    const fetchMock = mockFetch({
      response: {
        ok: true,
        json: async () => ({
          attendee_approval_required: false,
          capacity: 2,
          canceled: false,
          has_sellable_ticket_types: false,
          is_live: false,
          is_past: false,
          is_simple_rsvp: true,
          remaining_capacity: 0,
          ticket_types: [],
          waitlist_count: 3,
          waitlist_enabled: true,
        }),
      },
    });

    // Verify shows waitlist count after refreshing availability.
    try {
      await initializeAttendanceDom();
      await waitForMicrotask();

      // Assert the expected text is rendered.
      expect(availabilityCapacity.textContent.trim()).to.equal("2");
      expect(availabilityCaptions.waitlist.classList.contains("hidden")).to.equal(false);
      expect(availabilityCaptions.waitlist.classList.contains("inline")).to.equal(true);
      expect(availabilityCaptions.waitlist.textContent).to.include("3");
      expect(availabilityCaptions.remaining.classList.contains("hidden")).to.equal(true);
      expect(availabilityCaptions.remaining.classList.contains("inline")).to.equal(false);
      expect(availabilityCaptions.remaining.textContent).to.not.include("3");
    } finally {
      fetchMock.restore();
    }
  });

  it("shows attendee count when refreshed availability is unlimited", async () => {
    // Keep references to the fixture controls under assertion.
    const { availabilityAttendeeCount, availabilityCapacity, availabilityCaptions } = renderAttendanceDom({
      availabilityUrl: "/events/test-event/availability",
    });
    const fetchMock = mockFetch({
      response: {
        ok: true,
        json: async () => ({
          attendee_approval_required: false,
          attendee_count: 12,
          capacity: null,
          canceled: false,
          has_sellable_ticket_types: false,
          is_live: false,
          is_past: false,
          is_simple_rsvp: true,
          remaining_capacity: null,
          ticket_types: [],
          waitlist_count: 0,
          waitlist_enabled: false,
        }),
      },
    });

    // Verify shows attendee count when refreshed availability.
    try {
      await initializeAttendanceDom();
      await waitForMicrotask();

      // Verify shows attendee count when refreshed availability is unlimited.
      expect(availabilityCapacity.textContent.trim()).to.equal("");
      expect(availabilityAttendeeCount.textContent.trim()).to.equal("12");
      expect(availabilityCaptions.attendees.classList.contains("hidden")).to.equal(false);
      expect(availabilityCaptions.attendees.classList.contains("flex")).to.equal(true);
      expect(availabilityCaptions.capacity.classList.contains("hidden")).to.equal(true);
      expect(availabilityCaptions.remaining.classList.contains("hidden")).to.equal(true);
      expect(availabilityCaptions.waitlist.classList.contains("hidden")).to.equal(true);
    } finally {
      fetchMock.restore();
    }
  });

  it("hides attendee count when refreshed unlimited availability has no attendees", async () => {
    // Keep references to the fixture controls under assertion.
    const { availabilityAttendeeCount, availabilityCaptions } = renderAttendanceDom({
      availabilityUrl: "/events/test-event/availability",
    });
    const fetchMock = mockFetch({
      response: {
        ok: true,
        json: async () => ({
          attendee_approval_required: false,
          attendee_count: 0,
          capacity: null,
          canceled: false,
          has_sellable_ticket_types: false,
          is_live: false,
          is_past: false,
          is_simple_rsvp: true,
          remaining_capacity: null,
          ticket_types: [],
          waitlist_count: 0,
          waitlist_enabled: false,
        }),
      },
    });

    // Verify hides attendee count when refreshed unlimited.
    try {
      await initializeAttendanceDom();
      await waitForMicrotask();

      // Verify hides attendee count when refreshed unlimited availability has no.
      expect(availabilityAttendeeCount.textContent.trim()).to.equal("");
      expect(availabilityCaptions.attendees.classList.contains("hidden")).to.equal(true);
      expect(availabilityCaptions.attendees.classList.contains("flex")).to.equal(false);
    } finally {
      fetchMock.restore();
    }
  });

  it("keeps the sold-out ribbon hidden for canceled availability", async () => {
    // Render the attendance fixture.
    const { soldOutRibbon } = renderAttendanceDom({
      availabilityUrl: "/events/test-event/availability",
    });
    const fetchMock = mockFetch({
      response: {
        ok: true,
        json: async () => ({
          attendee_approval_required: false,
          capacity: 2,
          canceled: true,
          has_sellable_ticket_types: false,
          is_live: false,
          is_past: false,
          is_simple_rsvp: true,
          remaining_capacity: 0,
          ticket_types: [],
          waitlist_count: 0,
          waitlist_enabled: false,
        }),
      },
    });

    // Verify keeps the sold-out ribbon hidden for canceled.
    try {
      await initializeAttendanceDom();
      await waitForMicrotask();

      // Verify keeps the sold-out ribbon hidden for canceled availability.
      expect(soldOutRibbon.classList.contains("hidden")).to.equal(true);
    } finally {
      fetchMock.restore();
    }
  });

  it("disables attendance controls when cached event data is canceled", () => {
    // Render the attendance fixture.
    const { checker, attendButton, signinButton } = renderAttendanceDom({
      canceled: "true",
    });

    // Dispatch the HTMX after-request event.
    dispatchHtmxAfterRequest(checker, {
      responseText: JSON.stringify({ status: "guest" }),
    });

    // Verify disables attendance controls when cached event data is canceled.
    expect(attendButton.classList.contains("hidden")).to.equal(false);
    expect(attendButton.disabled).to.equal(true);
    expect(attendButton.title).to.equal("This event has been canceled.");
    expect(signinButton.classList.contains("hidden")).to.equal(true);
  });

  it("allows refund requests for paid attendees when cached event data is canceled", () => {
    // Render the attendance fixture.
    const { checker, leaveButton, refundButton } = renderAttendanceDom({
      canceled: "true",
    });

    // Dispatch the HTMX after-request event.
    dispatchHtmxAfterRequest(checker, {
      responseText: JSON.stringify({
        can_request_refund: true,
        purchase_amount_minor: 2500,
        refund_request_status: null,
        status: "attendee",
      }),
    });

    // Cached paid attendance data keeps refund requests available.
    expect(refundButton.classList.contains("hidden")).to.equal(false);
    expect(refundButton.disabled).to.equal(false);
    expect(refundButton.querySelector("[data-attendance-label]")?.textContent).to.equal("Request refund");
    expect(leaveButton.classList.contains("hidden")).to.equal(true);
  });

  it("shows escaped refund rejection reasons and clears stale reason state", () => {
    // Render the attendee refund controls with their reason container.
    const { checker, refundButton, refundRejectionReason } = renderAttendanceDom();

    // Render a rejected request with organizer-provided markup-like text.
    dispatchHtmxAfterRequest(checker, {
      responseText: JSON.stringify({
        purchase_amount_minor: 2500,
        refund_rejection_reason: "Outside policy\n<strong>Contact support</strong>",
        refund_request_status: "rejected",
        status: "attendee",
      }),
    });

    // Verify the rejected state preserves lines and treats the reason as text.
    expect(refundButton.querySelector("[data-attendance-label]")?.textContent).to.equal("Refund rejected");
    expect(refundButton.disabled).to.equal(true);
    expect(refundRejectionReason.classList.contains("hidden")).to.equal(false);
    expect(refundRejectionReason.textContent).to.equal(
      "Reason: Outside policy\n<strong>Contact support</strong>",
    );
    expect(refundRejectionReason.innerHTML).to.include("&lt;strong&gt;");
    expect(refundRejectionReason.querySelector("strong")).to.equal(null);

    // Move to a different refund state and clear the previous reason.
    dispatchHtmxAfterRequest(checker, {
      responseText: JSON.stringify({
        purchase_amount_minor: 2500,
        refund_request_status: "pending",
        status: "attendee",
      }),
    });
    expect(refundRejectionReason.classList.contains("hidden")).to.equal(true);
    expect(refundRejectionReason.textContent).to.equal("");

    // Keep a usable generic rejected state when the reason is malformed or absent.
    dispatchHtmxAfterRequest(checker, {
      responseText: JSON.stringify({
        purchase_amount_minor: 2500,
        refund_request_status: "rejected",
        status: "attendee",
      }),
    });
    expect(refundButton.querySelector("[data-attendance-label]")?.textContent).to.equal("Refund rejected");
    expect(refundRejectionReason.classList.contains("hidden")).to.equal(true);
    expect(refundRejectionReason.textContent).to.equal("");
  });

  it("leaves standalone ticket price badge text untouched", async () => {
    // Render the DOM fixture for leaving standalone ticket price badge text.
    document.body.innerHTML = `
      <div>
        From EUR 50.00
      </div>
    `;

    // Initialize attendance behavior.
    await initializeAttendanceDom();

    // Assert the expected text is rendered.
    expect(document.body.textContent?.trim()).to.equal("From EUR 50.00");
  });

  it('leaves the helper-provided "Free" label untouched', async () => {
    // Render standalone helper-provided ticket label text.
    document.body.innerHTML = `
      <div>
        Free
      </div>
    `;

    // Initialize attendance behavior.
    await initializeAttendanceDom();

    // Assert the expected text is rendered.
    expect(document.body.textContent?.trim()).to.equal("Free");
  });

  it("emits a success message when leaving the waitlist and restores the button on failure", () => {
    // Render the attendance fixture.
    const { leaveButton, loadingButton } = renderAttendanceDom();
    let changedEvents = 0;
    document.body.addEventListener("attendance-changed", () => {
      changedEvents += 1;
    });

    // Keep a reference to the attendance label element.
    leaveButton.querySelector("[data-attendance-label]").textContent = "Leave waiting list";
    dispatchHtmxBeforeRequest(leaveButton);

    // Dispatch the HTMX after-request event.
    dispatchHtmxAfterRequest(leaveButton, {
      responseText: JSON.stringify({ left_status: "waitlisted" }),
    });

    // Leaving the waitlist emits success and restores the action.
    expect(changedEvents).to.equal(1);
    expect(env.current.swal.calls.at(-1)).to.include({
      text: "You have left the waiting list for this event.",
      icon: "info",
    });

    // Update fixture state before asserting the new state.
    leaveButton.classList.remove("hidden");
    loadingButton.classList.remove("hidden");
    dispatchHtmxAfterRequest(leaveButton, {
      status: 500,
    });

    // The restored waitlist action remains available after success.
    expect(leaveButton.classList.contains("hidden")).to.equal(false);
    expect(loadingButton.classList.contains("hidden")).to.equal(true);
    expect(env.current.swal.calls.at(-1)).to.include({
      text: "Something went wrong canceling your attendance. Please try again later.",
      icon: "error",
    });
  });
});
