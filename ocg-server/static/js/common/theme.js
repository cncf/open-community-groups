/**
 * Applies the light, dark or system color theme and keeps it live.
 *
 * The color theme preference lives only in `localStorage` (`ocg_theme`, where
 * System removes the key); the server never sees it. The inline
 * `common/scripts/preferences_init.js` applies it to `<html>` before first
 * paint, and this module takes over after load: it repairs anything that
 * changed since then, switches live from the account menu, follows other tabs
 * and the OS while System is selected, re-reads storage on bfcache restores and
 * keeps the menu's theme controls checked. "Color theme" is used throughout to
 * avoid confusion with the site's brand palette (`site_settings.theme`).
 *
 * `ocg:themechange` fires on `document` only when the resolved color theme
 * changes. Rapid clicks, cross-tab storage events and OS scheme changes can fire
 * several changes in quick succession, so heavy consumers (ECharts and
 * MapLibre) coalesce the event in `requestAnimationFrame`.
 */
import {
  closestElement,
  initializeMatchingRoots,
  initializeOnReadyAndHtmxLoad,
} from "/static/js/common/dom.js";

const CHOICE_SELECTOR = "[data-ocg-theme-choice]";
const DARK_THEME = "dark";
const LIGHT_THEME = "light";
const SYSTEM_PREFERENCE = "system";
export const THEME_ATTRIBUTE = "data-theme";
export const THEME_CHANGE_EVENT = "ocg:themechange";
export const THEME_CHOICE_ATTRIBUTE = "data-ocg-theme-choice";
export const THEME_MEDIA_QUERY = "(prefers-color-scheme: dark)";
export const THEME_PREFERENCES = [LIGHT_THEME, DARK_THEME, SYSTEM_PREFERENCE];
export const THEME_STORAGE_KEY = "ocg_theme";
export const THEME_SWITCHING_ATTRIBUTE = "data-theme-switching";

let listenersBound = false;
// Choice kept for this document when the storage write failed. `<html>` is never swapped by
// boosted navigations, so it survives them.
let sessionPreference = null;
// Latest switching mark, so an earlier change never clears the mark of a newer one.
let switchingToken = 0;

/**
 * Applies the current color theme and binds the live-switch listeners once.
 *
 * Every call re-reads storage and the media query, so it also repairs a failed
 * or outdated pre-paint result. It dispatches `ocg:themechange` only when the
 * result differs from what `<html>` already carries.
 * @returns {void}
 */
export const initTheme = () => {
  applyTheme();

  if (listenersBound) {
    return;
  }

  document.addEventListener("click", handleClick);
  window.addEventListener("pageshow", handlePageShow);
  window.addEventListener("storage", handleStorage);
  window.matchMedia(THEME_MEDIA_QUERY).addEventListener("change", handleMediaChange);
  initializeOnReadyAndHtmxLoad(syncThemeControls);
  listenersBound = true;
};

/**
 * Resolves the color theme the page shows now.
 * @returns {"light"|"dark"} Resolved color theme.
 */
export const getResolvedTheme = () => resolveTheme(getThemePreference(), prefersDarkScheme());

/**
 * Returns the selected color theme preference.
 * @returns {"light"|"dark"|"system"} The in-memory choice after a failed write, otherwise the stored
 *   valid value, otherwise `system`.
 */
export const getThemePreference = () => sessionPreference ?? normalizePreference(readStoredPreference());

/**
 * Resolves a color theme preference to the theme to apply.
 * @param {string|null|undefined} preference - `light` or `dark` win; any other value means System.
 * @param {boolean} prefersDark - Whether the OS prefers a dark color scheme.
 * @returns {"light"|"dark"} Resolved color theme.
 */
export const resolveTheme = (preference, prefersDark) => {
  if (preference === LIGHT_THEME || preference === DARK_THEME) {
    return preference;
  }

  return prefersDark ? DARK_THEME : LIGHT_THEME;
};

/**
 * Stores a color theme preference and applies it live.
 * @param {string} preference - `light` or `dark` are stored; `system` and any other value remove the key.
 * @returns {boolean} Whether the choice persisted. A failed write still applies it to this document.
 */
export const setThemePreference = (preference) => {
  const normalizedPreference = normalizePreference(preference);
  let persisted = true;

  try {
    if (normalizedPreference === SYSTEM_PREFERENCE) {
      window.localStorage.removeItem(THEME_STORAGE_KEY);
    } else {
      window.localStorage.setItem(THEME_STORAGE_KEY, normalizedPreference);
    }
    sessionPreference = null;
  } catch {
    sessionPreference = normalizedPreference;
    persisted = false;
  }

  applyTheme();
  return persisted;
};

/**
 * Checks the theme control matching the current preference and unchecks the others.
 *
 * Sets the `aria-checked` attribute rather than a property, so htmx history
 * snapshots of the body markup keep the state.
 * @param {Document|Element} [root=document] - Root to scan for `[data-ocg-theme-choice]` controls.
 * @returns {void}
 */
export const syncThemeControls = (root = document) => {
  const preference = getThemePreference();

  initializeMatchingRoots(root, CHOICE_SELECTOR, (control) => {
    const checked = control.getAttribute(THEME_CHOICE_ATTRIBUTE) === preference;
    control.setAttribute("aria-checked", String(checked));
  });
};

/**
 * Applies the current color theme to `<html>` and the controls, announcing a resolved change.
 * @returns {void}
 */
const applyTheme = () => {
  const root = document.documentElement;
  const preference = getThemePreference();
  const previousTheme = root.getAttribute(THEME_ATTRIBUTE);
  const theme = resolveTheme(preference, prefersDarkScheme());

  if (previousTheme !== theme) {
    markThemeSwitching();
  }
  root.setAttribute(THEME_ATTRIBUTE, theme);
  root.style.colorScheme = theme;
  syncThemeControls(document);

  if (previousTheme !== theme) {
    document.dispatchEvent(
      new CustomEvent(THEME_CHANGE_EVENT, { detail: { preference, previousTheme, theme } }),
    );
  }
};

/**
 * Applies the clicked theme control's choice. The account menu closes itself (`common/header.js`).
 * @param {MouseEvent} event - Document click event.
 * @returns {void}
 */
const handleClick = (event) => {
  const control = closestElement(event.target, CHOICE_SELECTOR);
  if (!control) {
    return;
  }

  setThemePreference(control.getAttribute(THEME_CHOICE_ATTRIBUTE));
};

/**
 * Follows an OS color scheme change while System is selected.
 * @returns {void}
 */
const handleMediaChange = () => {
  if (getThemePreference() === SYSTEM_PREFERENCE) {
    applyTheme();
  }
};

/**
 * Re-reads storage and the media query when the page returns from the bfcache.
 * @param {PageTransitionEvent} event - Window pageshow event.
 * @returns {void}
 */
const handlePageShow = (event) => {
  if (event.persisted) {
    applyTheme();
  }
};

/**
 * Applies another tab's color theme write, or re-reads storage after it is cleared.
 * @param {StorageEvent} event - Window storage event.
 * @returns {void}
 */
const handleStorage = (event) => {
  if (event.key !== null && event.key !== THEME_STORAGE_KEY) {
    return;
  }

  // The other tab's write is newer than a choice this document could not store.
  sessionPreference = null;
  applyTheme();
};

/**
 * Disables transitions for the two animation frames of a live color theme switch.
 * @returns {void}
 */
const markThemeSwitching = () => {
  const root = document.documentElement;
  switchingToken += 1;
  const token = switchingToken;

  root.setAttribute(THEME_SWITCHING_ATTRIBUTE, "");
  requestAnimationFrame(() => {
    requestAnimationFrame(() => {
      if (token === switchingToken) {
        root.removeAttribute(THEME_SWITCHING_ATTRIBUTE);
      }
    });
  });
};

/**
 * Maps any value other than `light` or `dark` to `system`.
 * @param {string|null|undefined} preference - Raw preference.
 * @returns {"light"|"dark"|"system"} Valid preference.
 */
const normalizePreference = (preference) =>
  preference === LIGHT_THEME || preference === DARK_THEME ? preference : SYSTEM_PREFERENCE;

/**
 * Checks whether the OS prefers a dark color scheme.
 * @returns {boolean} True when the dark scheme query matches.
 */
const prefersDarkScheme = () => window.matchMedia(THEME_MEDIA_QUERY).matches;

/**
 * Reads the stored color theme preference.
 * @returns {string|null} Stored value, or null when missing or storage is blocked.
 */
const readStoredPreference = () => {
  try {
    return window.localStorage.getItem(THEME_STORAGE_KEY);
  } catch {
    return null;
  }
};

initTheme();
