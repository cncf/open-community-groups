import { expect } from "@open-wc/testing";

import "/static/js/event/attendance.js";
import { waitForMicrotask } from "/tests/unit/test-utils/async.js";
import { useDashboardTestEnv } from "/tests/unit/test-utils/env.js";
import { dispatchHtmxAfterRequest, dispatchHtmxBeforeRequest } from "/tests/unit/test-utils/htmx.js";
import { mockFetch } from "/tests/unit/test-utils/network.js";

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
    meetingDetails: Array.from(document.querySelectorAll("[data-meeting-details]")),
    alwaysJoinLink: document.querySelector("[data-join-link-always]"),
    liveJoinLink: document.querySelector("[data-join-link]"),
    menuJoinLink: document.querySelector("[data-join-link-menu]"),
    availabilityCaptions: {
      capacity: document.querySelector('[data-availability-caption="capacity"]'),
      remaining: document.querySelector('[data-availability-caption="remaining"]'),
      waitlist: document.querySelector('[data-availability-caption="waitlist"]'),
    },
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
    const { checker, leaveButton, alwaysJoinLink, liveJoinLink, meetingDetails } = renderAttendanceDom({
      attendeeMeetingAccessOpen: "true",
    });

    dispatchHtmxAfterRequest(checker, {
      responseText: JSON.stringify({ status: "attendee" }),
    });

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
    const { checker, alwaysJoinLink, liveJoinLink, menuJoinLink, meetingDetails } = renderAttendanceDom({
      attendeeMeetingAccessOpen: "true",
    });

    dispatchHtmxAfterRequest(checker, {
      responseText: JSON.stringify({ status: "attendee" }),
    });

    expect(alwaysJoinLink.classList.contains("hidden")).to.equal(false);
    expect(liveJoinLink.classList.contains("hidden")).to.equal(false);
    expect(liveJoinLink.classList.contains("xl:flex")).to.equal(true);
    expect(menuJoinLink.classList.contains("hidden")).to.equal(false);
    expect(menuJoinLink.classList.contains("max-xl:flex")).to.equal(true);
    expect(meetingDetails[0].classList.contains("hidden")).to.equal(false);
  });

  it("keeps the join meeting link hidden when the event is canceled", () => {
    const { checker, alwaysJoinLink, liveJoinLink, menuJoinLink, meetingDetails } = renderAttendanceDom({
      attendeeMeetingAccessOpen: "true",
      canceled: "true",
    });

    dispatchHtmxAfterRequest(checker, {
      responseText: JSON.stringify({ status: "attendee" }),
    });

    expect(alwaysJoinLink.classList.contains("hidden")).to.equal(true);
    expect(liveJoinLink.classList.contains("hidden")).to.equal(true);
    expect(liveJoinLink.classList.contains("xl:flex")).to.equal(false);
    expect(menuJoinLink.classList.contains("hidden")).to.equal(true);
    expect(menuJoinLink.classList.contains("max-xl:flex")).to.equal(false);
    expect(meetingDetails[0].classList.contains("hidden")).to.equal(true);
  });

  it("keeps the join meeting link hidden before attendee meeting access opens", () => {
    const { checker, alwaysJoinLink, liveJoinLink, menuJoinLink, meetingDetails } = renderAttendanceDom({
      attendeeMeetingAccessOpen: "false",
    });

    dispatchHtmxAfterRequest(checker, {
      responseText: JSON.stringify({ status: "attendee" }),
    });

    expect(alwaysJoinLink.classList.contains("hidden")).to.equal(true);
    expect(liveJoinLink.classList.contains("hidden")).to.equal(true);
    expect(liveJoinLink.classList.contains("xl:flex")).to.equal(false);
    expect(menuJoinLink.classList.contains("hidden")).to.equal(true);
    expect(menuJoinLink.classList.contains("max-xl:flex")).to.equal(false);
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
    expect(signinButton.querySelector("[data-attendance-label]")?.textContent).to.equal("Join waiting list");
    expect(attendButton.classList.contains("hidden")).to.equal(true);
    expect(leaveButton.classList.contains("hidden")).to.equal(true);
  });

  it("uses the request invitation icon for approval-required sign-in state", () => {
    const { checker, signinButton } = renderAttendanceDom({
      attendeeApprovalRequired: "true",
    });

    dispatchHtmxAfterRequest(checker, {
      responseText: "{invalid json}",
    });

    expect(signinButton.querySelector("[data-attendance-label]")?.textContent).to.equal("Request invitation");
    expect(
      signinButton.querySelector("[data-attendance-icon]")?.classList.contains("icon-request-invitation"),
    ).to.equal(true);
    expect(
      signinButton.querySelector("[data-attendance-icon]")?.classList.contains("icon-user-plus"),
    ).to.equal(false);
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

  it("confirms canceling a pending invitation request with request-specific copy", async () => {
    const { leaveButton } = renderAttendanceDom();

    leaveButton.querySelector("[data-attendance-label]").textContent = "Cancel request";
    env.current.swal.setNextResult({ isConfirmed: true });
    leaveButton.click();
    await waitForMicrotask();

    expect(env.current.swal.calls[0]).to.include({
      text: "Are you sure you want to cancel your invitation request?",
      icon: "warning",
    });
    expect(env.current.htmx.triggerCalls).to.deep.equal([["#leave-btn", "confirmed"]]);
  });

  it("uses cancel icons for waitlist and pending invitation cancellation", () => {
    const { checker, leaveButton } = renderAttendanceDom();

    dispatchHtmxAfterRequest(checker, {
      responseText: JSON.stringify({ status: "waitlisted" }),
    });

    expect(leaveButton.querySelector("[data-attendance-label]")?.textContent).to.equal("Leave waiting list");
    expect(leaveButton.querySelector("[data-attendance-icon]")?.classList.contains("icon-cancel")).to.equal(
      true,
    );

    dispatchHtmxAfterRequest(checker, {
      responseText: JSON.stringify({ status: "pending-approval" }),
    });

    expect(leaveButton.querySelector("[data-attendance-label]")?.textContent).to.equal("Cancel request");
    expect(leaveButton.querySelector("[data-attendance-icon]")?.classList.contains("icon-cancel")).to.equal(
      true,
    );
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

  it("uses the request invitation icon for approval-required guest state", () => {
    const { checker, attendButton } = renderAttendanceDom({
      attendeeApprovalRequired: "true",
    });

    dispatchHtmxAfterRequest(checker, {
      responseText: JSON.stringify({ status: "guest" }),
    });

    expect(attendButton.querySelector("[data-attendance-label]")?.textContent).to.equal("Request invitation");
    expect(
      attendButton.querySelector("[data-attendance-icon]")?.classList.contains("icon-request-invitation"),
    ).to.equal(true);
    expect(
      attendButton.querySelector("[data-attendance-icon]")?.classList.contains("icon-user-plus"),
    ).to.equal(false);
  });

  it("disables approved invitation rejoin when the event is sold out", () => {
    const { checker, attendButton } = renderAttendanceDom({
      attendeeApprovalRequired: "true",
      capacity: "10",
      remainingCapacity: "0",
    });

    dispatchHtmxAfterRequest(checker, {
      responseText: JSON.stringify({ status: "invitation-approved" }),
    });

    expect(attendButton.classList.contains("hidden")).to.equal(false);
    expect(attendButton.disabled).to.equal(true);
    expect(attendButton.title).to.equal("This event is sold out.");
    expect(attendButton.querySelector("[data-attendance-label]")?.textContent).to.equal("Attend event");
    expect(
      attendButton.querySelector("[data-attendance-icon]")?.classList.contains("icon-user-plus"),
    ).to.equal(true);
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

  it("shows remaining seats instead of waitlist while capacity is still available", async () => {
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

    try {
      await initializeAttendanceDom();
      await waitForMicrotask();

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

    try {
      await initializeAttendanceDom();

      dispatchHtmxAfterRequest(checker, {
        responseText: JSON.stringify({ status: "guest" }),
      });

      expect(attendButton.classList.contains("hidden")).to.equal(true);

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

      dispatchHtmxAfterRequest(checker, {
        responseText: JSON.stringify({ status: "guest" }),
      });

      expect(attendButton.classList.contains("hidden")).to.equal(false);
    } finally {
      fetchMock.restore();
    }
  });

  it("falls back to cached attendance metadata when availability fails", async () => {
    const { attendButton, checker, container } = renderAttendanceDom({
      availabilityUrl: "/events/test-event/availability",
    });
    const fetchMock = mockFetch({
      response: {
        ok: false,
      },
    });

    try {
      await initializeAttendanceDom();
      await waitForMicrotask();

      expect(container.dataset.availabilityHydrated).to.equal("true");

      dispatchHtmxAfterRequest(checker, {
        responseText: JSON.stringify({ status: "guest" }),
      });

      expect(attendButton.classList.contains("hidden")).to.equal(false);
      expect(attendButton.disabled).to.equal(false);
    } finally {
      fetchMock.restore();
    }
  });

  it("hydrates attendee meeting access from refreshed availability", async () => {
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

    try {
      await initializeAttendanceDom();
      await waitForMicrotask();

      expect(container.dataset.attendeeMeetingAccessOpen).to.equal("true");
      expect(changedEvents).to.equal(1);
    } finally {
      fetchMock.restore();
    }
  });

  it("shows waitlist count after refreshing availability", async () => {
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

    try {
      await initializeAttendanceDom();
      await waitForMicrotask();

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

  it("hides the capacity placeholder when refreshed availability is unlimited", async () => {
    const { availabilityCapacity, availabilityCaptions } = renderAttendanceDom({
      availabilityUrl: "/events/test-event/availability",
    });
    const fetchMock = mockFetch({
      response: {
        ok: true,
        json: async () => ({
          attendee_approval_required: false,
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

    try {
      await initializeAttendanceDom();
      await waitForMicrotask();

      expect(availabilityCapacity.textContent.trim()).to.equal("");
      expect(availabilityCaptions.capacity.classList.contains("hidden")).to.equal(true);
      expect(availabilityCaptions.remaining.classList.contains("hidden")).to.equal(true);
      expect(availabilityCaptions.waitlist.classList.contains("hidden")).to.equal(true);
    } finally {
      fetchMock.restore();
    }
  });

  it("keeps the sold-out ribbon hidden for canceled availability", async () => {
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

    try {
      await initializeAttendanceDom();
      await waitForMicrotask();

      expect(soldOutRibbon.classList.contains("hidden")).to.equal(true);
    } finally {
      fetchMock.restore();
    }
  });

  it("disables attendance controls when cached event data is canceled", () => {
    const { checker, attendButton, signinButton } = renderAttendanceDom({
      canceled: "true",
    });

    dispatchHtmxAfterRequest(checker, {
      responseText: JSON.stringify({ status: "guest" }),
    });

    expect(attendButton.classList.contains("hidden")).to.equal(false);
    expect(attendButton.disabled).to.equal(true);
    expect(attendButton.title).to.equal("This event has been canceled.");
    expect(signinButton.classList.contains("hidden")).to.equal(true);
  });

  it("allows refund requests for paid attendees when cached event data is canceled", () => {
    const { checker, leaveButton, refundButton } = renderAttendanceDom({
      canceled: "true",
    });

    dispatchHtmxAfterRequest(checker, {
      responseText: JSON.stringify({
        can_request_refund: true,
        purchase_amount_minor: 2500,
        refund_request_status: null,
        status: "attendee",
      }),
    });

    expect(refundButton.classList.contains("hidden")).to.equal(false);
    expect(refundButton.disabled).to.equal(false);
    expect(refundButton.querySelector("[data-attendance-label]")?.textContent).to.equal("Request refund");
    expect(leaveButton.classList.contains("hidden")).to.equal(true);
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
