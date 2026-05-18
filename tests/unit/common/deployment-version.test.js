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
  afterEach(() => {
    document.head.innerHTML = "";
    resetDeploymentReloadState();
  });

  it("stores and consumes a one-shot alert marker when the server requests a refresh", () => {
    let reloads = 0;
    setDeploymentReloadHandler(() => {
      reloads += 1;
    });

    const changed = reloadIfDeploymentChanged(new Headers({ [REFRESH_HEADER]: "true" }));

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

    const changed = reloadIfDeploymentChanged(new Headers({ [COMMIT_SHA_HEADER]: "def456" }));

    expect(changed).to.equal(true);
    expect(reloads).to.equal(1);
    expect(consumePendingDeploymentRefreshAlert()).to.equal(true);
    expect(consumePendingDeploymentRefreshAlert()).to.equal(false);
  });
});
