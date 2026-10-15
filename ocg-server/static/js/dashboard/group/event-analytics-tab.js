import { setElementHidden } from "/static/js/common/dom.js";

/** Selector of the analytics tab content container. */
const ANALYTICS_CONTENT_SELECTOR = "#analytics-content";

/** Analytics tab loading states. */
const ANALYTICS_STATE = {
  error: "error",
  idle: "idle",
  loaded: "loaded",
  loading: "loading",
};

/** Messages announced by the analytics status region; errors use their own alert. */
const ANALYTICS_STATUS_MESSAGES = {
  error: "",
  idle: "",
  loaded: "Analytics loaded.",
  loading: "Loading analytics.",
};

/**
 * Content containers whose listeners are bound. Kept in memory, unlike a
 * dataset marker, so containers restored from the HTMX history cache bind again.
 */
const boundContents = new WeakSet();

/** Content containers with an analytics request in flight. */
const loadingContents = new WeakSet();

/**
 * Loads the analytics tab content of the event page when it has not loaded yet
 * or its previous load failed.
 * @param {Document|Element} pageRoot - Event page root.
 * @returns {boolean} True when a request was started.
 */
export const loadEventAnalyticsTab = (pageRoot = document) => {
  const content = pageRoot.querySelector?.(ANALYTICS_CONTENT_SELECTOR);
  if (!content || !window.htmx) {
    return false;
  }

  bindAnalyticsTabEvents(content, pageRoot);

  // Only idle or failed tabs start a request, so repeated activations do not
  // duplicate it
  const state = getAnalyticsState(content);
  if (state !== ANALYTICS_STATE.idle && state !== ANALYTICS_STATE.error) {
    return false;
  }

  setAnalyticsState(content, ANALYTICS_STATE.loading);
  window.htmx.ajax("GET", content.dataset.analyticsUrl, {
    source: content,
    swap: "innerHTML",
    target: content,
  });

  return true;
};

/**
 * Binds the swap, error and retry listeners of the analytics tab once.
 * @param {HTMLElement} content - Analytics content container.
 * @param {Document|Element} pageRoot - Event page root.
 * @returns {void}
 */
const bindAnalyticsTabEvents = (content, pageRoot) => {
  if (boundContents.has(content)) {
    return;
  }
  boundContents.add(content);

  // Responses only change a tab that is still waiting for them
  content.addEventListener("htmx:afterSwap", (event) => {
    if (event.target !== content || getAnalyticsState(content) !== ANALYTICS_STATE.loading) {
      return;
    }
    setAnalyticsState(content, ANALYTICS_STATE.loaded);
  });

  const handleFailure = () => {
    if (!content.isConnected || getAnalyticsState(content) !== ANALYTICS_STATE.loading) {
      return;
    }
    setAnalyticsState(content, ANALYTICS_STATE.error);
    content.querySelector("#analytics-error")?.focus();
  };
  content.addEventListener("htmx:responseError", handleFailure);
  content.addEventListener("htmx:sendError", handleFailure);

  // Retry failed loads from the error message
  content.addEventListener("click", (event) => {
    const retryButton =
      event.target instanceof Element ? event.target.closest("[data-analytics-retry]") : null;
    if (!retryButton || !content.contains(retryButton)) {
      return;
    }
    loadEventAnalyticsTab(pageRoot);
  });
};

/**
 * Reads the loading state of the analytics tab. A loading state without a
 * request in flight, as restored from the HTMX history cache, reads as idle so
 * the tab can load again.
 * @param {HTMLElement} content - Analytics content container.
 * @returns {string} Current state.
 */
const getAnalyticsState = (content) => {
  const state = content.dataset.analyticsState || ANALYTICS_STATE.idle;
  if (state === ANALYTICS_STATE.loading && !loadingContents.has(content)) {
    return ANALYTICS_STATE.idle;
  }
  return state;
};

/**
 * Updates the loading state of the analytics tab, its loading and error
 * placeholders and the announced status.
 * @param {HTMLElement} content - Analytics content container.
 * @param {string} state - New state.
 * @returns {void}
 */
const setAnalyticsState = (content, state) => {
  const isLoading = state === ANALYTICS_STATE.loading;
  if (isLoading) {
    loadingContents.add(content);
  } else {
    loadingContents.delete(content);
  }
  content.dataset.analyticsState = state;
  content.setAttribute("aria-busy", isLoading ? "true" : "false");

  // Announce progress from a region outside the swapped content
  const status = content.closest('[data-content="analytics"]')?.querySelector("#analytics-status");
  if (status) {
    status.textContent = ANALYTICS_STATUS_MESSAGES[state] || "";
  }
  setElementHidden(content.querySelector("#analytics-loading"), state !== ANALYTICS_STATE.loading);
  setElementHidden(content.querySelector("#analytics-error"), state !== ANALYTICS_STATE.error);
};
