import { expect } from "@open-wc/testing";

import {
  computeEventDays,
  computeSessionScenario,
  createEmptySession,
  getNextSessionId,
  getOutOfRangeSessions,
  getSortedSessions,
  groupSessionsByDay,
} from "/static/js/dashboard/event/sessions/schedule.js";

describe("sessions schedule", () => {
  it("creates empty sessions with default form values", () => {
    // Build an empty session using the next generated id.
    const session = createEmptySession(4);

    // The helper fills all known session fields.
    expect(session).to.include({
      id: 4,
      name: "",
      description: "",
      kind: "",
      starts_at: "",
      ends_at: "",
      meeting_requested: false,
      meeting_recording_published: false,
    });
    expect(session.meeting_recording_raw_urls).to.deep.equal([]);
    expect(session.meeting_hosts).to.deep.equal([]);
    expect(session.speakers).to.deep.equal([]);
  });

  it("computes schedule scenarios and event days", () => {
    // Build single-day and multi-day event ranges.
    const singleDayStart = "2025-01-31T09:00";
    const singleDayEnd = "2025-01-31T17:00";
    const multiDayEnd = "2025-02-02T17:00";

    // The helpers identify the scenario and expand multi-day ranges.
    expect(computeSessionScenario("", "")).to.equal("no-dates");
    expect(computeSessionScenario(singleDayStart, singleDayEnd)).to.equal("single-day");
    expect(computeSessionScenario(singleDayStart, multiDayEnd)).to.equal("multi-day");
    expect(computeEventDays(singleDayStart, multiDayEnd)).to.deep.equal([
      "2025-01-31",
      "2025-02-01",
      "2025-02-02",
    ]);
  });

  it("sorts, groups, and isolates out-of-range sessions", () => {
    // Build sessions across two event days and one out-of-range day.
    const sessions = [
      { id: 4, name: "Day two afternoon", starts_at: "2025-02-01T15:00" },
      { id: 2, name: "Day one opening", starts_at: "2025-01-31T09:00" },
      { id: 3, name: "Day two morning", starts_at: "2025-02-01T09:00" },
      { id: 5, name: "Outside range", starts_at: "2025-02-03T09:00" },
    ];
    const days = ["2025-01-31", "2025-02-01", "2025-02-02"];

    // The helpers keep each list ordered by start time.
    expect(getSortedSessions(sessions).map((session) => session.name)).to.deep.equal([
      "Day one opening",
      "Day two morning",
      "Day two afternoon",
      "Outside range",
    ]);
    expect(
      groupSessionsByDay(sessions, days)
        .get("2025-02-01")
        .map((session) => session.name),
    ).to.deep.equal(["Day two morning", "Day two afternoon"]);
    expect(getOutOfRangeSessions(sessions, days).map((session) => session.name)).to.deep.equal([
      "Outside range",
    ]);
  });

  it("generates the next numeric session id", () => {
    // Build existing sessions with sparse ids.
    const sessions = [{ id: 2 }, { id: 7 }, { id: "ignored" }];

    // The helper starts at zero and increments from the highest finite id.
    expect(getNextSessionId([])).to.equal(0);
    expect(getNextSessionId(sessions)).to.equal(8);
  });
});
