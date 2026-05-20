import { expect } from "@open-wc/testing";

import { ocgFetch } from "/static/js/common/fetch.js";
import {
  COMMIT_SHA_HEADER,
  REFRESH_HEADER,
  reloadIfDeploymentChanged,
  resetDeploymentReloadState,
  setDeploymentReloadHandler,
} from "/static/js/common/deployment-version.js";
import { mockFetch } from "/tests/unit/test-utils/network.js";

// Set loaded commit sha for the test.
const setLoadedCommitSha = (commitSha) => {
  document.head.innerHTML = `<meta name="ocg-commit-sha" content="${commitSha}">`;
};

// Return settled state after current task for the test.
const getSettledStateAfterCurrentTask = (promise) =>
  Promise.race([
    promise.then(
      () => "resolved",
      () => "rejected",
    ),
    new Promise((resolve) => {
      setTimeout(() => resolve("pending"), 0);
    }),
  ]);

describe("ocgFetch", () => {
  const originalDateNow = Date.now;
  let fetchMock;

  beforeEach(() => {
    document.head.innerHTML = "";
    fetchMock = mockFetch();
  });

  afterEach(() => {
    Date.now = originalDateNow;
    document.head.innerHTML = "";
    fetchMock.restore();
    resetDeploymentReloadState();
  });

  it("adds OCG fetch and commit SHA headers for same-origin requests", async () => {
    // Mock the fetch response.
    setLoadedCommitSha("abc123");
    fetchMock.setImpl(async (_url, options) => {
      // Adds OCG fetch and commit SHA headers for same-origin requests.
      expect(options.headers).to.be.instanceOf(Headers);
      expect(options.headers.get("X-OCG-Fetch")).to.equal("true");
      expect(options.headers.get(COMMIT_SHA_HEADER)).to.equal("abc123");

      // Return the value used by the assertion.
      return {
        headers: new Headers(),
        ok: true,
        status: 200,
      };
    });

    // Execute the OCG fetch helper.
    await ocgFetch("/test");

    // The request uses the expected endpoint and options.
    expect(fetchMock.calls).to.have.length(1);
  });

  it("does not add OCG headers for cross-origin requests", async () => {
    // Mock the fetch response.
    setLoadedCommitSha("abc123");
    fetchMock.setImpl(async (_url, options) => {
      // Does not add OCG headers for cross-origin requests.
      expect(options.headers).to.be.instanceOf(Headers);
      expect(options.headers.get("X-OCG-Fetch")).to.equal(null);
      expect(options.headers.get(COMMIT_SHA_HEADER)).to.equal(null);

      // Return the value used by the assertion.
      return {
        headers: new Headers(),
        ok: true,
        status: 200,
      };
    });

    // Execute the OCG fetch helper.
    await ocgFetch("https://example.test/api");

    // The request uses the expected endpoint and options.
    expect(fetchMock.calls).to.have.length(1);
  });

  it("preserves HTMX headers while adding OCG fetch headers for same-origin requests", async () => {
    // Mock the fetch response.
    setLoadedCommitSha("abc123");
    fetchMock.setImpl(async (_url, options) => {
      // Preserves HTMX headers while adding OCG fetch headers for same-origin requests.
      expect(options.headers.get("HX-Request")).to.equal("true");
      expect(options.headers.get("X-OCG-Fetch")).to.equal("true");
      expect(options.headers.get(COMMIT_SHA_HEADER)).to.equal("abc123");

      // Return the value used by the assertion.
      return {
        headers: new Headers(),
        ok: true,
        status: 200,
      };
    });

    // Execute the OCG fetch helper.
    await ocgFetch("/test", {
      headers: {
        "HX-Request": "true",
      },
    });

    // The request uses the expected endpoint and options.
    expect(fetchMock.calls).to.have.length(1);
  });

  it("reloads and leaves callers pending when the server requests a deployment refresh", async () => {
    // Mock the fetch response.
    let reloads = 0;
    setDeploymentReloadHandler(() => {
      reloads += 1;
    });
    fetchMock.setImpl(async () => ({
      headers: new Headers({ [REFRESH_HEADER]: "true" }),
      ok: true,
      status: 204,
    }));

    // Capture the async result.
    const settledState = await getSettledStateAfterCurrentTask(
      ocgFetch("/test"),
    );

    // Check deployment refresh responses reload and leave callers pending.
    expect(settledState).to.equal("pending");
    expect(reloads).to.equal(1);
  });

  it("reloads and leaves callers pending when a same-origin response comes from a newer commit", async () => {
    // Mock the fetch response.
    setLoadedCommitSha("abc123");
    let reloads = 0;
    setDeploymentReloadHandler(() => {
      reloads += 1;
    });
    fetchMock.setImpl(async () => ({
      headers: new Headers({ [COMMIT_SHA_HEADER]: "def456" }),
      ok: true,
      status: 200,
    }));

    // Capture the async result.
    const settledState = await getSettledStateAfterCurrentTask(
      ocgFetch("/test"),
    );

    // Reloads and leaves callers pending when a same-origin response comes from a newer commit.
    expect(settledState).to.equal("pending");
    expect(reloads).to.equal(1);
  });

  it("leaves callers pending when deployment refresh enters retry mode", async () => {
    Date.now = () => 1_000;
    let reloads = 0;
    setDeploymentReloadHandler(() => {
      reloads += 1;
    });
    reloadIfDeploymentChanged(new Headers({ [REFRESH_HEADER]: "true" }));
    resetDeploymentReloadState({ clearRefreshHistory: false });
    setDeploymentReloadHandler(() => {
      reloads += 1;
    });
    Date.now = () => 1_000 + 4 * 60 * 1000;
    fetchMock.setImpl(async () => ({
      headers: new Headers({ [REFRESH_HEADER]: "true" }),
      ok: true,
      status: 204,
    }));

    // Capture the async result.
    const settledState = await getSettledStateAfterCurrentTask(
      ocgFetch("/test"),
    );

    expect(settledState).to.equal("pending");
    expect(reloads).to.equal(1);
  });
});
