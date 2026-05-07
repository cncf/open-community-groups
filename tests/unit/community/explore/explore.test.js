import { expect } from "@open-wc/testing";

import { fetchData, updateResults } from "/static/js/community/explore/explore.js";
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
    document.body.innerHTML = `<div id="results"></div>`;

    updateResults("<p>Updated</p>");

    expect(document.getElementById("results")?.innerHTML).to.equal("<p>Updated</p>");
  });

  it("fetches explore data as json", async () => {
    fetchMock.setImpl(async (url, options) => {
      expect(url).to.equal("/explore/events/search?kind=conference");
      expect(options.headers).to.be.instanceOf(Headers);
      expect(options.headers.get("Accept")).to.equal("application/json");
      expect(options.headers.get("X-OCG-Fetch")).to.equal("true");

      return {
        ok: true,
        json: async () => ({ items: [1, 2, 3] }),
      };
    });

    const result = await fetchData("events", "kind=conference");

    expect(result).to.deep.equal({ items: [1, 2, 3] });
    expect(swal.calls).to.have.length(0);
  });

  it("shows an alert and throws when the request fails", async () => {
    fetchMock.setImpl(async () => {
      throw new Error("network error");
    });

    let thrownError = null;

    try {
      await fetchData("groups", "region=emea");
    } catch (error) {
      thrownError = error;
    }

    expect(thrownError?.message).to.equal("network error");
    expect(swal.calls).to.have.length(1);
    expect(swal.calls[0].text).to.equal("Something went wrong loading results. Please try again later.");
  });

  it("shows an alert and throws when the server responds with an error", async () => {
    fetchMock.setImpl(async () => ({
      ok: false,
      status: 500,
      text: async () => "Internal error",
    }));

    let thrownError = null;

    try {
      await fetchData("groups", "region=emea");
    } catch (error) {
      thrownError = error;
    }

    expect(thrownError?.message).to.equal("Failed to fetch groups data (status 500)");
    expect(swal.calls).to.have.length(1);
    expect(swal.calls[0].text).to.equal("Something went wrong loading results. Please try again later.");
  });

  it("shows an alert and throws when the response body is not valid json", async () => {
    fetchMock.setImpl(async () => ({
      ok: true,
      json: async () => {
        throw new Error("invalid json");
      },
    }));

    let thrownError = null;

    try {
      await fetchData("events", "kind=conference");
    } catch (error) {
      thrownError = error;
    }

    expect(thrownError?.message).to.equal("invalid json");
    expect(swal.calls).to.have.length(1);
    expect(swal.calls[0].text).to.equal("Something went wrong loading results. Please try again later.");
  });
});
