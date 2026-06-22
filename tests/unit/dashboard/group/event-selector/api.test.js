import { expect } from "@open-wc/testing";

import {
  requestEventSelectorEvents,
} from "/static/js/dashboard/group/event-selector/api.js";

const mockEventSearchFetch = (response) => {
  const calls = [];
  const eventSearchFetch = async (...args) => {
    calls.push(args);
    return response;
  };
  return { calls, eventSearchFetch };
};

describe("event selector api", () => {
  it("requests event selector events with search filters", async () => {
    // The API helper owns fetch and response normalization for selector searches.
    const fetchMock = mockEventSearchFetch({
      headers: new Headers(),
      ok: true,
      async json() {
        return {
          events: [{ event_id: "event-1" }],
        };
      },
    });

    const events = await requestEventSelectorEvents(
      {
        allianceName: "goup",
        dateFrom: "2026-01-01",
        groupSlug: "platform-engineering",
        query: "platform",
        sortDirection: "desc",
      },
      fetchMock.eventSearchFetch,
    );

    expect(events).to.deep.equal([{ event_id: "event-1" }]);
    expect(fetchMock.calls[0][0]).to.include("/explore/events/search?");
    expect(fetchMock.calls[0][0]).to.include("alliance%5B%5D=goup");
    expect(fetchMock.calls[0][0]).to.include("group%5B%5D=platform-engineering");
    expect(fetchMock.calls[0][1].headers).to.deep.equal({
      Accept: "application/json",
    });
  });

  it("returns empty events when the payload has no event list", async () => {
    // Missing event arrays normalize to an empty result set.
    const fetchMock = mockEventSearchFetch({
      headers: new Headers(),
      ok: true,
      async json() {
        return {};
      },
    });

    expect(await requestEventSelectorEvents({}, fetchMock.eventSearchFetch)).to.deep.equal([]);
  });

  it("throws when event selector search fails", async () => {
    // Failed responses surface a clear selector search error.
    const fetchMock = mockEventSearchFetch({
      headers: new Headers(),
      ok: false,
      async json() {
        return {};
      },
    });

    let thrownError = null;
    try {
      await requestEventSelectorEvents({}, fetchMock.eventSearchFetch);
    } catch (error) {
      thrownError = error;
    }

    expect(thrownError?.message).to.equal("Failed to search events");
  });
});
