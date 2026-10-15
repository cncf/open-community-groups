import { initializeOnReadyAndHtmxLoad, markDatasetReady } from "/static/js/common/dom.js";

const HTMX_HISTORY_PATH_STORAGE_KEY = "htmx-current-path-for-history";
const PAGE_VIEW_SELECTOR = "[data-page-view]";
const PAGE_VIEW_READY_KEY = "pageViewReady";
const UTM_PARAM_NAMES = ["utm_campaign", "utm_medium", "utm_source"];

/** Mutable page view queue state shared by visibility and page-show listeners. */
const trackerState = {
  attribution: "",
  endpoint: null,
  initialized: false,
  pendingViews: 0,
};

/**
 * Queues a page view for a tracked community, group, or event.
 * The first view sent for an event page carries the UTM parameters of the
 * current URL, which are removed from it, so reloads, back-forward cache
 * restores, and shared links are not attributed again.
 * @param {Object} params Page view parameters.
 * @param {string} params.entityId Tracked entity id.
 * @param {string} params.entityType Tracked entity type.
 * @returns {void}
 */
export const trackPageView = ({ entityId, entityType }) => {
  if (!entityId || !entityType) {
    return;
  }

  const endpoint =
    entityType === "community"
      ? `/communities/${entityId}/views`
      : entityType === "event"
        ? `/events/${entityId}/views`
        : `/groups/${entityId}/views`;

  // Attribute event views to the UTM parameters of the current URL
  trackerState.attribution = entityType === "event" ? consumeUtmParams().toString() : "";
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
  trackerState.attribution = "";
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
 * The other query parameters are kept exactly as written.
 * @returns {URLSearchParams} Non-empty UTM parameters found in the URL.
 */
const consumeUtmParams = () => {
  const { hash, pathname, search } = window.location;
  const searchParams = new URLSearchParams(search);
  const utmParams = new URLSearchParams();

  UTM_PARAM_NAMES.forEach((name) => {
    const value = searchParams.get(name);
    if (value) {
      utmParams.set(name, value);
    }
  });

  // Drop the UTM segments from the raw query without re-encoding the others
  const querySegments = search.slice(1).split("&");
  const keptSegments = querySegments.filter((segment) => !isUtmParamSegment(segment));
  if (keptSegments.length === querySegments.length) {
    return utmParams;
  }

  // Keep the current history entry state while cleaning its URL
  const keptQuery = keptSegments.join("&");
  const path = `${pathname}${keptQuery ? `?${keptQuery}` : ""}`;
  history.replaceState(history.state, "", `${path}${hash}`);
  syncHtmxHistoryPath(path);

  return utmParams;
};

/**
 * Sends all queued page views for the current page once it becomes visible.
 * Only the first view sent carries the UTM attribution of the page.
 */
const flushPendingPageViews = () => {
  if (document.visibilityState !== "visible" || !trackerState.endpoint || trackerState.pendingViews === 0) {
    return;
  }

  const { attribution, endpoint, pendingViews } = trackerState;
  trackerState.attribution = "";
  trackerState.pendingViews = 0;

  for (let index = 0; index < pendingViews; index += 1) {
    sendPageView(index === 0 && attribution ? `${endpoint}?${attribution}` : endpoint);
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
 * Checks whether a raw query segment holds one of the UTM parameters.
 * @param {string} segment - Raw `name=value` query segment.
 * @returns {boolean} True when the decoded segment name is a UTM parameter.
 */
const isUtmParamSegment = (segment) => {
  const [name] = new URLSearchParams(segment).keys();
  return UTM_PARAM_NAMES.includes(name);
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
 * @param {string} path - Current history entry path and query, without the hash.
 */
const syncHtmxHistoryPath = (path) => {
  try {
    if (sessionStorage.getItem(HTMX_HISTORY_PATH_STORAGE_KEY) !== null) {
      sessionStorage.setItem(HTMX_HISTORY_PATH_STORAGE_KEY, path);
    }
  } catch {
    // Without session storage HTMX keeps no history snapshots to sync
  }
};

initializeOnReadyAndHtmxLoad(initializePageViewTracking);
