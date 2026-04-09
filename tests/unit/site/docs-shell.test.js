import { expect } from "@open-wc/testing";

import { waitForAnimationFrames, waitForMicrotask } from "/tests/unit/test-utils/async.js";
import { resetDom, trackAddedEventListeners } from "/tests/unit/test-utils/dom.js";
import { mockFetch } from "/tests/unit/test-utils/network.js";

describe("site docs shell", () => {
  let fetchMock;
  let listenerTracker;
  let originalAppendChild;
  let originalAppend;
  let originalInsertBefore;
  let processCalls;

  const docsHeadSelector = [
    "#ocg-docsify-vue-scoped-style",
    "#ocg-docs-theme-scoped-style",
    "#ocg-docs-shell-overrides",
    'script[src="/static/vendor/js/docsify.v4.13.1.min.js"]',
    'script[src="/static/vendor/js/docsify-copy-code.v3.0.2.min.js"]',
  ].join(", ");

  const cleanupDocsHead = () => {
    document.head.querySelectorAll(docsHeadSelector).forEach((node) => node.remove());
  };

  const importDocsShell = () => import(`/static/js/site/docs-shell.js?test=${Date.now()}-${Math.random()}`);

  const scheduleScriptLoad = (...nodes) => {
    nodes.flat().forEach((node) => {
      if (!(node instanceof HTMLScriptElement)) {
        return;
      }

      queueMicrotask(() => {
        node.dataset.loaded = "1";
        node.dispatchEvent(new Event("load"));
      });
    });
  };

  beforeEach(() => {
    resetDom();
    cleanupDocsHead();
    listenerTracker = trackAddedEventListeners();
    fetchMock = mockFetch();
    processCalls = [];
    window.htmx = {
      process(target) {
        processCalls.push(target);
      },
    };

    originalAppendChild = document.head.appendChild.bind(document.head);
    originalAppend = document.head.append.bind(document.head);
    originalInsertBefore = document.head.insertBefore.bind(document.head);
    document.head.appendChild = (node) => {
      const appendedNode = originalAppendChild(node);
      scheduleScriptLoad(node);
      return appendedNode;
    };
    document.head.append = (...nodes) => {
      const result = originalAppend(...nodes);
      scheduleScriptLoad(...nodes);
      return result;
    };
    document.head.insertBefore = (node, child) => {
      const insertedNode = originalInsertBefore(node, child);
      scheduleScriptLoad(node);
      return insertedNode;
    };
  });

  afterEach(() => {
    document.head.appendChild = originalAppendChild;
    document.head.append = originalAppend;
    document.head.insertBefore = originalInsertBefore;
    listenerTracker.restore();
    fetchMock.restore();
    cleanupDocsHead();
    delete window.$docsify;
    delete window.htmx;
    resetDom();
  });

  it("loads safely when the docs root is not present", async () => {
    await importDocsShell();

    expect(document.querySelector(".ocg-docs-root")).to.equal(null);
  });

  it("renders a fallback error when docs assets fail to load", async () => {
    document.body.innerHTML = `
      <div class="ocg-docs-root">
        <div id="ocg-docs-app"></div>
      </div>
    `;

    fetchMock.setImpl(async () => ({
      ok: false,
      status: 500,
      async text() {
        return "";
      },
    }));

    await importDocsShell();
    await waitForMicrotask();
    await waitForAnimationFrames(2);

    expect(document.querySelector("#ocg-docs-app [role='alert']")?.textContent).to.equal(
      "We could not load the documentation. Please refresh and try again.",
    );
  });

  it("rewrites app links, mirrors body classes, and enhances markdown tables after mount", async () => {
    document.body.innerHTML = `
      <div class="ocg-docs-root">
        <div id="ocg-docs-app">
          <div class="markdown-section">
            <a id="docs-link" href="#/dashboard/groups">Dashboard</a>
            <table>
              <thead>
                <tr>
                  <th>City</th>
                  <th>Country</th>
                </tr>
              </thead>
              <tbody>
                <tr>
                  <td>Málaga</td>
                  <td>Spain</td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>
      </div>
    `;
    document.body.classList.add("close");

    fetchMock.setImpl(async () => ({
      ok: true,
      async text() {
        return "body { color: black; }";
      },
    }));

    await importDocsShell();
    await waitForMicrotask();
    await waitForAnimationFrames(3);

    const docsRoot = document.querySelector(".ocg-docs-root");
    const docsLink = document.getElementById("docs-link");
    const tableCell = document.querySelector("tbody td");

    expect(window.$docsify?.basePath).to.equal("/static/docs/");
    expect(docsRoot?.classList.contains("close")).to.equal(true);
    expect(docsLink?.getAttribute("href")).to.equal("/dashboard/groups");
    expect(docsLink?.getAttribute("hx-boost")).to.equal("true");
    expect(docsLink?.getAttribute("hx-target")).to.equal("body");
    expect(tableCell?.getAttribute("data-label")).to.equal("City");
    expect(processCalls).to.have.length(1);

    document.body.classList.remove("close");
    await waitForMicrotask();

    expect(docsRoot?.classList.contains("close")).to.equal(false);
  });

  it("removes injected docs styles and scripts during head cleanup", async () => {
    document.body.innerHTML = `
      <div class="ocg-docs-root">
        <div id="ocg-docs-app"></div>
      </div>
    `;

    fetchMock.setImpl(async () => ({
      ok: true,
      async text() {
        return "body { color: black; }";
      },
    }));

    await importDocsShell();
    await waitForMicrotask();
    await waitForAnimationFrames(3);

    expect(document.head.querySelectorAll(docsHeadSelector).length).to.equal(5);

    cleanupDocsHead();

    expect(document.head.querySelectorAll(docsHeadSelector).length).to.equal(0);
  });
});
