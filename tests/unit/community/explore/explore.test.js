import { expect } from "@open-wc/testing";

import {
  fetchData,
  updateResults,
} from "/static/js/community/explore/explore.js";
import { resetDom } from "/tests/unit/test-utils/dom.js";
import { mockSwal } from "/tests/unit/test-utils/globals.js";
import { mockFetch } from "/tests/unit/test-utils/network.js";

describe("explore helpers", () => {
  let fetchMock;
  let swal;

  beforeEach(() => {
    resetDom();
    swal = mockSwal();
    fetchMock = mockFetch();
  });

  afterEach(() => {
    resetDom();
    fetchMock.restore();
    swal.restore();
  });

  it("updates the results container html", () => {
    // Build the DOM fixture with results.
    document.body.innerHTML = `<div id="results"></div>`;

    // Replace the results markup with the fetched response.
    updateResults("<p>Updated</p>");

    // Updates the results container html.
    expect(document.getElementById("results")?.innerHTML).to.equal(
      "<p>Updated</p>",
    );
  });

  it("fetches explore data as json", async () => {
    // Mock the fetch response.
    fetchMock.setImpl(async (url, options) => {
      // Fetches explore data as json.
      expect(url).to.equal("/explore/events/search?kind=conference");
      expect(options.headers).to.be.instanceOf(Headers);
      expect(options.headers.get("Accept")).to.equal("application/json");
      expect(options.headers.get("X-OCG-Fetch")).to.equal("true");

      // Return the value used by the assertion.
      return {
        ok: true,
        json: async () => ({ items: [1, 2, 3] }),
      };
    });

    // Capture the async result.
    const result = await fetchData("events", "kind=conference");

    // Fetches explore data as json.
    expect(result).to.deep.equal({ items: [1, 2, 3] });
    expect(swal.calls).to.have.length(0);
  });

  it("shows an alert and throws when the request fails", async () => {
    // Mock the fetch response.
    fetchMock.setImpl(async () => {
      throw new Error("network error");
    });

    // Set up shows an alert and throws when the request fails.
    let thrownError = null;

    // Set up shows an alert and throws when the request fails.
    try {
      await fetchData("groups", "region=emea");
    } catch (error) {
      thrownError = error;
    }

    // Shows an alert and throws when the request fails.
    expect(thrownError?.message).to.equal("network error");
    expect(swal.calls).to.have.length(1);
    expect(swal.calls[0].text).to.equal(
      "Something went wrong loading results. Please try again later.",
    );
  });

  it("shows an alert and throws when the server responds with an error", async () => {
    // Mock the fetch response.
    fetchMock.setImpl(async () => ({
      ok: false,
      status: 500,
      text: async () => "Internal error",
    }));

    // Set up shows an alert and throws when the server responds with an error.
    let thrownError = null;

    // Set up shows an alert and throws when the server responds with an error.
    try {
      await fetchData("groups", "region=emea");
    } catch (error) {
      thrownError = error;
    }

    // Shows an alert and throws when the server responds with an error.
    expect(thrownError?.message).to.equal(
      "Failed to fetch groups data (status 500)",
    );
    expect(swal.calls).to.have.length(1);
    expect(swal.calls[0].text).to.equal(
      "Something went wrong loading results. Please try again later.",
    );
  });

  it("shows an alert and throws when the response body is not valid json", async () => {
    // Mock the fetch response.
    fetchMock.setImpl(async () => ({
      ok: true,
      json: async () => {
        throw new Error("invalid json");
      },
    }));

    // Set up shows an alert and throws when the response body is not valid json.
    let thrownError = null;

    // Set up shows an alert and throws when the response body is not valid json.
    try {
      await fetchData("events", "kind=conference");
    } catch (error) {
      thrownError = error;
    }

    // Shows an alert and throws when the response body is not valid json.
    expect(thrownError?.message).to.equal("invalid json");
    expect(swal.calls).to.have.length(1);
    expect(swal.calls[0].text).to.equal(
      "Something went wrong loading results. Please try again later.",
    );
  });
});
