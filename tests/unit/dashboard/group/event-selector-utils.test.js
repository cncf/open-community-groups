import { expect } from "@open-wc/testing";

import {
  formatEventDate,
  parseEventTimestamp,
  uniqueEventsById,
} from "/static/js/dashboard/group/event-selector-utils.js";

describe("event selector utils", () => {
  it("parses event timestamps safely", () => {
    // Build timestamp values from different payload shapes.
    const timestamp = 1744466400;

    // The helper returns finite timestamps and null for invalid values.
    expect(parseEventTimestamp(timestamp)).to.equal(timestamp);
    expect(parseEventTimestamp(String(timestamp))).to.equal(timestamp);
    expect(parseEventTimestamp(null)).to.equal(null);
    expect(parseEventTimestamp(undefined)).to.equal(null);
    expect(parseEventTimestamp("not-a-number")).to.equal(null);
  });

  it("deduplicates events by id while preserving events without ids", () => {
    // Build event payloads with duplicate ids and id-less placeholders.
    const events = [
      { event_id: "event-1", name: "First" },
      { event_id: "event-1", name: "Duplicate" },
      { name: "No id" },
      { event_id: "event-2", name: "Second" },
    ];

    // The helper keeps the first event for each id.
    expect(uniqueEventsById(events).map((event) => event.name)).to.deep.equal([
      "First",
      "No id",
      "Second",
    ]);
  });

  it("formats event dates with a fallback timezone", () => {
    // Build an event payload with a UTC timestamp.
    const event = {
      starts_at: 1744466400,
      timezone: "Europe/Madrid",
    };

    // The helper formats a readable date label.
    const formattedDate = formatEventDate(event);
    expect(formattedDate.isPlaceholder).to.equal(false);
    expect(formattedDate.text).to.include("April 12, 2025");
    expect(formattedDate.text).to.include("4:00 PM");
  });

  it("returns placeholder and fallback date states", () => {
    // Missing timestamps render as placeholders.
    expect(formatEventDate(null)).to.deep.equal({ text: "TBD", isPlaceholder: true });
    expect(formatEventDate({ starts_at: "" })).to.deep.equal({
      text: "TBD",
      isPlaceholder: true,
    });

    // Invalid timezones fall back to a non-placeholder error label.
    expect(formatEventDate({ starts_at: 1744466400, timezone: "Invalid/Zone" })).to.deep.equal({
      text: "-",
      isPlaceholder: false,
    });
  });
});
