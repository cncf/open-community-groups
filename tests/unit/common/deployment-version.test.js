import { expect } from "@open-wc/testing";

import {
  COMMIT_SHA_HEADER,
  consumePendingDeploymentRefreshAlert,
  DEPLOYMENT_REFRESH_MESSAGE,
  DIRTY_DEPLOYMENT_BLOCKED_MESSAGE,
  DIRTY_DEPLOYMENT_NOTICE_MESSAGE,
  HTMX_REFRESH_HEADER,
  initializeDeploymentRefreshRetry,
  isDeploymentReloadRequested,
  REFRESH_HEADER,
  reloadIfDeploymentChanged,
  resetDeploymentReloadState,
  setDeploymentReloadHandler,
} from "/static/js/common/deployment-version.js";
import { mockSwal } from "/tests/unit/test-utils/globals.js";

// Set the loaded commit SHA meta tag for deployment checks.
const setLoadedCommitSha = (commitSha) => {
  document.head.innerHTML = `<meta name="ocg-commit-sha" content="${commitSha}">`;
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

      // Forced intercepts are consumed so callers do not treat the empty 204 as success.
      expect(htmxChanged).to.equal(true);
      expect(fetchChanged).to.equal(true);
      expect(reloads).to.equal(0);
      expect(isDeploymentReloadRequested()).to.equal(false);
      expect(swal.calls).to.have.length(1);
      expect(swal.calls[0].text).to.equal(DIRTY_DEPLOYMENT_BLOCKED_MESSAGE);
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
});
