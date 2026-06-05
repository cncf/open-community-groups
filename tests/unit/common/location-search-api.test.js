import { expect } from "@open-wc/testing";

import { searchNominatimLocations } from "/static/js/common/location-search-api.js";
import { mockFetch } from "/tests/unit/test-utils/network.js";

describe("location search api", () => {
  let fetchMock;

  beforeEach(() => {
    fetchMock = mockFetch();
  });

  afterEach(() => {
    fetchMock.restore();
  });

  it("searches Nominatim with browser-safe request headers", async () => {
    // Mock the fetch response.
    fetchMock.setImpl(async () => ({
      ok: true,
      async json() {
        return [{ place_id: 1, display_name: "Málaga, Andalusia, Spain" }];
      },
    }));

    // Search for a location with special characters.
    const results = await searchNominatimLocations("Málaga", new AbortController().signal);

    // The request uses the expected endpoint, query string, and headers.
    expect(fetchMock.calls).to.have.length(1);
    expect(fetchMock.calls[0][0]).to.include("q=M%C3%A1laga");
    expect(fetchMock.calls[0][0]).to.include("addressdetails=1");
    expect(fetchMock.calls[0][1].headers).to.deep.equal({
      Accept: "application/json",
    });
    expect(results).to.deep.equal([{ place_id: 1, display_name: "Málaga, Andalusia, Spain" }]);
  });

  it("throws a descriptive error for failed Nominatim responses", async () => {
    // Mock a failed Nominatim response.
    fetchMock.setImpl(async () => ({
      ok: false,
      status: 503,
    }));

    // Failed responses include the HTTP status in the thrown error.
    let error;
    try {
      await searchNominatimLocations("Broken", new AbortController().signal);
    } catch (err) {
      error = err;
    }

    expect(error.message).to.equal("HTTP error! status: 503");
  });
});
