import { expect } from "@open-wc/testing";

import {
  fetchData,
  updateResults,
  updateResultsFromSummary,
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

  it("updates the results container text", () => {
    // Build the DOM fixture with results.
    document.body.innerHTML = `<div id="results"></div>`;

    // Replace the results markup with the fetched response.
    updateResults("<p>Updated</p>");

    // The results container receives text, not trusted markup.
    expect(document.getElementById("results")?.textContent).to.equal("<p>Updated</p>");
    expect(document.getElementById("results")?.innerHTML).to.equal(
      "&lt;p&gt;Updated&lt;/p&gt;",
    );
  });

  it("updates the results container from a declarative summary marker", () => {
    // Build the DOM fixture with results and swapped summary content.
    document.body.innerHTML = `
      <div id="results"></div>
      <div id="cards-list">
        <span data-results-summary class="hidden">1-10 of 20</span>
      </div>
    `;

    // Read the summary marker from the swapped content.
    updateResultsFromSummary(document.getElementById("cards-list"));

    // The results container receives the summary marker text.
    expect(document.getElementById("results")?.textContent).to.equal("1-10 of 20");
  });

  it("updates the results container after an HTMX swap", () => {
    // Build the DOM fixture with results and swapped summary content.
    document.body.innerHTML = `
      <div id="results"></div>
      <div id="cards-list">
        <span data-results-summary class="hidden">11-20 of 20</span>
      </div>
    `;

    // Dispatch the HTMX swap event from the swapped content root.
    document.getElementById("cards-list").dispatchEvent(
      new CustomEvent("htmx:afterSwap", { bubbles: true }),
    );

    // The initialized explore module syncs the summary after swaps.
    expect(document.getElementById("results")?.textContent).to.equal("11-20 of 20");
  });

  it("fetches explore data as json", async () => {
    // Mock the fetch response.
    fetchMock.setImpl(async (url, options) => {
      // The request asks the search endpoint for JSON.
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

    // The parsed JSON response is returned without showing an alert.
    expect(result).to.deep.equal({ items: [1, 2, 3] });
    expect(swal.calls).to.have.length(0);
  });

  it("shows an alert and throws when the request fails", async () => {
    // Mock the fetch response.
    fetchMock.setImpl(async () => {
      throw new Error("network error");
    });

    // Set up thrown error.
    let thrownError = null;

    // Run the fetch call that should throw.
    try {
      await fetchData("groups", "region=emea");
    } catch (error) {
      thrownError = error;
    }

    // The original network error is surfaced and the fallback alert is shown.
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

    // Set up thrown error.
    let thrownError = null;

    // Run the fetch call that should reject the error response.
    try {
      await fetchData("groups", "region=emea");
    } catch (error) {
      thrownError = error;
    }

    // The error response is reported with the status code and fallback alert.
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

    // Set up thrown error.
    let thrownError = null;

    // Run the fetch call that should reject invalid JSON.
    try {
      await fetchData("events", "kind=conference");
    } catch (error) {
      thrownError = error;
    }

    // The JSON parsing error is surfaced with the fallback alert.
    expect(thrownError?.message).to.equal("invalid json");
    expect(swal.calls).to.have.length(1);
    expect(swal.calls[0].text).to.equal(
      "Something went wrong loading results. Please try again later.",
    );
  });
});
