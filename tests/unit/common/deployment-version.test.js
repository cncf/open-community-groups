import { expect } from "@open-wc/testing";

import {
  COMMIT_SHA_HEADER,
  consumePendingDeploymentRefreshAlert,
  createDeploymentRefreshUrl,
  DEPLOYMENT_REFRESH_MESSAGE,
  DEPLOYMENT_REFRESH_OUTCOME,
  DEPLOYMENT_REFRESH_PARAM,
  DEPLOYMENT_RELOAD_BLOCKED_MESSAGE,
  DIRTY_DEPLOYMENT_BLOCKED_MESSAGE,
  DIRTY_DEPLOYMENT_NOTICE_MESSAGE,
  DIRTY_DEPLOYMENT_RELOAD_BLOCKED_MESSAGE,
  HTMX_REFRESH_HEADER,
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

// Set the loaded commit SHA meta tag for deployment checks.
const setLoadedCommitSha = (commitSha) => {
  document.head.innerHTML = `<meta name="ocg-commit-sha" content="${commitSha}">`;
};

// Simulate the page loaded by a deployment reload, keeping the reload marker.
const loadReloadedPage = (commitSha, handler) => {
  resetDeploymentReloadState({ clearReloadMarker: false });
  setDeploymentReloadHandler(handler);
  setLoadedCommitSha(commitSha);
};

describe("deployment version", () => {
  const originalDateNow = Date.now;

  afterEach(() => {
    Date.now = originalDateNow;
    document.head.innerHTML = "";
    document.body.innerHTML = "";
    resetDeploymentReloadState();
  });

  it("shows the refreshed notice once after a forced refresh loads a new version", () => {
    // Count reloads requested by the deployment refresh handler.
    setLoadedCommitSha("old");
    let reloads = 0;
    const handler = () => {
      reloads += 1;
    };
    setDeploymentReloadHandler(handler);

    // Process the explicit refresh header from the server.
    const changed = reloadIfDeploymentChanged(new Headers({ [REFRESH_HEADER]: "true" }));
    expect(changed).to.equal(true);
    expect(reloads).to.equal(1);

    // The reloaded page on the new version consumes the one-shot notice.
    loadReloadedPage("new", handler);
    expect(DEPLOYMENT_REFRESH_MESSAGE).to.equal(
      "This page was refreshed because a new version is available.",
    );
    expect(consumePendingDeploymentRefreshAlert()).to.equal(true);
    expect(consumePendingDeploymentRefreshAlert()).to.equal(false);
  });

  it("shows the refreshed notice once after a newer commit response loads a new version", () => {
    // Store the current page commit SHA before reading the response.
    setLoadedCommitSha("abc123");
    let reloads = 0;
    const handler = () => {
      reloads += 1;
    };
    setDeploymentReloadHandler(handler);

    // Process a response from a different commit SHA.
    const changed = reloadIfDeploymentChanged(new Headers({ [COMMIT_SHA_HEADER]: "def456" }));
    expect(changed).to.equal(true);
    expect(reloads).to.equal(1);

    // The reloaded page on the new version consumes the one-shot notice.
    loadReloadedPage("def456", handler);
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

  it("offers a manual reload once instead of looping when a reload returns the same version", async () => {
    // Reload a stale page automatically.
    setLoadedCommitSha("old");
    const reloadUrls = [];
    const handler = (url) => reloadUrls.push(url);
    setDeploymentReloadHandler(handler);
    reloadIfDeploymentChanged(new Headers({ [COMMIT_SHA_HEADER]: "new" }));
    expect(reloadUrls).to.have.length(1);
    const swal = mockSwal();
    swal.setNextResult({ isConfirmed: false, isDismissed: true });

    try {
      // The reload returned the same stale version, so no refreshed notice is shown.
      loadReloadedPage("old", handler);
      expect(consumePendingDeploymentRefreshAlert()).to.equal(false);

      // Later mismatches keep the page and offer one passive reload prompt.
      expect(reloadIfDeploymentChanged(new Headers({ [COMMIT_SHA_HEADER]: "new" }))).to.equal(false);
      expect(reloadIfDeploymentChanged(new Headers({ [COMMIT_SHA_HEADER]: "new" }))).to.equal(false);
      await waitForMicrotask();
      expect(reloadUrls).to.have.length(1);
      expect(isDeploymentReloadRequested()).to.equal(false);
      expect(swal.calls).to.have.length(1);
      expect(swal.calls[0]).to.include({ confirmButtonText: "Reload", icon: "info", showCancelButton: true });
    } finally {
      swal.restore();
    }
  });

  it("reloads through a cache-busting URL when the manual reload prompt is accepted", async () => {
    // Load a page that an automatic reload could not move to the new version.
    setLoadedCommitSha("old");
    const reloadUrls = [];
    const handler = (url) => reloadUrls.push(url);
    setDeploymentReloadHandler(handler);
    reloadIfDeploymentChanged(new Headers({ [COMMIT_SHA_HEADER]: "new" }));
    loadReloadedPage("old", handler);
    const swal = mockSwal();

    try {
      // Accept the manual reload prompt.
      reloadIfDeploymentChanged(new Headers({ [COMMIT_SHA_HEADER]: "new" }));
      await waitForMicrotask();

      // The accepted prompt reloads through a fresh cache-busting URL.
      expect(reloadUrls).to.have.length(2);
      expect(new URL(reloadUrls[1]).searchParams.has(DEPLOYMENT_REFRESH_PARAM)).to.equal(true);
      expect(isDeploymentReloadRequested()).to.equal(true);
    } finally {
      swal.restore();
    }
  });

  it("does not discard edits made while the manual reload prompt was open", async () => {
    // Load a page that an automatic reload could not move to the new version.
    setLoadedCommitSha("old");
    const reloadUrls = [];
    const handler = (url) => reloadUrls.push(url);
    setDeploymentReloadHandler(handler);
    reloadIfDeploymentChanged(new Headers({ [COMMIT_SHA_HEADER]: "new" }));
    loadReloadedPage("old", handler);
    const swal = mockSwal();

    try {
      // Open the prompt, then edit the form before its Reload action is confirmed.
      reloadIfDeploymentChanged(new Headers({ [COMMIT_SHA_HEADER]: "new" }));
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

  it("warns on every blocked user request but prompts background intercepts once", () => {
    // Load a page that an automatic reload could not move to the new version.
    setLoadedCommitSha("old");
    let reloads = 0;
    const handler = () => {
      reloads += 1;
    };
    setDeploymentReloadHandler(handler);
    reloadIfDeploymentChanged(new Headers({ [COMMIT_SHA_HEADER]: "new" }));
    loadReloadedPage("old", handler);
    const swal = mockSwal();
    swal.setNextResult({ isConfirmed: false, isDismissed: true });

    try {
      // Background intercepts stay blocked but use the passive prompt once.
      const refreshHeaders = new Headers({ [HTMX_REFRESH_HEADER]: "true" });
      expect(processDeploymentRefresh(refreshHeaders, document, { background: true })).to.equal(
        DEPLOYMENT_REFRESH_OUTCOME.BLOCKED,
      );
      expect(processDeploymentRefresh(refreshHeaders, document, { background: true })).to.equal(
        DEPLOYMENT_REFRESH_OUTCOME.BLOCKED,
      );
      expect(swal.calls).to.have.length(1);
      expect(swal.calls.at(-1)).to.include({ confirmButtonText: "Reload", icon: "info" });

      // User-started intercepts always explain that their request did not complete.
      expect(processDeploymentRefresh(new Headers({ [REFRESH_HEADER]: "true" }))).to.equal(
        DEPLOYMENT_REFRESH_OUTCOME.BLOCKED,
      );
      expect(processDeploymentRefresh(refreshHeaders)).to.equal(DEPLOYMENT_REFRESH_OUTCOME.BLOCKED);
      expect(swal.calls).to.have.length(3);
      expect(swal.calls.at(-1)).to.include({
        confirmButtonText: "Reload",
        icon: "warning",
        text: DEPLOYMENT_RELOAD_BLOCKED_MESSAGE,
      });
      expect(reloads).to.equal(1);
      expect(isDeploymentReloadRequested()).to.equal(false);
    } finally {
      swal.restore();
    }
  });

  it("reloads automatically again once a newer version is loaded", () => {
    // Load a page that an automatic reload could not move to the new version.
    setLoadedCommitSha("old");
    let reloads = 0;
    const handler = () => {
      reloads += 1;
    };
    setDeploymentReloadHandler(handler);
    reloadIfDeploymentChanged(new Headers({ [COMMIT_SHA_HEADER]: "new" }));
    loadReloadedPage("old", handler);
    const swal = mockSwal();
    swal.setNextResult({ isConfirmed: false, isDismissed: true });

    try {
      // The stale page only offers a manual reload.
      expect(reloadIfDeploymentChanged(new Headers({ [COMMIT_SHA_HEADER]: "new" }))).to.equal(false);
      expect(reloads).to.equal(1);

      // A page on a newer version clears the marker and reloads automatically for the next deploy.
      loadReloadedPage("new", handler);
      expect(consumePendingDeploymentRefreshAlert()).to.equal(true);
      expect(reloadIfDeploymentChanged(new Headers({ [COMMIT_SHA_HEADER]: "newer" }))).to.equal(true);
      expect(reloads).to.equal(2);
    } finally {
      swal.restore();
    }
  });
});
