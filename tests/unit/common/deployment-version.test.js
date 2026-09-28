import { expect } from "@open-wc/testing";

import {
  COMMIT_SHA_HEADER,
  consumePendingDeploymentRefreshAlert,
  createDeploymentRefreshUrl,
  DEPLOYMENT_REFRESH_ATTRIBUTE,
  DEPLOYMENT_REFRESH_MESSAGE,
  DEPLOYMENT_REFRESH_OUTCOME,
  DEPLOYMENT_REFRESH_PARAM,
  DEPLOYMENT_REFRESH_STALLED_BLOCKED_MESSAGE,
  DIRTY_DEPLOYMENT_BLOCKED_MESSAGE,
  DIRTY_DEPLOYMENT_NOTICE_MESSAGE,
  DIRTY_DEPLOYMENT_RELOAD_BLOCKED_MESSAGE,
  HTMX_REFRESH_HEADER,
  initializeDeploymentRefreshRetry,
  initializeDeploymentReloadState,
  isDeploymentReloadRequested,
  processDeploymentRefresh,
  REFRESH_HEADER,
  reloadIfDeploymentChanged,
  resetDeploymentReloadState,
  setDeploymentReloadHandler,
  waitForDeploymentReloadRelease,
} from "/static/js/common/deployment-version.js";
import { waitForMicrotask } from "/tests/unit/test-utils/async.js";
import { mockSwal } from "/tests/unit/test-utils/globals.js";

const RETRY_WINDOW_MS = 7 * 60 * 1000;

// Set the loaded commit SHA meta tag for deployment checks.
const setLoadedCommitSha = (commitSha) => {
  document.head.innerHTML = `<meta name="ocg-commit-sha" content="${commitSha}">`;
};

// Mark the loaded page as produced by a deployment refresh, as the base template does.
const markDeploymentRefreshLoad = () => {
  document.documentElement.setAttribute(DEPLOYMENT_REFRESH_ATTRIBUTE, "");
};

// Enter the refresh retry loop by reporting a new commit twice within the cache window.
const enterDeploymentRefreshRetry = (startedAt, handler) => {
  Date.now = () => startedAt;
  setLoadedCommitSha("old");
  setDeploymentReloadHandler(handler);
  reloadIfDeploymentChanged(new Headers({ [COMMIT_SHA_HEADER]: "new" }));
  resetDeploymentReloadState({ clearRefreshHistory: false });
  setDeploymentReloadHandler(handler);
  reloadIfDeploymentChanged(new Headers({ [COMMIT_SHA_HEADER]: "new" }));
};

const captureDeploymentRefreshRetryTimer = () => {
  const originalSetTimeout = window.setTimeout;
  const originalClearTimeout = window.clearTimeout;
  let callback = null;
  let delay = null;

  window.setTimeout = (handler, timeout) => {
    callback = handler;
    delay = timeout;
    return 1;
  };
  window.clearTimeout = () => {};

  return {
    get callback() {
      return callback;
    },
    get delay() {
      return delay;
    },
    restore() {
      window.setTimeout = originalSetTimeout;
      window.clearTimeout = originalClearTimeout;
    },
  };
};

describe("deployment version", () => {
  const originalDateNow = Date.now;

  afterEach(() => {
    Date.now = originalDateNow;
    document.head.innerHTML = "";
    document.body.innerHTML = "";
    document.documentElement.removeAttribute(DEPLOYMENT_REFRESH_ATTRIBUTE);
    resetDeploymentReloadState();
  });

  it("stores and consumes a one-shot alert marker when the server requests a refresh", () => {
    // Count reloads requested by the deployment refresh handler.
    let reloads = 0;
    setDeploymentReloadHandler(() => {
      reloads += 1;
    });

    // Process the explicit refresh header from the server.
    const changed = reloadIfDeploymentChanged(new Headers({ [REFRESH_HEADER]: "true" }));

    // Commit-sha refresh stores and consumes the reload alert marker.
    expect(changed).to.equal(true);
    expect(reloads).to.equal(1);
    expect(DEPLOYMENT_REFRESH_MESSAGE).to.equal(
      "This page was refreshed because a new version is available.",
    );
    expect(consumePendingDeploymentRefreshAlert()).to.equal(true);
    expect(consumePendingDeploymentRefreshAlert()).to.equal(false);
  });

  it("releases the pending reload guard when the page is restored from the back/forward cache", async () => {
    // Request a reload, then simulate the browser restoring the cached page.
    setDeploymentReloadHandler(() => {});
    reloadIfDeploymentChanged(new Headers({ [REFRESH_HEADER]: "true" }));
    let released = false;
    waitForDeploymentReloadRelease().then(() => {
      released = true;
    });
    const target = new EventTarget();
    initializeDeploymentReloadState(target);

    // A regular pageshow keeps the guard and holds waiting callers.
    target.dispatchEvent(Object.assign(new Event("pageshow"), { persisted: false }));
    await waitForMicrotask();
    expect(isDeploymentReloadRequested()).to.equal(true);
    expect(released).to.equal(false);

    // A persisted pageshow clears the guard and settles waiting callers.
    target.dispatchEvent(Object.assign(new Event("pageshow"), { persisted: true }));
    await waitForMicrotask();
    expect(isDeploymentReloadRequested()).to.equal(false);
    expect(released).to.equal(true);
  });

  it("reports how each deployment refresh signal was handled", () => {
    setDeploymentReloadHandler(() => {});
    setLoadedCommitSha("abc123");
    const swal = mockSwal();

    try {
      // Responses from the loaded commit need no handling.
      expect(processDeploymentRefresh(new Headers({ [COMMIT_SHA_HEADER]: "abc123" }))).to.equal(
        DEPLOYMENT_REFRESH_OUTCOME.NONE,
      );

      // A forced refresh on a dirty form is blocked instead of reloading.
      document.body.innerHTML = '<div id="pending-changes-alert"></div>';
      expect(processDeploymentRefresh(new Headers({ [REFRESH_HEADER]: "true" }))).to.equal(
        DEPLOYMENT_REFRESH_OUTCOME.BLOCKED,
      );
      expect(isDeploymentReloadRequested()).to.equal(false);

      // A newer commit on a clean page reloads, and later responses wait for it.
      document.body.innerHTML = "";
      expect(processDeploymentRefresh(new Headers({ [COMMIT_SHA_HEADER]: "def456" }))).to.equal(
        DEPLOYMENT_REFRESH_OUTCOME.RELOADING,
      );
      expect(processDeploymentRefresh(new Headers({ [COMMIT_SHA_HEADER]: "abc123" }))).to.equal(
        DEPLOYMENT_REFRESH_OUTCOME.RELOADING,
      );
    } finally {
      swal.restore();
    }
  });

  it("settles reload waits immediately when no reload is pending", async () => {
    // No pending reload means there is nothing to wait for.
    await waitForDeploymentReloadRelease();
    expect(isDeploymentReloadRequested()).to.equal(false);
  });

  it("notifies once and leaves a dirty form in place when a response comes from a newer commit", () => {
    // Store the current page commit SHA and show pending changes.
    setLoadedCommitSha("abc123");
    document.body.innerHTML = '<div id="pending-changes-alert"></div>';
    let reloads = 0;
    setDeploymentReloadHandler(() => {
      reloads += 1;
    });
    const swal = mockSwal();

    try {
      // Process a response from a different commit SHA while the form is dirty.
      const changed = reloadIfDeploymentChanged(new Headers({ [COMMIT_SHA_HEADER]: "def456" }));
      const secondChanged = reloadIfDeploymentChanged(new Headers({ [COMMIT_SHA_HEADER]: "def456" }));

      // Dirty forms stay put, get one notice, and still process the response.
      expect(changed).to.equal(false);
      expect(secondChanged).to.equal(false);
      expect(reloads).to.equal(0);
      expect(isDeploymentReloadRequested()).to.equal(false);
      expect(swal.calls).to.have.length(1);
      expect(swal.calls[0].text).to.equal(DIRTY_DEPLOYMENT_NOTICE_MESSAGE);
    } finally {
      swal.restore();
    }
  });

  it("consumes a forced refresh on a dirty form without reloading", () => {
    // Show pending changes before a stale-client intercept arrives.
    document.body.innerHTML = '<div id="pending-changes-alert"></div>';
    let reloads = 0;
    setDeploymentReloadHandler(() => {
      reloads += 1;
    });
    const swal = mockSwal();

    try {
      // Process HTMX and ocgFetch refresh intercepts while the form is dirty.
      const htmxChanged = reloadIfDeploymentChanged(new Headers({ [HTMX_REFRESH_HEADER]: "true" }));
      const fetchChanged = reloadIfDeploymentChanged(new Headers({ [REFRESH_HEADER]: "true" }));

      // Forced intercepts are consumed and every blocked request warns the user.
      expect(htmxChanged).to.equal(true);
      expect(fetchChanged).to.equal(true);
      expect(reloads).to.equal(0);
      expect(isDeploymentReloadRequested()).to.equal(false);
      expect(swal.calls).to.have.length(2);
      expect(swal.calls[0].text).to.equal(DIRTY_DEPLOYMENT_BLOCKED_MESSAGE);
      expect(swal.calls[1].text).to.equal(DIRTY_DEPLOYMENT_BLOCKED_MESSAGE);
    } finally {
      swal.restore();
    }
  });

  it("warns about a blocked save after the generic notice was already shown", () => {
    // Show the one-shot generic notice for a dirty form on a newer commit first.
    setLoadedCommitSha("abc123");
    document.body.innerHTML = '<div id="pending-changes-alert"></div>';
    let reloads = 0;
    setDeploymentReloadHandler(() => {
      reloads += 1;
    });
    const swal = mockSwal();

    try {
      const noticed = reloadIfDeploymentChanged(new Headers({ [COMMIT_SHA_HEADER]: "def456" }));
      const blocked = reloadIfDeploymentChanged(new Headers({ [REFRESH_HEADER]: "true" }));

      // The blocked-mutation warning supersedes the earlier generic notice.
      expect(noticed).to.equal(false);
      expect(blocked).to.equal(true);
      expect(reloads).to.equal(0);
      expect(swal.calls).to.have.length(2);
      expect(swal.calls[0].text).to.equal(DIRTY_DEPLOYMENT_NOTICE_MESSAGE);
      expect(swal.calls[1].text).to.equal(DIRTY_DEPLOYMENT_BLOCKED_MESSAGE);
    } finally {
      swal.restore();
    }
  });

  it("stores and consumes a one-shot alert marker when a response comes from a newer commit", () => {
    // Store the current page commit SHA before reading the response.
    setLoadedCommitSha("abc123");
    let reloads = 0;
    setDeploymentReloadHandler(() => {
      reloads += 1;
    });

    // Process a response from a different commit SHA.
    const changed = reloadIfDeploymentChanged(new Headers({ [COMMIT_SHA_HEADER]: "def456" }));

    // Cross-version responses store and consume the reload alert marker.
    expect(changed).to.equal(true);
    expect(reloads).to.equal(1);
    expect(consumePendingDeploymentRefreshAlert()).to.equal(true);
    expect(consumePendingDeploymentRefreshAlert()).to.equal(false);
  });

  it("suppresses repeated automatic refreshes within the public cache window", () => {
    // Start inside the public cache window with a stale loaded commit.
    Date.now = () => 1_000;
    setLoadedCommitSha("old");
    let reloads = 0;
    setDeploymentReloadHandler(() => {
      reloads += 1;
    });

    // Set up first changed.
    const firstChanged = reloadIfDeploymentChanged(new Headers({ [COMMIT_SHA_HEADER]: "new" }));

    // Verify suppresses repeated automatic refreshes within the public cache window.
    expect(firstChanged).to.equal(true);
    expect(reloads).to.equal(1);
    expect(consumePendingDeploymentRefreshAlert()).to.equal(true);

    resetDeploymentReloadState({ clearRefreshHistory: false });
    setDeploymentReloadHandler(() => {
      reloads += 1;
    });
    Date.now = () => 1_000 + 4 * 60 * 1000;

    // Set up second changed.
    const secondChanged = reloadIfDeploymentChanged(new Headers({ [COMMIT_SHA_HEADER]: "new" }));

    // Assert that the flag is enabled.
    expect(secondChanged).to.equal(true);
    expect(reloads).to.equal(1);
    expect(consumePendingDeploymentRefreshAlert()).to.equal(false);
  });

  it("schedules automatic refresh retries when cached HTML is still loaded", () => {
    // Start inside the public cache window with a stale loaded commit.
    Date.now = () => 1_000;
    setLoadedCommitSha("old");
    let reloads = 0;
    setDeploymentReloadHandler(() => {
      reloads += 1;
    });
    const swal = mockSwal();
    const retryTimer = captureDeploymentRefreshRetryTimer();

    // Restore the page state after the check.
    try {
      reloadIfDeploymentChanged(new Headers({ [COMMIT_SHA_HEADER]: "new" }));
      resetDeploymentReloadState({ clearRefreshHistory: false });
      setDeploymentReloadHandler(() => {
        reloads += 1;
      });
      Date.now = () => 1_000 + 4 * 60 * 1000;

      // Set up changed.
      const changed = reloadIfDeploymentChanged(new Headers({ [COMMIT_SHA_HEADER]: "new" }));

      // Verify schedules automatic refresh retries when cached HTML is still loaded.
      expect(changed).to.equal(true);
      expect(reloads).to.equal(1);
      expect(swal.calls).to.have.length(1);
      expect(retryTimer.delay).to.equal(30_000);

      // Fire the retry timer.
      retryTimer.callback();

      // Assert the reload count.
      expect(reloads).to.equal(2);
    } finally {
      retryTimer.restore();
      swal.restore();
    }
  });

  it("defers a scheduled refresh retry when the form becomes dirty", () => {
    // Start inside the public cache window with a stale loaded commit.
    Date.now = () => 1_000;
    setLoadedCommitSha("old");
    let reloads = 0;
    setDeploymentReloadHandler(() => {
      reloads += 1;
    });
    const swal = mockSwal();
    const retryTimer = captureDeploymentRefreshRetryTimer();

    try {
      reloadIfDeploymentChanged(new Headers({ [COMMIT_SHA_HEADER]: "new" }));
      resetDeploymentReloadState({ clearRefreshHistory: false });
      setDeploymentReloadHandler(() => {
        reloads += 1;
      });
      Date.now = () => 1_000 + 4 * 60 * 1000;
      reloadIfDeploymentChanged(new Headers({ [COMMIT_SHA_HEADER]: "new" }));

      // A retry is armed while the form is still clean.
      expect(reloads).to.equal(1);
      expect(isDeploymentReloadRequested()).to.equal(true);

      // Dirtiness after arming must not reload when the timer fires.
      document.body.innerHTML = '<div id="pending-changes-alert"></div>';
      retryTimer.callback();

      expect(reloads).to.equal(1);
      expect(isDeploymentReloadRequested()).to.equal(false);
      expect(swal.calls.at(-1).text).to.equal(DIRTY_DEPLOYMENT_NOTICE_MESSAGE);
      expect(retryTimer.delay).to.equal(30_000);

      // Once the draft is gone, the next retry reload can proceed.
      document.body.innerHTML = '<div id="pending-changes-alert" class="hidden"></div>';
      retryTimer.callback();

      expect(reloads).to.equal(2);
      expect(isDeploymentReloadRequested()).to.equal(true);
    } finally {
      retryTimer.restore();
      swal.restore();
    }
  });

  it("unsticks a pending retry when a later dirty response arrives", () => {
    // Start inside the public cache window with a stale loaded commit.
    Date.now = () => 1_000;
    setLoadedCommitSha("old");
    let reloads = 0;
    setDeploymentReloadHandler(() => {
      reloads += 1;
    });
    const swal = mockSwal();
    const retryTimer = captureDeploymentRefreshRetryTimer();

    try {
      reloadIfDeploymentChanged(new Headers({ [COMMIT_SHA_HEADER]: "new" }));
      resetDeploymentReloadState({ clearRefreshHistory: false });
      setDeploymentReloadHandler(() => {
        reloads += 1;
      });
      Date.now = () => 1_000 + 4 * 60 * 1000;
      reloadIfDeploymentChanged(new Headers({ [COMMIT_SHA_HEADER]: "new" }));
      document.body.innerHTML = '<div id="pending-changes-alert"></div>';

      // A forced intercept after the form is dirty must not keep reload-pending callers stuck.
      const changed = reloadIfDeploymentChanged(new Headers({ [REFRESH_HEADER]: "true" }));

      expect(changed).to.equal(true);
      expect(reloads).to.equal(1);
      expect(isDeploymentReloadRequested()).to.equal(false);
      expect(swal.calls.at(-1).text).to.equal(DIRTY_DEPLOYMENT_BLOCKED_MESSAGE);
    } finally {
      retryTimer.restore();
      swal.restore();
    }
  });

  it("resumes refresh retries while the stale commit is still loaded", () => {
    // Start inside the public cache window with a stale loaded commit.
    Date.now = () => 1_000;
    setLoadedCommitSha("old");
    setDeploymentReloadHandler(() => {});
    const swal = mockSwal();
    const firstRetryTimer = captureDeploymentRefreshRetryTimer();

    // Restore the page state after the check.
    try {
      reloadIfDeploymentChanged(new Headers({ [COMMIT_SHA_HEADER]: "new" }));
      resetDeploymentReloadState({ clearRefreshHistory: false });
      Date.now = () => 1_000 + 4 * 60 * 1000;
      reloadIfDeploymentChanged(new Headers({ [COMMIT_SHA_HEADER]: "new" }));
    } finally {
      firstRetryTimer.restore();
    }

    resetDeploymentReloadState({
      clearRefreshHistory: false,
      clearRetryState: false,
    });
    const resumedRetryTimer = captureDeploymentRefreshRetryTimer();

    // Restore the page state after the check.
    try {
      setLoadedCommitSha("old");
      expect(initializeDeploymentRefreshRetry()).to.equal(true);
      expect(resumedRetryTimer.delay).to.equal(30_000);

      resetDeploymentReloadState({
        clearRefreshHistory: false,
        clearRetryState: false,
      });
      setLoadedCommitSha("new");
      expect(initializeDeploymentRefreshRetry()).to.equal(false);
    } finally {
      resumedRetryTimer.restore();
      swal.restore();
    }
  });

  it("allows another automatic refresh after the public cache window", () => {
    // Start inside the public cache window with a stale loaded commit.
    Date.now = () => 1_000;
    setLoadedCommitSha("old");
    let reloads = 0;
    setDeploymentReloadHandler(() => {
      reloads += 1;
    });

    reloadIfDeploymentChanged(new Headers({ [COMMIT_SHA_HEADER]: "new" }));
    resetDeploymentReloadState({ clearRefreshHistory: false });
    setDeploymentReloadHandler(() => {
      reloads += 1;
    });
    Date.now = () => 1_000 + 5 * 60 * 1000;

    // Set up changed.
    const changed = reloadIfDeploymentChanged(new Headers({ [COMMIT_SHA_HEADER]: "new" }));

    // Assert that the flag is enabled.
    expect(changed).to.equal(true);
    expect(reloads).to.equal(2);
    expect(consumePendingDeploymentRefreshAlert()).to.equal(true);
  });

  it("reloads through a unique cache-busting URL", () => {
    // Report a response from a newer commit.
    Date.now = () => 1_700_000_000_000;
    setLoadedCommitSha("abc123");
    const reloadUrls = [];
    setDeploymentReloadHandler((url) => reloadUrls.push(url));
    reloadIfDeploymentChanged(new Headers({ [COMMIT_SHA_HEADER]: "def456" }));

    // The reload keeps the current page and adds a unique refresh token.
    expect(reloadUrls).to.have.length(1);
    const reloadUrl = new URL(reloadUrls[0]);
    expect(reloadUrl.pathname).to.equal(window.location.pathname);
    expect(reloadUrl.searchParams.get(DEPLOYMENT_REFRESH_PARAM)).to.equal((1_700_000_000_000).toString(36));
  });

  it("builds cache-busting URLs without re-encoding existing query parameters", () => {
    // Existing parameters and fragments are preserved, previous tokens are replaced.
    expect(
      createDeploymentRefreshUrl(
        `https://example.test/explore?kind[0]=a%20b&${DEPLOYMENT_REFRESH_PARAM}=old#events`,
        "t1",
      ),
    ).to.equal(`https://example.test/explore?kind[0]=a%20b&${DEPLOYMENT_REFRESH_PARAM}=t1#events`);
    expect(createDeploymentRefreshUrl("https://example.test/cncf", "t1")).to.equal(
      `https://example.test/cncf?${DEPLOYMENT_REFRESH_PARAM}=t1`,
    );
  });

  it("stops automatic retries and offers a manual reload after the retry window", async () => {
    const reloadUrls = [];
    const swal = mockSwal();
    const retryTimer = captureDeploymentRefreshRetryTimer();

    try {
      // Enter the retry loop while stale HTML is still loaded.
      enterDeploymentRefreshRetry(1_000, (url) => reloadUrls.push(url));
      expect(reloadUrls).to.have.length(1);
      expect(isDeploymentReloadRequested()).to.equal(true);

      // Fire the retry timer once the retry window has elapsed.
      Date.now = () => 1_000 + RETRY_WINDOW_MS;
      retryTimer.callback();

      // The page is released and a dismissible reload notice replaces the overlay.
      expect(reloadUrls).to.have.length(1);
      expect(isDeploymentReloadRequested()).to.equal(false);
      expect(swal.calls.at(-1)).to.include({ confirmButtonText: "Reload", showCancelButton: true });
    } finally {
      retryTimer.restore();
    }

    try {
      // Accepting the notice reloads through a cache-busting URL.
      await waitForMicrotask();
      expect(reloadUrls).to.have.length(2);
      expect(new URL(reloadUrls[1]).searchParams.has(DEPLOYMENT_REFRESH_PARAM)).to.equal(true);
    } finally {
      swal.restore();
    }
  });

  it("does not discard edits made while the manual reload notice was open", async () => {
    const reloadUrls = [];
    const swal = mockSwal();
    const retryTimer = captureDeploymentRefreshRetryTimer();

    try {
      // Exhaust the retry window so the manual reload notice opens.
      enterDeploymentRefreshRetry(1_000, (url) => reloadUrls.push(url));
      Date.now = () => 1_000 + RETRY_WINDOW_MS;
      retryTimer.callback();
    } finally {
      retryTimer.restore();
    }

    try {
      // Edit the form before the notice's Reload action is confirmed.
      document.body.innerHTML = '<div id="pending-changes-alert"></div>';
      await waitForMicrotask();

      // The reload is refused and the user is told to keep their work first.
      expect(reloadUrls).to.have.length(1);
      expect(isDeploymentReloadRequested()).to.equal(false);
      expect(swal.calls.at(-1)).to.include({ icon: "error", text: DIRTY_DEPLOYMENT_RELOAD_BLOCKED_MESSAGE });
    } finally {
      swal.restore();
    }
  });

  it("keeps the page usable once the retry window has elapsed", () => {
    let reloads = 0;
    const handler = () => {
      reloads += 1;
    };
    const swal = mockSwal();
    swal.setNextResult({ isConfirmed: false, isDismissed: true });
    const retryTimer = captureDeploymentRefreshRetryTimer();

    try {
      // Retry until shortly before the window closes.
      enterDeploymentRefreshRetry(1_000, handler);
      Date.now = () => 1_000 + RETRY_WINDOW_MS - 30_000;
      retryTimer.callback();
      expect(reloads).to.equal(2);

      // A plain navigation after expiry loads silently.
      resetDeploymentReloadState({ clearRefreshHistory: false, clearRetryState: false });
      setDeploymentReloadHandler(handler);
      setLoadedCommitSha("old");
      Date.now = () => 1_000 + RETRY_WINDOW_MS;
      const callsBeforeNavigation = swal.calls.length;
      expect(initializeDeploymentRefreshRetry()).to.equal(false);
      expect(swal.calls).to.have.length(callsBeforeNavigation);

      // The page produced by an automatic retry explains the stalled refresh once.
      resetDeploymentReloadState({ clearRefreshHistory: false, clearRetryState: false });
      setDeploymentReloadHandler(handler);
      markDeploymentRefreshLoad();
      expect(initializeDeploymentRefreshRetry()).to.equal(false);
      expect(document.documentElement.hasAttribute(DEPLOYMENT_REFRESH_ATTRIBUTE)).to.equal(false);
      expect(swal.calls).to.have.length(callsBeforeNavigation + 1);
      expect(swal.calls.at(-1).confirmButtonText).to.equal("Reload");

      // Later responses are processed, intercepts warn every time, and nothing reloads.
      expect(reloadIfDeploymentChanged(new Headers({ [COMMIT_SHA_HEADER]: "new" }))).to.equal(false);
      expect(swal.calls).to.have.length(callsBeforeNavigation + 1);
      expect(reloadIfDeploymentChanged(new Headers({ [REFRESH_HEADER]: "true" }))).to.equal(true);
      expect(reloadIfDeploymentChanged(new Headers({ [HTMX_REFRESH_HEADER]: "true" }))).to.equal(true);
      expect(reloads).to.equal(2);
      expect(isDeploymentReloadRequested()).to.equal(false);
      expect(swal.calls).to.have.length(callsBeforeNavigation + 3);
      expect(swal.calls.at(-1)).to.include({
        confirmButtonText: "Reload",
        icon: "warning",
        text: DEPLOYMENT_REFRESH_STALLED_BLOCKED_MESSAGE,
      });
    } finally {
      retryTimer.restore();
      swal.restore();
    }
  });

  it("does not restart automatic reloads for an expired commit after the cooldown", () => {
    let reloads = 0;
    const handler = () => {
      reloads += 1;
    };
    const swal = mockSwal();
    swal.setNextResult({ isConfirmed: false, isDismissed: true });
    const retryTimer = captureDeploymentRefreshRetryTimer();

    try {
      // Exhaust the retry window for the stale commit.
      enterDeploymentRefreshRetry(1_000, handler);
      Date.now = () => 1_000 + RETRY_WINDOW_MS;
      retryTimer.callback();
      expect(reloads).to.equal(1);
      const callsAfterExpiry = swal.calls.length;

      // A mismatch after both the retry window and cooldown only offers a reload.
      Date.now = () => 1_000 + RETRY_WINDOW_MS + 5 * 60 * 1000;
      expect(reloadIfDeploymentChanged(new Headers({ [COMMIT_SHA_HEADER]: "new" }))).to.equal(false);
      expect(reloads).to.equal(1);
      expect(isDeploymentReloadRequested()).to.equal(false);
      expect(swal.calls).to.have.length(callsAfterExpiry);

      // A newer loaded commit starts a fresh deployment refresh cycle.
      setLoadedCommitSha("new");
      expect(reloadIfDeploymentChanged(new Headers({ [COMMIT_SHA_HEADER]: "newer" }))).to.equal(true);
      expect(reloads).to.equal(2);
    } finally {
      retryTimer.restore();
      swal.restore();
    }
  });

  it("does not claim a refresh succeeded when an automatic reload loads an expired commit", () => {
    const swal = mockSwal();
    swal.setNextResult({ isConfirmed: false, isDismissed: true });

    try {
      // Simulate an automatic reload queued after the retry window expired.
      Date.now = () => 1_000 + RETRY_WINDOW_MS;
      setLoadedCommitSha("old");
      window.sessionStorage.setItem("ocg.deploymentRefreshRetryStaleCommitSha", "old");
      window.sessionStorage.setItem("ocg.deploymentRefreshRetryStartedAt", "1000");
      window.sessionStorage.setItem("ocg.deploymentRefreshAlert", "true");
      markDeploymentRefreshLoad();

      // The stalled notice is shown and the pending refreshed alert is dropped.
      expect(initializeDeploymentRefreshRetry()).to.equal(false);
      expect(swal.calls).to.have.length(1);
      expect(swal.calls[0].confirmButtonText).to.equal("Reload");
      expect(consumePendingDeploymentRefreshAlert()).to.equal(false);
    } finally {
      swal.restore();
    }
  });

  it("bounds retries resumed from state saved before the retry window existed", () => {
    let reloads = 0;
    setDeploymentReloadHandler(() => {
      reloads += 1;
    });
    const swal = mockSwal();
    swal.setNextResult({ isConfirmed: false, isDismissed: true });
    const retryTimer = captureDeploymentRefreshRetryTimer();

    try {
      // Resume a retry that only recorded the stale commit.
      Date.now = () => 10_000;
      window.sessionStorage.setItem("ocg.deploymentRefreshRetryStaleCommitSha", "old");
      setLoadedCommitSha("old");
      expect(initializeDeploymentRefreshRetry()).to.equal(true);

      // The retry window starts on resume and still expires.
      Date.now = () => 10_000 + RETRY_WINDOW_MS;
      retryTimer.callback();
      expect(reloads).to.equal(0);
      expect(isDeploymentReloadRequested()).to.equal(false);
      expect(swal.calls.at(-1).confirmButtonText).to.equal("Reload");
    } finally {
      retryTimer.restore();
      swal.restore();
    }
  });
});
