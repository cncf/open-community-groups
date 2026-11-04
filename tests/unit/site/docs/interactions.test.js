import { expect } from "@open-wc/testing";

import { PHONE_MEDIA_QUERY } from "/static/js/common/phone-viewport.js";
import {
  createCurrentSidebarPageClickHandler,
  createSamePageAnchorClickHandler,
  jumpToElement,
  mirrorDocsifyBodyClasses,
  setupDocsPhoneShell,
  setupMobileSidebarOutsideDismiss,
  syncPhoneDocsTitle,
  updateDocsAnchorHash,
} from "/static/js/site/docs/interactions.js";
import { waitForMicrotask } from "/tests/unit/test-utils/async.js";
import { mockScrollTo, resetDom, setLocationPath } from "/tests/unit/test-utils/dom.js";
import { mockPhoneMedia } from "/tests/unit/test-utils/wake-lock.js";

/**
 * Replaces matchMedia with a phone query the test can flip.
 * @param {boolean} matches - Initial query state.
 * @returns {ReturnType<typeof mockPhoneMedia>} Query controls.
 */
const stubPhoneQuery = (matches) => mockPhoneMedia(PHONE_MEDIA_QUERY, matches);

/**
 * Records listener types added to the given targets.
 * @param {...EventTarget} targets - Targets to watch.
 * @returns {{restore: () => void, types: string[]}} Recorded types and a restore callback.
 */
const recordAddedListeners = (...targets) => {
  const types = [];
  targets.forEach((target) => {
    target.addEventListener = (type, ...rest) => {
      types.push(type);
      EventTarget.prototype.addEventListener.call(target, type, ...rest);
    };
  });

  return {
    restore: () => targets.forEach((target) => delete target.addEventListener),
    types,
  };
};

/**
 * Replaces CloseWatcher with a fake that records its instances.
 * @returns {{instances: object[], restore: () => void}} Fake controls.
 */
const stubCloseWatcher = () => {
  const descriptor = Object.getOwnPropertyDescriptor(window, "CloseWatcher");
  const instances = [];
  window.CloseWatcher = class extends EventTarget {
    destroyed = false;

    constructor() {
      super();
      instances.push(this);
    }

    destroy() {
      this.destroyed = true;
    }
  };

  return {
    instances,
    restore: () => {
      delete window.CloseWatcher;
      if (descriptor) {
        Object.defineProperty(window, "CloseWatcher", descriptor);
      }
    },
  };
};

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

  it("jumps below the header and strip on phones", () => {
    // Phone anchors clear the 64px header and the 44px strip.
    stubPhoneQuery(true);
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
        top: 84,
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

  describe("phone title", () => {
    let docsRoot;
    let originalTitle;

    beforeEach(() => {
      originalTitle = document.title;
      document.title = "- Open Community Groups";
      document.body.innerHTML = `
        <div class="ocg-docs-root">
          <div class="sidebar-nav">
            <ul>
              <li><p><a href="#/">Overview</a></p></li>
              <li class="active">
                <a href="#/guide"> Guide </a>
                <ul class="app-sub-sidebar">
                  <li class="active"><a href="#/guide?id=section">Section</a></li>
                </ul>
              </li>
            </ul>
          </div>
        </div>
      `;
      docsRoot = document.querySelector(".ocg-docs-root");
    });

    afterEach(() => {
      document.title = originalTitle;
    });

    it("takes the title from the page link, not its active section", () => {
      stubPhoneQuery(true);

      syncPhoneDocsTitle(docsRoot);

      expect(document.title).to.equal("Guide");
    });

    it("climbs to the page when only a section is active", () => {
      stubPhoneQuery(true);
      docsRoot.querySelector("li.active").classList.remove("active");

      syncPhoneDocsTitle(docsRoot);

      expect(document.title).to.equal("Guide");
    });

    it("reads a page link wrapped in a paragraph", () => {
      stubPhoneQuery(true);
      docsRoot.querySelectorAll(".active").forEach((item) => item.classList.remove("active"));
      docsRoot.querySelector("p").classList.add("active");

      syncPhoneDocsTitle(docsRoot);

      expect(document.title).to.equal("Overview");
    });

    it("keeps Docsify's title when no page link is active", () => {
      stubPhoneQuery(true);
      docsRoot.querySelectorAll(".active").forEach((item) => item.classList.remove("active"));

      syncPhoneDocsTitle(docsRoot);

      expect(document.title).to.equal("- Open Community Groups");
    });

    it("does nothing under a false query", () => {
      stubPhoneQuery(false);

      syncPhoneDocsTitle(docsRoot);

      expect(document.title).to.equal("- Open Community Groups");
    });
  });

  describe("phone shell", () => {
    let closeWatcherStub;
    let content;
    let docsRoot;
    let toggle;

    /** Applies a body class change and lets the observer run. */
    const setSheetOpen = async (open) => {
      document.body.classList.toggle("close", open);
      await waitForMicrotask();
    };

    beforeEach(() => {
      closeWatcherStub = stubCloseWatcher();
      window.$docsify = {};
      document.body.innerHTML = `
        <div class="ocg-docs-root">
          <button class="sidebar-toggle" aria-label="Menu"></button>
          <aside class="sidebar">
            <div class="sidebar-nav"><p id="section-label">Guides</p><a id="guide-link" href="#/guide">Guide</a></div>
          </aside>
          <section class="content"></section>
        </div>
        <button id="header-control"></button>
      `;
      docsRoot = document.querySelector(".ocg-docs-root");
      toggle = docsRoot.querySelector(".sidebar-toggle");
      content = docsRoot.querySelector(".content");
      // Docsify's toggle: it stops the click, so the document never sees it.
      toggle.addEventListener("click", (event) => {
        event.stopPropagation();
        document.body.classList.toggle("close");
      });
    });

    afterEach(() => {
      closeWatcherStub.restore();
      document.body.classList.remove("close");
      delete window.$docsify;
    });

    it("does nothing off phones", async () => {
      // Record what the shell binds under a false query.
      const added = recordAddedListeners(window, document, docsRoot);
      stubPhoneQuery(false);
      const release = setupDocsPhoneShell(docsRoot);

      // Verify an open sidebar creates no watcher and no listener lands anywhere.
      await setSheetOpen(true);
      expect(window.$docsify.topMargin).to.equal(0);
      expect(closeWatcherStub.instances).to.have.length(0);
      expect(added.types).to.deep.equal([]);

      // Verify the toggle and the page keep Docsify's state.
      expect(toggle.getAttribute("aria-label")).to.equal("Menu");
      expect(toggle.hasAttribute("aria-expanded")).to.equal(false);
      expect(content.hasAttribute("inert")).to.equal(false);

      // Verify a sidebar link keeps today's behavior.
      document.getElementById("guide-link").click();
      expect(document.body.classList.contains("close")).to.equal(true);

      release();
      added.restore();
    });

    it("sets the Docsify anchor offset while the query matches", () => {
      // Start on a phone.
      const { setMatches } = stubPhoneQuery(true);
      const release = setupDocsPhoneShell(docsRoot);
      expect(window.$docsify.topMargin).to.equal(116);

      // Verify the current object is written, because Docsify reassigns it.
      window.$docsify = {};
      setMatches(false);
      expect(window.$docsify.topMargin).to.equal(0);

      setMatches(true);
      expect(window.$docsify.topMargin).to.equal(116);
      release();
    });

    it("holds one query listener until cleanup", () => {
      // Mount under a false query, as a wide viewport does.
      const { listeners } = stubPhoneQuery(false);
      const release = setupDocsPhoneShell(docsRoot);
      expect(listeners.size).to.equal(1);

      // Verify cleanup leaves nothing on the query.
      release();
      expect(listeners.size).to.equal(0);
    });

    it("closes through the toggle on a close request", async () => {
      // Open the sheet through the toggle.
      stubPhoneQuery(true);
      const release = setupDocsPhoneShell(docsRoot);
      toggle.click();
      await waitForMicrotask();
      expect(closeWatcherStub.instances).to.have.length(1);

      // Verify Back runs the real toggle and takes focus out of the hiding sheet.
      document.getElementById("guide-link").focus();
      closeWatcherStub.instances[0].dispatchEvent(new Event("close"));
      await waitForMicrotask();
      expect(document.body.classList.contains("close")).to.equal(false);
      expect(document.activeElement).to.equal(toggle);

      // Verify the next opening gets a fresh watcher.
      await setSheetOpen(true);
      expect(closeWatcherStub.instances).to.have.length(2);
      release();
    });

    it("releases the watcher when the sheet closes another way", async () => {
      // Open the sheet.
      stubPhoneQuery(true);
      const release = setupDocsPhoneShell(docsRoot);
      await setSheetOpen(true);

      // Verify an outside tap, which skips the toggle, leaves no watcher to eat the next Back.
      await setSheetOpen(false);
      expect(closeWatcherStub.instances[0].destroyed).to.equal(true);
      release();
    });

    describe("without CloseWatcher", () => {
      let descriptor;

      /** Presses a key on the document. */
      const pressKey = (key) => {
        document.dispatchEvent(new KeyboardEvent("keydown", { bubbles: true, key }));
      };

      beforeEach(() => {
        // Remove the API, as browsers without it do.
        closeWatcherStub.restore();
        descriptor = Object.getOwnPropertyDescriptor(window, "CloseWatcher");
        delete window.CloseWatcher;
      });

      afterEach(() => {
        if (descriptor) {
          Object.defineProperty(window, "CloseWatcher", descriptor);
        }
      });

      it("still closes through links", async () => {
        stubPhoneQuery(true);
        const release = setupDocsPhoneShell(docsRoot);

        // Verify opening the sheet does not throw and links still close it.
        await setSheetOpen(true);
        document.getElementById("guide-link").click();
        expect(document.body.classList.contains("close")).to.equal(false);

        release();
      });

      it("closes on Escape and returns focus to the toggle", async () => {
        // Open the sheet with focus inside it.
        stubPhoneQuery(true);
        const release = setupDocsPhoneShell(docsRoot);
        await setSheetOpen(true);
        document.getElementById("guide-link").focus();

        // Verify other keys leave it open.
        pressKey("Tab");
        expect(document.body.classList.contains("close")).to.equal(true);

        pressKey("Escape");
        await waitForMicrotask();
        expect(document.body.classList.contains("close")).to.equal(false);
        expect(document.activeElement).to.equal(toggle);
        release();
      });

      it("closes when Back moves the hash behind the sheet", async () => {
        // Open the sheet with focus inside it.
        stubPhoneQuery(true);
        const release = setupDocsPhoneShell(docsRoot);
        await setSheetOpen(true);
        docsRoot.classList.add("close");
        document.getElementById("guide-link").focus();

        window.dispatchEvent(new HashChangeEvent("hashchange"));
        await waitForMicrotask();

        // Verify the page comes back and focus does not stay in the hidden sheet.
        expect(document.body.classList.contains("close")).to.equal(false);
        expect(docsRoot.classList.contains("close")).to.equal(false);
        expect(content.hasAttribute("inert")).to.equal(false);
        expect(toggle.getAttribute("aria-expanded")).to.equal("false");
        expect(document.activeElement).to.equal(toggle);
        release();
      });

      it("holds the hash listener only while the sheet is open", async () => {
        // Record what the shell binds on the window.
        const added = recordAddedListeners(window);
        stubPhoneQuery(true);
        const release = setupDocsPhoneShell(docsRoot);
        expect(added.types).not.to.include("hashchange");

        await setSheetOpen(true);
        expect(added.types).to.include("hashchange");

        // Verify a closed sheet has dropped the listener: a class added now survives the event.
        await setSheetOpen(false);
        release();
        document.body.classList.add("close");
        window.dispatchEvent(new HashChangeEvent("hashchange"));
        expect(document.body.classList.contains("close")).to.equal(true);
        added.restore();
      });

      it("holds the key listener only while the sheet is open", async () => {
        // Record what the shell binds on the document.
        const added = recordAddedListeners(document);
        stubPhoneQuery(true);
        const release = setupDocsPhoneShell(docsRoot);
        expect(added.types).not.to.include("keydown");

        await setSheetOpen(true);
        expect(added.types).to.include("keydown");

        // Verify a closed sheet ignores the key, which would otherwise reopen it.
        await setSheetOpen(false);
        pressKey("Escape");
        expect(document.body.classList.contains("close")).to.equal(false);

        // Verify the release takes the listener with it.
        await setSheetOpen(true);
        release();
        pressKey("Escape");
        expect(document.body.classList.contains("close")).to.equal(true);
        added.restore();
      });
    });

    it("closes on a hash change where CloseWatcher exists too", async () => {
      // Browsers with the API can still go Back without a close request.
      stubPhoneQuery(true);
      const release = setupDocsPhoneShell(docsRoot);
      await setSheetOpen(true);

      window.dispatchEvent(new HashChangeEvent("hashchange"));
      await waitForMicrotask();

      expect(document.body.classList.contains("close")).to.equal(false);
      expect(closeWatcherStub.instances[0].destroyed).to.equal(true);
      release();
    });

    it("leaves Escape to the watcher when CloseWatcher exists", async () => {
      // Record what the shell binds on the document.
      const added = recordAddedListeners(document);
      stubPhoneQuery(true);
      const release = setupDocsPhoneShell(docsRoot);
      await setSheetOpen(true);

      // Verify no key listener could close the sheet a second time.
      expect(added.types).not.to.include("keydown");
      release();
      added.restore();
    });

    describe("toggle and page state", () => {
      it("names the toggle after its visible word and restores it on release", () => {
        // Bind on a phone.
        stubPhoneQuery(true);
        const release = setupDocsPhoneShell(docsRoot);
        expect(toggle.getAttribute("aria-label")).to.equal("Contents");

        release();
        expect(toggle.getAttribute("aria-label")).to.equal("Menu");
      });

      it("reaches a toggle Docsify renders after the shell binds", async () => {
        // Bind before Docsify renders, as a phone load does.
        toggle.remove();
        content.remove();
        stubPhoneQuery(true);
        const release = setupDocsPhoneShell(docsRoot);

        // Render as Docsify does, ending on its ready class.
        docsRoot.append(toggle, content);
        document.body.classList.add("ready");
        await waitForMicrotask();

        // Verify the first render is already in phone state.
        expect(toggle.getAttribute("aria-label")).to.equal("Contents");
        expect(toggle.getAttribute("aria-expanded")).to.equal("false");
        document.body.classList.remove("ready");
        release();
      });

      it("follows the sheet with aria-expanded and inert", async () => {
        // Bind with the sheet closed.
        stubPhoneQuery(true);
        const release = setupDocsPhoneShell(docsRoot);
        expect(toggle.getAttribute("aria-expanded")).to.equal("false");
        expect(content.hasAttribute("inert")).to.equal(false);

        await setSheetOpen(true);
        expect(toggle.getAttribute("aria-expanded")).to.equal("true");
        expect(content.hasAttribute("inert")).to.equal(true);

        await setSheetOpen(false);
        expect(toggle.getAttribute("aria-expanded")).to.equal("false");
        expect(content.hasAttribute("inert")).to.equal(false);
        release();
      });

      it("clears everything on release with the sheet open", async () => {
        // Open the sheet on a phone.
        stubPhoneQuery(true);
        const release = setupDocsPhoneShell(docsRoot);
        await setSheetOpen(true);

        release();

        // Verify the sidebar stays open but nothing of the phone state remains.
        expect(document.body.classList.contains("close")).to.equal(true);
        expect(toggle.hasAttribute("aria-expanded")).to.equal(false);
        expect(content.hasAttribute("inert")).to.equal(false);
      });

      it("writes nothing more once released", async () => {
        // Release before the sheet opens.
        stubPhoneQuery(true);
        const release = setupDocsPhoneShell(docsRoot);
        release();

        // Verify the body observer went with it.
        await setSheetOpen(true);
        expect(toggle.hasAttribute("aria-expanded")).to.equal(false);
        expect(content.hasAttribute("inert")).to.equal(false);
      });
    });

    describe("focus on close", () => {
      it("returns to the toggle after an outside tap from inside the sheet", async () => {
        // Open the sheet with focus inside it.
        stubPhoneQuery(true);
        const release = setupDocsPhoneShell(docsRoot);
        await setSheetOpen(true);
        document.getElementById("guide-link").focus();

        await setSheetOpen(false);

        expect(document.activeElement).to.equal(toggle);
        release();
      });

      it("returns to the toggle when the tap already dropped focus", async () => {
        // Open the sheet with focus on the body, where a tap on the scrim leaves it.
        stubPhoneQuery(true);
        const release = setupDocsPhoneShell(docsRoot);
        await setSheetOpen(true);
        document.activeElement.blur();

        await setSheetOpen(false);

        expect(document.activeElement).to.equal(toggle);
        release();
      });

      it("stays on a control the tap focused outside the sheet", async () => {
        // Open the sheet, then focus a header control as a tap on it does.
        stubPhoneQuery(true);
        const release = setupDocsPhoneShell(docsRoot);
        await setSheetOpen(true);
        const headerControl = document.getElementById("header-control");
        headerControl.focus();

        await setSheetOpen(false);

        expect(document.activeElement).to.equal(headerControl);
        release();
      });

      it("stays out of the way on a link that navigates", async () => {
        // Open the sheet with focus on a link to another page.
        stubPhoneQuery(true);
        const release = setupDocsPhoneShell(docsRoot);
        await setSheetOpen(true);
        const guideLink = document.getElementById("guide-link");
        guideLink.focus();

        guideLink.click();
        await waitForMicrotask();

        expect(document.activeElement).to.not.equal(toggle);
        release();
      });

      it("returns to the toggle on a link to the current page", async () => {
        // Open the sheet on the page its link names.
        setLocationPath("/docs#/guide");
        stubPhoneQuery(true);
        const release = setupDocsPhoneShell(docsRoot);
        await setSheetOpen(true);
        const guideLink = document.getElementById("guide-link");
        guideLink.focus();

        guideLink.click();
        await waitForMicrotask();

        expect(document.body.classList.contains("close")).to.equal(false);
        expect(document.activeElement).to.equal(toggle);
        release();
      });
    });

    it("closes the sheet on a link tap at any phone width", async () => {
      // Open the sheet; above 600px Docsify binds no close on links.
      stubPhoneQuery(true);
      const release = setupDocsPhoneShell(docsRoot);
      await setSheetOpen(true);

      // Verify a section label keeps the sheet open and a link closes it.
      document.getElementById("section-label").click();
      expect(document.body.classList.contains("close")).to.equal(true);
      document.getElementById("guide-link").click();
      expect(document.body.classList.contains("close")).to.equal(false);
      release();
    });

    describe("current row", () => {
      let sheet;

      /** Renders a short scrolling sheet with one row at the given offset. */
      const renderRow = (rowTop, rowClass = "active") => {
        sheet = docsRoot.querySelector(".sidebar");
        sheet.style.cssText = "height: 200px; overflow: auto; position: relative;";
        sheet.querySelector(".sidebar-nav").innerHTML = `
          <ul style="height: 1000px; margin: 0; padding: 0; position: relative;">
            <li class="${rowClass}" style="position: absolute; top: ${rowTop}px;">
              <a id="current-row" href="#/guide" style="display: block; height: 40px;">Guide</a>
            </li>
          </ul>
        `;
      };

      it("scrolls a row below the fold into the sheet when it opens", async () => {
        // Open the sheet on a page low in the list.
        renderRow(600);
        stubPhoneQuery(true);
        const release = setupDocsPhoneShell(docsRoot);
        await setSheetOpen(true);

        // Verify the row lands in view, with room for sub-rows below it.
        const offset = document.getElementById("current-row").getBoundingClientRect().top;
        const sheetTop = sheet.getBoundingClientRect().top;
        expect(sheet.scrollTop).to.be.greaterThan(0);
        expect(offset - sheetTop).to.be.closeTo(200 / 3, 1);
        release();
      });

      it("leaves the scroll alone when the row is already in view", async () => {
        // Open the sheet on a page near the top of the list.
        renderRow(40);
        stubPhoneQuery(true);
        const release = setupDocsPhoneShell(docsRoot);
        await setSheetOpen(true);

        // Verify the sheet stays where it was.
        expect(sheet.scrollTop).to.equal(0);
        release();
      });

      it("scrolls once per open, not on later body class changes", async () => {
        // Open the sheet, then scroll it away as a reader would.
        renderRow(600);
        stubPhoneQuery(true);
        const release = setupDocsPhoneShell(docsRoot);
        await setSheetOpen(true);
        sheet.scrollTop = 0;

        // Verify an unrelated body class change keeps the reader's position.
        document.body.classList.add("sticky");
        await waitForMicrotask();
        expect(sheet.scrollTop).to.equal(0);
        document.body.classList.remove("sticky");
        release();
      });

      it("does nothing on pages with no current row", async () => {
        // Open the sheet with no active row, as on the overview.
        renderRow(600, "");
        stubPhoneQuery(true);
        const release = setupDocsPhoneShell(docsRoot);
        await setSheetOpen(true);

        // Verify the sheet stays at its top.
        expect(sheet.scrollTop).to.equal(0);
        release();
      });
    });

    it("keeps the sheet open on taps inside it when Docsify closes on body clicks", async () => {
      // Docsify binds this only when it loaded at 600px or less.
      const closeOnBodyClick = () => document.body.classList.remove("close");
      document.body.addEventListener("click", closeOnBodyClick);
      stubPhoneQuery(true);
      const release = setupDocsPhoneShell(docsRoot);
      await setSheetOpen(true);

      // Verify a section label stays inert and a link still closes the sheet.
      document.getElementById("section-label").click();
      expect(document.body.classList.contains("close")).to.equal(true);
      document.getElementById("guide-link").click();
      expect(document.body.classList.contains("close")).to.equal(false);

      // Verify a tap outside the sheet still reaches the body.
      await setSheetOpen(true);
      docsRoot.click();
      expect(document.body.classList.contains("close")).to.equal(false);

      document.body.removeEventListener("click", closeOnBodyClick);
      release();
    });

    it("keeps the sheet state out of history", async () => {
      // Open the sheet with the root mirror already applied.
      stubPhoneQuery(true);
      const release = setupDocsPhoneShell(docsRoot);
      await setSheetOpen(true);
      docsRoot.classList.add("close");

      // Verify the snapshot taken after this event has no open state, even before the mirror runs.
      document.dispatchEvent(new CustomEvent("htmx:beforeHistorySave"));
      expect(document.body.classList.contains("close")).to.equal(false);
      expect(docsRoot.classList.contains("close")).to.equal(false);
      expect(toggle.getAttribute("aria-expanded")).to.equal("false");
      expect(content.hasAttribute("inert")).to.equal(false);

      // Verify a history restore resets from the DOM.
      await setSheetOpen(true);
      document.dispatchEvent(new CustomEvent("htmx:historyRestore"));
      expect(document.body.classList.contains("close")).to.equal(false);
      release();
    });

    it("resets on bfcache restores only", async () => {
      // Open the sheet.
      stubPhoneQuery(true);
      const release = setupDocsPhoneShell(docsRoot);
      await setSheetOpen(true);

      // Verify the first pageshow of a slow load leaves an open sheet alone.
      window.dispatchEvent(new PageTransitionEvent("pageshow", { persisted: false }));
      expect(document.body.classList.contains("close")).to.equal(true);

      window.dispatchEvent(new PageTransitionEvent("pageshow", { persisted: true }));
      expect(document.body.classList.contains("close")).to.equal(false);
      release();
    });

    it("releases everything when the query turns false with the sheet open", async () => {
      // Open the sheet on a phone.
      const { setMatches } = stubPhoneQuery(true);
      const release = setupDocsPhoneShell(docsRoot);
      await setSheetOpen(true);

      // Verify the rotation destroys the watcher and leaves the open state alone.
      setMatches(false);
      expect(closeWatcherStub.instances[0].destroyed).to.equal(true);
      expect(document.body.classList.contains("close")).to.equal(true);

      // Verify no phone listener is left behind.
      document.getElementById("guide-link").click();
      document.dispatchEvent(new CustomEvent("htmx:beforeHistorySave"));
      expect(document.body.classList.contains("close")).to.equal(true);

      // Verify rotating back adopts the open sheet.
      setMatches(true);
      expect(closeWatcherStub.instances).to.have.length(2);
      release();
    });

    it("tears down on cleanup", async () => {
      // Open the sheet on a phone.
      stubPhoneQuery(true);
      const release = setupDocsPhoneShell(docsRoot);
      await setSheetOpen(true);

      release();

      // Verify the watcher and body observer are gone.
      expect(closeWatcherStub.instances[0].destroyed).to.equal(true);
      await setSheetOpen(false);
      await setSheetOpen(true);
      expect(closeWatcherStub.instances).to.have.length(1);
    });
  });
});
