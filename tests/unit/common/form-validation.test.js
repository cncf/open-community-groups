import { expect } from "@open-wc/testing";

import {
  clearCfsWindowValidity,
  clearSessionDateBoundsValidity,
  parseLocalDate,
  validateCfsWindow,
  validateEventDates,
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
    expect(parseLocalDate("2025-03-25T10:00")).to.be.instanceOf(Date);
    expect(parseLocalDate("")).to.equal(null);
    expect(parseLocalDate("invalid")).to.equal(null);
  });

  it("validates event start and end dates", () => {
    const startsInput = document.createElement("input");
    const endsInput = document.createElement("input");
    stubValidityUi(startsInput);
    stubValidityUi(endsInput);

    endsInput.value = "2025-03-25T12:00";
    expect(
      validateEventDates({
        startsInput,
        endsInput,
        allowPastDates: true,
      }),
    ).to.equal(false);
    expect(startsInput.validationMessage).to.equal("Start date is required when end date is set.");

    startsInput.value = "2025-03-25T10:00";
    endsInput.value = "2025-03-25T09:00";
    expect(
      validateEventDates({
        startsInput,
        endsInput,
        allowPastDates: true,
      }),
    ).to.equal(false);
    expect(endsInput.validationMessage).to.equal("End date must be after start date.");

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
    expect(endsInput.validationMessage).to.equal("End date cannot be in the future.");

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
    const form = document.createElement("form");
    const timezoneInput = document.createElement("input");
    const startsInput = document.createElement("input");
    const endsInput = document.createElement("input");
    let dateSectionCalls = 0;

    timezoneInput.name = "timezone";
    timezoneInput.value = "UTC";
    startsInput.value = "2020-03-25T10:00";
    endsInput.value = "2020-03-25T12:00";

    form.append(timezoneInput, startsInput, endsInput);
    document.body.append(form);
    stubValidityUi(startsInput);
    stubValidityUi(endsInput);

    expect(
      validateEventDates({
        startsInput,
        endsInput,
        onDateSection: () => {
          dateSectionCalls += 1;
        },
      }),
    ).to.equal(false);
    expect(startsInput.validationMessage).to.equal("Start date cannot be in the past.");
    expect(dateSectionCalls).to.equal(1);

    startsInput.value = "2025-03-25T10:00";
    endsInput.value = "2025-03-25T12:00";
    startsInput.setCustomValidity("");
    endsInput.setCustomValidity("");

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
    expect(endsInput.validationMessage).to.equal("End date cannot be in the future.");
    expect(dateSectionCalls).to.equal(2);
  });

  it("clears and validates cfs window constraints", () => {
    const cfsEnabledInput = document.createElement("input");
    const cfsStartsInput = document.createElement("input");
    const cfsEndsInput = document.createElement("input");
    const eventStartsInput = document.createElement("input");

    [cfsStartsInput, cfsEndsInput, eventStartsInput].forEach(stubValidityUi);

    cfsStartsInput.setCustomValidity("old");
    cfsEndsInput.setCustomValidity("old");
    clearCfsWindowValidity({ cfsStartsInput, cfsEndsInput });
    expect(cfsStartsInput.validationMessage).to.equal("");
    expect(cfsEndsInput.validationMessage).to.equal("");

    cfsEnabledInput.value = "true";
    expect(
      validateCfsWindow({
        cfsEnabledInput,
        cfsStartsInput,
        cfsEndsInput,
        eventStartsInput,
      }),
    ).to.equal(false);
    expect(eventStartsInput.validationMessage).to.equal("Event start date is required when CFS is enabled.");

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
    expect(cfsEndsInput.validationMessage).to.equal("CFS close date must be after CFS open date.");

    cfsEndsInput.value = "2025-03-25T12:00";
    expect(
      validateCfsWindow({
        cfsEnabledInput,
        cfsStartsInput,
        cfsEndsInput,
        eventStartsInput,
      }),
    ).to.equal(false);
    expect(cfsEndsInput.validationMessage).to.equal("CFS close date must be before the event start date.");

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
    const cfsEnabledInput = document.createElement("input");
    const cfsStartsInput = document.createElement("input");
    const cfsEndsInput = document.createElement("input");
    const eventStartsInput = document.createElement("input");
    let cfsSectionCalls = 0;

    cfsEnabledInput.value = "true";
    eventStartsInput.value = "2025-03-25T12:00";
    cfsStartsInput.value = "2025-03-25T12:00";
    cfsEndsInput.value = "2025-03-25T12:30";

    [cfsStartsInput, cfsEndsInput, eventStartsInput].forEach(stubValidityUi);

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
    expect(cfsStartsInput.validationMessage).to.equal("CFS open date must be before the event start date.");
    expect(cfsSectionCalls).to.equal(1);
  });

  it("clears and validates session date bounds", () => {
    document.body.innerHTML = `
      <form id="sessions-form">
        <input name="sessions[0][starts_at]" value="2025-03-25T09:00" />
        <input name="sessions[0][ends_at]" value="2025-03-25T11:00" />
        <input name="sessions[1][starts_at]" value="2025-03-25T13:00" />
        <input name="sessions[1][ends_at]" value="2025-03-25T12:00" />
      </form>
    `;

    const sessionForm = document.getElementById("sessions-form");
    const inputs = Array.from(sessionForm.querySelectorAll("input"));
    inputs.forEach(stubValidityUi);
    inputs.forEach((input) => input.setCustomValidity("stale"));

    clearSessionDateBoundsValidity({ sessionForm });
    expect(inputs.every((input) => input.validationMessage === "")).to.equal(true);

    expect(
      validateSessionDateBounds({
        eventStartsAt: new Date("2025-03-25T10:00:00"),
        eventEndsAt: new Date("2025-03-25T18:00:00"),
        sessionForm,
      }),
    ).to.equal(false);
    expect(inputs[0].validationMessage).to.equal("Session start cannot be before the event start.");

    inputs[0].value = "2025-03-25T10:30";
    inputs[1].value = "2025-03-25T11:00";

    expect(
      validateSessionDateBounds({
        eventStartsAt: new Date("2025-03-25T10:00:00"),
        eventEndsAt: new Date("2025-03-25T18:00:00"),
        sessionForm,
      }),
    ).to.equal(false);
    expect(inputs[3].validationMessage).to.equal("Session end must be after the session start.");

    inputs[2].value = "2025-03-25T13:00";
    inputs[3].value = "2025-03-25T14:00";

    expect(
      validateSessionDateBounds({
        eventStartsAt: new Date("2025-03-25T10:00:00"),
        eventEndsAt: new Date("2025-03-25T18:00:00"),
        sessionForm,
      }),
    ).to.equal(true);
  });

  it("reports sessions that end after the event and switches back to the sessions section", () => {
    document.body.innerHTML = `
      <form id="sessions-form">
        <input name="sessions[0][starts_at]" value="2025-03-25T16:00" />
        <input name="sessions[0][ends_at]" value="2025-03-25T19:00" />
      </form>
    `;

    const sessionForm = document.getElementById("sessions-form");
    const inputs = Array.from(sessionForm.querySelectorAll("input"));
    let sessionsSectionCalls = 0;

    inputs.forEach(stubValidityUi);

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
    expect(inputs[1].validationMessage).to.equal("Session end cannot be after the event end.");
    expect(sessionsSectionCalls).to.equal(1);
  });
});
