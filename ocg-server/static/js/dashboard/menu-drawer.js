import { closestElement, getElementById, setElementHidden } from "/static/js/common/dom.js";
import { isEscapeEvent } from "/static/js/common/keyboard.js";
import {
  lockBodyScroll,
  trapModalFocus,
  unlockBodyScroll,
} from "/static/js/common/modals/modal-lifecycle.js";

const BACKDROP_ID = "dashboard-menu-backdrop";
const CLOSE_BUTTON_ID = "close-dashboard-menu";
const DESKTOP_MEDIA_QUERY = "(min-width: 768px)";
const DRAWER_CLOSED_CLASS = "-translate-x-full";
const DRAWER_ID = "dashboard-menu-drawer";
const OPEN_BUTTON_ID = "open-dashboard-menu";

// Tracks whether the drawer currently holds the shared body scroll lock.
let drawerHoldsScrollLock = false;

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
  syncDrawerHiddenState(drawer);
  const openButton = getElementById(document, OPEN_BUTTON_ID);
  if (openButton) {
    openButton.setAttribute("aria-expanded", "false");
    openButton.focus();
  }
};

/**
 * Opens the dashboard menu drawer and moves focus into it (mobile only).
 */
export const openDashboardMenuDrawer = () => {
  const drawer = getElementById(document, DRAWER_ID);
  if (!drawer || !drawer.classList.contains(DRAWER_CLOSED_CLASS)) {
    return;
  }
  drawer.classList.remove(DRAWER_CLOSED_CLASS);
  setElementHidden(getElementById(document, BACKDROP_ID), false);
  acquireDrawerScrollLock();
  syncDrawerHiddenState(drawer);
  const openButton = getElementById(document, OPEN_BUTTON_ID);
  if (openButton) {
    openButton.setAttribute("aria-expanded", "true");
  }
  drawer.focus();
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
  if (closestElement(event.target, `#${OPEN_BUTTON_ID}`)) {
    event.preventDefault();
    openDashboardMenuDrawer();
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
 * Resets the drawer to its closed state without moving focus. Used when history
 * navigation, page restoration, or viewport changes invalidate the open state.
 */
const resetDrawerState = () => {
  releaseDrawerScrollLock();
  const drawer = getElementById(document, DRAWER_ID);
  if (drawer) {
    drawer.classList.add(DRAWER_CLOSED_CLASS);
  }
  setElementHidden(getElementById(document, BACKDROP_ID), true);
  const openButton = getElementById(document, OPEN_BUTTON_ID);
  if (openButton) {
    openButton.setAttribute("aria-expanded", "false");
  }
  syncDrawerHiddenState(drawer);
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
