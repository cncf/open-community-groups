import {
  showDeploymentRefreshRetryAlert,
  showDeploymentRefreshStalledAlert,
  showErrorAlert,
  showInfoAlert,
  waitForAlertToClose,
} from "/static/js/common/alerts.js";

export const COMMIT_SHA_HEADER = "X-OCG-Commit-SHA";
// Root element marker set by the base template after it strips the refresh parameter.
export const DEPLOYMENT_REFRESH_ATTRIBUTE = "data-deployment-refresh";
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
export const DEPLOYMENT_REFRESH_STALLED_BLOCKED_MESSAGE =
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
const PENDING_CHANGES_ALERT_SELECTOR = "#pending-changes-alert";
const DEPLOYMENT_REFRESH_ALERT_STORAGE_KEY = "ocg.deploymentRefreshAlert";
const DEPLOYMENT_LAST_AUTO_REFRESH_STORAGE_KEY = "ocg.deploymentLastAutoRefreshAt";
const DEPLOYMENT_REFRESH_RETRY_STALE_COMMIT_SHA_STORAGE_KEY = "ocg.deploymentRefreshRetryStaleCommitSha";
const DEPLOYMENT_REFRESH_RETRY_STARTED_AT_STORAGE_KEY = "ocg.deploymentRefreshRetryStartedAt";
// Match the public HTML cache window so stale pages do not refresh-loop after deploy.
const DEPLOYMENT_AUTO_REFRESH_COOLDOWN_MS = 5 * 60 * 1000;
// After the cooldown blocks an immediate reload, keep retrying until fresh HTML loads.
const DEPLOYMENT_REFRESH_RETRY_INTERVAL_MS = 30 * 1000;
// Stop blocking the page once the shared cache window plus stale grace has passed.
const DEPLOYMENT_REFRESH_RETRY_MAX_DURATION_MS = 7 * 60 * 1000;

let deploymentReloadOfferToken = null;
let dirtyDeploymentNoticeShown = false;
// Pending reload and the promise that settles when it is cancelled, or null when idle.
let pendingReload = null;
let reloadHandler = (url) => window.location.replace(url);
let refreshRetryTimeout = null;
let stalledDeploymentNoticeShown = false;

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
 * Reads the commit SHA embedded in the loaded page.
 * @param {Document} root Document used to find the commit SHA meta tag.
 * @returns {string} Loaded page commit SHA, or an empty string when absent.
 */
const getLoadedCommitSha = (root = document) =>
  root?.querySelector?.(COMMIT_SHA_META_SELECTOR)?.getAttribute("content")?.trim() || "";

/**
 * Returns whether a deployment reload has already been requested.
 * @returns {boolean} Whether the page is already navigating to a fresh copy.
 */
export const isDeploymentReloadRequested = () => pendingReload !== null;

/**
 * Returns whether a deployment refresh alert was pending and clears it.
 * @returns {boolean} Whether the alert should be shown.
 */
export const consumePendingDeploymentRefreshAlert = () => {
  const pending = sessionStorageGetItem(DEPLOYMENT_REFRESH_ALERT_STORAGE_KEY) === "true";
  sessionStorageRemoveItem(DEPLOYMENT_REFRESH_ALERT_STORAGE_KEY);
  return pending;
};

/**
 * Returns whether the response is a stale-client refresh intercept.
 * @param {XMLHttpRequest|Headers|object|null|undefined} headersSource Response headers source.
 * @returns {boolean} Whether the server asked the client to refresh without running the handler.
 */
export const isForcedDeploymentRefresh = (headersSource) =>
  getHeader(headersSource, REFRESH_HEADER) === "true" ||
  getHeader(headersSource, HTMX_REFRESH_HEADER) === "true";

/**
 * Handles deployment refresh signals from response headers and reports the outcome.
 * A forced-refresh intercept that cannot reload is blocked, so callers do not
 * treat the empty 204 as a successful mutation. A reloading outcome means the
 * page is navigating away until the pending reload is released.
 * @param {XMLHttpRequest|Headers|object|null|undefined} headersSource Response headers source.
 * @param {Document} root Document used to read the loaded commit SHA.
 * @returns {"blocked"|"none"|"reloading"} One of the DEPLOYMENT_REFRESH_OUTCOME values.
 */
export const processDeploymentRefresh = (headersSource, root = document) => {
  const forcedRefresh = isForcedDeploymentRefresh(headersSource);
  const dirty = hasVisiblePendingChanges(root);
  const unhandledOutcome = forcedRefresh
    ? DEPLOYMENT_REFRESH_OUTCOME.BLOCKED
    : DEPLOYMENT_REFRESH_OUTCOME.NONE;

  if (pendingReload) {
    if (dirty) {
      deferDeploymentReloadForDirtyForm(
        forcedRefresh ? DIRTY_DEPLOYMENT_BLOCKED_MESSAGE : DIRTY_DEPLOYMENT_NOTICE_MESSAGE,
      );
      return unhandledOutcome;
    }
    return DEPLOYMENT_REFRESH_OUTCOME.RELOADING;
  }

  const responseCommitSha = getHeader(headersSource, COMMIT_SHA_HEADER);
  if (!forcedRefresh && !isCommitShaMismatch(responseCommitSha, getLoadedCommitSha(root))) {
    return DEPLOYMENT_REFRESH_OUTCOME.NONE;
  }

  if (dirty) {
    notifyDirtyDeployment(forcedRefresh ? DIRTY_DEPLOYMENT_BLOCKED_MESSAGE : DIRTY_DEPLOYMENT_NOTICE_MESSAGE);
    return unhandledOutcome;
  }

  // Once this commit exhausted its retry window, only a manual reload is offered
  if (hasDeploymentRefreshRetryExpired(root)) {
    stopDeploymentRefreshRetry({ blocked: forcedRefresh });
    return unhandledOutcome;
  }

  if (wasDeploymentAutoRefreshRecent()) {
    requestDeploymentRefreshRetry(root);
    return DEPLOYMENT_REFRESH_OUTCOME.RELOADING;
  }

  requestDeploymentReload();
  return DEPLOYMENT_REFRESH_OUTCOME.RELOADING;
};

/**
 * Handles deployment refresh signals from response headers.
 * Forced-refresh intercepts on dirty forms return true so HTMX does not honor
 * HX-Refresh and callers do not treat the empty 204 as a successful mutation.
 * @param {XMLHttpRequest|Headers|object|null|undefined} headersSource Response headers source.
 * @param {Document} root Document used to read the loaded commit SHA.
 * @returns {boolean} Whether a refresh signal was handled or a reload is pending.
 */
export const reloadIfDeploymentChanged = (headersSource, root = document) =>
  processDeploymentRefresh(headersSource, root) !== DEPLOYMENT_REFRESH_OUTCOME.NONE;

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
 * Resets deployment reload state for isolated unit tests.
 * Real page reloads recreate module state; tests use this to simulate navigation.
 * @param {{clearRefreshHistory?: boolean, clearRetryState?: boolean}} options Reset options.
 * @returns {void}
 */
export const resetDeploymentReloadState = ({ clearRefreshHistory = true, clearRetryState = true } = {}) => {
  deploymentReloadOfferToken = null;
  dirtyDeploymentNoticeShown = false;
  pendingReload = null;
  reloadHandler = (url) => window.location.replace(url);
  stalledDeploymentNoticeShown = false;
  if (refreshRetryTimeout !== null) {
    window.clearTimeout(refreshRetryTimeout);
    refreshRetryTimeout = null;
  }
  sessionStorageRemoveItem(DEPLOYMENT_REFRESH_ALERT_STORAGE_KEY);
  if (clearRefreshHistory) {
    sessionStorageRemoveItem(DEPLOYMENT_LAST_AUTO_REFRESH_STORAGE_KEY);
  }
  if (clearRetryState) {
    sessionStorageRemoveItem(DEPLOYMENT_REFRESH_RETRY_STALE_COMMIT_SHA_STORAGE_KEY);
    sessionStorageRemoveItem(DEPLOYMENT_REFRESH_RETRY_STARTED_AT_STORAGE_KEY);
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
 * Resumes a pending deployment refresh retry when stale HTML is still loaded.
 * Stops blocking the page once the retry window has elapsed.
 * @param {Document} root Document used to read the loaded commit SHA and the
 * refresh marker left by the base template.
 * @returns {boolean} Whether a refresh retry is pending.
 */
export const initializeDeploymentRefreshRetry = (root = document) => {
  const reloadedForDeployment = Boolean(root.documentElement?.hasAttribute(DEPLOYMENT_REFRESH_ATTRIBUTE));
  root.documentElement?.removeAttribute(DEPLOYMENT_REFRESH_ATTRIBUTE);
  const staleCommitSha = sessionStorageGetItem(DEPLOYMENT_REFRESH_RETRY_STALE_COMMIT_SHA_STORAGE_KEY);
  if (!staleCommitSha) {
    return false;
  }

  if (getLoadedCommitSha(root) !== staleCommitSha) {
    clearDeploymentRefreshRetryState();
    return false;
  }

  // Only explain the stalled refresh when an automatic retry produced this page
  if (hasDeploymentRefreshRetryExpired(root)) {
    sessionStorageRemoveItem(DEPLOYMENT_REFRESH_ALERT_STORAGE_KEY);
    if (reloadedForDeployment) {
      stopDeploymentRefreshRetry();
    }
    return false;
  }

  requestDeploymentRefreshRetry(root);
  return true;
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
 * Returns whether the pending-changes banner is currently visible.
 * @param {Document|Element} root Document or fragment used to find the banner.
 * @returns {boolean} Whether unsaved dashboard changes are visible.
 */
const hasVisiblePendingChanges = (root = document) => {
  const alert = root.querySelector?.(PENDING_CHANGES_ALERT_SELECTOR);
  return Boolean(alert && !alert.classList.contains("hidden"));
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
 * Returns whether response and loaded commit SHAs differ.
 * @param {string|null} responseCommitSha Commit SHA sent by the server.
 * @param {string} loadedCommitSha Commit SHA embedded in the loaded page.
 * @returns {boolean} Whether the two versions differ.
 */
const isCommitShaMismatch = (responseCommitSha, loadedCommitSha) =>
  Boolean(responseCommitSha && loadedCommitSha && responseCommitSha !== loadedCommitSha);

/**
 * Returns whether an automatic deployment refresh happened within the cache window.
 * @returns {boolean} Whether automatic refreshes should be suppressed.
 */
const wasDeploymentAutoRefreshRecent = () => {
  const lastAutoRefreshAt = Number(sessionStorageGetItem(DEPLOYMENT_LAST_AUTO_REFRESH_STORAGE_KEY));
  return (
    Number.isFinite(lastAutoRefreshAt) &&
    lastAutoRefreshAt > 0 &&
    Date.now() - lastAutoRefreshAt < DEPLOYMENT_AUTO_REFRESH_COOLDOWN_MS
  );
};

/**
 * Requests repeated deployment refreshes while stale HTML is still served.
 * Callers stop retries for an expired commit before requesting another one.
 * @param {Document} root Document used to read the stale loaded commit SHA.
 * @returns {void}
 */
const requestDeploymentRefreshRetry = (root = document) => {
  sessionStorageRemoveItem(DEPLOYMENT_REFRESH_ALERT_STORAGE_KEY);
  const loadedCommitSha = getLoadedCommitSha(root);
  const staleCommitSha = sessionStorageGetItem(DEPLOYMENT_REFRESH_RETRY_STALE_COMMIT_SHA_STORAGE_KEY);
  const startedAt = sessionStorageGetItem(DEPLOYMENT_REFRESH_RETRY_STARTED_AT_STORAGE_KEY);
  if (loadedCommitSha && (loadedCommitSha !== staleCommitSha || !startedAt)) {
    sessionStorageSetItem(DEPLOYMENT_REFRESH_RETRY_STALE_COMMIT_SHA_STORAGE_KEY, loadedCommitSha);
    sessionStorageSetItem(DEPLOYMENT_REFRESH_RETRY_STARTED_AT_STORAGE_KEY, Date.now().toString());
  }

  markDeploymentReloadPending();
  showDeploymentRefreshRetryAlert();
  scheduleDeploymentRefreshRetry();
};

/**
 * Stops treating a retry as an in-flight reload so a dirty form can keep its draft.
 * @param {string} message Notice copy for this deferral.
 * @returns {void}
 */
const deferDeploymentReloadForDirtyForm = (message) => {
  releasePendingDeploymentReload();
  notifyDirtyDeployment(message);
  scheduleDeploymentRefreshRetry();
};

/**
 * Returns whether the loaded stale commit has exhausted its retry window.
 * @param {Document} root Document used to read the loaded commit SHA.
 * @returns {boolean} Whether automatic retries should stop.
 */
const hasDeploymentRefreshRetryExpired = (root = document) => {
  const staleCommitSha = sessionStorageGetItem(DEPLOYMENT_REFRESH_RETRY_STALE_COMMIT_SHA_STORAGE_KEY);
  if (!staleCommitSha || staleCommitSha !== getLoadedCommitSha(root)) {
    return false;
  }

  const startedAt = Number(sessionStorageGetItem(DEPLOYMENT_REFRESH_RETRY_STARTED_AT_STORAGE_KEY));
  return (
    Number.isFinite(startedAt) &&
    startedAt > 0 &&
    Date.now() - startedAt >= DEPLOYMENT_REFRESH_RETRY_MAX_DURATION_MS
  );
};

/**
 * Marks a deployment reload as pending so responses wait for the navigation.
 * Keeps an existing pending reload so earlier callers stay held.
 * @returns {void}
 */
const markDeploymentReloadPending = () => {
  if (pendingReload) {
    return;
  }

  let release;
  const released = new Promise((resolve) => {
    release = resolve;
  });
  pendingReload = { release, released };
};

/**
 * Navigates to a cache-busting copy of the current page.
 * @returns {void}
 */
const navigateToDeploymentRefresh = () => {
  reloadHandler(createDeploymentRefreshUrl(window.location.href));
};

/**
 * Offers a manual deployment reload until the user answers the prompt.
 * Another alert, such as the blocked caller's error, may replace the prompt;
 * it comes back once that alert closes so the Reload action is never lost.
 * Only the latest offer is restored, and a reload confirmed after the form
 * became dirty is refused so unsaved edits are not discarded.
 * @param {{icon?: string, text?: string}} alertOptions Stalled prompt options.
 * @returns {Promise<void>} Promise resolved once the offer is answered or superseded.
 */
const offerDeploymentReload = async (alertOptions) => {
  const offerToken = Symbol("deploymentReloadOffer");
  deploymentReloadOfferToken = offerToken;
  const isCurrentOffer = () => deploymentReloadOfferToken === offerToken && !pendingReload;

  let outcome = await showDeploymentRefreshStalledAlert(alertOptions);
  while (outcome === "replaced" && isCurrentOffer()) {
    await waitForAlertToClose();
    if (!isCurrentOffer()) {
      return;
    }
    outcome = await showDeploymentRefreshStalledAlert(alertOptions);
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
 * Schedules the next full page reload attempt during deployment refresh retry.
 * Re-checks dirtiness when the timer fires so a form edited after arming is not discarded.
 * @returns {void}
 */
const scheduleDeploymentRefreshRetry = () => {
  if (refreshRetryTimeout !== null) {
    return;
  }

  refreshRetryTimeout = window.setTimeout(() => {
    refreshRetryTimeout = null;
    if (hasVisiblePendingChanges()) {
      deferDeploymentReloadForDirtyForm(DIRTY_DEPLOYMENT_NOTICE_MESSAGE);
      return;
    }

    if (hasDeploymentRefreshRetryExpired()) {
      stopDeploymentRefreshRetry();
      return;
    }

    markDeploymentReloadPending();
    sessionStorageSetItem(DEPLOYMENT_LAST_AUTO_REFRESH_STORAGE_KEY, Date.now().toString());
    navigateToDeploymentRefresh();
  }, DEPLOYMENT_REFRESH_RETRY_INTERVAL_MS);
};

/**
 * Stops automatic retries and offers a manual reload without blocking the page.
 * The passive notice is shown once per page load; blocked requests always warn
 * so users never believe an intercepted action succeeded.
 * @param {{blocked?: boolean}} options Whether a request was blocked by the server.
 * @returns {void}
 */
const stopDeploymentRefreshRetry = ({ blocked = false } = {}) => {
  releasePendingDeploymentReload();
  if (refreshRetryTimeout !== null) {
    window.clearTimeout(refreshRetryTimeout);
    refreshRetryTimeout = null;
  }
  sessionStorageRemoveItem(DEPLOYMENT_REFRESH_ALERT_STORAGE_KEY);

  if (!blocked && stalledDeploymentNoticeShown) {
    return;
  }

  stalledDeploymentNoticeShown = true;
  offerDeploymentReload(blocked ? { icon: "warning", text: DEPLOYMENT_REFRESH_STALLED_BLOCKED_MESSAGE } : {});
};

/**
 * Clears deployment refresh retry markers after the target commit loads.
 * @returns {void}
 */
const clearDeploymentRefreshRetryState = () => {
  sessionStorageRemoveItem(DEPLOYMENT_REFRESH_ALERT_STORAGE_KEY);
  sessionStorageRemoveItem(DEPLOYMENT_LAST_AUTO_REFRESH_STORAGE_KEY);
  sessionStorageRemoveItem(DEPLOYMENT_REFRESH_RETRY_STALE_COMMIT_SHA_STORAGE_KEY);
  sessionStorageRemoveItem(DEPLOYMENT_REFRESH_RETRY_STARTED_AT_STORAGE_KEY);
};

/**
 * Requests a cache-busting full page reload once.
 * @returns {void}
 */
const requestDeploymentReload = () => {
  if (pendingReload) {
    return;
  }

  markDeploymentReloadPending();
  sessionStorageSetItem(DEPLOYMENT_LAST_AUTO_REFRESH_STORAGE_KEY, Date.now().toString());
  sessionStorageSetItem(DEPLOYMENT_REFRESH_ALERT_STORAGE_KEY, "true");
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

initializeDeploymentRefreshRetry();
