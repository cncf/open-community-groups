import { expect } from "@open-wc/testing";

import {
  COMMIT_SHA_HEADER,
  consumePendingDeploymentRefreshAlert,
  DEPLOYMENT_REFRESH_MESSAGE,
  REFRESH_HEADER,
  reloadIfDeploymentChanged,
  resetDeploymentReloadState,
  setDeploymentReloadHandler,
} from "/static/js/common/deployment-version.js";

const setLoadedCommitSha = (commitSha) => {
  document.head.innerHTML = `<meta name="ocg-commit-sha" content="${commitSha}">`;
};

describe("deployment version", () => {
  const originalDateNow = Date.now;

  afterEach(() => {
    Date.now = originalDateNow;
    document.head.innerHTML = "";
    resetDeploymentReloadState();
  });

  it("stores and consumes a one-shot alert marker when the server requests a refresh", () => {
    let reloads = 0;
    setDeploymentReloadHandler(() => {
      reloads += 1;
    });

    const changed = reloadIfDeploymentChanged(
      new Headers({ [REFRESH_HEADER]: "true" }),
    );

    expect(changed).to.equal(true);
    expect(reloads).to.equal(1);
    expect(DEPLOYMENT_REFRESH_MESSAGE).to.equal(
      "This page was refreshed because a new version is available.",
    );
    expect(consumePendingDeploymentRefreshAlert()).to.equal(true);
    expect(consumePendingDeploymentRefreshAlert()).to.equal(false);
  });

  it("stores and consumes a one-shot alert marker when a response comes from a newer commit", () => {
    setLoadedCommitSha("abc123");
    let reloads = 0;
    setDeploymentReloadHandler(() => {
      reloads += 1;
    });

    const changed = reloadIfDeploymentChanged(
      new Headers({ [COMMIT_SHA_HEADER]: "def456" }),
    );

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
