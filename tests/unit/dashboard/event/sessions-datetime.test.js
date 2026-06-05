import { expect } from "@open-wc/testing";

import {
  combineDateAndTime,
  extractDatePart,
  extractTimePart,
  formatDayHeader,
  formatTimeDisplay,
} from "/static/js/dashboard/event/sessions-datetime.js";

describe("sessions datetime", () => {
  it("extracts date and time parts from datetime-local strings", () => {
    // Split the datetime-local value used by session forms.
    const datetimeLocal = "2025-01-15T10:30";

    // The helpers return the date and time segments independently.
    expect(extractDatePart(datetimeLocal)).to.equal("2025-01-15");
    expect(extractTimePart(datetimeLocal)).to.equal("10:30");
    expect(formatTimeDisplay(datetimeLocal)).to.equal("10:30");
  });

  it("returns empty values for incomplete datetime inputs", () => {
    // Incomplete inputs can happen while a user is editing the form.
    const incompleteDatetime = "2025-01-15";

    // The helpers avoid returning partial time values.
    expect(extractDatePart("")).to.equal("");
    expect(extractTimePart(incompleteDatetime)).to.equal("");
    expect(combineDateAndTime("", "10:30")).to.equal("");
    expect(combineDateAndTime("2025-01-15", "")).to.equal("");
    expect(formatTimeDisplay("")).to.equal("");
  });

  it("combines date and time for datetime-local form values", () => {
    // Build the date and time values collected from split inputs.
    const date = "2025-01-15";
    const time = "10:30";

    // The helper creates the datetime-local value expected by the session payload.
    expect(combineDateAndTime(date, time)).to.equal("2025-01-15T10:30");
  });

  it("formats dates for session day headers", () => {
    // Build the date used by a session day group.
    const date = "2025-01-15";

    // The helper formats the day header with the current locale.
    expect(formatDayHeader(date)).to.equal(
      new Date(`${date}T12:00:00`).toLocaleDateString(undefined, {
        weekday: "long",
        year: "numeric",
        month: "long",
        day: "numeric",
      }),
    );
    expect(formatDayHeader("")).to.equal("");
  });
});
