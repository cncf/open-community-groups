import { expect } from "@open-wc/testing";

import {
  waitForAnimationFrames,
  waitForMicrotask,
} from "/tests/unit/test-utils/async.js";
import {
  mockScrollTo,
  resetDom,
  setLocationPath,
  trackAddedEventListeners,
} from "/tests/unit/test-utils/dom.js";
import { dispatchHtmxAfterSwap } from "/tests/unit/test-utils/htmx.js";
import { mockFetch } from "/tests/unit/test-utils/network.js";

describe("site docs shell", () => {
  let fetchMock;
  let listenerTracker;
  let originalAppendChild;
  let originalAppend;
  let originalInsertBefore;
  let processCalls;
  let scrollToMock;

  const docsHeadSelector = [
    "#ocg-docsify-vue-scoped-style",
    "#ocg-docs-theme-scoped-style",
    'link#ocg-docs-shell-overrides[href="/static/docs/assets/shell.css"]',
    'script[src="/static/vendor/js/docsify.v4.13.1.min.js"]',
    'script[src="/static/vendor/js/docsify-copy-code.v3.0.2.min.js"]',
  ].join(", ");

  // Clean up docs head state.
  const cleanupDocsHead = () => {
    document.head
      .querySelectorAll(docsHeadSelector)
      .forEach((node) => node.remove());
  };

  // Prepare the module under test.
  const importDocsShell = () =>
    import(`/static/js/site/docs/shell.js?test=${Date.now()}-${Math.random()}`);

  // Schedule script load for the test.
  const scheduleScriptLoad = (...nodes) => {
    nodes.flat().forEach((node) => {
      if (!(node instanceof HTMLScriptElement)) {
        return;
      }

      // Run the behavior under test.
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
    scrollToMock = mockScrollTo();
    window.htmx = {
      process(target) {
        processCalls.push(target);
      },
    };

    // Run the behavior under test.
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
    scrollToMock.restore();
    cleanupDocsHead();
    delete window.$docsify;
    delete window.htmx;
    resetDom();
  });

  it("loads safely when the docs root is not present", async () => {
    // Load the page module after setup.
    await importDocsShell();

    // Verify loads safely when the docs root is not present.
    expect(document.querySelector(".ocg-docs-root")).to.equal(null);
  });

  it("renders a fallback error when docs assets fail to load", async () => {
    // Render the DOM fixture for rendering a fallback error when docs assets fail.
    document.body.innerHTML = `
      <div class="ocg-docs-root">
        <div id="ocg-docs-app"></div>
      </div>
    `;

    // Configure browser state before loading failed docs assets.
    fetchMock.setImpl(async () => ({
      ok: false,
      status: 500,
      async text() {
        return "";
      },
    }));

    // Load the page module after setup.
    await importDocsShell();
    await waitForMicrotask();
    await waitForAnimationFrames(2);

    // Verify renders a fallback error when docs assets fail to load.
    expect(
      document.querySelector("#ocg-docs-app [role='alert']")?.textContent,
    ).to.equal(
      "We could not load the documentation. Please refresh and try again.",
    );
  });

  it("rewrites app links, mirrors body classes, and enhances markdown tables after mount", async () => {
    // Render the DOM fixture for rewriting app links, mirrors body classes.
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

    // Configure browser state before rewriting docs content.
    fetchMock.setImpl(async () => ({
      ok: true,
      async text() {
        return "body { color: black; }";
      },
    }));

    // Load the page module after setup.
    await importDocsShell();
    await waitForMicrotask();
    await waitForAnimationFrames(3);

    // Read the docs root after app links and body classes are synced.
    const docsRoot = document.querySelector(".ocg-docs-root");
    const docsLink = document.getElementById("docs-link");
    const tableCell = document.querySelector("tbody td");

    // App links, body classes, and markdown tables are updated.
    expect(window.$docsify?.basePath).to.equal("/static/docs/");
    expect(docsRoot?.classList.contains("close")).to.equal(true);
    expect(docsLink?.getAttribute("href")).to.equal("/dashboard/groups");
    expect(docsLink?.getAttribute("hx-boost")).to.equal("true");
    expect(docsLink?.getAttribute("hx-target")).to.equal("body");
    expect(tableCell?.getAttribute("data-label")).to.equal("City");
    expect(processCalls).to.have.length(1);

    // Update fixture state before asserting the new state.
    document.body.classList.remove("close");
    await waitForMicrotask();

    // Updated docs content keeps links, body classes, and tables in sync.
    expect(docsRoot?.classList.contains("close")).to.equal(false);
  });

  it("removes injected docs styles and scripts during head cleanup", async () => {
    // Build the docs shell fixture before loading injected assets.
    document.body.innerHTML = `
      <div class="ocg-docs-root">
        <div id="ocg-docs-app"></div>
      </div>
    `;

    // Return stylesheet content for the injected docs asset request.
    fetchMock.setImpl(async () => ({
      ok: true,
      async text() {
        return "body { color: black; }";
      },
    }));

    // Load the page module after setup.
    await importDocsShell();
    await waitForMicrotask();
    await waitForAnimationFrames(3);

    // Confirm the docs assets were injected into the document head.
    expect(document.head.querySelectorAll(docsHeadSelector).length).to.equal(5);
    expect(document.getElementById("ocg-docs-shell-overrides")?.tagName).to.equal("LINK");

    // Run the docs head cleanup helper.
    cleanupDocsHead();

    // Confirm the injected docs assets were removed.
    expect(document.head.querySelectorAll(docsHeadSelector).length).to.equal(0);
  });

  it("updates the docs hash, scrolls to the section, and syncs the active sidebar item", async () => {
    // Verify updates the docs hash, scrolls to the section.
    setLocationPath("/docs");
    window.location.hash = "#/guide";
    document.body.innerHTML = `
      <div class="ocg-docs-root">
        <div id="ocg-docs-app">
          <div class="sidebar-nav">
            <ul>
              <li id="guide-item" class="collapse">
                <a href="#/guide">Guide</a>
                <ul class="app-sub-sidebar">
                  <li id="section-item">
                    <a id="section-link" href="#/guide?id=section-a">Section A</a>
                  </li>
                </ul>
              </li>
            </ul>
          </div>
          <div class="markdown-section">
            <h2 id="section-a">Section A</h2>
          </div>
        </div>
      </div>
    `;

    // Keep a reference to the section a element.
    document.getElementById("section-a").getBoundingClientRect = () => ({
      top: 120,
      bottom: 160,
      left: 0,
      right: 100,
      width: 100,
      height: 40,
      x: 0,
      y: 120,
      toJSON() {},
    });

    // Configure browser state before testing docs hash navigation.
    fetchMock.setImpl(async () => ({
      ok: true,
      async text() {
        return "body { color: black; }";
      },
    }));

    // Load the page module after setup.
    await importDocsShell();
    await waitForMicrotask();
    await waitForAnimationFrames(3);

    // Click the section link inside the docs shell.
    document.getElementById("section-link")?.dispatchEvent(
      new MouseEvent("click", {
        bubbles: true,
        cancelable: true,
        composed: true,
      }),
    );
    await waitForAnimationFrames(3);

    // Verify updates the docs hash, scrolls to the section, and syncs the active.
    expect(window.location.hash).to.equal("#/guide?id=section-a");
    expect(scrollToMock.calls.at(-1)).to.deep.equal({
      behavior: "auto",
      top: 90,
    });
    expect(
      document.getElementById("guide-item")?.classList.contains("collapse"),
    ).to.equal(false);
    expect(
      document.getElementById("section-item")?.classList.contains("active"),
    ).to.equal(true);
  });

  it("cleans up and remounts docs lifecycle on swap and page events", async () => {
    // Render the DOM fixture for cleaning up and remounts docs lifecycle on swap.
    document.body.innerHTML = `
      <div class="ocg-docs-root">
        <div id="ocg-docs-app">
          <div class="markdown-section">
            <a id="docs-link" href="#/dashboard/groups">Dashboard</a>
          </div>
        </div>
      </div>
    `;

    // Configure browser state before testing docs lifecycle remounting.
    fetchMock.setImpl(async () => ({
      ok: true,
      async text() {
        return "body { color: black; }";
      },
    }));

    // Load the page module after setup.
    await importDocsShell();
    await waitForMicrotask();
    await waitForAnimationFrames(3);

    // Verify cleans up and remounts docs lifecycle on swap and page events.
    expect(document.head.querySelectorAll(docsHeadSelector).length).to.equal(5);

    // Render the DOM fixture for cleaning up and remounts docs lifecycle on swap.
    document.body.innerHTML = "";
    dispatchHtmxAfterSwap();
    await waitForMicrotask();

    // Mount the docs shell again after the body swap.
    document.body.innerHTML = `
      <div class="ocg-docs-root">
        <div id="ocg-docs-app">
          <div class="markdown-section">
            <a id="remounted-link" href="#/dashboard/groups">Dashboard</a>
          </div>
        </div>
      </div>
    `;
    window.dispatchEvent(new Event("pageshow"));
    await waitForMicrotask();
    await waitForAnimationFrames(3);

    // Verify cleans up and remounts docs lifecycle on swap and page events.
    expect(document.head.querySelectorAll(docsHeadSelector).length).to.equal(5);
    expect(window.$docsify?.basePath).to.equal("/static/docs/");
    expect(
      document.getElementById("remounted-link")?.getAttribute("hx-boost"),
    ).to.equal("true");
  });
});
