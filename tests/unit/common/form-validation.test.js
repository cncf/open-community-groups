import { expect } from "@open-wc/testing";

import {
  clearCfsWindowValidity,
  clearSessionDateBoundsValidity,
  parseLocalDate,
  validateCfsWindow,
  validateEventDates,
  validateGroupPrettySlugField,
  validateSessionDateBounds,
} from "/static/js/common/form-validation.js";
import { resetDom } from "/tests/unit/test-utils/dom.js";
import { stubValidityUi } from "/tests/unit/test-utils/forms.js";

describe("form validation helpers", () => {
  beforeEach(() => {
    resetDom();
  });

  afterEach(() => {
    resetDom();
  });

  it("parses datetime-local strings", () => {
    // Valid datetime-local strings become dates and invalid values return null.
    expect(parseLocalDate("2025-03-25T10:00")).to.be.instanceOf(Date);
    expect(parseLocalDate("")).to.equal(null);
    expect(parseLocalDate("invalid")).to.equal(null);
  });

  it("validates optional group pretty slugs before submit", () => {
    const input = document.createElement("input");
    input.dataset.groupGeneratedSlug = "generated-slug";
    stubValidityUi(input);

    input.value = "";
    expect(validateGroupPrettySlugField(input)).to.equal(true);

    input.value = " pretty-group ";
    expect(validateGroupPrettySlugField(input)).to.equal(true);
    expect(input.value).to.equal("pretty-group");

    input.value = "Pretty_Group";
    expect(validateGroupPrettySlugField(input)).to.equal(false);
    expect(input.validationMessage).to.equal(
      "Use lowercase ASCII letters, numbers, and single hyphens only. Start and end with a letter or number.",
    );

    input.value = "generated-slug";
    expect(validateGroupPrettySlugField(input)).to.equal(false);
    expect(input.validationMessage).to.equal("Pretty URL slug must be different from the generated slug.");
  });

  it("validates event start and end dates", () => {
    // Create date inputs with stubbed validity UI.
    const startsInput = document.createElement("input");
    const endsInput = document.createElement("input");
    stubValidityUi(startsInput);
    stubValidityUi(endsInput);

    // An end date without a start date marks the start field invalid.
    endsInput.value = "2025-03-25T12:00";
    expect(
      validateEventDates({
        startsInput,
        endsInput,
        allowPastDates: true,
      }),
    ).to.equal(false);
    expect(startsInput.validationMessage).to.equal(
      "Start date is required when end date is set.",
    );

    // An end date before the start date marks the end field invalid.
    startsInput.value = "2025-03-25T10:00";
    endsInput.value = "2025-03-25T09:00";
    expect(
      validateEventDates({
        startsInput,
        endsInput,
        allowPastDates: true,
      }),
    ).to.equal(false);
    expect(endsInput.validationMessage).to.equal(
      "End date must be after start date.",
    );

    // An end date beyond the configured limit marks the end field invalid.
    startsInput.value = "2025-03-25T10:00";
    endsInput.value = "2025-03-25T12:00";
    expect(
      validateEventDates({
        startsInput,
        endsInput,
        allowPastDates: true,
        latestDate: new Date("2025-03-25T11:00:00Z"),
        timezone: "UTC",
      }),
    ).to.equal(false);
    expect(endsInput.validationMessage).to.equal(
      "End date cannot be in the future.",
    );

    // A valid start and end range clears validation errors.
    endsInput.value = "2025-03-25T10:30";
    expect(
      validateEventDates({
        startsInput,
        endsInput,
        allowPastDates: true,
      }),
    ).to.equal(true);
  });

  it("reports past dates and resolves future-date limits from the form timezone field", () => {
    // Create form date inputs and track date-section focus calls.
    const form = document.createElement("form");
    const timezoneInput = document.createElement("input");
    const startsInput = document.createElement("input");
    const endsInput = document.createElement("input");
    let dateSectionCalls = 0;

    // Seed the form timezone and past event dates.
    timezoneInput.name = "timezone";
    timezoneInput.value = "UTC";
    startsInput.value = "2020-03-25T10:00";
    endsInput.value = "2020-03-25T12:00";

    // Attach the inputs and enable validity assertions.
    form.append(timezoneInput, startsInput, endsInput);
    document.body.append(form);
    stubValidityUi(startsInput);
    stubValidityUi(endsInput);

    // Past start dates fail validation and focus the date section.
    expect(
      validateEventDates({
        startsInput,
        endsInput,
        onDateSection: () => {
          dateSectionCalls += 1;
        },
      }),
    ).to.equal(false);
    expect(startsInput.validationMessage).to.equal(
      "Start date cannot be in the past.",
    );
    expect(dateSectionCalls).to.equal(1);

    // Move dates out of the past and clear stale validity messages.
    startsInput.value = "2025-03-25T10:00";
    endsInput.value = "2025-03-25T12:00";
    startsInput.setCustomValidity("");
    endsInput.setCustomValidity("");

    // Future end dates fail against the form timezone limit.
    expect(
      validateEventDates({
        startsInput,
        endsInput,
        allowPastDates: true,
        latestDate: new Date("2025-03-25T11:00:00Z"),
        onDateSection: () => {
          dateSectionCalls += 1;
        },
      }),
    ).to.equal(false);
    expect(endsInput.validationMessage).to.equal(
      "End date cannot be in the future.",
    );
    expect(dateSectionCalls).to.equal(2);
  });

  it("clears and validates cfs window constraints", () => {
    // Create CFS and event date inputs.
    const cfsEnabledInput = document.createElement("input");
    const cfsStartsInput = document.createElement("input");
    const cfsEndsInput = document.createElement("input");
    const eventStartsInput = document.createElement("input");

    // Enable validity assertions on the CFS date inputs.
    [cfsStartsInput, cfsEndsInput, eventStartsInput].forEach(stubValidityUi);

    // Clearing CFS validity removes stale messages.
    cfsStartsInput.setCustomValidity("old");
    cfsEndsInput.setCustomValidity("old");
    clearCfsWindowValidity({ cfsStartsInput, cfsEndsInput });
    expect(cfsStartsInput.validationMessage).to.equal("");
    expect(cfsEndsInput.validationMessage).to.equal("");

    // Enabled CFS without an event start marks the event date invalid.
    cfsEnabledInput.value = "true";
    expect(
      validateCfsWindow({
        cfsEnabledInput,
        cfsStartsInput,
        cfsEndsInput,
        eventStartsInput,
      }),
    ).to.equal(false);
    expect(eventStartsInput.validationMessage).to.equal(
      "Event start date is required when CFS is enabled.",
    );

    // A closing date before opening marks the CFS close date invalid.
    eventStartsInput.value = "2025-03-25T12:00";
    cfsStartsInput.value = "2025-03-25T11:00";
    cfsEndsInput.value = "2025-03-25T10:00";
    expect(
      validateCfsWindow({
        cfsEnabledInput,
        cfsStartsInput,
        cfsEndsInput,
        eventStartsInput,
      }),
    ).to.equal(false);
    expect(cfsEndsInput.validationMessage).to.equal(
      "CFS close date must be after CFS open date.",
    );

    // A closing date at event start remains invalid.
    cfsEndsInput.value = "2025-03-25T12:00";
    expect(
      validateCfsWindow({
        cfsEnabledInput,
        cfsStartsInput,
        cfsEndsInput,
        eventStartsInput,
      }),
    ).to.equal(false);
    expect(cfsEndsInput.validationMessage).to.equal(
      "CFS close date must be before the event start date.",
    );

    // A closing date before event start passes validation.
    cfsEndsInput.value = "2025-03-25T11:15";
    expect(
      validateCfsWindow({
        cfsEnabledInput,
        cfsStartsInput,
        cfsEndsInput,
        eventStartsInput,
      }),
    ).to.equal(true);
  });

  it("reports when cfs opens after the event start date", () => {
    // Create CFS inputs and track section focus calls.
    const cfsEnabledInput = document.createElement("input");
    const cfsStartsInput = document.createElement("input");
    const cfsEndsInput = document.createElement("input");
    const eventStartsInput = document.createElement("input");
    let cfsSectionCalls = 0;

    // Seed CFS dates that open at the event start.
    cfsEnabledInput.value = "true";
    eventStartsInput.value = "2025-03-25T12:00";
    cfsStartsInput.value = "2025-03-25T12:00";
    cfsEndsInput.value = "2025-03-25T12:30";

    // Enable validity assertions on the CFS date inputs.
    [cfsStartsInput, cfsEndsInput, eventStartsInput].forEach(stubValidityUi);

    // CFS opening at event start marks the open date invalid.
    expect(
      validateCfsWindow({
        cfsEnabledInput,
        cfsStartsInput,
        cfsEndsInput,
        eventStartsInput,
        onCfsSection: () => {
          cfsSectionCalls += 1;
        },
      }),
    ).to.equal(false);
    expect(cfsStartsInput.validationMessage).to.equal(
      "CFS open date must be before the event start date.",
    );
    expect(cfsSectionCalls).to.equal(1);
  });

  it("clears and validates session date bounds", () => {
    // Build the DOM fixture with sessions form.
    document.body.innerHTML = `
      <form id="sessions-form">
        <input name="sessions[0][starts_at]" value="2025-03-25T09:00" />
        <input name="sessions[0][ends_at]" value="2025-03-25T11:00" />
        <input name="sessions[1][starts_at]" value="2025-03-25T13:00" />
        <input name="sessions[1][ends_at]" value="2025-03-25T12:00" />
      </form>
    `;

    // Collect session inputs and seed stale validity messages.
    const sessionForm = document.getElementById("sessions-form");
    const inputs = Array.from(sessionForm.querySelectorAll("input"));
    inputs.forEach(stubValidityUi);
    inputs.forEach((input) => input.setCustomValidity("stale"));

    // Clearing session validity removes stale messages.
    clearSessionDateBoundsValidity({ sessionForm });
    expect(inputs.every((input) => input.validationMessage === "")).to.equal(
      true,
    );

    // A session before the event start marks the session start invalid.
    expect(
      validateSessionDateBounds({
        eventStartsAt: new Date("2025-03-25T10:00:00"),
        eventEndsAt: new Date("2025-03-25T18:00:00"),
        sessionForm,
      }),
    ).to.equal(false);
    expect(inputs[0].validationMessage).to.equal(
      "Session start cannot be before the event start.",
    );

    // Move the session inside the event bounds but keep times invalid.
    inputs[0].value = "2025-03-25T10:30";
    inputs[1].value = "2025-03-25T11:00";

    // A session end before its start marks the ending field invalid.
    expect(
      validateSessionDateBounds({
        eventStartsAt: new Date("2025-03-25T10:00:00"),
        eventEndsAt: new Date("2025-03-25T18:00:00"),
        sessionForm,
      }),
    ).to.equal(false);
    expect(inputs[3].validationMessage).to.equal(
      "Session end must be after the session start.",
    );

    // Move the session fully inside the event bounds.
    inputs[2].value = "2025-03-25T13:00";
    inputs[3].value = "2025-03-25T14:00";

    // Sessions fully inside the event bounds pass validation.
    expect(
      validateSessionDateBounds({
        eventStartsAt: new Date("2025-03-25T10:00:00"),
        eventEndsAt: new Date("2025-03-25T18:00:00"),
        sessionForm,
      }),
    ).to.equal(true);
  });

  it("reports sessions that end after the event and switches back to the sessions section", () => {
    // Build the DOM fixture with sessions form.
    document.body.innerHTML = `
      <form id="sessions-form">
        <input name="sessions[0][starts_at]" value="2025-03-25T16:00" />
        <input name="sessions[0][ends_at]" value="2025-03-25T19:00" />
      </form>
    `;

    // Collect session inputs and track sessions-section focus calls.
    const sessionForm = document.getElementById("sessions-form");
    const inputs = Array.from(sessionForm.querySelectorAll("input"));
    let sessionsSectionCalls = 0;

    // Enable validity assertions on the session inputs.
    inputs.forEach(stubValidityUi);

    // Invalid session bounds report the ending-after-event error.
    expect(
      validateSessionDateBounds({
        eventStartsAt: new Date("2025-03-25T10:00:00"),
        eventEndsAt: new Date("2025-03-25T18:00:00"),
        sessionForm,
        onSessionsSection: () => {
          sessionsSectionCalls += 1;
        },
      }),
    ).to.equal(false);
    expect(inputs[1].validationMessage).to.equal(
      "Session end cannot be after the event end.",
    );
    expect(sessionsSectionCalls).to.equal(1);
  });
});
