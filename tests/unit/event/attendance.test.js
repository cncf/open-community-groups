import { expect } from "@open-wc/testing";

import "/static/js/event/attendance.js";
import { waitForMicrotask } from "/tests/unit/test-utils/async.js";
import { useDashboardTestEnv } from "/tests/unit/test-utils/env.js";
import { dispatchHtmxAfterRequest, dispatchHtmxBeforeRequest } from "/tests/unit/test-utils/htmx.js";

const initializeAttendanceDom = async () => {
  document.body.dataset.attendanceListenersReady = "true";
  await import(`/static/js/event/attendance.js?test=${Date.now()}`);
};

const renderAttendanceDom = ({
  starts = "2099-05-10T10:00:00Z",
  capacity = "10",
  remainingCapacity = "5",
  waitlistEnabled = "false",
  isLive = "false",
  attendeeMeetingAccessOpen = "false",
} = {}) => {
  document.body.innerHTML = `
    <div
      data-attendance-container
      data-starts="${starts}"
      data-capacity="${capacity}"
      data-remaining-capacity="${remainingCapacity}"
      data-waitlist-enabled="${waitlistEnabled}"
      data-is-live="${isLive}"
      data-attendee-meeting-access-open="${attendeeMeetingAccessOpen}"
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
        <span data-attendance-label>Attend event</span>
      </button>
      <button
        id="attend-btn"
        data-attendance-role="attend-btn"
        class="hidden"
      >
        <span data-attendance-label>Attend event</span>
      </button>
      <button
        id="leave-btn"
        data-attendance-role="leave-btn"
        class="hidden"
      >
        <span data-attendance-label>Cancel attendance</span>
      </button>
      <button
        id="refund-btn"
        data-attendance-role="refund-btn"
        class="hidden"
      >
        <span data-attendance-label>Request refund</span>
      </button>
    </div>
    <div data-meeting-details class="hidden"></div>
    <div data-meeting-details data-has-recording="true" class="hidden"></div>
    <a data-join-link-always class="hidden"></a>
    <a data-join-link class="hidden"></a>
  `;

  return {
    checker: document.querySelector('[data-attendance-role="attendance-checker"]'),
    loadingButton: document.querySelector('[data-attendance-role="loading-btn"]'),
    signinButton: document.querySelector('[data-attendance-role="signin-btn"]'),
    attendButton: document.querySelector('[data-attendance-role="attend-btn"]'),
    leaveButton: document.querySelector('[data-attendance-role="leave-btn"]'),
    refundButton: document.querySelector('[data-attendance-role="refund-btn"]'),
    meetingDetails: Array.from(document.querySelectorAll("[data-meeting-details]")),
    alwaysJoinLink: document.querySelector("[data-join-link-always]"),
    liveJoinLink: document.querySelector("[data-join-link]"),
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
    const { checker, leaveButton, alwaysJoinLink, liveJoinLink, meetingDetails } = renderAttendanceDom({
      isLive: "true",
      attendeeMeetingAccessOpen: "true",
    });

    dispatchHtmxAfterRequest(checker, {
      responseText: JSON.stringify({ status: "attendee" }),
    });

    expect(leaveButton.classList.contains("hidden")).to.equal(false);
    expect(leaveButton.querySelector("[data-attendance-label]")?.textContent).to.equal(
      "Cancel attendance",
    );
    expect(alwaysJoinLink.classList.contains("hidden")).to.equal(false);
    expect(liveJoinLink.classList.contains("hidden")).to.equal(false);
    expect(liveJoinLink.classList.contains("xl:flex")).to.equal(true);
    expect(meetingDetails[0].classList.contains("hidden")).to.equal(false);
    expect(meetingDetails[1].classList.contains("hidden")).to.equal(false);
  });

  it("shows the join meeting link when attendee meeting access is open", () => {
    const { checker, alwaysJoinLink, liveJoinLink, meetingDetails } = renderAttendanceDom({
      isLive: "false",
      attendeeMeetingAccessOpen: "true",
    });

    dispatchHtmxAfterRequest(checker, {
      responseText: JSON.stringify({ status: "attendee" }),
    });

    expect(alwaysJoinLink.classList.contains("hidden")).to.equal(false);
    expect(liveJoinLink.classList.contains("hidden")).to.equal(false);
    expect(liveJoinLink.classList.contains("xl:flex")).to.equal(true);
    expect(meetingDetails[0].classList.contains("hidden")).to.equal(false);
  });

  it("keeps the join meeting link hidden when attendee meeting access is closed", () => {
    const { checker, alwaysJoinLink, liveJoinLink, meetingDetails } = renderAttendanceDom({
      isLive: "false",
      attendeeMeetingAccessOpen: "false",
    });

    dispatchHtmxAfterRequest(checker, {
      responseText: JSON.stringify({ status: "attendee" }),
    });

    expect(alwaysJoinLink.classList.contains("hidden")).to.equal(true);
    expect(liveJoinLink.classList.contains("hidden")).to.equal(true);
    expect(liveJoinLink.classList.contains("xl:flex")).to.equal(false);
    expect(meetingDetails[0].classList.contains("hidden")).to.equal(true);
  });

  it("falls back to the waitlist sign-in state when the check response cannot be parsed", () => {
    const { checker, signinButton, attendButton, leaveButton } = renderAttendanceDom({
      capacity: "10",
      remainingCapacity: "0",
      waitlistEnabled: "true",
    });

    dispatchHtmxAfterRequest(checker, {
      responseText: "{invalid json}",
    });

    expect(signinButton.classList.contains("hidden")).to.equal(false);
    expect(signinButton.querySelector("[data-attendance-label]")?.textContent).to.equal(
      "Join waiting list",
    );
    expect(attendButton.classList.contains("hidden")).to.equal(true);
    expect(leaveButton.classList.contains("hidden")).to.equal(true);
  });

  it("shows loading state before attending and emits a waitlist success message", () => {
    const { attendButton, loadingButton } = renderAttendanceDom();
    let changedEvents = 0;
    document.body.addEventListener("attendance-changed", () => {
      changedEvents += 1;
    });

    dispatchHtmxBeforeRequest(attendButton);

    expect(attendButton.classList.contains("hidden")).to.equal(true);
    expect(loadingButton.classList.contains("hidden")).to.equal(false);

    dispatchHtmxAfterRequest(attendButton, {
      responseText: JSON.stringify({ status: "waitlisted" }),
    });

    expect(changedEvents).to.equal(1);
    expect(env.current.swal.calls.at(-1)).to.include({
      text: "You have joined the waiting list for this event.",
      icon: "info",
    });
  });

  it("shows sign-in info for waitlists and confirms leaving the waitlist", async () => {
    const { signinButton, leaveButton } = renderAttendanceDom();

    signinButton.querySelector("[data-attendance-label]").textContent = "Join waiting list";
    signinButton.click();

    expect(env.current.swal.calls[0].icon).to.equal("info");
    expect(env.current.swal.calls[0].html).to.include("join the waiting list");
    expect(env.current.swal.calls[0].html).to.include("/log-in?next_url=/events/test-event");

    leaveButton.querySelector("[data-attendance-label]").textContent = "Leave waiting list";
    env.current.swal.setNextResult({ isConfirmed: true });
    leaveButton.click();
    await waitForMicrotask();

    expect(env.current.swal.calls[1]).to.include({
      text: "Are you sure you want to leave the waiting list?",
      icon: "warning",
    });
    expect(env.current.htmx.triggerCalls).to.deep.equal([["#leave-btn", "confirmed"]]);
  });

  it("disables attendance changes for past events", () => {
    const { checker, attendButton } = renderAttendanceDom({
      starts: "2000-05-10T10:00:00Z",
      capacity: "10",
      remainingCapacity: "5",
    });

    dispatchHtmxAfterRequest(checker, {
      responseText: JSON.stringify({ status: "guest" }),
    });

    expect(attendButton.classList.contains("hidden")).to.equal(false);
    expect(attendButton.disabled).to.equal(true);
    expect(attendButton.title).to.equal(
      "You cannot change attendance because the event has already started.",
    );
  });

  it("shows a sold-out attend button when no waitlist is available", () => {
    const { checker, attendButton, signinButton } = renderAttendanceDom({
      capacity: "10",
      remainingCapacity: "0",
      waitlistEnabled: "false",
    });

    dispatchHtmxAfterRequest(checker, {
      responseText: JSON.stringify({ status: "guest" }),
    });

    expect(attendButton.classList.contains("hidden")).to.equal(false);
    expect(attendButton.disabled).to.equal(true);
    expect(attendButton.title).to.equal("This event is sold out.");
    expect(signinButton.classList.contains("hidden")).to.equal(true);
  });

  it("leaves standalone ticket price badge text untouched", async () => {
    document.body.innerHTML = `
      <div>
        From EUR 50.00
      </div>
    `;

    await initializeAttendanceDom();

    expect(document.body.textContent?.trim()).to.equal("From EUR 50.00");
  });

  it('leaves the helper-provided "Free" label untouched', async () => {
    document.body.innerHTML = `
      <div>
        Free
      </div>
    `;

    await initializeAttendanceDom();

    expect(document.body.textContent?.trim()).to.equal("Free");
  });

  it("emits a success message when leaving the waitlist and restores the button on failure", () => {
    const { leaveButton, loadingButton } = renderAttendanceDom();
    let changedEvents = 0;
    document.body.addEventListener("attendance-changed", () => {
      changedEvents += 1;
    });

    leaveButton.querySelector("[data-attendance-label]").textContent = "Leave waiting list";
    dispatchHtmxBeforeRequest(leaveButton);

    dispatchHtmxAfterRequest(leaveButton, {
      responseText: JSON.stringify({ left_status: "waitlisted" }),
    });

    expect(changedEvents).to.equal(1);
    expect(env.current.swal.calls.at(-1)).to.include({
      text: "You have left the waiting list for this event.",
      icon: "info",
    });

    leaveButton.classList.remove("hidden");
    loadingButton.classList.remove("hidden");
    dispatchHtmxAfterRequest(leaveButton, {
      status: 500,
    });

    expect(leaveButton.classList.contains("hidden")).to.equal(false);
    expect(loadingButton.classList.contains("hidden")).to.equal(true);
    expect(env.current.swal.calls.at(-1)).to.include({
      text: "Something went wrong canceling your attendance. Please try again later.",
      icon: "error",
    });
  });
});
