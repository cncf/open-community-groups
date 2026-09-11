export const DASHBOARD_CONTEXT_REFRESH_MESSAGE =
  "Your dashboard selection changed, so this page was refreshed.";
export const SELECTED_COMMUNITY_ID_HEADER = "X-OCG-Selected-Community-Id";
export const SELECTED_GROUP_ID_HEADER = "X-OCG-Selected-Group-Id";
export const STALE_DASHBOARD_CONTEXT_HEADER = "X-OCG-Stale-Dashboard-Context";

const DASHBOARD_CONTEXT_REFRESH_ALERT_STORAGE_KEY = "ocg.dashboardContextRefreshAlert";
const DASHBOARD_LAYOUT_SELECTOR = "#dashboard-layout";

let reloadRequested = false;
let reloadHandler = () => reloadDashboardRoot();

/**
 * Adds the community and group ids the loaded dashboard page was rendered for.
 * Requests outside a dashboard page carry no context headers.
 * @param {Headers|object} headers Mutable request headers.
 * @param {Document} root Document used to read the loaded dashboard context.
 * @returns {void}
 */
export const addLoadedDashboardContextHeaders = (headers, root = document) => {
  const context = getLoadedDashboardContext(root);
  if (!context || !headers) {
    return;
  }

  setHeader(headers, SELECTED_COMMUNITY_ID_HEADER, context.communityId);
  if (context.groupId) {
    setHeader(headers, SELECTED_GROUP_ID_HEADER, context.groupId);
  }
};

/**
 * Returns whether a dashboard context refresh alert was pending and clears it.
 * @returns {boolean} Whether the alert should be shown.
 */
export const consumePendingDashboardContextRefreshAlert = () => {
  const pending = sessionStorageGetItem(DASHBOARD_CONTEXT_REFRESH_ALERT_STORAGE_KEY) === "true";
  sessionStorageRemoveItem(DASHBOARD_CONTEXT_REFRESH_ALERT_STORAGE_KEY);
  return pending;
};

/**
 * Returns the URL a stale dashboard context reload navigates to.
 * The query string is dropped because a tab from the previous context may not
 * be accessible in the newly selected one.
 * @param {Location|{pathname: string}} location Current page location.
 * @returns {string} Dashboard root path for the current page.
 */
export const getDashboardContextReloadUrl = (location = window.location) => location.pathname;

/**
 * Clears the pending reload guard when the browser restores this page from
 * the back/forward cache, so restored pages keep handling responses.
 * @param {Window} target Window receiving page lifecycle events.
 * @returns {void}
 */
export const initializeDashboardContextState = (target = window) => {
  target.addEventListener("pageshow", (event) => {
    if (event.persisted) {
      reloadRequested = false;
    }
  });
};

/**
 * Returns whether a dashboard context reload has already been requested.
 * @returns {boolean} Whether the page is already navigating to the current context.
 */
export const isDashboardContextReloadRequested = () => reloadRequested;

/**
 * Returns whether the server refused the request because the loaded dashboard
 * context no longer matches the selected one.
 * @param {XMLHttpRequest|Headers|object|null|undefined} headersSource Response headers source.
 * @returns {boolean} Whether the response is a stale dashboard context intercept.
 */
export const isStaleDashboardContextResponse = (headersSource) =>
  getHeader(headersSource, STALE_DASHBOARD_CONTEXT_HEADER) === "true";

/**
 * Reloads the page once when the response reports a stale dashboard context.
 * The reload always happens: any pending work belongs to a context the user
 * no longer sees or can no longer access.
 * @param {XMLHttpRequest|Headers|object|null|undefined} headersSource Response headers source.
 * @returns {boolean} Whether a reload was requested or is already pending.
 */
export const reloadIfDashboardContextStale = (headersSource) => {
  if (reloadRequested) {
    return true;
  }
  if (!isStaleDashboardContextResponse(headersSource)) {
    return false;
  }

  reloadRequested = true;
  sessionStorageSetItem(DASHBOARD_CONTEXT_REFRESH_ALERT_STORAGE_KEY, "true");
  reloadHandler();
  return true;
};

/**
 * Resets dashboard context reload state for isolated unit tests.
 * Real page reloads recreate module state; tests use this to simulate navigation.
 * @returns {void}
 */
export const resetDashboardContextReloadState = () => {
  reloadRequested = false;
  reloadHandler = () => reloadDashboardRoot();
  sessionStorageRemoveItem(DASHBOARD_CONTEXT_REFRESH_ALERT_STORAGE_KEY);
};

/**
 * Overrides the page reload handler for isolated unit tests.
 * @param {Function} handler Replacement reload handler.
 * @returns {void}
 */
export const setDashboardContextReloadHandler = (handler) => {
  reloadHandler = typeof handler === "function" ? handler : () => reloadDashboardRoot();
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
 * Reads the dashboard context embedded in the loaded page layout.
 * @param {Document} root Document used to find the dashboard layout.
 * @returns {{communityId: string, groupId: string}|null} Loaded context, or null outside dashboards.
 */
const getLoadedDashboardContext = (root = document) => {
  const layout = root?.querySelector?.(DASHBOARD_LAYOUT_SELECTOR);
  const communityId = layout?.dataset?.ocgSelectedCommunityId?.trim() || "";
  if (!communityId) {
    return null;
  }

  return {
    communityId,
    groupId: layout.dataset.ocgSelectedGroupId?.trim() || "",
  };
};

/**
 * Navigates to the dashboard root of the current page.
 * @returns {void}
 */
const reloadDashboardRoot = () => {
  window.location.assign(getDashboardContextReloadUrl());
};

/**
 * Sets a header on a `Headers` instance or a plain HTMX headers object.
 * @param {Headers|object} headers Mutable request headers.
 * @param {string} name Header name.
 * @param {string} value Header value.
 * @returns {void}
 */
const setHeader = (headers, name, value) => {
  if (typeof headers.set === "function") {
    headers.set(name, value);
  } else {
    headers[name] = value;
  }
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
    // Storage may be unavailable in private modes or restricted contexts.
  }
};

/**
 * Stores a session storage item when browser storage is available.
 * @param {string} key Storage key.
 * @param {string} value Stored value.
 * @returns {void}
 */
const sessionStorageSetItem = (key, value) => {
  try {
    window.sessionStorage?.setItem(key, value);
  } catch {
    // Storage may be unavailable in private modes or restricted contexts.
  }
};
