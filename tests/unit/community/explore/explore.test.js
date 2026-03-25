import { expect } from "@open-wc/testing";

import { fetchData, updateResults } from "/static/js/community/explore/explore.js";

describe("explore helpers", () => {
  const originalFetch = globalThis.fetch;
  const originalSwal = globalThis.Swal;

  let alertCalls;

  beforeEach(() => {
    document.body.innerHTML = "";
    alertCalls = [];

    globalThis.Swal = {
      fire: (options) => {
        alertCalls.push(options);
        return Promise.resolve({ isConfirmed: true });
      },
    };
  });

  afterEach(() => {
    document.body.innerHTML = "";
    globalThis.fetch = originalFetch;
    globalThis.Swal = originalSwal;
  });

  it("updates the results container html", () => {
    document.body.innerHTML = `<div id="results"></div>`;

    updateResults("<p>Updated</p>");

    expect(document.getElementById("results")?.innerHTML).to.equal("<p>Updated</p>");
  });

  it("fetches explore data as json", async () => {
    globalThis.fetch = async (url, options) => {
      expect(url).to.equal("/explore/events/search?kind=conference");
      expect(options).to.deep.equal({
        headers: { Accept: "application/json" },
      });

      return {
        ok: true,
        json: async () => ({ items: [1, 2, 3] }),
      };
    };

    const result = await fetchData("events", "kind=conference");

    expect(result).to.deep.equal({ items: [1, 2, 3] });
    expect(alertCalls).to.have.length(0);
  });

  it("shows an alert and throws when the request fails", async () => {
    globalThis.fetch = async () => {
      throw new Error("network error");
    };

    let thrownError = null;

    try {
      await fetchData("groups", "region=emea");
    } catch (error) {
      thrownError = error;
    }

    expect(thrownError?.message).to.equal("network error");
    expect(alertCalls).to.have.length(1);
    expect(alertCalls[0].text).to.equal("Something went wrong loading results. Please try again later.");
  });

  it("shows an alert and throws when the server responds with an error", async () => {
    globalThis.fetch = async () => ({
      ok: false,
      status: 500,
      text: async () => "Internal error",
    });

    let thrownError = null;

    try {
      await fetchData("groups", "region=emea");
    } catch (error) {
      thrownError = error;
    }

    expect(thrownError?.message).to.equal("Failed to fetch groups data (status 500)");
    expect(alertCalls).to.have.length(1);
    expect(alertCalls[0].text).to.equal("Something went wrong loading results. Please try again later.");
  });

  it("shows an alert and throws when the response body is not valid json", async () => {
    globalThis.fetch = async () => ({
      ok: true,
      json: async () => {
        throw new Error("invalid json");
      },
    });

    let thrownError = null;

    try {
      await fetchData("events", "kind=conference");
    } catch (error) {
      thrownError = error;
    }

    expect(thrownError?.message).to.equal("invalid json");
    expect(alertCalls).to.have.length(1);
    expect(alertCalls[0].text).to.equal("Something went wrong loading results. Please try again later.");
  });
});
