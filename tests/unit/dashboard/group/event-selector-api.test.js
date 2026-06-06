import { expect } from "@open-wc/testing";

import {
  requestEventSelectorEvents,
} from "/static/js/dashboard/group/event-selector-api.js";
import { mockFetch } from "/tests/unit/test-utils/network.js";

describe("event selector api", () => {
  let fetchMock;

  beforeEach(() => {
    fetchMock = mockFetch();
  });

  afterEach(() => {
    fetchMock.restore();
  });

  it("requests event selector events with search filters", async () => {
    // The API helper owns fetch and response normalization for selector searches.
    fetchMock.setImpl(async () => ({
      ok: true,
      async json() {
        return {
          events: [{ event_id: "event-1" }],
        };
      },
    }));

    const events = await requestEventSelectorEvents({
      communityName: "cncf",
      dateFrom: "2026-01-01",
      groupSlug: "platform-engineering",
      query: "platform",
      sortDirection: "desc",
    });

    expect(events).to.deep.equal([{ event_id: "event-1" }]);
    expect(fetchMock.calls[0][0]).to.include("/explore/events/search?");
    expect(fetchMock.calls[0][0]).to.include("community%5B%5D=cncf");
    expect(fetchMock.calls[0][0]).to.include("group%5B%5D=platform-engineering");
    expect(fetchMock.calls[0][1].headers).to.deep.equal({
      Accept: "application/json",
    });
  });

  it("returns empty events when the payload has no event list", async () => {
    // Missing event arrays normalize to an empty result set.
    fetchMock.setImpl(async () => ({
      ok: true,
      async json() {
        return {};
      },
    }));

    expect(await requestEventSelectorEvents({})).to.deep.equal([]);
  });

  it("throws when event selector search fails", async () => {
    // Failed responses surface a clear selector search error.
    fetchMock.setImpl(async () => ({
      ok: false,
      async json() {
        return {};
      },
    }));

    let thrownError = null;
    try {
      await requestEventSelectorEvents({});
    } catch (error) {
      thrownError = error;
    }

    expect(thrownError?.message).to.equal("Failed to search events");
  });
});
