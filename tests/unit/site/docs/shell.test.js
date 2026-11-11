import { expect } from "@open-wc/testing";

import {
  COMMIT_SHA_HEADER,
  isDeploymentReloadRequested,
  resetDeploymentReloadState,
  setDeploymentReloadHandler,
} from "/static/js/common/deployment-version.js";
import { PHONE_MEDIA_QUERY } from "/static/js/common/phone-viewport.js";
import { setDocsReloadHandler } from "/static/js/site/docs/interactions.js";
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
import { stubMatchMedia } from "/tests/unit/test-utils/media.js";
import { mockFetch } from "/tests/unit/test-utils/network.js";

const SCROLL_POSITIONS_KEY = "ocg-docs-scroll-positions";
const SCROLL_RESTORE_KEY = "ocg-docs-scroll-restore";

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
    document.head.querySelector('meta[name="ocg-commit-sha"]')?.remove();
    resetDeploymentReloadState();
    sessionStorage.removeItem(SCROLL_RESTORE_KEY);
    delete window.$docsify;
    delete window.Docsify;
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

  it("loads cached docs styles from an older deployment without reloading the page", async () => {
    // Render the docs shell on a page loaded from the current deployment.
    document.body.innerHTML = `
      <div class="ocg-docs-root">
        <div id="ocg-docs-app"></div>
      </div>
    `;
    const commitShaMeta = document.createElement("meta");
    commitShaMeta.name = "ocg-commit-sha";
    commitShaMeta.content = "current-commit";
    document.head.appendChild(commitShaMeta);

    // Record reloads and serve stylesheets cached with an older commit SHA.
    const reloadUrls = [];
    setDeploymentReloadHandler((url) => reloadUrls.push(url));
    fetchMock.setImpl(async () => ({
      headers: new Headers({ [COMMIT_SHA_HEADER]: "older-commit" }),
      ok: true,
      status: 200,
      async text() {
        return "body { color: black; }";
      },
    }));

    // Load the page module after setup.
    await importDocsShell();
    await waitForMicrotask();
    await waitForAnimationFrames(3);

    // Verify the styles load without deployment headers or reloads.
    const styleCalls = fetchMock.calls.filter(([url]) =>
      String(url).endsWith(".css"),
    );
    expect(styleCalls.map(([url]) => url)).to.have.members([
      "/static/vendor/css/docsify-vue.v4.13.1.min.css",
      "/static/docs/assets/theme.css",
    ]);
    styleCalls.forEach(([, init]) => {
      expect(new Headers(init?.headers).has(COMMIT_SHA_HEADER)).to.equal(false);
    });
    expect(
      document.getElementById("ocg-docsify-vue-scoped-style")?.textContent,
    ).to.include("color: black");
    expect(
      document.getElementById("ocg-docs-theme-scoped-style")?.textContent,
    ).to.include("color: black");
    expect(isDeploymentReloadRequested()).to.equal(false);
    expect(reloadUrls).to.deep.equal([]);
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

  describe("after Docsify replaces the app node", () => {
    let media;
    let reloads;

    /** Mounts docs, replaces the app node as Docsify does, then runs a later swap. */
    const mountAndSwap = async () => {
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

      document.getElementById("ocg-docs-app").replaceWith(document.createElement("main"));
      dispatchHtmxAfterSwap();
      await waitForMicrotask();
    };

    /** Reports whether the mount still mirrors the body classes. */
    const isMounted = async () => {
      document.body.classList.add("close");
      await waitForMicrotask();
      const mounted = document.querySelector(".ocg-docs-root").classList.contains("close");
      document.body.classList.remove("close");
      await waitForMicrotask();
      return mounted;
    };

    beforeEach(() => {
      reloads = 0;
      setDocsReloadHandler(() => {
        reloads += 1;
      });
    });

    afterEach(() => {
      setDocsReloadHandler(() => window.location.reload());
      media?.restore();
      document.body.classList.remove("close");
    });

    for (const { matches, name } of [
      { matches: false, name: "off phones" },
      { matches: true, name: "on phones" },
    ]) {
      it(`keeps the mount through a later swap ${name}`, async () => {
        media = stubMatchMedia({ [PHONE_MEDIA_QUERY]: matches });

        await mountAndSwap();

        // Verify a late swap, such as the user menu, leaves the mount live.
        expect(await isMounted()).to.equal(true);
      });
    }

    it("keeps the mount through a later pageshow", async () => {
      await mountAndSwap();

      window.dispatchEvent(new PageTransitionEvent("pageshow"));
      await waitForMicrotask();

      expect(await isMounted()).to.equal(true);
    });

    it("keeps enhancing later pages off phones", async () => {
      // Lose the app node, then render a later page as Docsify does.
      await mountAndSwap();
      window.location.hash = "#/guide";
      document.querySelector(".ocg-docs-root main").innerHTML = `
        <div class="markdown-section">
          <a id="app-link" href="#/dashboard/groups">Dashboard</a>
          <a id="anchor-link" href="#/guide?id=section-a">Section A</a>
          <h2 id="section-a">Section A</h2>
          <table>
            <thead><tr><th>City</th></tr></thead>
            <tbody><tr><td>Málaga</td></tr></tbody>
          </table>
        </div>
      `;
      window.$docsify.plugins.forEach((plugin) => plugin({ doneEach: (callback) => callback() }));
      await waitForAnimationFrames(3);

      // Verify tables and app links are still enhanced.
      expect(document.querySelector("tbody td")?.getAttribute("data-label")).to.equal("City");
      expect(document.getElementById("app-link")?.getAttribute("href")).to.equal("/dashboard/groups");

      // Verify same-page anchors still take the instant jump.
      const event = new MouseEvent("click", { bubbles: true, cancelable: true });
      document.getElementById("anchor-link").dispatchEvent(event);
      expect(event.defaultPrevented).to.equal(true);
      expect(scrollToMock.calls.at(-1)?.behavior).to.equal("auto");
    });

    describe("on a phone query change", () => {
      it("follows the query from a mount that outlived a swap, without reloading", async () => {
        // Load wider than the query and take a later swap, then rotate both ways.
        media = stubMatchMedia();
        await mountAndSwap();
        expect(window.$docsify.topMargin).to.equal(0);

        media.setMatches(PHONE_MEDIA_QUERY, true);
        expect(window.$docsify.topMargin).to.equal(72);
        media.setMatches(PHONE_MEDIA_QUERY, false);
        expect(window.$docsify.topMargin).to.equal(0);
        expect(reloads).to.equal(0);
      });

      it("leaves a mount that is still starting to read the query itself", async () => {
        // Hold the styles, so the mount owns the root but has no phone shell yet.
        let releaseStyles;
        const stylesHeld = new Promise((resolve) => {
          releaseStyles = resolve;
        });
        media = stubMatchMedia();
        document.body.innerHTML = `
          <div class="ocg-docs-root">
            <div id="ocg-docs-app"></div>
          </div>
        `;
        fetchMock.setImpl(async () => {
          await stylesHeld;
          return {
            ok: true,
            async text() {
              return "body { color: black; }";
            },
          };
        });
        await importDocsShell();

        media.setMatches(PHONE_MEDIA_QUERY, true);
        expect(reloads).to.equal(0);

        // Verify the mount picks up the phone once it finishes.
        releaseStyles();
        await waitForMicrotask();
        await waitForAnimationFrames(3);
        expect(window.$docsify.topMargin).to.equal(72);
        expect(reloads).to.equal(0);
      });

      it("ignores pages without docs", async () => {
        // Leave the docs through a swap.
        media = stubMatchMedia();
        await mountAndSwap();
        document.body.innerHTML = "<div></div>";
        dispatchHtmxAfterSwap();
        await waitForMicrotask();

        media.setMatches(PHONE_MEDIA_QUERY, true);

        // Verify the listener left with the mount.
        expect(media.listeners(PHONE_MEDIA_QUERY).size).to.equal(0);
        expect(reloads).to.equal(0);
      });

      it("keeps one query listener through unmounts and remounts", async () => {
        // Mount, leave and mount a new root.
        media = stubMatchMedia();
        await mountAndSwap();
        expect(media.listeners(PHONE_MEDIA_QUERY).size).to.equal(1);

        document.body.innerHTML = "<div></div>";
        dispatchHtmxAfterSwap();
        await waitForMicrotask();
        document.body.innerHTML = `
          <div class="ocg-docs-root">
            <div id="ocg-docs-app"></div>
          </div>
        `;
        dispatchHtmxAfterSwap();
        await waitForMicrotask();
        await waitForAnimationFrames(3);

        expect(media.listeners(PHONE_MEDIA_QUERY).size).to.equal(1);
      });
    });

    describe("on an HTMX history restore", () => {
      /** Leaves the docs and restores their snapshot, which keeps Docsify's markup only. */
      const leaveAndRestore = async () => {
        await mountAndSwap();
        document.body.innerHTML = "<div></div>";
        dispatchHtmxAfterSwap();
        document.body.innerHTML = '<div class="ocg-docs-root"><main></main></div>';
        document.dispatchEvent(new CustomEvent("htmx:historyRestore"));
        await waitForMicrotask();
      };

      for (const { matches, name } of [
        { matches: false, name: "off phones" },
        { matches: true, name: "on phones" },
      ]) {
        it(`reloads ${name}, where the snapshot's markup is dead`, async () => {
          media = stubMatchMedia({ [PHONE_MEDIA_QUERY]: matches });

          await leaveAndRestore();

          expect(reloads).to.equal(1);
        });
      }

      it("ignores restores of pages without docs", async () => {
        await mountAndSwap();
        document.body.innerHTML = "<div></div>";
        document.dispatchEvent(new CustomEvent("htmx:historyRestore"));
        await waitForMicrotask();

        expect(reloads).to.equal(0);
      });

      describe("on markup that still has the app node", () => {
        const dispatchRestore = () => {
          document.dispatchEvent(
            new CustomEvent("htmx:historyRestore", { detail: { cacheMiss: true } }),
          );
        };

        /** Leaves the docs, then swaps fresh markup in with the events in the given order. */
        const leaveAndMiss = async (dispatchEvents) => {
          await mountAndSwap();
          document.body.innerHTML = "<div></div>";
          dispatchHtmxAfterSwap();
          document.body.innerHTML = `
            <div class="ocg-docs-root">
              <div id="ocg-docs-app"></div>
            </div>
          `;
          dispatchEvents();
          await waitForMicrotask();
        };

        for (const { docsifyLoaded, name } of [
          { docsifyLoaded: true, name: "with Docsify loaded" },
          { docsifyLoaded: false, name: "before Docsify loaded" },
        ]) {
          it(`reloads once ${name}, when afterSwap comes first`, async () => {
            if (docsifyLoaded) {
              window.Docsify = {};
            }

            await leaveAndMiss(() => {
              dispatchHtmxAfterSwap();
              dispatchRestore();
            });

            expect(reloads).to.equal(1);
          });

          it(`reloads once ${name}, when the restore comes first`, async () => {
            if (docsifyLoaded) {
              window.Docsify = {};
            }

            await leaveAndMiss(() => {
              dispatchRestore();
              dispatchHtmxAfterSwap();
            });

            expect(reloads).to.equal(1);
          });
        }
      });

      it("arms the scroll restore for the reload", async () => {
        await leaveAndRestore();

        expect(JSON.parse(sessionStorage.getItem(SCROLL_RESTORE_KEY)).url).to.equal(window.location.href);
      });
    });

    it("reloads a boosted arrival once Docsify has run, without arming a restore", async () => {
      window.Docsify = {};

      // Arrive through a boosted link, which is no history restore.
      await mountAndSwap();
      document.body.innerHTML = "<div></div>";
      dispatchHtmxAfterSwap();
      document.body.innerHTML = `
        <div class="ocg-docs-root">
          <div id="ocg-docs-app"></div>
        </div>
      `;
      dispatchHtmxAfterSwap();
      await waitForMicrotask();

      // Verify the reload starts Docsify and no old position comes back.
      expect(reloads).to.equal(1);
      expect(sessionStorage.getItem(SCROLL_RESTORE_KEY)).to.equal(null);
    });

    it("reloads a snapshot this module first runs on, after the restore event fired", async () => {
      document.body.innerHTML = '<div class="ocg-docs-root"><main></main></div>';

      await importDocsShell();
      await waitForMicrotask();

      expect(reloads).to.equal(1);
      expect(JSON.parse(sessionStorage.getItem(SCROLL_RESTORE_KEY)).url).to.equal(window.location.href);
    });
  });

  describe("after the reload that replaces a history entry", () => {
    const originalPath = `${window.location.pathname}${window.location.search}`;

    /** Mounts docs, then finishes the given number of Docsify renders. */
    const mountAndRender = async (renders) => {
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
      await waitForAnimationFrames(2);

      let doneEach = null;
      window.$docsify.plugins[0]({
        doneEach(callback) {
          doneEach = callback;
        },
      });
      for (let render = 0; render < renders; render += 1) {
        doneEach();
      }
      await waitForAnimationFrames(2);
    };

    /** Leaves a saved position for the current URL, armed or not. */
    const savePosition = ({ armed }) => {
      const url = window.location.href;
      sessionStorage.setItem(SCROLL_POSITIONS_KEY, JSON.stringify({ [url]: 1500 }));
      if (armed) {
        sessionStorage.setItem(
          SCROLL_RESTORE_KEY,
          JSON.stringify({ document: window.performance.timeOrigin - 1, url }),
        );
      }
    };

    beforeEach(() => {
      setLocationPath(`${originalPath}#/guide`);
    });

    afterEach(() => {
      // Unmount, which also ends the restore's hold.
      document.body.innerHTML = "";
      dispatchHtmxAfterSwap();
      sessionStorage.removeItem(SCROLL_POSITIONS_KEY);
      setLocationPath(originalPath);
    });

    it("restores the saved position after the first render", async () => {
      savePosition({ armed: true });

      await mountAndRender(1);

      expect(scrollToMock.calls[0]).to.deep.equal({ behavior: "auto", top: 1500 });
      expect(sessionStorage.getItem(SCROLL_RESTORE_KEY)).to.equal(null);
    });

    it("leaves the page alone until that render", async () => {
      savePosition({ armed: true });

      await mountAndRender(0);

      expect(scrollToMock.calls).to.deep.equal([]);
    });

    it("gives a fresh visit no old position", async () => {
      savePosition({ armed: false });

      await mountAndRender(1);

      expect(scrollToMock.calls).to.deep.equal([]);
    });
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
