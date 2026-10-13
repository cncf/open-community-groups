import { initializeOnReadyAndHtmxLoad, markDatasetReady } from "/static/js/common/dom.js";

const HTMX_HISTORY_PATH_STORAGE_KEY = "htmx-current-path-for-history";
const PAGE_VIEW_SELECTOR = "[data-page-view]";
const PAGE_VIEW_READY_KEY = "pageViewReady";
const UTM_PARAM_NAMES = ["utm_campaign", "utm_medium", "utm_source"];

/** Mutable page view queue state shared by visibility and page-show listeners. */
const trackerState = {
  endpoint: null,
  initialized: false,
  pendingViews: 0,
};

/**
 * Queues a page view for a tracked community, group, or event.
 * Event page views carry the UTM parameters of the current URL, which are
 * removed from the URL so reloads and shared links are not attributed again.
 * @param {Object} params Page view parameters.
 * @param {string} params.entityId Tracked entity id.
 * @param {string} params.entityType Tracked entity type.
 * @returns {void}
 */
export const trackPageView = ({ entityId, entityType }) => {
  if (!entityId || !entityType) {
    return;
  }

  let endpoint =
    entityType === "community"
      ? `/communities/${entityId}/views`
      : entityType === "event"
        ? `/events/${entityId}/views`
        : `/groups/${entityId}/views`;

  // Attribute event views to the UTM parameters of the current URL
  if (entityType === "event") {
    const utmQuery = consumeUtmParams().toString();
    if (utmQuery) {
      endpoint = `${endpoint}?${utmQuery}`;
    }
  }

  trackerState.endpoint = endpoint;
  trackerState.pendingViews += 1;

  bindLifecycleListeners();
  flushPendingPageViews();
};

/**
 * Tracks declarative page view markers rendered by the server.
 * @param {Document|Element} root - Root element containing page view markers
 */
export const initializePageViewTracking = (root = document) => {
  getPageViewMarkers(root).forEach((marker) => {
    if (!markDatasetReady(marker, PAGE_VIEW_READY_KEY)) {
      return;
    }

    trackPageView({
      entityId: marker.dataset.entityId || "",
      entityType: marker.dataset.entityType || "",
    });
  });
};

/**
 * Resets page view tracker state for isolated browser tests.
 */
export const resetPageViewTracker = () => {
  trackerState.endpoint = null;
  trackerState.initialized = false;
  trackerState.pendingViews = 0;
};

/**
 * Binds lifecycle listeners once so page views can be retried later.
 */
const bindLifecycleListeners = () => {
  if (trackerState.initialized) {
    return;
  }

  document.addEventListener("visibilitychange", () => {
    flushPendingPageViews();
  });

  window.addEventListener("pageshow", (event) => {
    if (!event.persisted) {
      return;
    }

    trackerState.pendingViews += 1;
    flushPendingPageViews();
  });

  trackerState.initialized = true;
};

/**
 * Reads the UTM parameters of the current URL and removes them from it.
 * @returns {URLSearchParams} Non-empty UTM parameters found in the URL.
 */
const consumeUtmParams = () => {
  const url = new URL(window.location.href);
  const utmParams = new URLSearchParams();
  let hasUtmParams = false;

  UTM_PARAM_NAMES.forEach((name) => {
    if (!url.searchParams.has(name)) {
      return;
    }

    const value = url.searchParams.get(name);
    if (value) {
      utmParams.set(name, value);
    }
    url.searchParams.delete(name);
    hasUtmParams = true;
  });

  // Keep the current history entry state while cleaning its URL
  if (hasUtmParams) {
    history.replaceState(history.state, "", url.href);
    syncHtmxHistoryPath(url);
  }

  return utmParams;
};

/**
 * Sends all queued page views for the current page once it becomes visible.
 */
const flushPendingPageViews = () => {
  if (document.visibilityState !== "visible" || !trackerState.endpoint || trackerState.pendingViews === 0) {
    return;
  }

  const { endpoint, pendingViews } = trackerState;
  trackerState.pendingViews = 0;

  for (let index = 0; index < pendingViews; index += 1) {
    sendPageView(endpoint);
  }
};

/**
 * Finds page view marker elements in the current root and its descendants.
 * @param {Document|Element} root Root element containing page view markers.
 * @returns {Array<Element>} Page view marker elements.
 */
const getPageViewMarkers = (root) => {
  const markers = [];
  if (root instanceof HTMLElement && root.matches(PAGE_VIEW_SELECTOR)) {
    markers.push(root);
  }

  markers.push(...(root.querySelectorAll?.(PAGE_VIEW_SELECTOR) || []));
  return markers;
};

/**
 * Sends a single page view using sendBeacon when possible.
 * @param {string | null} endpoint - View tracking endpoint
 */
const sendPageView = (endpoint) => {
  if (!endpoint) {
    return;
  }

  if (typeof navigator.sendBeacon === "function") {
    const queued = navigator.sendBeacon(endpoint, new Blob([], { type: "text/plain" }));
    if (queued) {
      return;
    }
  }

  fetch(endpoint, {
    method: "POST",
    keepalive: true,
  }).catch(() => {
    // Silently ignore analytics failures
  });
};

/**
 * Points the path HTMX recorded for the current history entry to its URL.
 * HTMX saves the page snapshot under that path when navigating away and looks
 * it up by the entry URL on back navigation, so both must stay in sync after
 * the URL is cleaned. HTMX only records the path when session storage works.
 * The storage key is an HTMX internal, so unit tests check the loaded bundle
 * still uses it.
 * @param {URL} url Current history entry URL.
 */
const syncHtmxHistoryPath = (url) => {
  try {
    if (sessionStorage.getItem(HTMX_HISTORY_PATH_STORAGE_KEY) !== null) {
      sessionStorage.setItem(HTMX_HISTORY_PATH_STORAGE_KEY, `${url.pathname}${url.search}`);
    }
  } catch {
    // Without session storage HTMX keeps no history snapshots to sync
  }
};

initializeOnReadyAndHtmxLoad(initializePageViewTracking);
