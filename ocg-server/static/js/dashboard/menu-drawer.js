import { closestElement, getElementById, setElementHidden } from "/static/js/common/dom.js";
import { isEscapeEvent } from "/static/js/common/keyboard.js";
import {
  lockBodyScroll,
  trapModalFocus,
  unlockBodyScroll,
} from "/static/js/common/modals/modal-lifecycle.js";
import { bindSheetGestures } from "/static/js/common/modals/sheet-gestures.js";

const BACKDROP_ID = "dashboard-menu-backdrop";
const CLOSE_BUTTON_ID = "close-dashboard-menu";
// Mirrors the md variant in styles.src.css: fine pointers keep the desktop layout when narrow.
const DESKTOP_MEDIA_QUERY = "(min-width: 768px), (pointer: fine)";
const DRAWER_CLOSED_CLASS = "-translate-x-full";
const DRAWER_ID = "dashboard-menu-drawer";
const OPEN_BUTTON_ID = "open-dashboard-menu";
// Page controls that open the drawer too, such as the phone group context on the group dashboard.
const OPENER_SELECTOR = `#${OPEN_BUTTON_ID}, [data-dashboard-menu-open]`;

// Tracks whether the drawer currently holds the shared body scroll lock.
let drawerHoldsScrollLock = false;
// Releases the phone bottom-sheet drag gestures while the drawer is open, when bound.
let releaseDrawerGestures = null;
// Control that opened the drawer, which takes focus back on close.
let drawerOpener = null;

/**
 * Closes the dashboard menu drawer and returns focus to the open button (mobile only).
 */
export const closeDashboardMenuDrawer = () => {
  const drawer = getElementById(document, DRAWER_ID);
  if (!drawer || drawer.classList.contains(DRAWER_CLOSED_CLASS)) {
    return;
  }
  drawer.classList.add(DRAWER_CLOSED_CLASS);
  setElementHidden(getElementById(document, BACKDROP_ID), true);
  releaseDrawerScrollLock();
  releaseDrawerSheetGestures();
  syncDrawerHiddenState(drawer);
  setOpenersExpanded(false);
  const opener = drawerOpener?.isConnected ? drawerOpener : getElementById(document, OPEN_BUTTON_ID);
  drawerOpener = null;
  opener?.focus();
};

/**
 * Opens the dashboard menu drawer and moves focus to its close button (mobile only).
 * @param {HTMLElement|null} [opener] - Control that opened it, the menu button when omitted
 */
export const openDashboardMenuDrawer = (opener = null) => {
  const drawer = getElementById(document, DRAWER_ID);
  if (!drawer || !drawer.classList.contains(DRAWER_CLOSED_CLASS)) {
    return;
  }
  drawer.classList.remove(DRAWER_CLOSED_CLASS);
  setElementHidden(getElementById(document, BACKDROP_ID), false);
  acquireDrawerScrollLock();
  releaseDrawerGestures = bindSheetGestures(drawer);
  syncDrawerHiddenState(drawer);
  drawerOpener = opener;
  setOpenersExpanded(true);
  const closeButton = getElementById(document, CLOSE_BUTTON_ID);
  if (closeButton) {
    closeButton.focus();
  } else {
    drawer.focus();
  }
};

/**
 * Acquires the shared body scroll lock once while the drawer is open.
 */
const acquireDrawerScrollLock = () => {
  if (!drawerHoldsScrollLock) {
    drawerHoldsScrollLock = true;
    lockBodyScroll();
  }
};

/**
 * Handles clicks on the drawer controls through document-level delegation.
 * @param {MouseEvent} event - Click event
 */
const handleMenuDrawerClick = (event) => {
  const opener = closestElement(event.target, OPENER_SELECTOR);
  if (opener) {
    event.preventDefault();
    openDashboardMenuDrawer(opener);
    return;
  }
  if (
    closestElement(event.target, `#${CLOSE_BUTTON_ID}`) ||
    closestElement(event.target, `#${BACKDROP_ID}`)
  ) {
    event.preventDefault();
    closeDashboardMenuDrawer();
  }
};

/**
 * Closes the drawer on Escape and keeps Tab focus inside it while it is open.
 * Key presses already consumed by other widgets are ignored.
 * @param {KeyboardEvent} event - Keydown event
 */
const handleMenuDrawerKeydown = (event) => {
  if (event.defaultPrevented) {
    return;
  }
  if (isEscapeEvent(event)) {
    closeDashboardMenuDrawer();
    return;
  }
  const drawer = getElementById(document, DRAWER_ID);
  if (drawer && !drawer.classList.contains(DRAWER_CLOSED_CLASS) && !isDesktopViewport()) {
    trapModalFocus(event, drawer);
  }
};

/**
 * Releases drawer state after an HTMX swap that replaced the drawer markup while it
 * was open, then re-synchronizes the assistive state of the swapped-in drawer.
 */
const handleSwapDrawerCleanup = () => {
  const drawer = getElementById(document, DRAWER_ID);
  if (!drawer || drawer.classList.contains(DRAWER_CLOSED_CLASS)) {
    releaseDrawerScrollLock();
    releaseDrawerSheetGestures();
  }
  syncDrawerHiddenState(drawer);
};

/**
 * Checks whether the viewport is at the md breakpoint where the menu is static.
 * @returns {boolean} True when the static desktop menu is displayed
 */
const isDesktopViewport = () =>
  typeof window.matchMedia === "function" && window.matchMedia(DESKTOP_MEDIA_QUERY).matches;

/**
 * Releases the shared body scroll lock when the drawer holds it.
 */
const releaseDrawerScrollLock = () => {
  if (drawerHoldsScrollLock) {
    drawerHoldsScrollLock = false;
    unlockBodyScroll();
  }
};

/**
 * Releases the phone bottom-sheet drag gestures bound while the drawer was open.
 */
const releaseDrawerSheetGestures = () => {
  if (releaseDrawerGestures) {
    releaseDrawerGestures();
    releaseDrawerGestures = null;
  }
};

/**
 * Resets the drawer to its closed state without moving focus. Used when history
 * navigation, page restoration, or viewport changes invalidate the open state.
 */
const resetDrawerState = () => {
  releaseDrawerScrollLock();
  releaseDrawerSheetGestures();
  const drawer = getElementById(document, DRAWER_ID);
  if (drawer) {
    drawer.classList.add(DRAWER_CLOSED_CLASS);
  }
  setElementHidden(getElementById(document, BACKDROP_ID), true);
  drawerOpener = null;
  setOpenersExpanded(false);
  syncDrawerHiddenState(drawer);
};

/**
 * Reflects the drawer state on every control that opens it.
 * @param {boolean} isExpanded - Whether the drawer is open
 */
const setOpenersExpanded = (isExpanded) => {
  document.querySelectorAll(OPENER_SELECTOR).forEach((opener) => {
    opener.setAttribute("aria-expanded", String(isExpanded));
  });
};

/**
 * Synchronizes the drawer assistive state: while it is closed below the md breakpoint
 * the off-canvas menu is inert and hidden from assistive technologies.
 * @param {HTMLElement|null} [drawer] - Drawer element, looked up when omitted
 */
const syncDrawerHiddenState = (drawer = getElementById(document, DRAWER_ID)) => {
  if (!drawer) {
    return;
  }
  const isHiddenOffCanvas = !isDesktopViewport() && drawer.classList.contains(DRAWER_CLOSED_CLASS);
  drawer.inert = isHiddenOffCanvas;
  if (isHiddenOffCanvas) {
    drawer.setAttribute("aria-hidden", "true");
  } else {
    drawer.removeAttribute("aria-hidden");
  }
};

document.addEventListener("click", handleMenuDrawerClick);
document.addEventListener("keydown", handleMenuDrawerKeydown);
document.addEventListener("htmx:afterSwap", handleSwapDrawerCleanup);
document.addEventListener("htmx:beforeHistorySave", resetDrawerState);
document.addEventListener("htmx:historyRestore", resetDrawerState);
window.addEventListener("pageshow", resetDrawerState);
if (typeof window.matchMedia === "function") {
  window.matchMedia(DESKTOP_MEDIA_QUERY).addEventListener("change", resetDrawerState);
}
syncDrawerHiddenState();
