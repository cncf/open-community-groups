import { closeActionsMenus } from "/static/js/common/actions-menu.js";
import { initializeMatchingRoots } from "/static/js/common/dom.js";
import { resetRestoredModalState } from "/static/js/common/modals/modal-lifecycle.js";

const NAVIGATION_TARGET_ID = "dashboard-layout";
const REQUEST_CLASS = "htmx-request";

/**
 * Returns whether an HTMX swap replaces the page or dashboard view.
 * @param {Event} event HTMX before-swap event.
 * @returns {boolean} Whether the swap is a navigation transition.
 */
export const isNavigationSwap = (event) => {
  const swapTarget = event?.detail?.target || event?.target;
  return (
    swapTarget === document.body || (swapTarget instanceof Element && swapTarget.id === NAVIGATION_TARGET_ID)
  );
};

/** Closes transient dialogs and menus before the current view is replaced. */
export const dismissNavigationOverlays = () => {
  globalThis.Swal?.close?.();
  closeActionsMenus();
  resetRestoredModalState(document);
};

/**
 * Clears request classes that can be retained in an HTMX history snapshot.
 * @param {Document|Element} root Restored document or fragment.
 */
export const clearRestoredLoadingState = (root = document) => {
  initializeMatchingRoots(root, `.${REQUEST_CLASS}`, (element) => {
    element.classList.remove(REQUEST_CLASS);
  });
};

/** Restores transient UI after browser or HTMX history navigation. */
export const restoreNavigationState = () => {
  dismissNavigationOverlays();
  clearRestoredLoadingState(document);
};

/** Registers shared cleanup for dashboard and full-page navigation. */
export const initializeNavigationState = () => {
  document.addEventListener("htmx:beforeSwap", (event) => {
    if (isNavigationSwap(event)) {
      dismissNavigationOverlays();
    }
  });
  document.addEventListener("htmx:historyRestore", restoreNavigationState);
  window.addEventListener("pageshow", (event) => {
    if (event.persisted) {
      restoreNavigationState();
    }
  });
};
