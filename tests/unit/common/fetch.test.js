import { expect } from "@open-wc/testing";

import { ocgFetch } from "/static/js/common/fetch.js";
import {
  COMMIT_SHA_HEADER,
  isDeploymentReloadRequested,
  REFRESH_HEADER,
  reloadIfDeploymentChanged,
  resetDeploymentReloadState,
  setDeploymentReloadHandler,
} from "/static/js/common/deployment-version.js";
import { mockSwal } from "/tests/unit/test-utils/globals.js";
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
    document.body.innerHTML = "";
    fetchMock.restore();
    resetDeploymentReloadState();
  });

  it("adds OCG fetch and commit SHA headers for same-origin requests", async () => {
    // Mock the fetch response.
    setLoadedCommitSha("abc123");
    fetchMock.setImpl(async (_url, options) => {
      // Same-origin requests include the OCG and commit headers.
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
      // Cross-origin requests keep the OCG headers unset.
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
    const settledState = await getSettledStateAfterCurrentTask(ocgFetch("/test"));

    // Deployment refresh responses reload and leave callers pending.
    expect(settledState).to.equal("pending");
    expect(reloads).to.equal(1);
  });

  it("returns the response when a dirty form sees a newer commit", async () => {
    // Mock a newer commit while the pending-changes banner is visible.
    setLoadedCommitSha("abc123");
    document.body.innerHTML = '<div id="pending-changes-alert"></div>';
    let reloads = 0;
    setDeploymentReloadHandler(() => {
      reloads += 1;
    });
    const swal = mockSwal();
    fetchMock.setImpl(async () => ({
      headers: new Headers({ [COMMIT_SHA_HEADER]: "def456" }),
      ok: true,
      status: 200,
    }));

    try {
      // Capture the async result.
      const settledState = await getSettledStateAfterCurrentTask(ocgFetch("/test"));

      // Dirty forms keep the fetch result instead of waiting for a reload.
      expect(settledState).to.equal("resolved");
      expect(reloads).to.equal(0);
    } finally {
      swal.restore();
    }
  });

  it("does not treat a dirty-form forced refresh as success", async () => {
    // Mock a stale-client intercept while the pending-changes banner is visible.
    document.body.innerHTML = '<div id="pending-changes-alert"></div>';
    let reloads = 0;
    setDeploymentReloadHandler(() => {
      reloads += 1;
    });
    const swal = mockSwal();
    fetchMock.setImpl(async () => ({
      headers: new Headers({ [REFRESH_HEADER]: "true" }),
      ok: true,
      status: 204,
    }));

    try {
      const response = await ocgFetch("/test");

      // The empty 204 intercept is returned as a conflict so callers do not save-succeed.
      expect(response.status).to.equal(409);
      expect(response.ok).to.equal(false);
      expect(reloads).to.equal(0);
    } finally {
      swal.restore();
    }
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
    const settledState = await getSettledStateAfterCurrentTask(ocgFetch("/test"));

    // Verify refresh keeps callers pending for a newer same-origin commit.
    expect(settledState).to.equal("pending");
    expect(reloads).to.equal(1);
  });

  it("leaves callers pending when deployment refresh enters retry mode", async () => {
    // Start inside the public cache window before entering retry mode.
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
    const settledState = await getSettledStateAfterCurrentTask(ocgFetch("/test"));

    // The fetch promise remains pending while the page reloads.
    expect(settledState).to.equal("pending");
    expect(reloads).to.equal(1);
  });

  it("does not leave dirty-form callers pending after a retry is disarmed", async () => {
    // Start inside the public cache window before entering retry mode.
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
    reloadIfDeploymentChanged(new Headers({ [REFRESH_HEADER]: "true" }));
    document.body.innerHTML = '<div id="pending-changes-alert"></div>';
    const swal = mockSwal();
    fetchMock.setImpl(async () => ({
      headers: new Headers({ [REFRESH_HEADER]: "true" }),
      ok: true,
      status: 204,
    }));

    try {
      const response = await ocgFetch("/test");

      // Dirty retry intercepts fail closed instead of hanging until a reload.
      expect(response.status).to.equal(409);
      expect(response.ok).to.equal(false);
      expect(isDeploymentReloadRequested()).to.equal(false);
      expect(reloads).to.equal(1);
    } finally {
      swal.restore();
    }
  });
});
