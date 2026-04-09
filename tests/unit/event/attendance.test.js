import { expect } from "@open-wc/testing";

import "/static/js/event/attendance.js";
import { waitForMicrotask } from "/tests/unit/test-utils/async.js";
import { setupDashboardTestEnv } from "/tests/unit/test-utils/env.js";

const renderAttendanceDom = ({
  starts = "2099-05-10T10:00:00Z",
  capacity = "10",
  remainingCapacity = "5",
  waitlistEnabled = "false",
  isLive = "false",
} = {}) => {
  document.body.innerHTML = `
    <div
      data-attendance-container
      data-starts="${starts}"
      data-capacity="${capacity}"
      data-remaining-capacity="${remainingCapacity}"
      data-waitlist-enabled="${waitlistEnabled}"
      data-is-live="${isLive}"
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
        data-attend-label="Attend event"
        data-waitlist-label="Join waiting list"
      >
        <span data-attendance-label>Attend event</span>
      </button>
      <button
        id="leave-btn"
        data-attendance-role="leave-btn"
        class="hidden"
        data-attendee-label="Cancel attendance"
        data-waitlist-label="Leave waiting list"
      >
        <span data-attendance-label>Cancel attendance</span>
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
    meetingDetails: Array.from(document.querySelectorAll("[data-meeting-details]")),
    alwaysJoinLink: document.querySelector("[data-join-link-always]"),
    liveJoinLink: document.querySelector("[data-join-link]"),
  };
};

describe("event attendance", () => {
  let env;

  beforeEach(() => {
    env = setupDashboardTestEnv({
      path: "/events/test-event",
      withHtmx: true,
      withScroll: true,
      withSwal: true,
    });
  });

  afterEach(() => {
    delete document.body.dataset.attendanceListenersReady;
    env.restore();
  });

  it("shows attendee controls and meeting details after a successful attendance check", () => {
    const { checker, leaveButton, alwaysJoinLink, liveJoinLink, meetingDetails } = renderAttendanceDom({
      isLive: "true",
    });

    checker.dispatchEvent(
      new CustomEvent("htmx:afterRequest", {
        bubbles: true,
        detail: {
          xhr: {
            status: 200,
            responseText: JSON.stringify({ status: "attendee" }),
          },
        },
      }),
    );

    expect(leaveButton.classList.contains("hidden")).to.equal(false);
    expect(leaveButton.querySelector("[data-attendance-label]")?.textContent).to.equal(
      "Cancel attendance",
    );
    expect(alwaysJoinLink.classList.contains("hidden")).to.equal(false);
    expect(liveJoinLink.classList.contains("hidden")).to.equal(false);
    expect(meetingDetails[0].classList.contains("hidden")).to.equal(false);
    expect(meetingDetails[1].classList.contains("hidden")).to.equal(false);
  });

  it("falls back to the waitlist sign-in state when the check response cannot be parsed", () => {
    const { checker, signinButton, attendButton, leaveButton } = renderAttendanceDom({
      capacity: "10",
      remainingCapacity: "0",
      waitlistEnabled: "true",
    });

    checker.dispatchEvent(
      new CustomEvent("htmx:afterRequest", {
        bubbles: true,
        detail: {
          xhr: {
            status: 200,
            responseText: "{invalid json}",
          },
        },
      }),
    );

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

    attendButton.dispatchEvent(
      new CustomEvent("htmx:beforeRequest", {
        bubbles: true,
      }),
    );

    expect(attendButton.classList.contains("hidden")).to.equal(true);
    expect(loadingButton.classList.contains("hidden")).to.equal(false);

    attendButton.dispatchEvent(
      new CustomEvent("htmx:afterRequest", {
        bubbles: true,
        detail: {
          xhr: {
            status: 200,
            responseText: JSON.stringify({ status: "waitlisted" }),
          },
        },
      }),
    );

    expect(changedEvents).to.equal(1);
    expect(env.swal.calls.at(-1)).to.include({
      text: "You have joined the waiting list for this event.",
      icon: "info",
    });
  });

  it("shows sign-in info for waitlists and confirms leaving the waitlist", async () => {
    const { signinButton, leaveButton } = renderAttendanceDom();

    signinButton.querySelector("[data-attendance-label]").textContent = "Join waiting list";
    signinButton.click();

    expect(env.swal.calls[0].icon).to.equal("info");
    expect(env.swal.calls[0].html).to.include("join the waiting list");
    expect(env.swal.calls[0].html).to.include("/log-in?next_url=/events/test-event");

    leaveButton.querySelector("[data-attendance-label]").textContent = "Leave waiting list";
    env.swal.setNextResult({ isConfirmed: true });
    leaveButton.click();
    await waitForMicrotask();

    expect(env.swal.calls[1]).to.include({
      text: "Are you sure you want to leave the waiting list?",
      icon: "warning",
    });
    expect(env.htmx.triggerCalls).to.deep.equal([["#leave-btn", "confirmed"]]);
  });
});
