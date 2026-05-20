import { expect } from "@open-wc/testing";

import {
  COMMIT_SHA_HEADER,
  consumePendingDeploymentRefreshAlert,
  DEPLOYMENT_REFRESH_MESSAGE,
  initializeDeploymentRefreshRetry,
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
    resetDeploymentReloadState();
  });

  it("stores and consumes a one-shot alert marker when the server requests a refresh", () => {
    // Count reloads requested by the deployment refresh handler.
    let reloads = 0;
    setDeploymentReloadHandler(() => {
      reloads += 1;
    });

    // Process the explicit refresh header from the server.
    const changed = reloadIfDeploymentChanged(
      new Headers({ [REFRESH_HEADER]: "true" }),
    );

    // Commit-sha refresh stores and consumes the reload alert marker.
    expect(changed).to.equal(true);
    expect(reloads).to.equal(1);
    expect(DEPLOYMENT_REFRESH_MESSAGE).to.equal(
      "This page was refreshed because a new version is available.",
    );
    expect(consumePendingDeploymentRefreshAlert()).to.equal(true);
    expect(consumePendingDeploymentRefreshAlert()).to.equal(false);
  });

  it("stores and consumes a one-shot alert marker when a response comes from a newer commit", () => {
    // Store the current page commit SHA before reading the response.
    setLoadedCommitSha("abc123");
    let reloads = 0;
    setDeploymentReloadHandler(() => {
      reloads += 1;
    });

    // Process a response from a different commit SHA.
    const changed = reloadIfDeploymentChanged(
      new Headers({ [COMMIT_SHA_HEADER]: "def456" }),
    );

    // Cross-version responses store and consume the reload alert marker.
    expect(changed).to.equal(true);
    expect(reloads).to.equal(1);
    expect(consumePendingDeploymentRefreshAlert()).to.equal(true);
    expect(consumePendingDeploymentRefreshAlert()).to.equal(false);
  });

  it("suppresses repeated automatic refreshes within the public cache window", () => {
    Date.now = () => 1_000;
    setLoadedCommitSha("old");
    let reloads = 0;
    setDeploymentReloadHandler(() => {
      reloads += 1;
    });

    const firstChanged = reloadIfDeploymentChanged(
      new Headers({ [COMMIT_SHA_HEADER]: "new" }),
    );

    expect(firstChanged).to.equal(true);
    expect(reloads).to.equal(1);
    expect(consumePendingDeploymentRefreshAlert()).to.equal(true);

    resetDeploymentReloadState({ clearRefreshHistory: false });
    setDeploymentReloadHandler(() => {
      reloads += 1;
    });
    Date.now = () => 1_000 + 4 * 60 * 1000;

    const secondChanged = reloadIfDeploymentChanged(
      new Headers({ [COMMIT_SHA_HEADER]: "new" }),
    );

    expect(secondChanged).to.equal(true);
    expect(reloads).to.equal(1);
    expect(consumePendingDeploymentRefreshAlert()).to.equal(false);
  });

  it("schedules automatic refresh retries when cached HTML is still loaded", () => {
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

      const changed = reloadIfDeploymentChanged(
        new Headers({ [COMMIT_SHA_HEADER]: "new" }),
      );

      expect(changed).to.equal(true);
      expect(reloads).to.equal(1);
      expect(swal.calls).to.have.length(1);
      expect(retryTimer.delay).to.equal(30_000);

      retryTimer.callback();

      expect(reloads).to.equal(2);
    } finally {
      retryTimer.restore();
      swal.restore();
    }
  });

  it("resumes refresh retries while the stale commit is still loaded", () => {
    Date.now = () => 1_000;
    setLoadedCommitSha("old");
    setDeploymentReloadHandler(() => {});
    const swal = mockSwal();
    const firstRetryTimer = captureDeploymentRefreshRetryTimer();

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

    const changed = reloadIfDeploymentChanged(
      new Headers({ [COMMIT_SHA_HEADER]: "new" }),
    );

    expect(changed).to.equal(true);
    expect(reloads).to.equal(2);
    expect(consumePendingDeploymentRefreshAlert()).to.equal(true);
  });
});
