import { expect } from "@open-wc/testing";

import {
  buildEventSearchUrl,
  buildPrimaryEventResults,
  buildSelectedEventFromDetails,
  findEventById,
  formatEventDate,
  getActiveEventResult,
  getDashboardSelectionContext,
  getEmptyEventSearchState,
  getEventSelectorKeyAction,
  getEventOptionState,
  getLoadedPrimaryEventSearchState,
  getLoadedQueryEventSearchState,
  getNoGroupEventSearchState,
  getSelectedEvent,
  normalizeEventId,
  parseEventTimestamp,
  resolveEventSearchContext,
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

  it("builds selected event state from copied details", () => {
    // Copied event details are normalized before updating component selection.
    expect(
      buildSelectedEventFromDetails({
        event_id: 12,
        name: "Cloud Native Malaga",
        starts_at: "1744466400",
        timezone: "Europe/Madrid",
      }),
    ).to.deep.equal({
      event_id: "12",
      name: "Cloud Native Malaga",
      starts_at: 1744466400,
      timezone: "Europe/Madrid",
    });
    expect(buildSelectedEventFromDetails(null)).to.equal(null);
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

  it("finds the selected event from selected state or results", () => {
    // Selected event state wins when it matches the selected id.
    expect(
      getSelectedEvent({
        selectedEvent: { event_id: "event-1", name: "Selected" },
        selectedEventId: "event-1",
        results: [{ event_id: "event-2", name: "Result" }],
      }),
    ).to.deep.equal({ event_id: "event-1", name: "Selected" });

    // Results are used when the selected event is stale.
    expect(
      getSelectedEvent({
        selectedEvent: { event_id: "event-1", name: "Stale" },
        selectedEventId: "event-2",
        results: [{ event_id: "event-2", name: "Result" }],
      }),
    ).to.deep.equal({ event_id: "event-2", name: "Result" });
  });

  it("finds events by normalized id", () => {
    // Matching accepts numeric and string ids.
    expect(normalizeEventId(12)).to.equal("12");
    expect(normalizeEventId(0)).to.equal("0");
    expect(normalizeEventId(null)).to.equal("");
    expect(findEventById([{ event_id: 12, name: "Event" }], "12")).to.deep.equal({
      event_id: 12,
      name: "Event",
    });
    expect(findEventById([{ event_id: 12 }], "")).to.equal(null);
  });

  it("gets the active event result when the index is valid", () => {
    // Active result lookup guards keyboard selection bounds.
    const results = [{ event_id: "event-1" }, { event_id: "event-2" }];

    expect(getActiveEventResult(results, 1)).to.deep.equal({ event_id: "event-2" });
    expect(getActiveEventResult(results, -1)).to.equal(null);
    expect(getActiveEventResult(results, 2)).to.equal(null);
  });

  it("builds event search URLs", () => {
    // The search URL includes only configured filters.
    expect(
      buildEventSearchUrl({
        communityName: "open-source",
        dateFrom: "2025-01-01",
        groupSlug: "maintainers",
        query: "platform",
        sortDirection: "desc",
      }),
    ).to.equal(
      [
        "/explore/events/search?limit=10",
        "date_from=2025-01-01",
        "sort_direction=desc",
        "ts_query=platform",
        "group%5B%5D=maintainers",
        "community%5B%5D=open-source",
      ].join("&"),
    );
  });

  it("gets dashboard selection context from closest or fallback content", () => {
    // Closest dashboard content wins when the selector is inside the page root.
    const fallbackRoot = document.createElement("div");
    fallbackRoot.innerHTML = `
      <div id="dashboard-content" data-community="fallback" data-group-slug="fallback-group">
      </div>
    `;
    const pageRoot = document.createElement("div");
    pageRoot.id = "dashboard-content";
    pageRoot.dataset.community = "cncf";
    pageRoot.dataset.groupSlug = "platform-engineering";
    const selector = document.createElement("event-selector");
    pageRoot.append(selector);

    expect(getDashboardSelectionContext(selector, fallbackRoot)).to.deep.equal({
      community: "cncf",
      groupSlug: "platform-engineering",
    });

    // A detached selector falls back to the configured dashboard content root.
    expect(
      getDashboardSelectionContext(document.createElement("event-selector"), fallbackRoot),
    ).to.deep.equal({
      community: "fallback",
      groupSlug: "fallback-group",
    });
  });

  it("resolves event search context from attributes or dashboard fallback", () => {
    // Explicit selector attributes win over dashboard fallback values.
    expect(
      resolveEventSearchContext({
        community: "cncf",
        dashboardSelection: { community: "fallback", groupSlug: "fallback-group" },
        groupSlug: "platform-engineering",
      }),
    ).to.deep.equal({
      communityName: "cncf",
      groupSlug: "platform-engineering",
    });

    // Missing attributes fall back to the dashboard selection context.
    expect(
      resolveEventSearchContext({
        dashboardSelection: { community: "fallback", groupSlug: "fallback-group" },
      }),
    ).to.deep.equal({
      communityName: "fallback",
      groupSlug: "fallback-group",
    });
  });

  it("builds deduplicated primary event results", () => {
    // Upcoming events are reversed before past events and duplicates are removed.
    const upcomingEvents = [
      { event_id: "upcoming-1" },
      { event_id: "shared" },
      { event_id: "upcoming-3" },
      { event_id: "upcoming-4" },
      { event_id: "upcoming-5" },
      { event_id: "extra-upcoming" },
    ];
    const pastEvents = [
      { event_id: "past-1" },
      { event_id: "shared" },
      { event_id: "past-3" },
      { event_id: "past-4" },
      { event_id: "past-5" },
    ];

    expect(buildPrimaryEventResults({ upcomingEvents, pastEvents, limit: 6 })).to.deep.equal([
      { event_id: "upcoming-5" },
      { event_id: "upcoming-4" },
      { event_id: "upcoming-3" },
      { event_id: "shared" },
      { event_id: "upcoming-1" },
      { event_id: "past-1" },
    ]);
  });

  it("returns empty search state defaults", () => {
    // Empty search state resets result navigation and errors.
    expect(getEmptyEventSearchState()).to.deep.equal({
      activeIndex: -1,
      error: "",
      results: [],
    });
  });

  it("builds event selector search state patches", () => {
    // State patches keep selector assignment logic outside the component.
    const primaryResults = [{ event_id: "event-1" }];
    expect(getNoGroupEventSearchState()).to.deep.equal({
      _activeIndex: -1,
      _error: "",
      _loading: false,
      _primaryResults: [],
      _results: [],
    });
    expect(getLoadedPrimaryEventSearchState(primaryResults)).to.deep.equal({
      _activeIndex: -1,
      _error: "",
      _hasFetched: true,
      _loading: false,
      _results: primaryResults,
    });
    expect(
      getLoadedQueryEventSearchState([
        { event_id: "event-1" },
        { event_id: "event-1" },
        { event_id: "event-2" },
      ]),
    ).to.deep.equal({
      _activeIndex: -1,
      _hasFetched: true,
      _results: [{ event_id: "event-1" }, { event_id: "event-2" }],
    });
  });

  it("returns event option visual state", () => {
    // Selected state takes precedence over active hover state.
    expect(
      getEventOptionState({
        activeIndex: 0,
        event: { event_id: "event-1" },
        index: 0,
        selectedEventId: "event-1",
      }),
    ).to.deep.equal({ isSelected: true, statusClass: "bg-stone-100" });
    expect(
      getEventOptionState({
        activeIndex: 0,
        event: { event_id: "event-2" },
        index: 0,
        selectedEventId: "event-1",
      }),
    ).to.deep.equal({ isSelected: false, statusClass: "bg-stone-50" });
  });

  it("resolves keyboard actions for result navigation", () => {
    // Arrow keys delegate index movement to the provided navigation helper.
    const getNextIndex = (...args) => args.join(":");
    expect(
      getEventSelectorKeyAction({
        activeIndex: -1,
        getNextIndex,
        isEscape: false,
        key: "ArrowDown",
        resultsLength: 3,
      }),
    ).to.deep.equal({
      action: "highlight",
      activeIndex: ":3:1",
      preventDefault: true,
    });
    expect(
      getEventSelectorKeyAction({
        activeIndex: 2,
        getNextIndex,
        isEscape: false,
        key: "Enter",
        resultsLength: 3,
      }).action,
    ).to.equal("select");
    expect(
      getEventSelectorKeyAction({
        activeIndex: 2,
        getNextIndex,
        isEscape: true,
        key: "Escape",
        resultsLength: 3,
      }).action,
    ).to.equal("close");
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
