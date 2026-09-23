/**
 * Switches between the responsive layout and the forced desktop version mode.
 *
 * The preference lives in a JavaScript-readable cookie that the inline
 * initializer in templates/common/base.html applies before first paint; the
 * server never reads it. Selecting a mode writes or clears the cookie and
 * reloads the page so the initializer runs again for the current URL.
 */
import { closestElement } from "/static/js/common/dom.js";

// Scoped to buttons: the same attribute marks the active mode on `<html>`.
const ACTION_SELECTOR = "button[data-viewport-mode]";
const COOKIE_MAX_AGE_SECONDS = 365 * 24 * 60 * 60;
export const DESKTOP_MODE = "desktop";
export const VIEWPORT_MODE_ATTRIBUTE = "data-viewport-mode";
export const VIEWPORT_MODE_COOKIE = "ocg_viewport_mode";

let clickHandlerBound = false;
let reloadHandler = () => window.location.reload();

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
 * Builds the `document.cookie` assignment string for a viewport mode.
 * @param {string} mode - `desktop` writes the long-lived cookie; any other value expires it.
 * @param {{ secure?: boolean }} [options] - Adds the `Secure` attribute when the page is served over HTTPS.
 * @returns {string} Cookie string ready to assign to `document.cookie`.
 */
export const buildViewportModeCookie = (mode, { secure = false } = {}) => {
  const isDesktop = mode === DESKTOP_MODE;
  const parts = [
    `${VIEWPORT_MODE_COOKIE}=${isDesktop ? DESKTOP_MODE : ""}`,
    "Path=/",
    `Max-Age=${isDesktop ? COOKIE_MAX_AGE_SECONDS : 0}`,
    "SameSite=Lax",
  ];
  if (secure) {
    parts.push("Secure");
  }

  return parts.join("; ");
};

/**
 * Persists the requested viewport mode and reloads the page to apply it.
 * @param {string} mode - `desktop` enables the desktop version; any other value restores the default.
 * @returns {void}
 */
export const setViewportMode = (mode) => {
  document.cookie = buildViewportModeCookie(mode, { secure: window.location.protocol === "https:" });
  reloadHandler();
};

/**
 * Overrides the page reload used after the cookie changes.
 * @param {() => void} handler - Replacement reload callback (used by tests).
 * @returns {void}
 */
export const setViewportModeReloadHandler = (handler) => {
  reloadHandler = handler;
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
