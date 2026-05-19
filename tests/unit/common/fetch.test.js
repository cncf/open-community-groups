import { expect } from "@open-wc/testing";

import { ocgFetch } from "/static/js/common/fetch.js";
import {
  COMMIT_SHA_HEADER,
  REFRESH_HEADER,
  resetDeploymentReloadState,
  setDeploymentReloadHandler,
} from "/static/js/common/deployment-version.js";
import { mockFetch } from "/tests/unit/test-utils/network.js";

const setLoadedCommitSha = (commitSha) => {
  document.head.innerHTML = `<meta name="ocg-commit-sha" content="${commitSha}">`;
};

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
  let fetchMock;

  beforeEach(() => {
    document.head.innerHTML = "";
    fetchMock = mockFetch();
  });

  afterEach(() => {
    document.head.innerHTML = "";
    fetchMock.restore();
    resetDeploymentReloadState();
  });

  it("adds OCG fetch and commit SHA headers for same-origin requests", async () => {
    setLoadedCommitSha("abc123");
    fetchMock.setImpl(async (_url, options) => {
      expect(options.headers).to.be.instanceOf(Headers);
      expect(options.headers.get("X-OCG-Fetch")).to.equal("true");
      expect(options.headers.get(COMMIT_SHA_HEADER)).to.equal("abc123");

      return {
        headers: new Headers(),
        ok: true,
        status: 200,
      };
    });

    await ocgFetch("/test");

    expect(fetchMock.calls).to.have.length(1);
  });

  it("does not add OCG headers for cross-origin requests", async () => {
    setLoadedCommitSha("abc123");
    fetchMock.setImpl(async (_url, options) => {
      expect(options.headers).to.be.instanceOf(Headers);
      expect(options.headers.get("X-OCG-Fetch")).to.equal(null);
      expect(options.headers.get(COMMIT_SHA_HEADER)).to.equal(null);

      return {
        headers: new Headers(),
        ok: true,
        status: 200,
      };
    });

    await ocgFetch("https://example.test/api");

    expect(fetchMock.calls).to.have.length(1);
  });

  it("preserves HTMX headers while adding OCG fetch headers for same-origin requests", async () => {
    setLoadedCommitSha("abc123");
    fetchMock.setImpl(async (_url, options) => {
      expect(options.headers.get("HX-Request")).to.equal("true");
      expect(options.headers.get("X-OCG-Fetch")).to.equal("true");
      expect(options.headers.get(COMMIT_SHA_HEADER)).to.equal("abc123");

      return {
        headers: new Headers(),
        ok: true,
        status: 200,
      };
    });

    await ocgFetch("/test", {
      headers: {
        "HX-Request": "true",
      },
    });

    expect(fetchMock.calls).to.have.length(1);
  });

  it("reloads and leaves callers pending when the server requests a deployment refresh", async () => {
    let reloads = 0;
    setDeploymentReloadHandler(() => {
      reloads += 1;
    });
    fetchMock.setImpl(async () => ({
      headers: new Headers({ [REFRESH_HEADER]: "true" }),
      ok: true,
      status: 204,
    }));

    const settledState = await getSettledStateAfterCurrentTask(ocgFetch("/test"));

    expect(settledState).to.equal("pending");
    expect(reloads).to.equal(1);
  });

  it("reloads and leaves callers pending when a same-origin response comes from a newer commit", async () => {
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

    const settledState = await getSettledStateAfterCurrentTask(ocgFetch("/test"));

    expect(settledState).to.equal("pending");
    expect(reloads).to.equal(1);
  });
});
