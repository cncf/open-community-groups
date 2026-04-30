import { expect } from "@open-wc/testing";

import "/static/js/dashboard/event/sessions.js";
import { resetDom } from "/tests/unit/test-utils/dom.js";
import { mountLitComponent, useMountedElementsCleanup } from "/tests/unit/test-utils/lit.js";

describe("sessions-section", () => {
  const originalHtmx = globalThis.htmx;
  const SessionsSection = customElements.get("sessions-section");

  useMountedElementsCleanup("sessions-section");

  let htmxOnCalls;

  beforeEach(() => {
    resetDom();
    htmxOnCalls = [];
    SessionsSection._cleanupBound = false;
    globalThis.htmx = {
      on(eventName, handler) {
        htmxOnCalls.push({ eventName, handler });
      },
    };
  });

  afterEach(() => {
    SessionsSection._cleanupBound = false;
    globalThis.htmx = originalHtmx;
  });

  const renderSessionsSection = async (properties = {}) => {
    return mountLitComponent("sessions-section", properties);
  };

  it("parses and initializes session payloads from server attributes", async () => {
    const element = await renderSessionsSection({
      timezone: "America/New_York",
      sessions: JSON.stringify({
        day_one: [
          {
            name: "Opening keynote",
            starts_at: 1735689600,
            ends_at: 1735693200,
            meeting_provider: "zoom",
          },
        ],
        day_two: [
          {
            name: "Community panel",
            starts_at: 1735776000,
            ends_at: 1735779600,
          },
        ],
      }),
      sessionKinds: JSON.stringify([{ session_kind_id: "talk", display_name: "Talk" }]),
      approvedSubmissions: JSON.stringify([{ cfs_submission_id: 10 }]),
      meetingMaxParticipants: JSON.stringify({ zoom: 100 }),
    });

    expect(element.sessions).to.have.length(2);
    expect(element.sessions[0]).to.include({
      id: 0,
      name: "Opening keynote",
      meeting_provider_id: "zoom",
      starts_at: "2024-12-31T19:00",
      ends_at: "2024-12-31T20:00",
    });
    expect(element.sessions[1]).to.include({
      id: 1,
      name: "Community panel",
      starts_at: "2025-01-01T19:00",
      ends_at: "2025-01-01T20:00",
    });
    expect(element.sessionKinds).to.deep.equal([{ session_kind_id: "talk", display_name: "Talk" }]);
    expect(element.approvedSubmissions).to.deep.equal([{ cfs_submission_id: 10 }]);
    expect(element.meetingMaxParticipants).to.deep.equal({ zoom: 100 });
  });

  it("falls back safely when server attributes contain invalid payloads", async () => {
    const element = await renderSessionsSection({
      sessions: "{invalid",
      sessionKinds: "{invalid",
      approvedSubmissions: "{invalid",
      meetingMaxParticipants: "[invalid",
    });

    expect(element.sessions).to.deep.equal([]);
    expect(element.sessionKinds).to.deep.equal([]);
    expect(element.approvedSubmissions).to.deep.equal([]);
    expect(element.meetingMaxParticipants).to.deep.equal({});
  });

  it("computes event days, groups sessions, and isolates out-of-range entries", async () => {
    const element = await renderSessionsSection({
      eventStartsAt: "2025-01-31T09:00",
      eventEndsAt: "2025-02-02T17:00",
    });

    element.sessions = [
      { id: 4, name: "Day two afternoon", starts_at: "2025-02-01T15:00", ends_at: "2025-02-01T16:00" },
      { id: 2, name: "Day one opening", starts_at: "2025-01-31T09:00", ends_at: "2025-01-31T10:00" },
      { id: 3, name: "Day two morning", starts_at: "2025-02-01T09:00", ends_at: "2025-02-01T10:00" },
      { id: 5, name: "Outside range", starts_at: "2025-02-03T09:00", ends_at: "2025-02-03T10:00" },
    ];

    const days = element._computeEventDays();
    const grouped = element._groupSessionsByDay();
    const outOfRange = element._getOutOfRangeSessions(days);

    expect(days).to.deep.equal(["2025-01-31", "2025-02-01", "2025-02-02"]);
    expect(grouped.get("2025-01-31").map((session) => session.name)).to.deep.equal(["Day one opening"]);
    expect(grouped.get("2025-02-01").map((session) => session.name)).to.deep.equal([
      "Day two morning",
      "Day two afternoon",
    ]);
    expect(grouped.get("2025-02-02")).to.deep.equal([]);
    expect(outOfRange.map((session) => session.name)).to.deep.equal(["Outside range"]);
  });

  it("renders hidden inputs for automatic meetings and speaker payloads", async () => {
    const element = await renderSessionsSection({
      sessions: [
        {
          id: 1,
          session_id: "abc",
          name: "Linked session",
          kind: "talk",
          starts_at: "2025-05-10T10:00",
          ends_at: "2025-05-10T11:00",
          location: "Main hall",
          description: "Should be cleared",
          cfs_submission_id: "sub-1",
          meeting_requested: true,
          meeting_provider_id: "",
          meeting_join_instructions: "Automatic instructions should clear",
          meeting_join_url: "https://join.example",
          meeting_recording_url: "https://recording.example",
          speakers: [{ user_id: "speaker-1", featured: true }],
        },
        {
          id: 2,
          session_id: "def",
          name: "Manual session",
          kind: "workshop",
          starts_at: "2025-05-10T12:00",
          ends_at: "2025-05-10T13:00",
          location: "Room B",
          description: "Keep this description",
          cfs_submission_id: "",
          meeting_requested: false,
          meeting_provider_id: "teams",
          meeting_join_instructions: "Manual instructions",
          meeting_join_url: "https://teams.example",
          meeting_recording_url: "https://recording.example/manual",
          speakers: [{ user_id: "speaker-2", featured: true }],
        },
      ],
    });

    await element.updateComplete;

    expect(element.querySelector('input[name="sessions[0][description]"]')?.value).to.equal("");
    expect(element.querySelector('input[name="sessions[0][meeting_join_instructions]"]')?.value).to.equal("");
    expect(element.querySelector('input[name="sessions[0][meeting_join_url]"]')?.value).to.equal("");
    expect(element.querySelector('input[name="sessions[0][meeting_recording_url]"]')?.value).to.equal(
      "https://recording.example",
    );
    expect(element.querySelector('input[name="sessions[0][meeting_provider_id]"]')?.value).to.equal("zoom");
    expect(element.querySelector('input[name="sessions[0][speakers][0][user_id]"]')).to.equal(null);

    expect(element.querySelector('input[name="sessions[1][description]"]')?.value).to.equal(
      "Keep this description",
    );
    expect(element.querySelector('input[name="sessions[1][meeting_join_instructions]"]')?.value).to.equal(
      "Manual instructions",
    );
    expect(element.querySelector('input[name="sessions[1][meeting_provider_id]"]')?.value).to.equal("teams");
    expect(element.querySelector('input[name="sessions[1][speakers][0][user_id]"]')?.value).to.equal(
      "speaker-2",
    );
    expect(element.querySelector('input[name="sessions[1][speakers][0][featured]"]')?.value).to.equal("true");
  });

  it("adds new sessions with the next numeric id and updates existing ones in place", async () => {
    const element = await renderSessionsSection();
    element.sessions = [
      { id: 2, name: "Opening", starts_at: "2025-05-10T09:00" },
      { id: 7, name: "Panel", starts_at: "2025-05-10T10:00" },
    ];

    element._handleSessionSaved({
      detail: {
        isNew: true,
        session: { name: "Workshop", starts_at: "2025-05-10T11:00" },
      },
    });

    expect(element.sessions.map((session) => session.id)).to.deep.equal([2, 7, 8]);
    expect(element.sessions.at(-1)).to.include({
      id: 8,
      name: "Workshop",
      starts_at: "2025-05-10T11:00",
    });

    element._handleSessionSaved({
      detail: {
        isNew: false,
        session: { id: 7, name: "Updated panel", starts_at: "2025-05-10T10:30" },
      },
    });

    expect(element.sessions).to.deep.equal([
      { id: 2, name: "Opening", starts_at: "2025-05-10T09:00" },
      { id: 7, name: "Updated panel", starts_at: "2025-05-10T10:30" },
      { id: 8, name: "Workshop", starts_at: "2025-05-10T11:00" },
    ]);
  });

  it("starts session ids at zero when adding the first saved session", async () => {
    const element = await renderSessionsSection();
    element.sessions = [];

    element._handleSessionSaved({
      detail: {
        isNew: true,
        session: { name: "First session", starts_at: "2025-05-10T09:00" },
      },
    });

    expect(element.sessions).to.deep.equal([{ id: 0, name: "First session", starts_at: "2025-05-10T09:00" }]);
  });

  it("registers htmx cleanup that removes empty session buckets", async () => {
    await renderSessionsSection();

    expect(htmxOnCalls).to.have.length(1);
    expect(htmxOnCalls[0].eventName).to.equal("htmx:configRequest");

    const params = {
      "sessions[0][name]": "",
      "sessions[0][meeting_requested]": "false",
      "sessions[0][capacity]": "0",
      "sessions[1][name]": "Closing keynote",
      "sessions[1][meeting_requested]": "false",
    };

    htmxOnCalls[0].handler({
      detail: {
        parameters: params,
      },
    });

    expect(params).to.deep.equal({
      "sessions[1][name]": "Closing keynote",
      "sessions[1][meeting_requested]": "false",
    });
  });

  it("keeps session buckets that still contain non-empty array values during htmx cleanup", async () => {
    await renderSessionsSection();

    const params = {
      "sessions[0][name]": "",
      "sessions[0][meeting_requested]": "false",
      "sessions[0][meeting_hosts]": ["host-1"],
      "sessions[1][name]": "",
      "sessions[1][meeting_requested]": "false",
    };

    htmxOnCalls[0].handler({
      detail: {
        parameters: params,
      },
    });

    expect(params).to.deep.equal({
      "sessions[0][name]": "",
      "sessions[0][meeting_requested]": "false",
      "sessions[0][meeting_hosts]": ["host-1"],
    });
  });
});
