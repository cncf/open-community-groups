import { expect } from "@open-wc/testing";

import "/static/js/event/attendance.js";
import { getAttendanceMeta } from "/static/js/event/attendance-dom.js";
import { showSignedOutAttendanceState } from "/static/js/event/attendance-view.js";
import { waitForMicrotask } from "/tests/unit/test-utils/async.js";
import { useDashboardTestEnv } from "/tests/unit/test-utils/env.js";
import {
  dispatchHtmxAfterRequest,
  dispatchHtmxBeforeRequest,
} from "/tests/unit/test-utils/htmx.js";
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
      data-attendee-meeting-access-open="${attendeeMeetingAccessOpen}"
      data-attendee-approval-required="${attendeeApprovalRequired}"
    >
      <button data-attendance-role="attendance-checker"></button>
      <button data-attendance-role="loading-btn" class="hidden">
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
            <textarea data-registration-answer required></textarea>
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
    checker: document.querySelector(
      '[data-attendance-role="attendance-checker"]',
    ),
    loadingButton: document.querySelector(
      '[data-attendance-role="loading-btn"]',
    ),
    signinButton: document.querySelector('[data-attendance-role="signin-btn"]'),
    attendButton: document.querySelector('[data-attendance-role="attend-btn"]'),
    leaveButton: document.querySelector('[data-attendance-role="leave-btn"]'),
    refundButton: document.querySelector('[data-attendance-role="refund-btn"]'),
    questionsModal: document.querySelector(
      '[data-attendance-role="registration-modal"]',
    ),
    meetingDetails: Array.from(
      document.querySelectorAll("[data-meeting-details]"),
    ),
    alwaysJoinLink: document.querySelector("[data-join-link-always]"),
    liveJoinLink: document.querySelector("[data-join-link]"),
    menuJoinLink: document.querySelector("[data-join-link-menu]"),
    availabilityCaptions: {
      capacity: document.querySelector(
        '[data-availability-caption="capacity"]',
      ),
      attendees: document.querySelector(
        '[data-availability-caption="attendees"]',
      ),
      remaining: document.querySelector(
        '[data-availability-caption="remaining"]',
      ),
      waitlist: document.querySelector(
        '[data-availability-caption="waitlist"]',
      ),
    },
    availabilityAttendeeCount: document.querySelector(
      "[data-availability-attendee-count]",
    ),
    availabilityCapacity: document.querySelector(
      "[data-availability-capacity]",
    ),
    soldOutRibbon: document.querySelector(
      "[data-availability-sold-out-ribbon]",
    ),
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
    const {
      checker,
      leaveButton,
      alwaysJoinLink,
      liveJoinLink,
      meetingDetails,
    } = renderAttendanceDom({
      attendeeMeetingAccessOpen: "true",
    });

    // Dispatch the HTMX after-request event.
    dispatchHtmxAfterRequest(checker, {
      responseText: JSON.stringify({ status: "attendee" }),
    });

    // Confirm a successful attendance check reveals attendee-only controls.
    expect(leaveButton.classList.contains("hidden")).to.equal(false);
    expect(
      leaveButton.querySelector("[data-attendance-label]")?.textContent,
    ).to.equal("Cancel attendance");
    expect(
      leaveButton
        .querySelector("[data-attendance-icon]")
        ?.classList.contains("icon-cancel"),
    ).to.equal(true);
    expect(alwaysJoinLink.classList.contains("hidden")).to.equal(false);
    expect(liveJoinLink.classList.contains("hidden")).to.equal(false);
    expect(liveJoinLink.classList.contains("xl:flex")).to.equal(true);
    expect(meetingDetails[0].classList.contains("hidden")).to.equal(false);
    expect(meetingDetails[1].classList.contains("hidden")).to.equal(false);
  });

  it("shows the join meeting link when attendee meeting access is open", () => {
    // Read controls for the attendee meeting-access state.
    const {
      checker,
      alwaysJoinLink,
      liveJoinLink,
      menuJoinLink,
      meetingDetails,
    } = renderAttendanceDom({
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

  it("handles attendance clicks after the page body is swapped", () => {
    // Prepare replacement body for handling attendance clicks after the page body.
    const replacementBody = document.createElement("body");
    document.documentElement.replaceChild(replacementBody, document.body);
    const { signinButton } = renderAttendanceDom();

    // Attendance clicks still work after the page body is swapped.
    signinButton.click();

    // Verify attendance clicks work after the page body is swapped.
    expect(env.current.swal.calls[0].icon).to.equal("info");
    expect(env.current.swal.calls[0].html).to.include(
      "/log-in?next_url=/events/test-event",
    );
  });

  it("keeps the join meeting link hidden when the event is canceled", () => {
    // Read controls for canceled meeting-access state.
    const {
      checker,
      alwaysJoinLink,
      liveJoinLink,
      menuJoinLink,
      meetingDetails,
    } = renderAttendanceDom({
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
    const {
      checker,
      alwaysJoinLink,
      liveJoinLink,
      menuJoinLink,
      meetingDetails,
    } = renderAttendanceDom({
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
    const { checker, signinButton, attendButton, leaveButton } =
      renderAttendanceDom({
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
    expect(
      signinButton.querySelector("[data-attendance-label]")?.textContent,
    ).to.equal("Join waiting list");
    expect(attendButton.classList.contains("hidden")).to.equal(true);
    expect(leaveButton.classList.contains("hidden")).to.equal(true);
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
    expect(
      signinButton.querySelector("[data-attendance-label]")?.textContent,
    ).to.equal("Request invitation");
    expect(
      signinButton
        .querySelector("[data-attendance-icon]")
        ?.classList.contains("icon-request-invitation"),
    ).to.equal(true);
    expect(
      signinButton
        .querySelector("[data-attendance-icon]")
        ?.classList.contains("icon-user-plus"),
    ).to.equal(false);
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
    expect(
      signinButton.querySelector("[data-attendance-label]")?.textContent,
    ).to.equal("Attend event");
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
    expect(
      signinButton.querySelector("[data-attendance-label]")?.textContent,
    ).to.equal("Request invitation");
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
    dispatchHtmxBeforeRequest(attendButton);

    // Verify shows loading state before attending and emits a waitlist success.
    expect(attendButton.classList.contains("hidden")).to.equal(true);
    expect(loadingButton.classList.contains("hidden")).to.equal(false);

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
    const event = new CustomEvent("htmx:beforeRequest", {
      bubbles: true,
      cancelable: true,
    });

    // Expose the attend button before dispatching the event.
    attendButton.classList.remove("hidden");
    attendButton.dispatchEvent(event);

    // Verify blocks the attend request until registration questions are answered.
    expect(event.defaultPrevented).to.equal(true);
    expect(container.dataset.questionsContinueAction).to.equal("attend");
    expect(questionsModal.classList.contains("hidden")).to.equal(false);
    expect(attendButton.classList.contains("hidden")).to.equal(false);
    expect(loadingButton.classList.contains("hidden")).to.equal(true);
  });

  it("allows waitlist joins before registration questions are answered", () => {
    // Render full-event attendance controls with waitlist enabled.
    const { attendButton, loadingButton, questionsModal } = renderAttendanceDom({
      capacity: "10",
      includeRegistrationQuestions: true,
      remainingCapacity: "0",
      waitlistEnabled: "true",
    });
    const event = new CustomEvent("htmx:beforeRequest", {
      bubbles: true,
      cancelable: true,
    });

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

  it("opens registration questions for promoted waitlist attendees", () => {
    // Render waitlist controls with registration questions.
    const { attendButton, checker, container, loadingButton, questionsModal } = renderAttendanceDom({
      capacity: "10",
      includeRegistrationQuestions: true,
      remainingCapacity: "0",
      waitlistEnabled: "true",
    });

    dispatchHtmxAfterRequest(checker, {
      responseText: JSON.stringify({ status: "registration-questions-pending" }),
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
      responseText: JSON.stringify({ status: "registration-questions-pending" }),
    });
    attendButton.dispatchEvent(event);

    // Assert whether the event was prevented.
    expect(event.defaultPrevented).to.equal(true);
    expect(questionsModal.classList.contains("hidden")).to.equal(false);
  });

  it("shows sign-in info for waitlists and confirms leaving the waitlist", async () => {
    // Render the attendance fixture.
    const { signinButton, leaveButton } = renderAttendanceDom();

    // Keep a reference to the attendance label element.
    signinButton.querySelector("[data-attendance-label]").textContent =
      "Join waiting list";
    signinButton.click();

    // Verify shows sign-in info for waitlists and confirms leaving the waitlist.
    expect(env.current.swal.calls[0].icon).to.equal("info");
    expect(env.current.swal.calls[0].html).to.include("join the waiting list");
    expect(env.current.swal.calls[0].html).to.include(
      "/log-in?next_url=/events/test-event",
    );

    // Keep a reference to the attendance label element.
    leaveButton.querySelector("[data-attendance-label]").textContent =
      "Leave waiting list";
    env.current.swal.setNextResult({ isConfirmed: true });
    leaveButton.click();
    await waitForMicrotask();

    // Verify shows sign-in info for waitlists and confirms leaving the waitlist.
    expect(env.current.swal.calls[1]).to.include({
      text: "Are you sure you want to leave the waiting list?",
      icon: "warning",
    });
    expect(env.current.htmx.triggerCalls).to.deep.equal([
      ["#leave-btn", "confirmed"],
    ]);
  });

  it("confirms canceling a pending invitation request with request-specific copy", async () => {
    // Render the attendance fixture.
    const { leaveButton } = renderAttendanceDom();

    // Keep a reference to the attendance label element.
    leaveButton.querySelector("[data-attendance-label]").textContent =
      "Cancel request";
    env.current.swal.setNextResult({ isConfirmed: true });
    leaveButton.click();
    await waitForMicrotask();

    // Verify confirms canceling a pending invitation request with request-specific.
    expect(env.current.swal.calls[0]).to.include({
      text: "Are you sure you want to cancel your invitation request?",
      icon: "warning",
    });
    expect(env.current.htmx.triggerCalls).to.deep.equal([
      ["#leave-btn", "confirmed"],
    ]);
  });

  it("uses cancel icons for waitlist and pending invitation cancellation", () => {
    // Render the attendance fixture.
    const { checker, leaveButton } = renderAttendanceDom();

    // Dispatch the HTMX after-request event.
    dispatchHtmxAfterRequest(checker, {
      responseText: JSON.stringify({ status: "waitlisted" }),
    });

    // Verify uses cancel icons for waitlist and pending invitation cancellation.
    expect(
      leaveButton.querySelector("[data-attendance-label]")?.textContent,
    ).to.equal("Leave waiting list");
    expect(
      leaveButton
        .querySelector("[data-attendance-icon]")
        ?.classList.contains("icon-cancel"),
    ).to.equal(true);

    // Dispatch the HTMX after-request event.
    dispatchHtmxAfterRequest(checker, {
      responseText: JSON.stringify({ status: "pending-approval" }),
    });

    // Verify uses cancel icons for waitlist and pending invitation cancellation.
    expect(
      leaveButton.querySelector("[data-attendance-label]")?.textContent,
    ).to.equal("Cancel request");
    expect(
      leaveButton
        .querySelector("[data-attendance-icon]")
        ?.classList.contains("icon-cancel"),
    ).to.equal(true);
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
    expect(
      attendButton.querySelector("[data-attendance-label]")?.textContent,
    ).to.equal("Request invitation");
    expect(
      attendButton
        .querySelector("[data-attendance-icon]")
        ?.classList.contains("icon-request-invitation"),
    ).to.equal(true);
    expect(
      attendButton
        .querySelector("[data-attendance-icon]")
        ?.classList.contains("icon-user-plus"),
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
    expect(
      attendButton.querySelector("[data-attendance-label]")?.textContent,
    ).to.equal("Attend event");
    expect(
      attendButton
        .querySelector("[data-attendance-icon]")
        ?.classList.contains("icon-user-plus"),
    ).to.equal(true);
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
    expect(
      attendButton.querySelector("[data-attendance-label]")?.textContent,
    ).to.equal("Attend event");
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

  it("disables approval-required attendance when event capacity is zero", () => {
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

    // Verify disables approval-required attendance when event capacity is zero.
    expect(attendButton.classList.contains("hidden")).to.equal(false);
    expect(attendButton.disabled).to.equal(true);
    expect(attendButton.title).to.equal("This event has no attendee capacity.");
    expect(
      attendButton.querySelector("[data-attendance-label]")?.textContent,
    ).to.equal("Attend event");
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
          is_ticketed: false,
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
      expect(
        availabilityCaptions.attendees.classList.contains("hidden"),
      ).to.equal(true);
      expect(
        availabilityCaptions.capacity.classList.contains("hidden"),
      ).to.equal(false);
      expect(availabilityCapacity.textContent.trim()).to.equal("2");
      expect(
        availabilityCaptions.remaining.classList.contains("hidden"),
      ).to.equal(false);
      expect(
        availabilityCaptions.remaining.classList.contains("inline"),
      ).to.equal(true);
      expect(availabilityCaptions.remaining.textContent).to.include("1");
      expect(
        availabilityCaptions.waitlist.classList.contains("hidden"),
      ).to.equal(true);
      expect(
        availabilityCaptions.waitlist.classList.contains("inline"),
      ).to.equal(false);
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
          is_ticketed: false,
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
          is_ticketed: false,
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
          is_ticketed: false,
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
      expect(
        availabilityCaptions.waitlist.classList.contains("hidden"),
      ).to.equal(false);
      expect(
        availabilityCaptions.waitlist.classList.contains("inline"),
      ).to.equal(true);
      expect(availabilityCaptions.waitlist.textContent).to.include("3");
      expect(
        availabilityCaptions.remaining.classList.contains("hidden"),
      ).to.equal(true);
      expect(
        availabilityCaptions.remaining.classList.contains("inline"),
      ).to.equal(false);
      expect(availabilityCaptions.remaining.textContent).to.not.include("3");
    } finally {
      fetchMock.restore();
    }
  });

  it("shows attendee count when refreshed availability is unlimited", async () => {
    // Keep references to the fixture controls under assertion.
    const {
      availabilityAttendeeCount,
      availabilityCapacity,
      availabilityCaptions,
    } = renderAttendanceDom({
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
          is_ticketed: false,
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
      expect(
        availabilityCaptions.attendees.classList.contains("hidden"),
      ).to.equal(false);
      expect(
        availabilityCaptions.attendees.classList.contains("flex"),
      ).to.equal(true);
      expect(
        availabilityCaptions.capacity.classList.contains("hidden"),
      ).to.equal(true);
      expect(
        availabilityCaptions.remaining.classList.contains("hidden"),
      ).to.equal(true);
      expect(
        availabilityCaptions.waitlist.classList.contains("hidden"),
      ).to.equal(true);
    } finally {
      fetchMock.restore();
    }
  });

  it("hides attendee count when refreshed unlimited availability has no attendees", async () => {
    // Keep references to the fixture controls under assertion.
    const { availabilityAttendeeCount, availabilityCaptions } =
      renderAttendanceDom({
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
          is_ticketed: false,
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
      expect(
        availabilityCaptions.attendees.classList.contains("hidden"),
      ).to.equal(true);
      expect(
        availabilityCaptions.attendees.classList.contains("flex"),
      ).to.equal(false);
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
          is_ticketed: false,
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
    expect(
      refundButton.querySelector("[data-attendance-label]")?.textContent,
    ).to.equal("Request refund");
    expect(leaveButton.classList.contains("hidden")).to.equal(true);
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
    leaveButton.querySelector("[data-attendance-label]").textContent =
      "Leave waiting list";
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
