export const COMMIT_SHA_HEADER = "X-OCG-Commit-SHA";
export const DEPLOYMENT_REFRESH_MESSAGE = "This page was refreshed because a new version is available.";
export const REFRESH_HEADER = "X-OCG-Refresh";

const COMMIT_SHA_META_SELECTOR = 'meta[name="ocg-commit-sha"]';
const DEPLOYMENT_REFRESH_ALERT_STORAGE_KEY = "ocg.deploymentRefreshAlert";

let reloadRequested = false;
let reloadHandler = () => window.location.reload();

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
export const getLoadedCommitSha = (root = document) =>
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
 * Reloads the page once when response headers indicate a deployment mismatch.
 * @param {XMLHttpRequest|Headers|object|null|undefined} headersSource Response headers source.
 * @param {Document} root Document used to read the loaded commit SHA.
 * @returns {boolean} Whether a reload is needed or already in progress.
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

  requestDeploymentReload();
  return true;
};

/**
 * Resets deployment reload state for isolated unit tests.
 * @returns {void}
 */
export const resetDeploymentReloadState = () => {
  reloadRequested = false;
  reloadHandler = () => window.location.reload();
  sessionStorageRemoveItem(DEPLOYMENT_REFRESH_ALERT_STORAGE_KEY);
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
 * Requests a full page reload once.
 * @returns {void}
 */
const requestDeploymentReload = () => {
  if (reloadRequested) {
    return;
  }

  reloadRequested = true;
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
