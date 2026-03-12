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
 * Sends all queued page views for the current page once it becomes visible.
 * @param {{ endpoint: string | null, initialized: boolean, pendingViews: number }} trackerState - Shared page view tracker state
 */
const flushPendingPageViews = (trackerState) => {
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
 * @param {{ endpoint: string | null, initialized: boolean, pendingViews: number }} trackerState - Shared page view tracker state
 */
const bindLifecycleListeners = (trackerState) => {
  if (trackerState.initialized) {
    return;
  }

  document.addEventListener("visibilitychange", () => {
    flushPendingPageViews(trackerState);
  });

  window.addEventListener("pageshow", (event) => {
    if (!event.persisted) {
      return;
    }

    trackerState.pendingViews += 1;
    flushPendingPageViews(trackerState);
  });

  trackerState.initialized = true;
};

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

  const trackerState = (window.__ocgPageViewTracker = window.__ocgPageViewTracker || {
    endpoint: null,
    initialized: false,
    pendingViews: 0,
  });

  trackerState.endpoint = endpoint;
  trackerState.pendingViews += 1;

  bindLifecycleListeners(trackerState);
  flushPendingPageViews(trackerState);
};
