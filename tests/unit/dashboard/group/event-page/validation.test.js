import { expect } from "@open-wc/testing";

import "/static/js/common/online-event-details.js";
import {
  attachEventSaveBeforeRequestValidation,
  createEventPageValidationCallbacks,
} from "/static/js/dashboard/group/event-page/validation.js";
import { resetDom } from "/tests/unit/test-utils/dom.js";
import { mockSwal } from "/tests/unit/test-utils/globals.js";

describe("event page validation", () => {
  let swal;

  beforeEach(() => {
    resetDom();
    swal = mockSwal();
  });

  afterEach(() => {
    resetDom();
    swal.restore();
  });

  it("accepts synced session meetings when event capacity exceeds the meeting limit", async () => {
    // Render a synced session meeting with event capacity above the limit.
    const { sections, validateSessionOnlineDetails } = await renderSessionMeeting({ meetingInSync: true });

    // The event form keeps the synced session meeting without capacity errors.
    expect(validateSessionOnlineDetails()).to.equal(true);
    expect(sections).to.deep.equal([]);
    expect(swal.calls).to.have.length(0);
  });

  it("blocks new session meetings when event capacity exceeds the meeting limit", async () => {
    // Render a new session meeting with event capacity above the limit.
    const { sections, validateSessionOnlineDetails } = await renderSessionMeeting({ meetingInSync: false });

    // The event form reports the capacity error from the sessions section.
    expect(validateSessionOnlineDetails()).to.equal(false);
    expect(sections).to.include("sessions");
    expect(swal.calls).to.have.length(1);
    expect(swal.calls[0].text).to.include(
      "Event capacity (150) exceeds the configured meeting participant limit (100)",
    );
  });

  it("focuses the event end time when the event meeting duration is too short", async () => {
    // Render an event automatic meeting with a 3-minute schedule.
    document.body.innerHTML = `
      <input id="capacity" value="50" />
      <input id="starts_at" value="2030-05-10T10:00" />
      <input id="ends_at" value="2030-05-10T10:03" />
      <form id="sessions-form"></form>
      <button id="save-button" type="button"></button>
    `;
    const onlineEventDetails = document.createElement("online-event-details");
    Object.assign(onlineEventDetails, {
      endsAt: "2030-05-10T11:00",
      kind: "virtual",
      meetingMaxParticipants: { zoom: 100 },
      meetingProviderId: "zoom",
      meetingRequested: true,
      startsAt: "2030-05-10T10:00",
    });
    document.body.append(onlineEventDetails);
    await onlineEventDetails.updateComplete;

    // Attach the save validation flow.
    const saveButton = document.getElementById("save-button");
    const sections = [];
    attachEventSaveBeforeRequestValidation({
      saveButton,
      saveButtonId: "save-button",
      validateEventForms: () => true,
      validateSessionOnlineDetails: () => true,
      showSessionBoundsError: () => {},
      displayActiveSection: (section) => sections.push(section),
      pageRoot: document,
      startsAtInput: document.getElementById("starts_at"),
      endsAtInput: document.getElementById("ends_at"),
      registrationStartsAtInput: null,
      registrationEndsAtInput: null,
      cfsEnabledInput: null,
      cfsStartsAtInput: null,
      cfsEndsAtInput: null,
      onlineEventDetails,
      allowPastDates: true,
    });

    // Dispatch the save request.
    const requestEvent = new CustomEvent("htmx:beforeRequest", {
      cancelable: true,
      detail: { elt: saveButton },
    });
    saveButton.dispatchEvent(requestEvent);

    // The save is blocked and the end time keeps focus behind the alert.
    expect(requestEvent.defaultPrevented).to.equal(true);
    expect(sections).to.include("date-venue");
    expect(swal.calls).to.have.length(1);
    expect(swal.calls[0].text).to.include("between 5 and 720 minutes");
    expect(document.activeElement).to.equal(document.getElementById("ends_at"));
  });
});

/**
 * Renders a session automatic meeting above the meeting participant limit.
 * @param {object} options Fixture options.
 * @param {boolean} options.meetingInSync Whether the session meeting is synced.
 * @returns {Promise<{
 *   sections: Array<string>,
 *   validateSessionOnlineDetails: () => boolean
 * }>} Activated sections and the session meeting validation callback.
 */
const renderSessionMeeting = async ({ meetingInSync }) => {
  // Render the event capacity and sessions section fixtures.
  document.body.innerHTML = `
    <input id="capacity" value="150" />
    <sessions-section></sessions-section>
  `;

  // Render the session automatic meeting inside the sessions section.
  const onlineEventDetails = document.createElement("online-event-details");
  Object.assign(onlineEventDetails, {
    endsAt: "2030-05-10T11:00",
    fieldNamePrefix: "sessions[0]",
    kind: "virtual",
    meetingInSync,
    meetingMaxParticipants: { zoom: 100 },
    meetingProviderId: "zoom",
    meetingRequested: true,
    startsAt: "2030-05-10T10:00",
  });
  document.querySelector("sessions-section").append(onlineEventDetails);
  await onlineEventDetails.updateComplete;

  // Build the event page validation callbacks.
  const sections = [];
  const { validateSessionOnlineDetails } = createEventPageValidationCallbacks({
    pageRoot: document,
    queryOne: (selector) => document.querySelector(selector),
    displayActiveSection: (section) => sections.push(section),
    cfsStartsAtInput: null,
    cfsEndsAtInput: null,
    syncEventEnrollmentState: () => {},
  });

  return { sections, validateSessionOnlineDetails };
};
