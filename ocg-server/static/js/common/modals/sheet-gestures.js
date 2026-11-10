import { isPhoneViewport, PHONE_MEDIA_QUERY } from "/static/js/common/phone-viewport.js";

const ACCOUNT_SHEET_SELECTOR = ".account-sheet";
const CLOSE_BUTTON_SELECTOR = "button:has(> .icon-close)";
const DRAG_CLOSE_DISTANCE_PX = 120;
const DRAG_CLOSE_HEIGHT_RATIO = 0.25;
const DRAG_FLICK_DISTANCE_PX = 24;
const DRAG_FLICK_SPEED_PX_PER_MS = 0.5;
const DRAG_IGNORED_TARGET_SELECTOR = "button, a, input, select, textarea";
const GRAB_SELECTOR = ".sheet-grab";
const SHEET_PANEL_SELECTOR = ".sheet-panel";
const SHEET_SELECTOR = `${SHEET_PANEL_SELECTOR}, ${ACCOUNT_SHEET_SELECTOR}`;
const noGestures = () => {};
const sheetCleanups = new WeakMap();

/**
 * Binds Android Back and the draggable grabber to an open bottom sheet. Call it
 * once the panel is visible. Off phones nothing runs. Binding a bound sheet
 * again returns its existing cleanup. The sheet releases everything by itself
 * when the phone query turns false or an HTMX history snapshot is taken, and
 * stays open as an ordinary modal. It also releases when an HTMX swap removes it.
 * @param {Element|null|undefined} panel Sheet panel, or the account sheet wrapper.
 * @param {Object} [options] Binding options.
 * @param {() => void} [options.onPageRestore] Runs when the page returns from the
 *   back-forward cache, for sheets the shared restore cannot close by itself.
 * @returns {() => void} Idempotent cleanup callback.
 */
export const bindSheetGestures = (panel, { onPageRestore } = {}) => {
  if (!isBottomSheet(panel)) {
    return noGestures;
  }

  const sheet = getDraggedSheet(panel);
  const existingCleanup = sheetCleanups.get(sheet);
  if (existingCleanup) {
    return existingCleanup;
  }

  const phoneQuery = window.matchMedia(PHONE_MEDIA_QUERY);
  const handlePhoneQueryChange = (event) => {
    if (!event.matches) {
      cleanup();
    }
  };
  const handlePageShow = (event) => {
    if (event.persisted) {
      onPageRestore();
    }
  };
  const handleSwap = () => {
    if (!sheet.isConnected) {
      cleanup();
    }
  };
  const unbindDrag = bindSheetDrag(sheet);
  const watcher = createCloseWatcher(sheet, () => cleanup());
  const cleanup = () => {
    if (sheetCleanups.get(sheet) !== cleanup) {
      return;
    }

    sheetCleanups.delete(sheet);
    unbindDrag();
    watcher?.destroy();
    phoneQuery.removeEventListener("change", handlePhoneQueryChange);
    document.removeEventListener("htmx:afterSwap", handleSwap);
    document.removeEventListener("htmx:beforeHistorySave", cleanup);
    window.removeEventListener("pageshow", handlePageShow);
    delete sheet.dataset.sheetDrag;
  };

  sheetCleanups.set(sheet, cleanup);
  sheet.dataset.sheetDrag = "";
  phoneQuery.addEventListener("change", handlePhoneQueryChange);
  document.addEventListener("htmx:afterSwap", handleSwap);
  document.addEventListener("htmx:beforeHistorySave", cleanup);
  if (onPageRestore) {
    window.addEventListener("pageshow", handlePageShow);
  }

  return cleanup;
};

/**
 * Checks whether an element is laid out as a bottom sheet. The query test comes
 * first because #drawer-filters is fixed at every width.
 * @param {Element|null|undefined} panel Sheet panel, or the account sheet wrapper.
 * @returns {boolean} True when the element is a bottom sheet on a phone.
 */
export const isBottomSheet = (panel) =>
  isPhoneViewport() &&
  panel?.matches(SHEET_SELECTOR) === true &&
  window.getComputedStyle(panel).position === "fixed";

/**
 * Returns the close button of a sheet.
 * @param {Element} panel Sheet panel.
 * @returns {HTMLElement|null} Close button, when the sheet has one.
 */
export const getSheetCloseButton = (panel) => panel.querySelector(CLOSE_BUTTON_SELECTOR);

/**
 * Closes a sheet through its real close button, so the sheet's own close logic runs.
 * @param {Element} panel Sheet panel.
 * @returns {void}
 */
export const requestSheetClose = (panel) => {
  getSheetCloseButton(panel)?.click();
};

/**
 * Binds the title row drag. A disabled close button leaves the sheet open, so
 * the drag state clears after a close request as well.
 * @param {Element} sheet Sheet panel.
 * @returns {() => void} Cleanup callback that removes the listeners.
 */
const bindSheetDrag = (sheet) => {
  let drag = null;

  const clearDrag = () => {
    drag = null;
    sheet.style.removeProperty("transition");
    sheet.style.removeProperty("translate");
  };

  const handlePointerDown = (event) => {
    const grab = event.target.closest(GRAB_SELECTOR);
    if (
      !grab ||
      drag ||
      !event.isPrimary ||
      event.button !== 0 ||
      event.target.closest(DRAG_IGNORED_TARGET_SELECTOR)
    ) {
      return;
    }

    grab.setPointerCapture(event.pointerId);
    drag = { pointerId: event.pointerId, startTime: event.timeStamp, startY: event.clientY };
    sheet.style.transition = "none";
  };

  const handlePointerMove = (event) => {
    if (event.pointerId === drag?.pointerId) {
      sheet.style.translate = `0 ${getDragDistance(drag, event)}px`;
    }
  };

  const handlePointerUp = (event) => {
    if (event.pointerId !== drag?.pointerId) {
      return;
    }

    if (shouldCloseAfterDrag(sheet, drag, event)) {
      requestSheetClose(sheet);
    }
    clearDrag();
  };

  const handlePointerAbort = (event) => {
    if (event.pointerId === drag?.pointerId) {
      clearDrag();
    }
  };

  sheet.addEventListener("pointerdown", handlePointerDown);
  sheet.addEventListener("pointermove", handlePointerMove);
  sheet.addEventListener("pointerup", handlePointerUp);
  sheet.addEventListener("pointercancel", handlePointerAbort);
  sheet.addEventListener("lostpointercapture", handlePointerAbort);

  return () => {
    sheet.removeEventListener("pointerdown", handlePointerDown);
    sheet.removeEventListener("pointermove", handlePointerMove);
    sheet.removeEventListener("pointerup", handlePointerUp);
    sheet.removeEventListener("pointercancel", handlePointerAbort);
    sheet.removeEventListener("lostpointercapture", handlePointerAbort);
    clearDrag();
  };
};

/**
 * Creates the watcher that turns Android Back into a close request. A sheet
 * swapped out while open has no close logic left to run, so it only releases.
 * @param {Element} sheet Sheet panel.
 * @param {() => void} release Releases the sheet's gestures.
 * @returns {CloseWatcher|null} Watcher, or null where the API is missing.
 */
const createCloseWatcher = (sheet, release) => {
  if (!("CloseWatcher" in window)) {
    return null;
  }

  const watcher = new window.CloseWatcher();
  watcher.addEventListener("close", () => {
    if (sheet.isConnected) {
      requestSheetClose(sheet);
    } else {
      release();
    }
  });
  return watcher;
};

/**
 * Returns how far a drag has moved down. Sheets only move down.
 * @param {{startY: number}} drag Drag state.
 * @param {PointerEvent} event Pointer event.
 * @returns {number} Downward distance in pixels.
 */
const getDragDistance = (drag, event) => Math.max(0, event.clientY - drag.startY);

/**
 * Returns the element that moves: the account sheet wrapper is the scrim, and
 * its list is the panel.
 * @param {Element} panel Sheet panel, or the account sheet wrapper.
 * @returns {Element} Sheet panel.
 */
const getDraggedSheet = (panel) =>
  panel.matches(ACCOUNT_SHEET_SELECTOR) ? (panel.querySelector(SHEET_PANEL_SELECTOR) ?? panel) : panel;

/**
 * Checks whether a finished drag travelled far or fast enough to close the sheet.
 * @param {Element} sheet Sheet panel.
 * @param {{startTime: number, startY: number}} drag Drag state.
 * @param {PointerEvent} event Final pointer event.
 * @returns {boolean} True when the sheet should close.
 */
const shouldCloseAfterDrag = (sheet, drag, event) => {
  const distance = getDragDistance(drag, event);
  const closeDistance = Math.min(
    DRAG_CLOSE_DISTANCE_PX,
    sheet.getBoundingClientRect().height * DRAG_CLOSE_HEIGHT_RATIO,
  );
  const speed = distance / (event.timeStamp - drag.startTime);

  return (
    distance > closeDistance || (distance >= DRAG_FLICK_DISTANCE_PX && speed >= DRAG_FLICK_SPEED_PX_PER_MS)
  );
};
