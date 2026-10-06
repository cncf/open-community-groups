import {
  showDeploymentReloadPrompt,
  showErrorAlert,
  showInfoAlert,
  waitForAlertToClose,
} from "/static/js/common/alerts.js";

export const COMMIT_SHA_HEADER = "X-OCG-Commit-SHA";
export const DEPLOYMENT_REFRESH_MESSAGE = "This page was refreshed because a new version is available.";
// How a response's deployment refresh signal was handled.
export const DEPLOYMENT_REFRESH_OUTCOME = Object.freeze({
  BLOCKED: "blocked",
  NONE: "none",
  RELOADING: "reloading",
});
// Unique query parameter that makes deployment reloads bypass shared caches.
// The base template strips it before HTMX records the history path.
export const DEPLOYMENT_REFRESH_PARAM = "ocg_refresh";
export const DEPLOYMENT_RELOAD_BLOCKED_MESSAGE =
  "A new version is live. This request did not complete. Reload to pick up the update.";
export const DIRTY_DEPLOYMENT_BLOCKED_MESSAGE =
  "A new version is live. This request did not complete. Copy any unsaved work, then reload to pick up the update.";
export const DIRTY_DEPLOYMENT_NOTICE_MESSAGE =
  "A new version is live. Save or leave this page, then reload to pick up the update.";
export const DIRTY_DEPLOYMENT_RELOAD_BLOCKED_MESSAGE =
  "A new version is live. Copy any unsaved work, then reload to pick up the update.";
export const HTMX_REFRESH_HEADER = "HX-Refresh";
export const REFRESH_HEADER = "X-OCG-Refresh";

const COMMIT_SHA_META_SELECTOR = 'meta[name="ocg-commit-sha"]';
// Commit SHA the last automatic deployment reload navigated away from.
const DEPLOYMENT_RELOADED_FROM_COMMIT_SHA_STORAGE_KEY = "ocg.deploymentReloadedFromCommitSha";
const PENDING_CHANGES_ALERT_SELECTOR = "#pending-changes-alert";

let deploymentReloadOfferToken = null;
let dirtyDeploymentNoticeShown = false;
// Pending reload and the promise that settles when it is cancelled, or null when idle.
let pendingReload = null;
let reloadHandler = (url) => window.location.replace(url);
let reloadPromptShown = false;

/**
 * Handles deployment refresh signals from response headers and reports the outcome.
 * A stale page reloads once through a cache-busting URL. When that reload still
 * returns the same version, the page offers a manual reload instead of looping.
 * Pages with unsaved changes are never reloaded automatically. A forced-refresh
 * intercept that cannot reload is blocked, so callers do not treat the empty 204
 * as a successful mutation. Background requests, which started without a user
 * action, never claim that a user request did not complete.
 * @param {XMLHttpRequest|Headers|object|null|undefined} headersSource Response headers source.
 * @param {Document} root Document used to read the loaded commit SHA.
 * @param {{background?: boolean}} options Whether the request started without a user action.
 * @returns {"blocked"|"none"|"reloading"} One of the DEPLOYMENT_REFRESH_OUTCOME values.
 */
export const processDeploymentRefresh = (headersSource, root = document, { background = false } = {}) => {
  if (pendingReload) {
    return DEPLOYMENT_REFRESH_OUTCOME.RELOADING;
  }

  const forcedRefresh = isForcedDeploymentRefresh(headersSource);
  const responseCommitSha = getHeader(headersSource, COMMIT_SHA_HEADER);
  if (!forcedRefresh && !isCommitShaMismatch(responseCommitSha, getLoadedCommitSha(root))) {
    return DEPLOYMENT_REFRESH_OUTCOME.NONE;
  }

  const unhandledOutcome = forcedRefresh
    ? DEPLOYMENT_REFRESH_OUTCOME.BLOCKED
    : DEPLOYMENT_REFRESH_OUTCOME.NONE;

  // Keep unsaved edits and explain how to pick up the new version
  if (hasVisiblePendingChanges(root)) {
    notifyDirtyDeployment(forcedRefresh ? DIRTY_DEPLOYMENT_BLOCKED_MESSAGE : DIRTY_DEPLOYMENT_NOTICE_MESSAGE);
    return unhandledOutcome;
  }

  // An automatic reload already returned this version, so let the user retry
  if (wasReloadedFromLoadedCommit(root)) {
    const blocked = forcedRefresh && !background;
    if (blocked || !reloadPromptShown) {
      reloadPromptShown = true;
      offerDeploymentReload(blocked ? { icon: "warning", text: DEPLOYMENT_RELOAD_BLOCKED_MESSAGE } : {});
    }
    return unhandledOutcome;
  }

  requestDeploymentReload(root);
  return DEPLOYMENT_REFRESH_OUTCOME.RELOADING;
};

/**
 * Adds the loaded page commit SHA header when a baseline is available.
 * @param {Headers|object} headers Mutable request headers.
 * @param {Document} root Document used to read the loaded commit SHA.
 * @returns {void}
 */
export const addLoadedCommitShaHeader = (headers, root = document) => {
  const commitSha = getLoadedCommitSha(root);
  if (!commitSha || !headers) {
    return;
  }

  if (typeof headers.set === "function") {
    headers.set(COMMIT_SHA_HEADER, commitSha);
  } else {
    headers[COMMIT_SHA_HEADER] = commitSha;
  }
};

/**
 * Returns whether an automatic deployment reload loaded a new version.
 * Clears the reload marker once the version changed. The marker stays while the
 * reload returned the same version, so the next refresh signal is not retried
 * automatically.
 * @param {Document} root Document used to read the loaded commit SHA.
 * @returns {boolean} Whether the post-reload notice should be shown.
 */
export const consumePendingDeploymentRefreshAlert = (root = document) => {
  const reloadedFromCommitSha = sessionStorageGetItem(DEPLOYMENT_RELOADED_FROM_COMMIT_SHA_STORAGE_KEY);
  if (!reloadedFromCommitSha || wasReloadedFromLoadedCommit(root)) {
    return false;
  }

  sessionStorageRemoveItem(DEPLOYMENT_RELOADED_FROM_COMMIT_SHA_STORAGE_KEY);
  return true;
};

/**
 * Adds a unique cache-busting parameter to a deployment reload URL.
 * Existing query parameters keep their original encoding.
 * @param {string} href Current page URL.
 * @param {string} token Unique reload token.
 * @returns {string} URL that misses shared caches for the current page.
 */
export const createDeploymentRefreshUrl = (href, token = Date.now().toString(36)) => {
  const url = new URL(href);
  const search = removeDeploymentRefreshParamFromSearch(url.search);
  const refreshParam = `${DEPLOYMENT_REFRESH_PARAM}=${encodeURIComponent(token)}`;
  url.search = search ? `${search}&${refreshParam}` : refreshParam;
  return url.toString();
};

/**
 * Clears the pending reload guard when the browser restores this page from
 * the back/forward cache, so restored pages keep handling responses.
 * @param {Window} target Window receiving page lifecycle events.
 * @returns {void}
 */
export const initializeDeploymentReloadState = (target = window) => {
  target.addEventListener("pageshow", (event) => {
    if (event.persisted) {
      releasePendingDeploymentReload();
    }
  });
};

/**
 * Returns whether a deployment reload has already been requested.
 * @returns {boolean} Whether the page is already navigating to a fresh copy.
 */
export const isDeploymentReloadRequested = () => pendingReload !== null;

/**
 * Returns whether the server asked the client to refresh without running the handler.
 * @param {XMLHttpRequest|Headers|object|null|undefined} headersSource Response headers source.
 * @returns {boolean} Whether the response is a forced deployment refresh.
 */
export const isForcedDeploymentRefresh = (headersSource) =>
  getHeader(headersSource, REFRESH_HEADER) === "true" ||
  getHeader(headersSource, HTMX_REFRESH_HEADER) === "true";

/**
 * Handles deployment refresh signals from response headers.
 * @param {XMLHttpRequest|Headers|object|null|undefined} headersSource Response headers source.
 * @param {Document} root Document used to read the loaded commit SHA.
 * @param {{background?: boolean}} options Whether the request started without a user action.
 * @returns {boolean} Whether a refresh signal was handled or a reload is pending.
 */
export const reloadIfDeploymentChanged = (headersSource, root = document, options = {}) =>
  processDeploymentRefresh(headersSource, root, options) !== DEPLOYMENT_REFRESH_OUTCOME.NONE;

/**
 * Resets deployment reload state for isolated unit tests.
 * Real page reloads recreate module state; tests use this to simulate navigation.
 * @param {{clearReloadMarker?: boolean}} options Whether to forget the last automatic reload.
 * @returns {void}
 */
export const resetDeploymentReloadState = ({ clearReloadMarker = true } = {}) => {
  deploymentReloadOfferToken = null;
  dirtyDeploymentNoticeShown = false;
  pendingReload = null;
  reloadHandler = (url) => window.location.replace(url);
  reloadPromptShown = false;
  if (clearReloadMarker) {
    sessionStorageRemoveItem(DEPLOYMENT_RELOADED_FROM_COMMIT_SHA_STORAGE_KEY);
  }
};

/**
 * Overrides the page reload handler for isolated unit tests.
 * The handler receives the cache-busting URL to navigate to.
 * @param {Function} handler Replacement reload handler.
 * @returns {void}
 */
export const setDeploymentReloadHandler = (handler) => {
  reloadHandler = typeof handler === "function" ? handler : (url) => window.location.replace(url);
};

/**
 * Waits while a requested deployment reload replaces the page.
 * Settles only when the reload is cancelled and the page stays loaded, so
 * callers never render intercepted results while the page navigates away.
 * Settles immediately when no reload is pending.
 * @returns {Promise<void>} Promise resolved when the pending reload is released.
 */
export const waitForDeploymentReloadRelease = () => pendingReload?.released ?? Promise.resolve();

/**
 * Reads a response header from common browser response/header objects.
 * @param {XMLHttpRequest|Headers|object|null|undefined} source Response headers source.
 * @param {string} name Header name.
 * @returns {string|null} Header value, or null when absent.
 */
const getHeader = (source, name) => {
  if (!source) {
    return null;
  }

  if (typeof source.getResponseHeader === "function") {
    return source.getResponseHeader(name);
  }
  if (typeof source.get === "function") {
    return source.get(name);
  }

  return source[name] ?? source[name.toLowerCase()] ?? null;
};

/**
 * Reads the commit SHA embedded in the loaded page.
 * @param {Document} root Document used to find the commit SHA meta tag.
 * @returns {string} Loaded page commit SHA, or an empty string when absent.
 */
const getLoadedCommitSha = (root = document) =>
  root?.querySelector?.(COMMIT_SHA_META_SELECTOR)?.getAttribute("content")?.trim() || "";

/**
 * Returns whether the pending-changes banner is currently visible.
 * @param {Document|Element} root Document or fragment used to find the banner.
 * @returns {boolean} Whether unsaved dashboard changes are visible.
 */
const hasVisiblePendingChanges = (root = document) => {
  const alert = root.querySelector?.(PENDING_CHANGES_ALERT_SELECTOR);
  return Boolean(alert && !alert.classList.contains("hidden"));
};

/**
 * Returns whether response and loaded commit SHAs differ.
 * @param {string|null} responseCommitSha Commit SHA sent by the server.
 * @param {string} loadedCommitSha Commit SHA embedded in the loaded page.
 * @returns {boolean} Whether the two versions differ.
 */
const isCommitShaMismatch = (responseCommitSha, loadedCommitSha) =>
  Boolean(responseCommitSha && loadedCommitSha && responseCommitSha !== loadedCommitSha);

/**
 * Marks a deployment reload as pending so responses wait for the navigation.
 * @returns {void}
 */
const markDeploymentReloadPending = () => {
  let release;
  const released = new Promise((resolve) => {
    release = resolve;
  });
  pendingReload = { release, released };
};

/**
 * Navigates to a cache-busting copy of the current page.
 * Unlike location.reload(), this navigates to a new URL, so the browser does not
 * restore scroll position or form field values.
 * @returns {void}
 */
const navigateToDeploymentRefresh = () => {
  reloadHandler(createDeploymentRefreshUrl(window.location.href));
};

/**
 * Notifies that a new version is live without reloading a dirty form.
 * Blocked-mutation warnings always surface so users never believe a dropped save
 * succeeded; the passive stale-version notice is deduped to a one-shot info alert.
 * @param {string} message Notice copy for this intercept.
 * @returns {void}
 */
const notifyDirtyDeployment = (message) => {
  if (message === DIRTY_DEPLOYMENT_BLOCKED_MESSAGE) {
    showErrorAlert(message);
    return;
  }

  if (dirtyDeploymentNoticeShown) {
    return;
  }

  dirtyDeploymentNoticeShown = true;
  showInfoAlert(message);
};

/**
 * Offers a manual deployment reload until the user answers the prompt.
 * Another alert, such as the blocked caller's error, may replace the prompt;
 * it comes back once that alert closes so the Reload action is never lost.
 * Only the latest offer is restored, and a reload confirmed after the form
 * became dirty is refused so unsaved edits are not discarded.
 * @param {{icon?: string, text?: string}} alertOptions Reload prompt options.
 * @returns {Promise<void>} Promise resolved once the offer is answered or superseded.
 */
const offerDeploymentReload = async (alertOptions) => {
  const offerToken = Symbol("deploymentReloadOffer");
  deploymentReloadOfferToken = offerToken;
  const isCurrentOffer = () => deploymentReloadOfferToken === offerToken && !pendingReload;

  let outcome = await showDeploymentReloadPrompt(alertOptions);
  while (outcome === "replaced" && isCurrentOffer()) {
    await waitForAlertToClose();
    if (!isCurrentOffer()) {
      return;
    }
    outcome = await showDeploymentReloadPrompt(alertOptions);
  }

  if (outcome !== "reload" || !isCurrentOffer()) {
    return;
  }
  if (hasVisiblePendingChanges()) {
    showErrorAlert(DIRTY_DEPLOYMENT_RELOAD_BLOCKED_MESSAGE);
    return;
  }

  markDeploymentReloadPending();
  navigateToDeploymentRefresh();
};

/**
 * Cancels the pending deployment reload and settles callers waiting on it.
 * @returns {void}
 */
const releasePendingDeploymentReload = () => {
  const reload = pendingReload;
  pendingReload = null;
  reload?.release();
};

/**
 * Removes the deployment cache-busting parameter from a URL search string.
 * @param {string} search URL search string, with or without the leading question mark.
 * @returns {string} Remaining search string without the leading question mark.
 */
const removeDeploymentRefreshParamFromSearch = (search) =>
  search
    .replace(/^\?/, "")
    .split("&")
    .filter((part) => part && part.split("=")[0] !== DEPLOYMENT_REFRESH_PARAM)
    .join("&");

/**
 * Reloads the page once, remembering the version it navigated away from.
 * @param {Document} root Document used to read the loaded commit SHA.
 * @returns {void}
 */
const requestDeploymentReload = (root = document) => {
  markDeploymentReloadPending();
  sessionStorageSetItem(DEPLOYMENT_RELOADED_FROM_COMMIT_SHA_STORAGE_KEY, getLoadedCommitSha(root));
  navigateToDeploymentRefresh();
};

/**
 * Reads a session storage item when browser storage is available.
 * @param {string} key Storage key.
 * @returns {string|null} Stored value, or null when unavailable.
 */
const sessionStorageGetItem = (key) => {
  try {
    return window.sessionStorage?.getItem(key) ?? null;
  } catch {
    return null;
  }
};

/**
 * Removes a session storage item when browser storage is available.
 * @param {string} key Storage key.
 * @returns {void}
 */
const sessionStorageRemoveItem = (key) => {
  try {
    window.sessionStorage?.removeItem(key);
  } catch {
    // Ignore unavailable browser storage.
  }
};

/**
 * Stores a session storage item when browser storage is available.
 * @param {string} key Storage key.
 * @param {string} value Storage value.
 * @returns {void}
 */
const sessionStorageSetItem = (key, value) => {
  try {
    window.sessionStorage?.setItem(key, value);
  } catch {
    // Ignore unavailable browser storage.
  }
};

/**
 * Returns whether the last automatic deployment reload returned the loaded version.
 * @param {Document} root Document used to read the loaded commit SHA.
 * @returns {boolean} Whether another automatic reload would load the same version.
 */
const wasReloadedFromLoadedCommit = (root = document) => {
  const loadedCommitSha = getLoadedCommitSha(root);
  return (
    Boolean(loadedCommitSha) &&
    sessionStorageGetItem(DEPLOYMENT_RELOADED_FROM_COMMIT_SHA_STORAGE_KEY) === loadedCommitSha
  );
};
