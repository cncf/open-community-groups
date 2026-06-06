import { expect } from "@open-wc/testing";

import {
  createCurrentSidebarPageClickHandler,
  createSamePageAnchorClickHandler,
  jumpToElement,
  mirrorDocsifyBodyClasses,
  setupMobileSidebarOutsideDismiss,
  updateDocsAnchorHash,
} from "/static/js/site/docs-shell-interactions.js";
import { waitForMicrotask } from "/tests/unit/test-utils/async.js";
import { mockScrollTo, resetDom, setLocationPath } from "/tests/unit/test-utils/dom.js";

describe("docs shell interactions", () => {
  let originalMatchMedia;
  let originalPageYOffset;
  let scrollToMock;

  beforeEach(() => {
    resetDom();
    setLocationPath("/docs#/");
    originalMatchMedia = window.matchMedia;
    originalPageYOffset = Object.getOwnPropertyDescriptor(window, "pageYOffset");
    scrollToMock = mockScrollTo();
  });

  afterEach(() => {
    window.matchMedia = originalMatchMedia;
    if (originalPageYOffset) {
      Object.defineProperty(window, "pageYOffset", originalPageYOffset);
    }
    scrollToMock.restore();
    resetDom();
  });

  it("mirrors docsify body classes to the docs root", async () => {
    // Body class mirroring keeps docsify global state scoped to the docs root.
    const docsRoot = document.createElement("div");
    document.body.append(docsRoot);
    document.body.classList.add("close");
    const cleanup = mirrorDocsifyBodyClasses(docsRoot);

    expect(docsRoot.classList.contains("close")).to.equal(true);

    document.body.classList.remove("close");
    document.body.classList.add("ready");
    await waitForMicrotask();

    expect(docsRoot.classList.contains("close")).to.equal(false);
    expect(docsRoot.classList.contains("ready")).to.equal(true);
    cleanup();
  });

  it("updates docs anchor hash and dispatches hashchange", () => {
    // Docs anchor hash updates include the route and encoded section id.
    const hashChanges = [];
    window.addEventListener("hashchange", (event) => {
      hashChanges.push({ newURL: event.newURL, oldURL: event.oldURL });
    });

    updateDocsAnchorHash("/guide", "Install & Run");

    expect(window.location.hash).to.equal("#/guide?id=Install%20%26%20Run");
    expect(hashChanges).to.have.length(1);
    expect(hashChanges[0].oldURL).to.include("/docs#/");
    expect(hashChanges[0].newURL).to.include("#/guide?id=Install%20%26%20Run");
  });

  it("jumps to a docs anchor without smooth scrolling", () => {
    // Anchor jumps use fixed docs shell padding.
    const target = document.createElement("section");
    target.getBoundingClientRect = () => ({ top: 125 });
    Object.defineProperty(window, "pageYOffset", {
      configurable: true,
      value: 75,
    });

    jumpToElement(target);

    expect(scrollToMock.calls).to.deep.equal([
      {
        behavior: "auto",
        top: 170,
      },
    ]);
  });

  it("dismisses the mobile sidebar when clicking outside docs controls", () => {
    // Mobile outside clicks close the docs sidebar.
    window.matchMedia = () => ({ matches: true });
    document.body.innerHTML = `
      <div class="ocg-docs-root">
        <aside class="sidebar"></aside>
        <button class="sidebar-toggle"></button>
      </div>
      <main id="outside"></main>
    `;
    document.body.classList.add("close");
    const cleanup = setupMobileSidebarOutsideDismiss();

    document.querySelector(".sidebar").click();
    expect(document.body.classList.contains("close")).to.equal(true);

    document.getElementById("outside").click();
    expect(document.body.classList.contains("close")).to.equal(false);
    cleanup();
  });

  it("handles current sidebar page clicks without letting docsify collapse sections", () => {
    // Current-page sidebar clicks are intercepted and resync sidebar state.
    let syncs = 0;
    document.body.innerHTML = `
      <nav class="sidebar-nav">
        <a id="current-link" href="#/guide">Guide</a>
      </nav>
    `;
    const handler = createCurrentSidebarPageClickHandler({
      getCurrentDocsRoute: () => ({ id: "", path: "/guide" }),
      parseDocsRoute: () => ({ id: "", path: "/guide" }),
      scheduleCurrentSidebarSectionStateSync: () => {
        syncs += 1;
      },
    });
    const event = new MouseEvent("click", { bubbles: true, cancelable: true });
    let laterListeners = 0;
    const laterListener = () => {
      laterListeners += 1;
    };

    document.addEventListener("click", handler);
    document.addEventListener("click", laterListener);
    document.getElementById("current-link").dispatchEvent(event);
    document.removeEventListener("click", handler);
    document.removeEventListener("click", laterListener);

    expect(event.defaultPrevented).to.equal(true);
    expect(laterListeners).to.equal(0);
    expect(syncs).to.equal(1);
  });

  it("handles same-page anchor clicks with instant docs jumps", () => {
    // Same-page anchor clicks update the docs hash and jump without smooth scroll.
    let syncs = 0;
    document.body.innerHTML = `
      <main class="markdown-section">
        <a id="anchor-link" href="#/guide?id=Install">Install</a>
        <section id="Install"></section>
      </main>
    `;
    document.getElementById("Install").getBoundingClientRect = () => ({ top: 125 });
    Object.defineProperty(window, "pageYOffset", {
      configurable: true,
      value: 75,
    });
    const handler = createSamePageAnchorClickHandler({
      getCurrentDocsRoute: () => ({ path: "/guide", rawPath: "/guide" }),
      parseSamePageAnchor: () => ({ id: "Install", path: "/guide" }),
      scheduleCurrentSidebarSectionStateSync: () => {
        syncs += 1;
      },
    });
    const event = new MouseEvent("click", { bubbles: true, cancelable: true });

    document.addEventListener("click", handler);
    document.getElementById("anchor-link").dispatchEvent(event);
    document.removeEventListener("click", handler);

    expect(event.defaultPrevented).to.equal(true);
    expect(window.location.hash).to.equal("#/guide?id=Install");
    expect(scrollToMock.calls.at(-1)).to.deep.equal({
      behavior: "auto",
      top: 170,
    });
    expect(syncs).to.equal(1);
  });
});
