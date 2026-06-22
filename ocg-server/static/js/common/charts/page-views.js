import { initializeOnReadyAndHtmxLoad, markDatasetReady } from "/static/js/common/dom.js";

const PAGE_VIEW_SELECTOR = "[data-page-view]";
const PAGE_VIEW_READY_KEY = "pageViewReady";

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

/** Mutable page view queue state shared by visibility and page-show listeners. */
const trackerState = {
  endpoint: null,
  initialized: false,
  pendingViews: 0,
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
 * Queues a page view for a tracked alliance, group, or event.
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
    entityType === "alliance"
      ? `/alliances/${entityId}/views`
      : entityType === "event"
        ? `/events/${entityId}/views`
        : `/groups/${entityId}/views`;

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

initializeOnReadyAndHtmxLoad(initializePageViewTracking);

/**
 * Resets page view tracker state for isolated browser tests.
 */
export const resetPageViewTracker = () => {
  trackerState.endpoint = null;
  trackerState.initialized = false;
  trackerState.pendingViews = 0;
};
