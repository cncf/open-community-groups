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
    // Confirm it exposes the expected meeting constants.
    expect(MIN_MEETING_MINUTES).to.equal(5);
    expect(MAX_MEETING_MINUTES).to.equal(720);
    expect(DEFAULT_MEETING_PROVIDER).to.equal("zoom");
  });

  it("toggles venue and online sections based on event kind", () => {
    // Build the DOM fixture to check it toggles venue and online sections based on event.
    document.body.innerHTML = `
      <section id="venue-information-section" class="hidden"></section>
      <section id="online-event-details-section" class="hidden"></section>
    `;

    // Exercise the flow to check it toggles venue and online sections based on event.
    updateSectionVisibility("hybrid");
    expect(
      document
        .getElementById("venue-information-section")
        ?.classList.contains("hidden"),
    ).to.equal(false);
    expect(
      document
        .getElementById("online-event-details-section")
        ?.classList.contains("hidden"),
    ).to.equal(false);

    // Exercise the flow to check it toggles venue and online sections based on event.
    updateSectionVisibility("virtual");
    expect(
      document
        .getElementById("venue-information-section")
        ?.classList.contains("hidden"),
    ).to.equal(true);
    expect(
      document
        .getElementById("online-event-details-section")
        ?.classList.contains("hidden"),
    ).to.equal(false);

    // Exercise the flow to check it toggles venue and online sections based on event.
    updateSectionVisibility("in-person");
    expect(
      document
        .getElementById("venue-information-section")
        ?.classList.contains("hidden"),
    ).to.equal(false);
    expect(
      document
        .getElementById("online-event-details-section")
        ?.classList.contains("hidden"),
    ).to.equal(true);
  });

  it("scopes venue helpers to the provided root", () => {
    // Build the DOM fixture to check it scopes venue helpers to the provided root.
    document.body.innerHTML = `
      <div id="outside-root">
        <section id="venue-information-section" class="outside-venue hidden"></section>
        <section id="online-event-details-section" class="outside-online hidden"></section>
        <input id="venue_name" value="Outside hall" />
        <input id="venue_address" value="Outside street" />
        <location-search-field id="outside-location"></location-search-field>
      </div>
      <div id="page-root">
        <section id="venue-information-section" class="hidden"></section>
        <section id="online-event-details-section" class="hidden"></section>
        <input id="venue_name" value="Main hall" />
        <input id="venue_address" value="123 Street" />
        <location-search-field id="inside-location"></location-search-field>
      </div>
    `;

    // Read the page root element to check it scopes venue helpers to the provided root.
    const pageRoot = document.getElementById("page-root");
    const insideLocation = document.getElementById("inside-location");
    const outsideLocation = document.getElementById("outside-location");
    let insideCleared = 0;
    let outsideCleared = 0;

    // Exercise the flow to check it scopes venue helpers to the provided root.
    insideLocation.clearLocationFields = () => {
      insideCleared += 1;
    };
    outsideLocation.clearLocationFields = () => {
      outsideCleared += 1;
    };

    // Confirm it scopes venue helpers to the provided root.
    expect(hasVenueData(pageRoot)).to.equal(true);

    // Exercise the flow to check it scopes venue helpers to the provided root.
    clearVenueFields(pageRoot);
    updateSectionVisibility("virtual", pageRoot);

    // Confirm it scopes venue helpers to the provided root.
    expect(pageRoot.querySelector("#venue_name")?.value).to.equal("");
    expect(pageRoot.querySelector("#venue_address")?.value).to.equal("");
    expect(
      pageRoot
        .querySelector("#venue-information-section")
        ?.classList.contains("hidden"),
    ).to.equal(true);
    expect(
      pageRoot
        .querySelector("#online-event-details-section")
        ?.classList.contains("hidden"),
    ).to.equal(false);
    expect(insideCleared).to.equal(1);

    // Confirm it scopes venue helpers to the provided root.
    expect(document.querySelector("#outside-root #venue_name")?.value).to.equal(
      "Outside hall",
    );
    expect(
      document.querySelector("#outside-root #venue_address")?.value,
    ).to.equal("Outside street");
    expect(
      document
        .querySelector("#outside-root #venue-information-section")
        ?.classList.contains("hidden"),
    ).to.equal(true);
    expect(
      document
        .querySelector("#outside-root #online-event-details-section")
        ?.classList.contains("hidden"),
    ).to.equal(true);
    expect(outsideCleared).to.equal(0);
  });

  it("validates happy-path meeting requests", () => {
    // Prepare errors to check it validates happy-path meeting requests.
    const errors = [];

    // Prepare result to check it validates happy-path meeting requests.
    const result = validateMeetingRequest({
      requested: true,
      kindValue: "virtual",
      startsAtValue: "2025-03-25T10:00",
      endsAtValue: "2025-03-25T11:00",
      capacityValue: 50,
      capacityLimit: 100,
      showError: (message) => errors.push(message),
    });

    // Confirm it validates happy-path meeting requests.
    expect(result).to.equal(true);
    expect(errors).to.deep.equal([]);
  });

  it("rejects unsupported event kinds", () => {
    // Prepare errors to check it rejects unsupported event kinds.
    const errors = [];

    // Prepare result to check it rejects unsupported event kinds.
    const result = validateMeetingRequest({
      requested: true,
      kindValue: "in-person",
      startsAtValue: "2025-03-25T10:00",
      endsAtValue: "2025-03-25T11:00",
      capacityValue: 50,
      showError: (message) => errors.push(message),
    });

    // Confirm it rejects unsupported event kinds.
    expect(result).to.equal(false);
    expect(errors[0]).to.include(
      "Automatic meetings can only be created for virtual or hybrid events",
    );
  });

  it("rejects missing or invalid date values and focuses the relevant field", () => {
    // Prepare errors to check it rejects missing or invalid date values and focuses.
    const errors = [];
    const sections = [];
    const startInput = document.createElement("input");
    const endInput = document.createElement("input");
    let focusedField = "";

    // Exercise the flow to check it rejects missing or invalid date values and focuses.
    startInput.focus = () => {
      focusedField = "start";
    };
    endInput.focus = () => {
      focusedField = "end";
    };

    // Prepare result to check it rejects missing or invalid date values and focuses.
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

    // Confirm it rejects missing or invalid date values and focuses the relevant field.
    expect(result).to.equal(false);
    expect(focusedField).to.equal("start");
    expect(sections).to.deep.equal(["date-venue"]);

    // Exercise the flow to check it rejects missing or invalid date values and focuses.
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

    // Confirm it rejects missing or invalid date values and focuses the relevant field.
    expect(result).to.equal(false);
    expect(focusedField).to.equal("start");
    expect(errors[1]).to.include("need valid start and end dates");
  });

  it("rejects invalid durations and invalid capacities", () => {
    // Prepare errors to check it rejects invalid durations and invalid capacities.
    const errors = [];
    const sections = [];
    const endInput = document.createElement("input");
    let endFocused = false;

    // Exercise the flow to check it rejects invalid durations and invalid capacities.
    endInput.focus = () => {
      endFocused = true;
    };

    // Prepare result to check it rejects invalid durations and invalid capacities.
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

    // Confirm it rejects invalid durations and invalid capacities.
    expect(result).to.equal(false);
    expect(endFocused).to.equal(true);
    expect(errors[0]).to.include("require an end time after the start time");

    // Exercise the flow to check it rejects invalid durations and invalid capacities.
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

    // Confirm it rejects invalid durations and invalid capacities.
    expect(result).to.equal(false);
    expect(errors[1]).to.include(
      `between ${MIN_MEETING_MINUTES} and ${MAX_MEETING_MINUTES} minutes`,
    );

    // Exercise the flow to check it rejects invalid durations and invalid capacities.
    result = validateMeetingRequest({
      requested: true,
      kindValue: "hybrid",
      startsAtValue: "2025-03-25T10:00",
      endsAtValue: "2025-03-25T11:00",
      capacityValue: 0,
      showError: (message) => errors.push(message),
      displaySection: (section) => sections.push(section),
    });

    // Confirm it rejects invalid durations and invalid capacities.
    expect(result).to.equal(false);
    expect(errors[2]).to.equal(
      "Event capacity is required for automatic meeting creation.",
    );
    expect(sections.at(-1)).to.equal("details");

    // Exercise the flow to check it rejects invalid durations and invalid capacities.
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

    // Confirm it rejects invalid durations and invalid capacities.
    expect(result).to.equal(false);
    expect(errors[3]).to.include(
      "exceeds the configured meeting participant limit",
    );
    expect(sections.at(-1)).to.equal("details");
  });

  it("detects and clears venue data, including custom location fields", () => {
    // Build the DOM fixture to check it detects and clears venue data, including custom.
    document.body.innerHTML = `
      <input id="venue_name" value="Main Hall" />
      <input name="venue_address" value="123 Street" />
      <input id="venue_city" value="" />
      <input id="venue_zip_code" value="" />
      <location-search-field></location-search-field>
    `;

    // Prepare emitted events to check it detects and clears venue data, including custom.
    const emittedEvents = [];
    const venueName = document.getElementById("venue_name");
    const venueAddress = document.querySelector('[name="venue_address"]');
    const venueCity = document.getElementById("venue_city");
    const venueZipCode = document.getElementById("venue_zip_code");
    const locationSearchField = document.querySelector("location-search-field");
    let locationFieldsCleared = false;

    // Exercise the flow to check it detects and clears venue data, including custom.
    venueName.addEventListener("input", () => emittedEvents.push("venue_name"));
    venueAddress.addEventListener("input", () =>
      emittedEvents.push("venue_address"),
    );
    venueCity.addEventListener("input", () => emittedEvents.push("venue_city"));
    venueZipCode.addEventListener("input", () =>
      emittedEvents.push("venue_zip_code"),
    );
    locationSearchField.clearLocationFields = () => {
      locationFieldsCleared = true;
    };

    // Confirm it detects and clears venue data, including custom location fields.
    expect(hasVenueData()).to.equal(true);

    // Exercise the flow to check it detects and clears venue data, including custom.
    clearVenueFields();

    // Confirm it detects and clears venue data, including custom location fields.
    expect(venueName.value).to.equal("");
    expect(venueAddress.value).to.equal("");
    expect(emittedEvents).to.deep.equal([
      "venue_name",
      "venue_address",
      "venue_city",
      "venue_zip_code",
    ]);
    expect(locationFieldsCleared).to.equal(true);
    expect(hasVenueData()).to.equal(false);
  });

  it("confirms venue data deletion through swal", async () => {
    // Exercise the flow to check it confirms venue data deletion through swal.
    swal.setNextResult({ isConfirmed: true });
    expect(await confirmVenueDataDeletion()).to.equal(true);

    // Exercise the flow to check it confirms venue data deletion through swal.
    swal.setNextResult({ isConfirmed: false });
    expect(await confirmVenueDataDeletion()).to.equal(false);

    // Confirm it confirms venue data deletion through swal.
    expect(swal.calls).to.have.length(2);
    expect(swal.calls[0].text).to.include(
      "Switching to a virtual event will delete the venue information",
    );
    expect(swal.calls[0].confirmButtonText).to.equal("Yes, delete venue info");
  });
});
