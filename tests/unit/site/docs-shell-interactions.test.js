import { expect } from "@open-wc/testing";

import {
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
});
