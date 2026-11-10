/**
 * Switches between the responsive layout and the forced desktop version mode.
 *
 * The preference lives in `localStorage` (`ocg_viewport_mode`), and the inline
 * `common/scripts/preferences_init.js` applies it before first paint; the
 * server never sees it. Selecting a mode writes or clears the key and loads the
 * current URL again so the inline script runs. A fresh navigation is used
 * instead of a reload, because a reload restores the previous zoom and the
 * desktop zoom-out can leave the phone layout scrolling sideways.
 */
import { closestElement } from "/static/js/common/dom.js";

// Scoped to buttons: the same attribute marks the active mode on `<html>`.
const ACTION_SELECTOR = "button[data-viewport-mode]";
export const DESKTOP_MODE = "desktop";
export const VIEWPORT_MODE_ATTRIBUTE = "data-viewport-mode";
// Also the name of the legacy cookie that earlier releases stored the mode in.
export const VIEWPORT_MODE_STORAGE_KEY = "ocg_viewport_mode";

let clickHandlerBound = false;
let reloadHandler = () => window.location.replace(getViewportModeReloadUrl(window.location.href));

/**
 * Binds the delegated click handler for `button[data-viewport-mode]` controls.
 *
 * Delegated on the document so the inline menu, the lazily loaded user menu
 * partial and HTMX body swaps all share one listener.
 * @returns {void}
 */
export const initViewportModeToggle = () => {
  if (clickHandlerBound) {
    return;
  }

  document.addEventListener("click", handleClick);
  clickHandlerBound = true;
};

/**
 * Returns the URL that reapplies the viewport mode. The hash is dropped because
 * replacing a URL with only a hash scrolls to it without loading the page.
 * @param {string} href - Current page URL.
 * @returns {string} URL to navigate to.
 */
export const getViewportModeReloadUrl = (href) => {
  const url = new URL(href);
  url.hash = "";

  return url.href;
};

/**
 * Persists the requested viewport mode and reloads the page to apply it.
 *
 * Nothing reloads when storage rejects the write, because the inline script
 * would apply the previous mode again.
 * @param {string} mode - `desktop` enables the desktop version; any other value restores the default.
 * @returns {void}
 */
export const setViewportMode = (mode) => {
  let persisted = true;
  try {
    if (mode === DESKTOP_MODE) {
      window.localStorage.setItem(VIEWPORT_MODE_STORAGE_KEY, DESKTOP_MODE);
    } else {
      window.localStorage.removeItem(VIEWPORT_MODE_STORAGE_KEY);
    }
  } catch {
    persisted = false;
  }

  expireLegacyCookie();
  if (persisted) {
    reloadHandler();
  }
};

/**
 * Overrides the page reload used after the stored mode changes.
 * @param {() => void} handler - Replacement reload callback (used by tests).
 * @returns {void}
 */
export const setViewportModeReloadHandler = (handler) => {
  reloadHandler = handler;
};

/**
 * Expires the legacy viewport mode cookie when one is present.
 *
 * A tab loaded before the move to `localStorage` can still write the cookie.
 * This is the module's only cookie operation, and it never sets one. The
 * expiry can go one year after release, with the shim in preferences_init.js.
 * @returns {void}
 */
const expireLegacyCookie = () => {
  const hasLegacyCookie = document.cookie
    .split(";")
    .map((cookie) => cookie.trim())
    .some((cookie) => cookie.split("=")[0] === VIEWPORT_MODE_STORAGE_KEY);
  if (!hasLegacyCookie) {
    return;
  }

  const expiry = `${VIEWPORT_MODE_STORAGE_KEY}=; Path=/; Max-Age=0; SameSite=Lax`;
  document.cookie = window.location.protocol === "https:" ? `${expiry}; Secure` : expiry;
};

/**
 * Applies the mode of the clicked `button[data-viewport-mode]` control.
 * @param {MouseEvent} event - Document click event.
 * @returns {void}
 */
const handleClick = (event) => {
  const control = closestElement(event.target, ACTION_SELECTOR);
  if (!control) {
    return;
  }

  setViewportMode(control.dataset.viewportMode);
};

initViewportModeToggle();
