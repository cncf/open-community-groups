import { showDeploymentRefreshRetryAlert } from "/static/js/common/alerts.js";

export const COMMIT_SHA_HEADER = "X-OCG-Commit-SHA";
export const DEPLOYMENT_REFRESH_MESSAGE = "This page was refreshed because a new version is available.";
export const REFRESH_HEADER = "X-OCG-Refresh";

const COMMIT_SHA_META_SELECTOR = 'meta[name="ocg-commit-sha"]';
const DEPLOYMENT_REFRESH_ALERT_STORAGE_KEY = "ocg.deploymentRefreshAlert";
const DEPLOYMENT_LAST_AUTO_REFRESH_STORAGE_KEY = "ocg.deploymentLastAutoRefreshAt";
const DEPLOYMENT_REFRESH_RETRY_STALE_COMMIT_SHA_STORAGE_KEY = "ocg.deploymentRefreshRetryStaleCommitSha";
// Match the public HTML cache window so stale pages do not refresh-loop after deploy.
const DEPLOYMENT_AUTO_REFRESH_COOLDOWN_MS = 5 * 60 * 1000;
// After the cooldown blocks an immediate reload, keep retrying until fresh HTML loads.
const DEPLOYMENT_REFRESH_RETRY_INTERVAL_MS = 30 * 1000;

let reloadRequested = false;
let reloadHandler = () => window.location.reload();
let refreshRetryTimeout = null;

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
export const isDeploymentReloadRequested = () => reloadRequested;

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
 * Handles deployment refresh signals from response headers.
 * @param {XMLHttpRequest|Headers|object|null|undefined} headersSource Response headers source.
 * @param {Document} root Document used to read the loaded commit SHA.
 * @returns {boolean} Whether a refresh signal was handled or a reload is pending.
 */
export const reloadIfDeploymentChanged = (headersSource, root = document) => {
  if (reloadRequested) {
    return true;
  }

  const forcedRefresh = getHeader(headersSource, REFRESH_HEADER) === "true";
  const responseCommitSha = getHeader(headersSource, COMMIT_SHA_HEADER);
  if (!forcedRefresh && !isCommitShaMismatch(responseCommitSha, getLoadedCommitSha(root))) {
    return false;
  }

  if (wasDeploymentAutoRefreshRecent()) {
    requestDeploymentRefreshRetry(root);
    return true;
  }

  requestDeploymentReload();
  return true;
};

/**
 * Resets deployment reload state for isolated unit tests.
 * Real page reloads recreate module state; tests use this to simulate navigation.
 * @param {{clearRefreshHistory?: boolean, clearRetryState?: boolean}} options Reset options.
 * @returns {void}
 */
export const resetDeploymentReloadState = ({ clearRefreshHistory = true, clearRetryState = true } = {}) => {
  reloadRequested = false;
  reloadHandler = () => window.location.reload();
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
  }
};

/**
 * Overrides the page reload handler for isolated unit tests.
 * @param {Function} handler Replacement reload handler.
 * @returns {void}
 */
export const setDeploymentReloadHandler = (handler) => {
  reloadHandler = typeof handler === "function" ? handler : () => window.location.reload();
};

/**
 * Resumes a pending deployment refresh retry when cached HTML is still loaded.
 * @param {Document} root Document used to read the loaded commit SHA.
 * @returns {boolean} Whether a refresh retry is pending.
 */
export const initializeDeploymentRefreshRetry = (root = document) => {
  const staleCommitSha = sessionStorageGetItem(DEPLOYMENT_REFRESH_RETRY_STALE_COMMIT_SHA_STORAGE_KEY);
  if (!staleCommitSha) {
    return false;
  }

  if (getLoadedCommitSha(root) !== staleCommitSha) {
    clearDeploymentRefreshRetryState();
    return false;
  }

  requestDeploymentRefreshRetry();
  return true;
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
 * Requests repeated deployment refreshes while cached HTML is still served.
 * @param {Document} root Document used to read the stale loaded commit SHA.
 * @returns {void}
 */
const requestDeploymentRefreshRetry = (root = document) => {
  reloadRequested = true;
  sessionStorageRemoveItem(DEPLOYMENT_REFRESH_ALERT_STORAGE_KEY);
  const loadedCommitSha = getLoadedCommitSha(root);
  if (loadedCommitSha) {
    sessionStorageSetItem(DEPLOYMENT_REFRESH_RETRY_STALE_COMMIT_SHA_STORAGE_KEY, loadedCommitSha);
  }
  showDeploymentRefreshRetryAlert();
  scheduleDeploymentRefreshRetry();
};

/**
 * Schedules the next full page reload attempt during deployment refresh retry.
 * @returns {void}
 */
const scheduleDeploymentRefreshRetry = () => {
  if (refreshRetryTimeout !== null) {
    return;
  }

  refreshRetryTimeout = window.setTimeout(() => {
    refreshRetryTimeout = null;
    sessionStorageSetItem(DEPLOYMENT_LAST_AUTO_REFRESH_STORAGE_KEY, Date.now().toString());
    reloadHandler();
  }, DEPLOYMENT_REFRESH_RETRY_INTERVAL_MS);
};

/**
 * Clears deployment refresh retry markers after the target commit loads.
 * @returns {void}
 */
const clearDeploymentRefreshRetryState = () => {
  sessionStorageRemoveItem(DEPLOYMENT_REFRESH_ALERT_STORAGE_KEY);
  sessionStorageRemoveItem(DEPLOYMENT_LAST_AUTO_REFRESH_STORAGE_KEY);
  sessionStorageRemoveItem(DEPLOYMENT_REFRESH_RETRY_STALE_COMMIT_SHA_STORAGE_KEY);
};

/**
 * Requests a full page reload once.
 * @returns {void}
 */
const requestDeploymentReload = () => {
  if (reloadRequested) {
    return;
  }

  reloadRequested = true;
  sessionStorageSetItem(DEPLOYMENT_LAST_AUTO_REFRESH_STORAGE_KEY, Date.now().toString());
  sessionStorageSetItem(DEPLOYMENT_REFRESH_ALERT_STORAGE_KEY, "true");
  reloadHandler();
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
