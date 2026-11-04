import { expect } from "@open-wc/testing";

import {
  bindOpenModalKeyboard,
  resetRestoredModalState,
  toggleModalVisibility,
} from "/static/js/common/modals/modal-lifecycle.js";
import {
  bindSheetGestures,
  isBottomSheet,
  requestSheetClose,
} from "/static/js/common/modals/sheet-gestures.js";
import { PHONE_MEDIA_QUERY } from "/static/js/common/phone-viewport.js";
import { resetDom } from "/tests/unit/test-utils/dom.js";

/** Close watcher double that records its instances. */
class FakeCloseWatcher extends EventTarget {
  static instances = [];

  destroyCount = 0;

  constructor() {
    super();
    FakeCloseWatcher.instances.push(this);
  }

  destroy() {
    this.destroyCount += 1;
  }

  requestClose() {
    this.dispatchEvent(new Event("close"));
  }
}

/**
 * Replaces matchMedia with a query whose state tests can change.
 * @param {boolean} matches Initial phone query state.
 * @returns {{listeners: Set<Function>, setMatches: (next: boolean) => void}} Query controls.
 */
const mockPhoneQuery = (matches) => {
  const listeners = new Set();
  const query = {
    addEventListener: (type, listener) => {
      if (type === "change") {
        listeners.add(listener);
      }
    },
    matches,
    removeEventListener: (type, listener) => {
      if (type === "change") {
        listeners.delete(listener);
      }
    },
  };

  window.matchMedia = (text) => (text === PHONE_MEDIA_QUERY ? query : { matches: false });

  return {
    listeners,
    setMatches: (next) => {
      query.matches = next;
      [...listeners].forEach((listener) => listener({ matches: next }));
    },
  };
};

/**
 * Renders a sheet with a title row, a close button and a body control.
 * @param {string} [panelStyle] Inline panel style.
 * @returns {{close: HTMLButtonElement, closeCount: () => number, grab: HTMLElement, panel: HTMLElement}} Sheet.
 */
const renderSheet = (panelStyle = "position: fixed; height: 400px") => {
  const panel = document.createElement("div");
  panel.className = "sheet-panel";
  panel.setAttribute("style", panelStyle);
  panel.innerHTML = `
    <div class="sheet-grab"><span>Title</span><button type="button"><div class="icon-close"></div></button></div>
    <input type="text" />
  `;
  document.body.append(panel);

  const close = panel.querySelector("button");
  const grab = panel.querySelector(".sheet-grab");
  grab.setPointerCapture = () => {};
  let closes = 0;
  close.addEventListener("click", () => {
    closes += 1;
  });

  return { close, closeCount: () => closes, grab, panel };
};

/**
 * Renders a hidden modal wrapping a sheet panel, closed by toggleModalVisibility.
 * @returns {{close: HTMLButtonElement, modal: HTMLElement, panel: HTMLElement, trigger: HTMLButtonElement}} Modal.
 */
const renderSheetModal = () => {
  const trigger = document.createElement("button");
  const modal = document.createElement("div");
  modal.id = "sheet-modal";
  modal.className = "hidden";
  modal.setAttribute("role", "dialog");
  modal.setAttribute("aria-modal", "true");
  modal.setAttribute("aria-hidden", "true");
  modal.innerHTML = `
    <div class="sheet-panel" style="position: fixed">
      <div class="sheet-grab"><button type="button"><div class="icon-close"></div></button></div>
    </div>
  `;
  document.body.append(trigger, modal);

  const close = modal.querySelector("button");
  close.addEventListener("click", () => toggleModalVisibility(modal));

  return { close, modal, panel: modal.querySelector(".sheet-panel"), trigger };
};

/**
 * Dispatches a pointer event with a fixed timestamp.
 * @param {EventTarget} target Event target.
 * @param {string} type Event type.
 * @param {{clientY?: number, time?: number, init?: PointerEventInit}} [options] Event options.
 * @returns {void}
 */
const firePointer = (target, type, { clientY = 0, time = 0, init = {} } = {}) => {
  const event = new PointerEvent(type, {
    bubbles: true,
    button: 0,
    clientY,
    isPrimary: true,
    pointerId: 1,
    ...init,
  });
  Object.defineProperty(event, "timeStamp", { value: time });
  target.dispatchEvent(event);
};

describe("sheet gestures", () => {
  const originalCloseWatcher = window.CloseWatcher;
  const originalGetComputedStyle = window.getComputedStyle;
  const originalMatchMedia = window.matchMedia;

  beforeEach(() => {
    resetDom();
    FakeCloseWatcher.instances = [];
    window.CloseWatcher = FakeCloseWatcher;
  });

  afterEach(() => {
    window.CloseWatcher = originalCloseWatcher;
    window.getComputedStyle = originalGetComputedStyle;
    window.matchMedia = originalMatchMedia;
    resetRestoredModalState(document);
    resetDom();
  });

  describe("false query", () => {
    it("does nothing", () => {
      mockPhoneQuery(false);
      const { closeCount, grab, panel } = renderSheet();
      const addedListeners = [];
      const originalAddEventListener = document.addEventListener;
      document.addEventListener = (type) => addedListeners.push(type);
      panel.addEventListener = (type) => addedListeners.push(type);
      let computedStyleReads = 0;
      window.getComputedStyle = (...args) => {
        computedStyleReads += 1;
        return originalGetComputedStyle.apply(window, args);
      };

      // Bind and try to drag the sheet.
      const cleanup = bindSheetGestures(panel);
      firePointer(grab, "pointerdown", { clientY: 100 });
      firePointer(grab, "pointermove", { clientY: 400 });
      firePointer(grab, "pointerup", { clientY: 400 });
      cleanup();
      document.addEventListener = originalAddEventListener;

      // Verify no watcher, listener, attribute, style write or style read.
      expect(FakeCloseWatcher.instances).to.have.length(0);
      expect(addedListeners).to.deep.equal([]);
      expect(panel.hasAttribute("data-sheet-drag")).to.equal(false);
      expect(panel.getAttribute("style")).to.equal("position: fixed; height: 400px");
      expect(computedStyleReads).to.equal(0);
      expect(closeCount()).to.equal(0);
    });

    it("leaves a fixed sheet panel out of isBottomSheet", () => {
      mockPhoneQuery(false);

      expect(isBottomSheet(renderSheet().panel)).to.equal(false);
    });

    it("returns the same no-op for every unbound panel", () => {
      mockPhoneQuery(false);
      const first = bindSheetGestures(renderSheet().panel);

      // A true query without a usable panel resolves to the same no-op.
      mockPhoneQuery(true);
      expect(bindSheetGestures(null)).to.equal(first);
      expect(bindSheetGestures(undefined)).to.equal(first);
      expect(bindSheetGestures(renderSheet("position: static").panel)).to.equal(first);
      expect(bindSheetGestures(document.createElement("div"))).to.equal(first);
      expect(FakeCloseWatcher.instances).to.have.length(0);
    });

    it("keeps toggleModalVisibility free of gestures", () => {
      mockPhoneQuery(false);
      const { modal, panel, trigger } = renderSheetModal();

      // Open and verify the modal contract without any gesture state.
      toggleModalVisibility(modal, trigger);
      expect(modal.getAttribute("aria-hidden")).to.equal("false");
      expect(document.body.dataset.modalOpenCount).to.equal("1");
      expect(FakeCloseWatcher.instances).to.have.length(0);
      expect(panel.hasAttribute("data-sheet-drag")).to.equal(false);

      // Close and verify lock and focus come back.
      toggleModalVisibility(modal);
      expect(modal.getAttribute("aria-hidden")).to.equal("true");
      expect(document.body.dataset.modalOpenCount).to.equal("0");
      expect(document.activeElement).to.equal(trigger);
    });
  });

  describe("isBottomSheet", () => {
    it("matches fixed sheet panels and account sheets on phones", () => {
      mockPhoneQuery(true);
      const accountSheet = document.createElement("div");
      accountSheet.className = "account-sheet";
      accountSheet.style.position = "fixed";
      document.body.append(accountSheet);

      expect(isBottomSheet(renderSheet().panel)).to.equal(true);
      expect(isBottomSheet(accountSheet)).to.equal(true);
    });

    it("rejects static panels, other elements and null", () => {
      mockPhoneQuery(true);
      const other = document.createElement("div");
      other.style.position = "fixed";
      document.body.append(other);

      expect(isBottomSheet(renderSheet("position: static").panel)).to.equal(false);
      expect(isBottomSheet(other)).to.equal(false);
      expect(isBottomSheet(null)).to.equal(false);
    });
  });

  describe("requestSheetClose", () => {
    it("clicks the real close button", () => {
      const { closeCount, panel } = renderSheet();

      requestSheetClose(panel);

      expect(closeCount()).to.equal(1);
    });

    it("ignores a panel without a close button", () => {
      const panel = document.createElement("div");

      expect(() => requestSheetClose(panel)).to.not.throw();
    });
  });

  describe("binding", () => {
    it("marks the panel and creates one watcher", () => {
      mockPhoneQuery(true);
      const { panel } = renderSheet();

      const cleanup = bindSheetGestures(panel);

      expect(panel.hasAttribute("data-sheet-drag")).to.equal(true);
      expect(FakeCloseWatcher.instances).to.have.length(1);
      cleanup();
    });

    it("returns the existing cleanup when the sheet is already bound", () => {
      const query = mockPhoneQuery(true);
      const { panel } = renderSheet();

      const cleanup = bindSheetGestures(panel);

      expect(bindSheetGestures(panel)).to.equal(cleanup);
      expect(FakeCloseWatcher.instances).to.have.length(1);
      expect(query.listeners.size).to.equal(1);
      cleanup();
    });

    it("removes everything once, however many times cleanup runs", () => {
      const query = mockPhoneQuery(true);
      const { grab, panel } = renderSheet();
      const cleanup = bindSheetGestures(panel);

      // Clean up in the middle of a drag.
      firePointer(grab, "pointerdown", { clientY: 100 });
      firePointer(grab, "pointermove", { clientY: 150 });
      cleanup();
      cleanup();

      expect(FakeCloseWatcher.instances[0].destroyCount).to.equal(1);
      expect(query.listeners.size).to.equal(0);
      expect(panel.hasAttribute("data-sheet-drag")).to.equal(false);
      expect(panel.style.translate).to.equal("");
      expect(panel.style.transition).to.equal("");

      // A later drag has no effect.
      firePointer(grab, "pointerdown", { clientY: 100 });
      firePointer(grab, "pointermove", { clientY: 150 });
      expect(panel.style.translate).to.equal("");
    });

    it("can bind again after cleanup", () => {
      mockPhoneQuery(true);
      const { panel } = renderSheet();

      bindSheetGestures(panel)();
      const cleanup = bindSheetGestures(panel);

      expect(panel.hasAttribute("data-sheet-drag")).to.equal(true);
      expect(FakeCloseWatcher.instances).to.have.length(2);
      cleanup();
    });

    it("binds the account sheet list, not the scrim", () => {
      mockPhoneQuery(true);
      const wrapper = document.createElement("div");
      wrapper.className = "account-sheet";
      wrapper.style.position = "fixed";
      const { grab, panel } = renderSheet();
      wrapper.append(panel);
      document.body.append(wrapper);

      // Bind through the wrapper and drag the title row.
      const cleanup = bindSheetGestures(wrapper);
      firePointer(grab, "pointerdown", { clientY: 100 });
      firePointer(grab, "pointermove", { clientY: 130 });

      expect(panel.hasAttribute("data-sheet-drag")).to.equal(true);
      expect(wrapper.hasAttribute("data-sheet-drag")).to.equal(false);
      expect(panel.style.translate).to.equal("0px 30px");
      expect(wrapper.style.translate).to.equal("");
      expect(bindSheetGestures(panel)).to.equal(cleanup);
      cleanup();
    });
  });

  describe("Android Back", () => {
    it("clicks the close button on a close request", () => {
      mockPhoneQuery(true);
      const { closeCount, panel } = renderSheet();
      const cleanup = bindSheetGestures(panel);
      const historyLength = window.history.length;

      FakeCloseWatcher.instances[0].requestClose();

      expect(closeCount()).to.equal(1);
      expect(window.history.length).to.equal(historyLength);
      cleanup();
    });

    it("keeps dragging where CloseWatcher is missing", () => {
      mockPhoneQuery(true);
      delete window.CloseWatcher;
      const { grab, panel } = renderSheet();

      const cleanup = bindSheetGestures(panel);
      firePointer(grab, "pointerdown", { clientY: 100 });
      firePointer(grab, "pointermove", { clientY: 130 });

      expect(panel.style.translate).to.equal("0px 30px");
      expect(() => cleanup()).to.not.throw();
    });

    it("only releases a sheet swapped out while open", () => {
      const query = mockPhoneQuery(true);
      const { closeCount, panel } = renderSheet();
      bindSheetGestures(panel);
      panel.remove();

      FakeCloseWatcher.instances[0].requestClose();

      expect(closeCount()).to.equal(0);
      expect(FakeCloseWatcher.instances[0].destroyCount).to.equal(1);
      expect(query.listeners.size).to.equal(0);
    });
  });

  describe("drag", () => {
    /**
     * Binds a sheet, then drags its title row from y=100 by the given distance.
     * @param {number} distance Dragged pixels.
     * @param {number} time Drag duration in milliseconds.
     * @param {string} [panelStyle] Inline panel style.
     * @returns {ReturnType<typeof renderSheet> & {cleanup: () => void}} Sheet after the drag.
     */
    const dragSheet = (distance, time, panelStyle) => {
      mockPhoneQuery(true);
      const sheet = renderSheet(panelStyle);
      const cleanup = bindSheetGestures(sheet.panel);

      firePointer(sheet.grab, "pointerdown", { clientY: 100 });
      firePointer(sheet.grab, "pointermove", { clientY: 100 + distance, time });
      firePointer(sheet.grab, "pointerup", { clientY: 100 + distance, time });

      return { ...sheet, cleanup };
    };

    it("captures the pointer and follows it down", () => {
      mockPhoneQuery(true);
      const { grab, panel } = renderSheet();
      const captures = [];
      grab.setPointerCapture = (pointerId) => captures.push(pointerId);
      const cleanup = bindSheetGestures(panel);

      firePointer(grab, "pointerdown", { clientY: 100 });
      expect(captures).to.deep.equal([1]);
      expect(panel.style.transition).to.equal("none");

      firePointer(grab, "pointermove", { clientY: 145 });
      expect(panel.style.translate).to.equal("0px 45px");

      // The sheet never moves above its resting place.
      firePointer(grab, "pointermove", { clientY: 40 });
      expect(panel.style.translate).to.equal("0px");
      cleanup();
    });

    it("ignores secondary pointers, other buttons, controls and the body", () => {
      mockPhoneQuery(true);
      const { close, grab, panel } = renderSheet();
      const body = panel.querySelector("input");
      const cleanup = bindSheetGestures(panel);

      firePointer(grab, "pointerdown", { init: { isPrimary: false } });
      firePointer(grab, "pointerdown", { init: { button: 2 } });
      firePointer(close, "pointerdown");
      firePointer(close.firstElementChild, "pointerdown");
      firePointer(body, "pointerdown");
      firePointer(grab, "pointermove", { clientY: 200 });

      expect(panel.style.transition).to.equal("");
      expect(panel.style.translate).to.equal("");
      cleanup();
    });

    it("ignores other pointers during a drag", () => {
      mockPhoneQuery(true);
      const { closeCount, grab, panel } = renderSheet();
      const cleanup = bindSheetGestures(panel);

      firePointer(grab, "pointerdown", { clientY: 100 });
      firePointer(grab, "pointermove", { clientY: 130 });
      firePointer(grab, "pointermove", { clientY: 300, init: { pointerId: 2 } });
      firePointer(grab, "pointerup", { clientY: 300, init: { pointerId: 2 } });

      expect(panel.style.translate).to.equal("0px 30px");
      expect(closeCount()).to.equal(0);
      cleanup();
    });

    it("closes past a quarter of a short panel", () => {
      const { cleanup, closeCount, panel } = dragSheet(101, 10000);

      expect(closeCount()).to.equal(1);
      expect(panel.style.translate).to.equal("");
      cleanup();
    });

    it("snaps back at a quarter of a short panel", () => {
      const { cleanup, closeCount, panel } = dragSheet(100, 10000);

      expect(closeCount()).to.equal(0);
      expect(panel.style.translate).to.equal("");
      expect(panel.style.transition).to.equal("");
      expect(panel.hasAttribute("data-sheet-drag")).to.equal(true);
      cleanup();
    });

    it("caps the distance at 120px on a tall panel", () => {
      const panelStyle = "position: fixed; height: 800px";
      const short = dragSheet(120, 10000, panelStyle);
      const long = dragSheet(121, 10000, panelStyle);

      expect(short.closeCount()).to.equal(0);
      expect(long.closeCount()).to.equal(1);
      short.cleanup();
      long.cleanup();
    });

    it("closes on a fast flick of at least 24px", () => {
      const { cleanup, closeCount } = dragSheet(24, 48);

      expect(closeCount()).to.equal(1);
      cleanup();
    });

    it("snaps back on a slow or tiny flick", () => {
      const slow = dragSheet(24, 49);
      const tiny = dragSheet(23, 10);

      expect(slow.closeCount()).to.equal(0);
      expect(tiny.closeCount()).to.equal(0);
      slow.cleanup();
      tiny.cleanup();
    });

    it("snaps back when the close button does not close", () => {
      mockPhoneQuery(true);
      const { close, grab, panel } = renderSheet();
      close.disabled = true;
      const cleanup = bindSheetGestures(panel);

      firePointer(grab, "pointerdown", { clientY: 100 });
      firePointer(grab, "pointermove", { clientY: 300, time: 100 });
      firePointer(grab, "pointerup", { clientY: 300, time: 100 });

      expect(panel.style.translate).to.equal("");
      expect(panel.style.transition).to.equal("");
      cleanup();
    });

    ["pointercancel", "lostpointercapture"].forEach((type) => {
      it(`snaps back on ${type}`, () => {
        mockPhoneQuery(true);
        const { closeCount, grab, panel } = renderSheet();
        const cleanup = bindSheetGestures(panel);

        firePointer(grab, "pointerdown", { clientY: 100 });
        firePointer(grab, "pointermove", { clientY: 400 });
        firePointer(grab, type, { clientY: 400 });

        expect(closeCount()).to.equal(0);
        expect(panel.style.translate).to.equal("");
        expect(panel.style.transition).to.equal("");
        cleanup();
      });
    });
  });

  describe("release without a close", () => {
    it("releases on rotation and leaves the sheet open", () => {
      const query = mockPhoneQuery(true);
      const { close, modal, panel } = renderSheetModal();
      toggleModalVisibility(modal);

      // Rotate past 768px with the sheet open.
      query.setMatches(false);

      expect(FakeCloseWatcher.instances[0].destroyCount).to.equal(1);
      expect(query.listeners.size).to.equal(0);
      expect(panel.hasAttribute("data-sheet-drag")).to.equal(false);
      expect(modal.classList.contains("hidden")).to.equal(false);
      expect(document.body.dataset.modalOpenCount).to.equal("1");

      // The ordinary close afterwards does not clean up twice.
      close.click();
      expect(FakeCloseWatcher.instances[0].destroyCount).to.equal(1);
      expect(document.body.dataset.modalOpenCount).to.equal("0");
    });

    it("gives a modal opened off phones no gestures after rotating in", () => {
      const query = mockPhoneQuery(false);
      const { modal, panel } = renderSheetModal();
      toggleModalVisibility(modal);

      query.setMatches(true);

      expect(FakeCloseWatcher.instances).to.have.length(0);
      expect(panel.hasAttribute("data-sheet-drag")).to.equal(false);
    });

    it("strips drag state before an HTMX history snapshot", () => {
      const query = mockPhoneQuery(true);
      const { grab, panel } = renderSheet();
      bindSheetGestures(panel);
      firePointer(grab, "pointerdown", { clientY: 100 });
      firePointer(grab, "pointermove", { clientY: 150 });

      document.body.dispatchEvent(new CustomEvent("htmx:beforeHistorySave", { bubbles: true }));

      expect(panel.hasAttribute("data-sheet-drag")).to.equal(false);
      expect(panel.style.translate).to.equal("");
      expect(FakeCloseWatcher.instances[0].destroyCount).to.equal(1);
      expect(query.listeners.size).to.equal(0);
    });
  });

  describe("page restore", () => {
    /**
     * Records the window pageshow listeners a test adds and removes.
     * @returns {{active: Set<Function>, restore: () => void}} Listener log.
     */
    const recordPageShowListeners = () => {
      const { addEventListener, removeEventListener } = window;
      const active = new Set();
      window.addEventListener = function (type, listener, ...rest) {
        if (type === "pageshow") {
          active.add(listener);
        }
        return addEventListener.call(this, type, listener, ...rest);
      };
      window.removeEventListener = function (type, listener, ...rest) {
        if (type === "pageshow") {
          active.delete(listener);
        }
        return removeEventListener.call(this, type, listener, ...rest);
      };

      return {
        active,
        restore: () => {
          window.addEventListener = addEventListener;
          window.removeEventListener = removeEventListener;
        },
      };
    };

    /** Builds a pageshow event. */
    const pageShowEvent = (persisted) => {
      const event = new Event("pageshow");
      Object.defineProperty(event, "persisted", { value: persisted });
      return event;
    };

    let pageShow;

    beforeEach(() => {
      pageShow = recordPageShowListeners();
    });

    afterEach(() => {
      pageShow.restore();
    });

    it("runs the callback on a back-forward cache restore only", () => {
      mockPhoneQuery(true);
      const { panel } = renderSheet();
      let restores = 0;
      const cleanup = bindSheetGestures(panel, { onPageRestore: () => (restores += 1) });

      window.dispatchEvent(pageShowEvent(false));
      expect(restores).to.equal(0);

      window.dispatchEvent(pageShowEvent(true));
      expect(restores).to.equal(1);

      cleanup();
    });

    it("listens only for sheets that ask", () => {
      mockPhoneQuery(true);
      const cleanup = bindSheetGestures(renderSheet().panel);

      expect(pageShow.active.size).to.equal(0);

      cleanup();
    });

    it("stops listening on cleanup", () => {
      mockPhoneQuery(true);
      const cleanup = bindSheetGestures(renderSheet().panel, { onPageRestore() {} });
      expect(pageShow.active.size).to.equal(1);

      cleanup();

      expect(pageShow.active.size).to.equal(0);
    });

    it("stops listening when the phone query turns false", () => {
      const query = mockPhoneQuery(true);
      bindSheetGestures(renderSheet().panel, { onPageRestore() {} });

      query.setMatches(false);

      expect(pageShow.active.size).to.equal(0);
    });

    it("adds no listener under a false phone query", () => {
      mockPhoneQuery(false);

      bindSheetGestures(renderSheet().panel, { onPageRestore() {} });

      expect(pageShow.active.size).to.equal(0);
    });
  });

  describe("HTMX swaps", () => {
    it("keeps gestures while the sheet stays in the page", () => {
      mockPhoneQuery(true);
      const { panel } = renderSheet();
      bindSheetGestures(panel);

      document.body.dispatchEvent(new CustomEvent("htmx:afterSwap", { bubbles: true }));

      expect(panel.hasAttribute("data-sheet-drag")).to.equal(true);
      expect(FakeCloseWatcher.instances[0].destroyCount).to.equal(0);
    });

    it("releases a sheet the swap removed, so no watcher eats the next Back", () => {
      const query = mockPhoneQuery(true);
      const { panel } = renderSheet();
      bindSheetGestures(panel);
      panel.remove();

      document.body.dispatchEvent(new CustomEvent("htmx:afterSwap", { bubbles: true }));

      expect(FakeCloseWatcher.instances[0].destroyCount).to.equal(1);
      expect(query.listeners.size).to.equal(0);
    });
  });

  describe("modal lifecycle", () => {
    it("binds on open and cleans up on close", () => {
      const query = mockPhoneQuery(true);
      const { modal, panel, trigger } = renderSheetModal();

      toggleModalVisibility(modal, trigger);
      expect(panel.hasAttribute("data-sheet-drag")).to.equal(true);
      expect(FakeCloseWatcher.instances).to.have.length(1);

      toggleModalVisibility(modal);
      expect(panel.hasAttribute("data-sheet-drag")).to.equal(false);
      expect(FakeCloseWatcher.instances[0].destroyCount).to.equal(1);
      expect(query.listeners.size).to.equal(0);
      expect(document.activeElement).to.equal(trigger);
    });

    it("binds a modal that is itself the sheet panel", () => {
      mockPhoneQuery(true);
      const { modal, panel } = renderSheetModal();
      panel.classList.remove("sheet-panel");
      modal.classList.add("sheet-panel");
      modal.style.position = "fixed";

      toggleModalVisibility(modal);

      expect(modal.hasAttribute("data-sheet-drag")).to.equal(true);
    });

    it("gives a phone modal without a sheet panel the no-op", () => {
      const query = mockPhoneQuery(true);
      const { modal, panel } = renderSheetModal();
      panel.classList.remove("sheet-panel");

      toggleModalVisibility(modal);
      toggleModalVisibility(modal);

      expect(FakeCloseWatcher.instances).to.have.length(0);
      expect(query.listeners.size).to.equal(0);
    });

    it("closes through Back, restoring lock and focus", () => {
      mockPhoneQuery(true);
      const { modal, trigger } = renderSheetModal();
      toggleModalVisibility(modal, trigger);

      FakeCloseWatcher.instances[0].requestClose();

      expect(modal.classList.contains("hidden")).to.equal(true);
      expect(document.body.dataset.modalOpenCount).to.equal("0");
      expect(document.activeElement).to.equal(trigger);
      expect(FakeCloseWatcher.instances[0].destroyCount).to.equal(1);
    });

    it("closes through a drag past the threshold", () => {
      mockPhoneQuery(true);
      const { modal, panel } = renderSheetModal();
      const grab = panel.querySelector(".sheet-grab");
      grab.setPointerCapture = () => {};
      toggleModalVisibility(modal);

      firePointer(grab, "pointerdown", { clientY: 100 });
      firePointer(grab, "pointermove", { clientY: 300, time: 1000 });
      firePointer(grab, "pointerup", { clientY: 300, time: 1000 });

      expect(modal.classList.contains("hidden")).to.equal(true);
      expect(panel.style.translate).to.equal("");
    });

    it("keeps gestures when bindOpenModalKeyboard runs after opening", () => {
      mockPhoneQuery(true);
      const { modal, panel } = renderSheetModal();

      // Open the way map-modal.js does.
      toggleModalVisibility(modal);
      bindOpenModalKeyboard(modal);
      expect(FakeCloseWatcher.instances[0].destroyCount).to.equal(0);
      expect(panel.hasAttribute("data-sheet-drag")).to.equal(true);

      // Escape closes through the keyboard cleanup and releases the gestures too.
      document.dispatchEvent(new KeyboardEvent("keydown", { cancelable: true, key: "Escape" }));
      expect(modal.classList.contains("hidden")).to.equal(true);
      expect(FakeCloseWatcher.instances[0].destroyCount).to.equal(1);
      expect(panel.hasAttribute("data-sheet-drag")).to.equal(false);
    });

    it("cleans up on navigation and bfcache reset", () => {
      const query = mockPhoneQuery(true);
      const { modal, panel } = renderSheetModal();
      toggleModalVisibility(modal);

      resetRestoredModalState(document);

      expect(modal.classList.contains("hidden")).to.equal(true);
      expect(FakeCloseWatcher.instances[0].destroyCount).to.equal(1);
      expect(panel.hasAttribute("data-sheet-drag")).to.equal(false);
      expect(query.listeners.size).to.equal(0);
    });

    it("binds again when the modal reopens", () => {
      mockPhoneQuery(true);
      const { modal, panel } = renderSheetModal();

      toggleModalVisibility(modal);
      toggleModalVisibility(modal);
      toggleModalVisibility(modal);

      expect(FakeCloseWatcher.instances).to.have.length(2);
      expect(panel.hasAttribute("data-sheet-drag")).to.equal(true);
    });
  });
});
