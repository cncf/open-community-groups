import { expect } from "@open-wc/testing";

import {
  DEFAULT_MEETING_PROVIDER,
  MAX_MEETING_MINUTES,
  MIN_MEETING_MINUTES,
  clearVenueFields,
  confirmVenueDataDeletion,
  hasVenueData,
  updateSectionVisibility,
  validateMeetingRequest,
} from "/static/js/dashboard/group/meeting-validations.js";
import { resetDom } from "/tests/unit/test-utils/dom.js";
import { mockSwal } from "/tests/unit/test-utils/globals.js";

describe("meeting validations", () => {
  let swal;

  beforeEach(() => {
    resetDom();
    swal = mockSwal();
  });

  afterEach(() => {
    resetDom();
    swal.restore();
  });

  it("exposes the expected meeting constants", () => {
    expect(MIN_MEETING_MINUTES).to.equal(5);
    expect(MAX_MEETING_MINUTES).to.equal(720);
    expect(DEFAULT_MEETING_PROVIDER).to.equal("zoom");
  });

  it("toggles venue and online sections based on event kind", () => {
    document.body.innerHTML = `
      <section id="venue-information-section" class="hidden"></section>
      <section id="online-event-details-section" class="hidden"></section>
    `;

    updateSectionVisibility("hybrid");
    expect(document.getElementById("venue-information-section")?.classList.contains("hidden")).to.equal(false);
    expect(document.getElementById("online-event-details-section")?.classList.contains("hidden")).to.equal(false);

    updateSectionVisibility("virtual");
    expect(document.getElementById("venue-information-section")?.classList.contains("hidden")).to.equal(true);
    expect(document.getElementById("online-event-details-section")?.classList.contains("hidden")).to.equal(false);

    updateSectionVisibility("in-person");
    expect(document.getElementById("venue-information-section")?.classList.contains("hidden")).to.equal(false);
    expect(document.getElementById("online-event-details-section")?.classList.contains("hidden")).to.equal(true);
  });

  it("validates happy-path meeting requests", () => {
    const errors = [];

    const result = validateMeetingRequest({
      requested: true,
      kindValue: "virtual",
      startsAtValue: "2025-03-25T10:00",
      endsAtValue: "2025-03-25T11:00",
      capacityValue: 50,
      capacityLimit: 100,
      showError: (message) => errors.push(message),
    });

    expect(result).to.equal(true);
    expect(errors).to.deep.equal([]);
  });

  it("rejects unsupported event kinds", () => {
    const errors = [];

    const result = validateMeetingRequest({
      requested: true,
      kindValue: "in-person",
      startsAtValue: "2025-03-25T10:00",
      endsAtValue: "2025-03-25T11:00",
      capacityValue: 50,
      showError: (message) => errors.push(message),
    });

    expect(result).to.equal(false);
    expect(errors[0]).to.include("Automatic meetings can only be created for virtual or hybrid events");
  });

  it("rejects missing or invalid date values and focuses the relevant field", () => {
    const errors = [];
    const sections = [];
    const startInput = document.createElement("input");
    const endInput = document.createElement("input");
    let focusedField = "";

    startInput.focus = () => {
      focusedField = "start";
    };
    endInput.focus = () => {
      focusedField = "end";
    };

    let result = validateMeetingRequest({
      requested: true,
      kindValue: "virtual",
      startsAtValue: "",
      endsAtValue: "2025-03-25T11:00",
      capacityValue: 50,
      showError: (message) => errors.push(message),
      displaySection: (section) => sections.push(section),
      startsAtInput: startInput,
      endsAtInput: endInput,
    });

    expect(result).to.equal(false);
    expect(focusedField).to.equal("start");
    expect(sections).to.deep.equal(["date-venue"]);

    focusedField = "";
    result = validateMeetingRequest({
      requested: true,
      kindValue: "virtual",
      startsAtValue: "invalid",
      endsAtValue: "2025-03-25T11:00",
      capacityValue: 50,
      showError: (message) => errors.push(message),
      displaySection: (section) => sections.push(section),
      startsAtInput: startInput,
      endsAtInput: endInput,
    });

    expect(result).to.equal(false);
    expect(focusedField).to.equal("start");
    expect(errors[1]).to.include("need valid start and end dates");
  });

  it("rejects invalid durations and invalid capacities", () => {
    const errors = [];
    const sections = [];
    const endInput = document.createElement("input");
    let endFocused = false;

    endInput.focus = () => {
      endFocused = true;
    };

    let result = validateMeetingRequest({
      requested: true,
      kindValue: "hybrid",
      startsAtValue: "2025-03-25T10:00",
      endsAtValue: "2025-03-25T10:00",
      capacityValue: 50,
      showError: (message) => errors.push(message),
      displaySection: (section) => sections.push(section),
      endsAtInput: endInput,
    });

    expect(result).to.equal(false);
    expect(endFocused).to.equal(true);
    expect(errors[0]).to.include("require an end time after the start time");

    result = validateMeetingRequest({
      requested: true,
      kindValue: "hybrid",
      startsAtValue: "2025-03-25T10:00",
      endsAtValue: "2025-03-25T10:03",
      capacityValue: 50,
      showError: (message) => errors.push(message),
      displaySection: (section) => sections.push(section),
      endsAtInput: endInput,
    });

    expect(result).to.equal(false);
    expect(errors[1]).to.include(`between ${MIN_MEETING_MINUTES} and ${MAX_MEETING_MINUTES} minutes`);

    result = validateMeetingRequest({
      requested: true,
      kindValue: "hybrid",
      startsAtValue: "2025-03-25T10:00",
      endsAtValue: "2025-03-25T11:00",
      capacityValue: 0,
      showError: (message) => errors.push(message),
      displaySection: (section) => sections.push(section),
    });

    expect(result).to.equal(false);
    expect(errors[2]).to.equal("Event capacity is required for automatic meeting creation.");
    expect(sections.at(-1)).to.equal("details");

    result = validateMeetingRequest({
      requested: true,
      kindValue: "hybrid",
      startsAtValue: "2025-03-25T10:00",
      endsAtValue: "2025-03-25T11:00",
      capacityValue: 150,
      capacityLimit: 100,
      showError: (message) => errors.push(message),
      displaySection: (section) => sections.push(section),
    });

    expect(result).to.equal(false);
    expect(errors[3]).to.include("exceeds the configured meeting participant limit");
    expect(sections.at(-1)).to.equal("details");
  });

  it("detects and clears venue data, including custom location fields", () => {
    document.body.innerHTML = `
      <input id="venue_name" value="Main Hall" />
      <input name="venue_address" value="123 Street" />
      <input id="venue_city" value="" />
      <input id="venue_zip_code" value="" />
      <location-search-field></location-search-field>
    `;

    const emittedEvents = [];
    const venueName = document.getElementById("venue_name");
    const venueAddress = document.querySelector('[name="venue_address"]');
    const venueCity = document.getElementById("venue_city");
    const venueZipCode = document.getElementById("venue_zip_code");
    const locationSearchField = document.querySelector("location-search-field");
    let locationFieldsCleared = false;

    venueName.addEventListener("input", () => emittedEvents.push("venue_name"));
    venueAddress.addEventListener("input", () => emittedEvents.push("venue_address"));
    venueCity.addEventListener("input", () => emittedEvents.push("venue_city"));
    venueZipCode.addEventListener("input", () => emittedEvents.push("venue_zip_code"));
    locationSearchField.clearLocationFields = () => {
      locationFieldsCleared = true;
    };

    expect(hasVenueData()).to.equal(true);

    clearVenueFields();

    expect(venueName.value).to.equal("");
    expect(venueAddress.value).to.equal("");
    expect(emittedEvents).to.deep.equal(["venue_name", "venue_address", "venue_city", "venue_zip_code"]);
    expect(locationFieldsCleared).to.equal(true);
    expect(hasVenueData()).to.equal(false);
  });

  it("confirms venue data deletion through swal", async () => {
    swal.setNextResult({ isConfirmed: true });
    expect(await confirmVenueDataDeletion()).to.equal(true);

    swal.setNextResult({ isConfirmed: false });
    expect(await confirmVenueDataDeletion()).to.equal(false);

    expect(swal.calls).to.have.length(2);
    expect(swal.calls[0].text).to.include("Switching to a virtual event will delete the venue information");
    expect(swal.calls[0].confirmButtonText).to.equal("Yes, delete venue info");
  });
});
