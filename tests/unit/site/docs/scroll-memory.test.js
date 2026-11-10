import { expect } from "@open-wc/testing";

import {
  armDocsScrollRestore,
  createDocsScrollRestore,
  setupDocsScrollMemory,
} from "/static/js/site/docs/scroll-memory.js";
import { waitForAnimationFrames } from "/tests/unit/test-utils/async.js";
import { mockScrollTo, setLocationPath } from "/tests/unit/test-utils/dom.js";

const POSITIONS_KEY = "ocg-docs-scroll-positions";
const RESTORE_KEY = "ocg-docs-scroll-restore";

/**
 * Builds the absolute URL of a docs route.
 * @param {string} route - Docs route.
 * @returns {string} Absolute URL.
 */
const docsUrl = (route) => new URL(`#${route}`, window.location.href).href;

/**
 * Reads the stored positions.
 * @returns {Record<string, number>} Scroll positions by URL.
 */
const storedPositions = () => JSON.parse(sessionStorage.getItem(POSITIONS_KEY) ?? "{}");

describe("docs scroll memory", () => {
  const originalPath = `${window.location.pathname}${window.location.search}`;
  let scrollToMock;
  let scrollYDescriptor;

  /** Reports the given window scroll position. */
  const setScrollY = (value) => {
    Object.defineProperty(window, "scrollY", { configurable: true, value });
  };

  /** Moves to a docs route without events, as a traversal does before they fire. */
  const moveTo = (route) => {
    setLocationPath(`${originalPath}#${route}`);
  };

  /** Fires HTMX's save, which also runs on Back once the URL has moved. */
  const dispatchBeforeHistorySave = () => {
    document.dispatchEvent(new CustomEvent("htmx:beforeHistorySave"));
  };

  beforeEach(() => {
    scrollYDescriptor = Object.getOwnPropertyDescriptor(window, "scrollY");
    scrollToMock = mockScrollTo();
    sessionStorage.removeItem(POSITIONS_KEY);
    sessionStorage.removeItem(RESTORE_KEY);
    moveTo("/first");
  });

  afterEach(() => {
    Object.defineProperty(window, "scrollY", scrollYDescriptor);
    scrollToMock.restore();
    sessionStorage.removeItem(POSITIONS_KEY);
    sessionStorage.removeItem(RESTORE_KEY);
    setLocationPath(originalPath);
  });

  describe("saving", () => {
    it("files the position under the page when a boosted link leaves it", () => {
      const release = setupDocsScrollMemory();

      setScrollY(1500);
      dispatchBeforeHistorySave();

      expect(storedPositions()).to.deep.equal({ [docsUrl("/first")]: 1500 });
      release();
    });

    it("files a Back onto a saved entry under the page left, not the destination", () => {
      const release = setupDocsScrollMemory();

      // HTMX saves from popstate, when the URL already names the destination.
      setScrollY(400);
      moveTo("/second");
      dispatchBeforeHistorySave();
      window.dispatchEvent(new PopStateEvent("popstate"));

      expect(storedPositions()).to.deep.equal({ [docsUrl("/first")]: 400 });
      release();
    });

    it("files the position when a docs link changes the hash", () => {
      const release = setupDocsScrollMemory();

      setScrollY(900);
      moveTo("/second");
      window.dispatchEvent(new HashChangeEvent("hashchange"));

      expect(storedPositions()).to.deep.equal({ [docsUrl("/first")]: 900 });
      release();
    });

    it("keeps the popstate position when the browser scrolls before hashchange", () => {
      const release = setupDocsScrollMemory();

      // Traverse without HTMX, which has no save for entries it never touched.
      setScrollY(700);
      moveTo("/second");
      window.dispatchEvent(new PopStateEvent("popstate"));

      // Verify the browser's own restore does not overwrite the page left.
      setScrollY(50);
      window.dispatchEvent(new HashChangeEvent("hashchange"));

      expect(storedPositions()).to.deep.equal({ [docsUrl("/first")]: 700 });
      release();
    });

    it("follows the URL across several pages", () => {
      const release = setupDocsScrollMemory();

      setScrollY(100);
      moveTo("/second");
      window.dispatchEvent(new HashChangeEvent("hashchange"));
      setScrollY(200);
      dispatchBeforeHistorySave();

      expect(storedPositions()).to.deep.equal({
        [docsUrl("/first")]: 100,
        [docsUrl("/second")]: 200,
      });
      release();
    });

    it("forgets an older position when the reader leaves from the top", () => {
      sessionStorage.setItem(POSITIONS_KEY, JSON.stringify({ [docsUrl("/first")]: 1500 }));
      const release = setupDocsScrollMemory();

      setScrollY(0);
      dispatchBeforeHistorySave();

      expect(storedPositions()).to.deep.equal({});
      release();
    });

    it("ignores a hashchange that kept the URL", () => {
      const release = setupDocsScrollMemory();

      window.dispatchEvent(new HashChangeEvent("hashchange"));

      expect(storedPositions()).to.deep.equal({});
      release();
    });

    it("keeps only the newest positions", () => {
      // Fill the store past its limit, with the first page saved again last.
      const positions = Object.fromEntries(
        Array.from({ length: 50 }, (_, index) => [docsUrl(`/page-${index}`), index]),
      );
      sessionStorage.setItem(POSITIONS_KEY, JSON.stringify(positions));
      const release = setupDocsScrollMemory();

      setScrollY(10);
      dispatchBeforeHistorySave();

      const stored = storedPositions();
      expect(Object.keys(stored)).to.have.length(50);
      expect(stored).not.to.have.property(docsUrl("/page-0"));
      expect(Object.keys(stored).at(-1)).to.equal(docsUrl("/first"));
      release();
    });

    it("recovers from a malformed store", () => {
      sessionStorage.setItem(POSITIONS_KEY, "{not json");
      const release = setupDocsScrollMemory();

      setScrollY(30);
      dispatchBeforeHistorySave();

      expect(storedPositions()).to.deep.equal({ [docsUrl("/first")]: 30 });
      release();
    });

    it("survives a full store", () => {
      const originalSetItem = Storage.prototype.setItem;
      Storage.prototype.setItem = () => {
        throw new DOMException("full", "QuotaExceededError");
      };
      const release = setupDocsScrollMemory();

      // Verify the save neither throws nor records anything.
      try {
        dispatchBeforeHistorySave();
        armDocsScrollRestore();
      } finally {
        Storage.prototype.setItem = originalSetItem;
      }

      expect(storedPositions()).to.deep.equal({});
      release();
    });

    it("stops saving after cleanup", () => {
      const release = setupDocsScrollMemory();
      release();

      setScrollY(100);
      dispatchBeforeHistorySave();
      moveTo("/second");
      window.dispatchEvent(new PopStateEvent("popstate"));
      window.dispatchEvent(new HashChangeEvent("hashchange"));

      expect(storedPositions()).to.deep.equal({});
    });
  });

  describe("restoring", () => {
    let now;
    let originalNow;

    /** Saves a position and arms it from the document the reload replaced. */
    const saveAndArm = (top) => {
      sessionStorage.setItem(POSITIONS_KEY, JSON.stringify({ [docsUrl("/first")]: top }));
      armDocsScrollRestore();
      const armed = JSON.parse(sessionStorage.getItem(RESTORE_KEY));
      sessionStorage.setItem(RESTORE_KEY, JSON.stringify({ ...armed, document: armed.document - 1 }));
    };

    beforeEach(() => {
      now = 0;
      originalNow = window.performance.now;
      window.performance.now = () => now;
    });

    afterEach(() => {
      window.performance.now = originalNow;
    });

    it("ignores a restore armed by this document, whose reload was aborted", async () => {
      sessionStorage.setItem(POSITIONS_KEY, JSON.stringify({ [docsUrl("/first")]: 1500 }));
      armDocsScrollRestore();

      // A later visit in the same document starts at the top, and the arm is gone.
      createDocsScrollRestore().start();
      await waitForAnimationFrames(2);

      expect(scrollToMock.calls).to.have.length(0);
      expect(sessionStorage.getItem(RESTORE_KEY)).to.equal(null);
    });

    it("restores the armed position once, then forgets it", async () => {
      saveAndArm(1500);

      const restore = createDocsScrollRestore();
      restore.start();
      now = 1000;
      await waitForAnimationFrames(2);

      // Verify the position applied and nothing is left for a later visit.
      expect(scrollToMock.calls).to.deep.equal([{ behavior: "auto", top: 1500 }]);
      expect(storedPositions()).to.deep.equal({});
      expect(sessionStorage.getItem(RESTORE_KEY)).to.equal(null);

      // Verify later renders and later mounts leave the page alone.
      restore.start();
      createDocsScrollRestore().start();
      await waitForAnimationFrames(2);
      expect(scrollToMock.calls).to.have.length(1);
    });

    it("waits for the first render", async () => {
      saveAndArm(1500);

      createDocsScrollRestore();
      await waitForAnimationFrames(2);

      expect(scrollToMock.calls).to.deep.equal([]);
    });

    it("gives a fresh visit no old position", async () => {
      // Leave a position behind without arming it.
      sessionStorage.setItem(POSITIONS_KEY, JSON.stringify({ [docsUrl("/first")]: 1500 }));

      createDocsScrollRestore().start();
      await waitForAnimationFrames(2);

      expect(scrollToMock.calls).to.deep.equal([]);
    });

    it("drops a restore armed for another URL", async () => {
      saveAndArm(1500);
      moveTo("/second");

      createDocsScrollRestore().start();
      await waitForAnimationFrames(2);

      expect(scrollToMock.calls).to.deep.equal([]);
      expect(sessionStorage.getItem(RESTORE_KEY)).to.equal(null);
    });

    it("holds the position until Docsify's anchor scroll has ended", async () => {
      saveAndArm(700);
      const restore = createDocsScrollRestore();
      restore.start();

      // Verify each frame reapplies the position inside the hold.
      await waitForAnimationFrames(3);
      expect(scrollToMock.calls.length).to.be.greaterThan(1);

      // Verify the hold outlasts the 500ms scroll and then ends.
      now = 550;
      await waitForAnimationFrames(1);
      const callsPastAnchorScroll = scrollToMock.calls.length;
      await waitForAnimationFrames(2);
      expect(scrollToMock.calls.length).to.be.greaterThan(callsPastAnchorScroll);

      now = 601;
      await waitForAnimationFrames(2);
      const callsAtEnd = scrollToMock.calls.length;
      await waitForAnimationFrames(2);
      expect(scrollToMock.calls).to.have.length(callsAtEnd);
    });

    it("stops holding when the reader moves to another page", async () => {
      saveAndArm(700);
      const restore = createDocsScrollRestore();
      restore.start();
      await waitForAnimationFrames(2);

      moveTo("/second");
      await waitForAnimationFrames(1);
      const callsAfterMove = scrollToMock.calls.length;
      await waitForAnimationFrames(2);

      expect(scrollToMock.calls).to.have.length(callsAfterMove);
      restore.cancel();
    });

    for (const type of ["keydown", "pointerdown", "wheel"]) {
      it(`gives the page back to the reader on ${type}`, async () => {
        saveAndArm(700);
        const restore = createDocsScrollRestore();
        restore.start();
        await waitForAnimationFrames(1);

        window.dispatchEvent(new Event(type));
        const callsAtInput = scrollToMock.calls.length;
        await waitForAnimationFrames(2);

        expect(scrollToMock.calls).to.have.length(callsAtInput);
      });
    }

    it("holds no input listener once the hold ends", async () => {
      // Record the listeners the hold adds and removes.
      const added = [];
      const removed = [];
      const addEventListener = window.addEventListener;
      const removeEventListener = window.removeEventListener;
      window.addEventListener = (type, ...rest) => {
        added.push(type);
        addEventListener.call(window, type, ...rest);
      };
      window.removeEventListener = (type, ...rest) => {
        removed.push(type);
        removeEventListener.call(window, type, ...rest);
      };

      // Run a hold to its end.
      saveAndArm(700);
      createDocsScrollRestore().start();
      now = 601;
      await waitForAnimationFrames(2);
      window.addEventListener = addEventListener;
      window.removeEventListener = removeEventListener;

      expect(added).to.deep.equal(["keydown", "pointerdown", "wheel"]);
      expect(removed).to.deep.equal(added);
    });

    it("stops holding when cancelled", async () => {
      saveAndArm(700);
      const restore = createDocsScrollRestore();
      restore.start();
      restore.cancel();

      await waitForAnimationFrames(2);

      expect(scrollToMock.calls).to.deep.equal([]);
    });
  });
});
