import { expect } from "@open-wc/testing";

import { ocgFetch } from "/static/js/common/fetch.js";
import { showErrorAlert } from "/static/js/common/alerts.js";
import {
  resetDashboardContextReloadState,
  SELECTED_COMMUNITY_ID_HEADER,
  SELECTED_GROUP_ID_HEADER,
  setDashboardContextReloadHandler,
  STALE_DASHBOARD_CONTEXT_HEADER,
} from "/static/js/common/dashboard-context.js";
import {
  COMMIT_SHA_HEADER,
  isDeploymentReloadRequested,
  REFRESH_HEADER,
  reloadIfDeploymentChanged,
  resetDeploymentReloadState,
  setDeploymentReloadHandler,
} from "/static/js/common/deployment-version.js";
import { waitForMicrotask } from "/tests/unit/test-utils/async.js";
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

// Mock SweetAlert2 so a new alert replaces and dismisses the open one.
const mockReplacingSwal = () => {
  const originalSwal = globalThis.Swal;
  const calls = [];
  let container = null;
  let resolveOpen = null;

  const close = (result) => {
    const resolve = resolveOpen;
    resolveOpen = null;
    container?.remove();
    container = null;
    resolve?.(result);
  };

  globalThis.Swal = {
    fire: (options) => {
      calls.push(options);
      const resolveReplaced = resolveOpen;
      container?.remove();
      container = document.createElement("div");
      container.className = "swal2-container";
      document.body.append(container);
      resolveReplaced?.({ isDismissed: true });
      return new Promise((resolve) => {
        resolveOpen = resolve;
      });
    },
    getPopup: () => container,
    isVisible: () => Boolean(container?.isConnected),
  };

  return {
    calls,
    close(result = { isConfirmed: false, isDismissed: true, dismiss: "close" }) {
      close(result);
    },
    restore() {
      close({ isConfirmed: false, isDismissed: true, dismiss: "cancel" });
      globalThis.Swal = originalSwal;
    },
  };
};

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
    resetDashboardContextReloadState();
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

  it("adds the loaded dashboard context headers for same-origin requests", async () => {
    // Render the group dashboard layout marker.
    document.body.innerHTML =
      '<div id="dashboard-layout" data-ocg-selected-community-id="community-1" data-ocg-selected-group-id="group-1"></div>';
    fetchMock.setImpl(async (_url, options) => {
      // Same-origin requests declare the loaded dashboard context.
      expect(options.headers.get(SELECTED_COMMUNITY_ID_HEADER)).to.equal("community-1");
      expect(options.headers.get(SELECTED_GROUP_ID_HEADER)).to.equal("group-1");

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

  it("reloads and leaves callers pending when the server reports a stale dashboard context", async () => {
    // Mock the stale dashboard context intercept.
    let reloads = 0;
    setDashboardContextReloadHandler(() => {
      reloads += 1;
    });
    fetchMock.setImpl(async () => ({
      headers: new Headers({ [STALE_DASHBOARD_CONTEXT_HEADER]: "true" }),
      ok: true,
      status: 204,
    }));

    // Capture the async result.
    const settledState = await getSettledStateAfterCurrentTask(ocgFetch("/test"));

    // Stale context responses reload and leave callers pending.
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

  it("settles pending callers when deployment refresh retries stop", async () => {
    // Capture the retry timer while keeping other timers working.
    const originalSetTimeout = window.setTimeout;
    let retryCallback = null;
    window.setTimeout = (handler, timeout, ...args) => {
      if (timeout === 30_000) {
        retryCallback = handler;
        return 0;
      }
      return originalSetTimeout(handler, timeout, ...args);
    };
    const swal = mockSwal();
    swal.setNextResult({ isConfirmed: false, isDismissed: true });

    try {
      // Enter retry mode while stale HTML is still loaded.
      Date.now = () => 1_000;
      setLoadedCommitSha("old");
      setDeploymentReloadHandler(() => {});
      reloadIfDeploymentChanged(new Headers({ [COMMIT_SHA_HEADER]: "new" }));
      resetDeploymentReloadState({ clearRefreshHistory: false });
      setDeploymentReloadHandler(() => {});
      reloadIfDeploymentChanged(new Headers({ [COMMIT_SHA_HEADER]: "new" }));
      fetchMock.setImpl(async (url) =>
        url === "/blocked"
          ? { headers: new Headers({ [REFRESH_HEADER]: "true" }), ok: true, status: 204 }
          : { headers: new Headers({ [COMMIT_SHA_HEADER]: "new" }), ok: true, status: 200 },
      );
      const blocked = ocgFetch("/blocked");
      const processed = ocgFetch("/processed");
      expect(await getSettledStateAfterCurrentTask(blocked)).to.equal("pending");
      expect(await getSettledStateAfterCurrentTask(processed)).to.equal("pending");

      // Expire the retry window so the page stays loaded.
      Date.now = () => 1_000 + 7 * 60 * 1000;
      retryCallback();

      // Blocked requests fail closed and handled responses reach their callers.
      const blockedResponse = await blocked;
      expect(blockedResponse.status).to.equal(409);
      expect(blockedResponse.ok).to.equal(false);
      expect((await processed).status).to.equal(200);
      expect(isDeploymentReloadRequested()).to.equal(false);
    } finally {
      window.setTimeout = originalSetTimeout;
      swal.restore();
    }
  });

  it("runs stale dashboard context checks on responses released by stopped retries", async () => {
    // Capture the retry timer while keeping other timers working.
    const originalSetTimeout = window.setTimeout;
    let retryCallback = null;
    window.setTimeout = (handler, timeout, ...args) => {
      if (timeout === 30_000) {
        retryCallback = handler;
        return 0;
      }
      return originalSetTimeout(handler, timeout, ...args);
    };
    const swal = mockSwal();
    swal.setNextResult({ isConfirmed: false, isDismissed: true });
    let dashboardReloads = 0;
    setDashboardContextReloadHandler(() => {
      dashboardReloads += 1;
    });

    try {
      // Hold a stale dashboard context intercept while the deployment retry is pending.
      Date.now = () => 1_000;
      setLoadedCommitSha("old");
      setDeploymentReloadHandler(() => {});
      reloadIfDeploymentChanged(new Headers({ [COMMIT_SHA_HEADER]: "new" }));
      resetDeploymentReloadState({ clearRefreshHistory: false });
      setDeploymentReloadHandler(() => {});
      reloadIfDeploymentChanged(new Headers({ [COMMIT_SHA_HEADER]: "new" }));
      fetchMock.setImpl(async () => ({
        headers: new Headers({ [COMMIT_SHA_HEADER]: "new", [STALE_DASHBOARD_CONTEXT_HEADER]: "true" }),
        ok: true,
        status: 204,
      }));
      const staleContext = ocgFetch("/dashboard/group/sponsors/1/featured");
      expect(await getSettledStateAfterCurrentTask(staleContext)).to.equal("pending");

      // Expire the retry window so the held response is released.
      Date.now = () => 1_000 + 7 * 60 * 1000;
      retryCallback();

      // The handler never ran, so the dashboard reloads and the caller stays pending.
      expect(await getSettledStateAfterCurrentTask(staleContext)).to.equal("pending");
      expect(dashboardReloads).to.equal(1);
    } finally {
      window.setTimeout = originalSetTimeout;
      swal.restore();
    }
  });

  it("releases held callers when a pending retry is deferred for a dirty form", async () => {
    // Capture the retry timer while keeping other timers working.
    const originalSetTimeout = window.setTimeout;
    let retryCallback = null;
    window.setTimeout = (handler, timeout, ...args) => {
      if (timeout === 30_000) {
        retryCallback = handler;
        return 0;
      }
      return originalSetTimeout(handler, timeout, ...args);
    };
    const swal = mockSwal();

    try {
      // Hold a processed response while the deployment retry is pending.
      Date.now = () => 1_000;
      setLoadedCommitSha("old");
      setDeploymentReloadHandler(() => {});
      reloadIfDeploymentChanged(new Headers({ [COMMIT_SHA_HEADER]: "new" }));
      resetDeploymentReloadState({ clearRefreshHistory: false });
      setDeploymentReloadHandler(() => {});
      reloadIfDeploymentChanged(new Headers({ [COMMIT_SHA_HEADER]: "new" }));
      fetchMock.setImpl(async () => ({
        headers: new Headers({ [COMMIT_SHA_HEADER]: "new" }),
        ok: true,
        status: 200,
      }));
      const processed = ocgFetch("/processed");
      expect(await getSettledStateAfterCurrentTask(processed)).to.equal("pending");

      // Dirty the form before the next retry fires.
      document.body.innerHTML = '<div id="pending-changes-alert"></div>';
      retryCallback();

      // The retry is deferred and the held response reaches its caller.
      expect((await processed).status).to.equal(200);
      expect(isDeploymentReloadRequested()).to.equal(false);
    } finally {
      window.setTimeout = originalSetTimeout;
      swal.restore();
    }
  });

  it("restores the blocked-request reload prompt after the caller's error alert closes", async () => {
    // Record an expired retry window for the loaded commit.
    const swal = mockReplacingSwal();
    Date.now = () => 1_000 + 7 * 60 * 1000;
    setLoadedCommitSha("old");
    window.sessionStorage.setItem("ocg.deploymentRefreshRetryStaleCommitSha", "old");
    window.sessionStorage.setItem("ocg.deploymentRefreshRetryStartedAt", "1000");
    fetchMock.setImpl(async () => ({
      headers: new Headers({ [REFRESH_HEADER]: "true" }),
      ok: true,
      status: 204,
    }));

    try {
      // A caller shows its generic failure alert for the blocked response.
      const response = await ocgFetch("/dashboard/group/sponsors/1/featured");
      expect(response.status).to.equal(409);
      showErrorAlert("Failed to update sponsor visibility. Please try again.");
      await waitForMicrotask();

      // The caller's error replaces the Reload prompt instead of being dropped.
      expect(swal.calls).to.have.length(2);
      expect(swal.calls[0]).to.include({ confirmButtonText: "Reload", icon: "warning" });
      expect(swal.calls[1]).to.include({
        icon: "error",
        text: "Failed to update sponsor visibility. Please try again.",
      });

      // Closing the error alert brings the Reload prompt back.
      swal.close({ isConfirmed: false, isDismissed: true, dismiss: "timer" });
      await waitForMicrotask();
      expect(swal.calls).to.have.length(3);
      expect(swal.calls[2]).to.include({ confirmButtonText: "Reload", icon: "warning" });
    } finally {
      swal.restore();
    }
  });

  it("offers the blocked-request reload prompt to callers released by an expired retry timer", async () => {
    // Capture the retry timer while keeping other timers working.
    const originalSetTimeout = window.setTimeout;
    let retryCallback = null;
    window.setTimeout = (handler, timeout, ...args) => {
      if (timeout === 30_000) {
        retryCallback = handler;
        return 0;
      }
      return originalSetTimeout(handler, timeout, ...args);
    };
    const swal = mockReplacingSwal();

    try {
      // Hold a forced-refresh intercept while the deployment retry is pending.
      Date.now = () => 1_000;
      setLoadedCommitSha("old");
      setDeploymentReloadHandler(() => {});
      reloadIfDeploymentChanged(new Headers({ [COMMIT_SHA_HEADER]: "new" }));
      resetDeploymentReloadState({ clearRefreshHistory: false });
      setDeploymentReloadHandler(() => {});
      reloadIfDeploymentChanged(new Headers({ [COMMIT_SHA_HEADER]: "new" }));
      fetchMock.setImpl(async () => ({
        headers: new Headers({ [REFRESH_HEADER]: "true" }),
        ok: true,
        status: 204,
      }));
      const blocked = ocgFetch("/event/1/availability");
      expect(await getSettledStateAfterCurrentTask(blocked)).to.equal("pending");

      // Expire the retry window from the timer.
      Date.now = () => 1_000 + 7 * 60 * 1000;
      retryCallback();
      const response = await blocked;

      // The released intercept opens the blocked-request prompt, not the passive notice.
      expect(response.status).to.equal(409);
      expect(swal.calls.at(-1)).to.include({ confirmButtonText: "Reload", icon: "warning" });

      // The caller's error alert shows, and the prompt returns once it closes.
      showErrorAlert("Something went wrong loading event availability.");
      await waitForMicrotask();
      expect(swal.calls.at(-1)).to.include({ icon: "error" });
      swal.close();
      await waitForMicrotask();
      expect(swal.calls.at(-1)).to.include({ confirmButtonText: "Reload", icon: "warning" });
    } finally {
      window.setTimeout = originalSetTimeout;
      swal.restore();
    }
  });
});
