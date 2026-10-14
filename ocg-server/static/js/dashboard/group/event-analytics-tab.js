import { markDatasetReady, setElementHidden } from "/static/js/common/dom.js";

/** Selector of the analytics tab content container. */
const ANALYTICS_CONTENT_SELECTOR = "#analytics-content";

/** Dataset key guarding the analytics tab listeners. */
const ANALYTICS_EVENTS_BOUND_KEY = "analyticsEventsBound";

/** Analytics tab loading states. */
const ANALYTICS_STATE = {
  error: "error",
  idle: "idle",
  loaded: "loaded",
  loading: "loading",
};

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
  if (!markDatasetReady(content, ANALYTICS_EVENTS_BOUND_KEY)) {
    return;
  }

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
 * Reads the loading state of the analytics tab.
 * @param {HTMLElement} content - Analytics content container.
 * @returns {string} Current state.
 */
const getAnalyticsState = (content) => content.dataset.analyticsState || ANALYTICS_STATE.idle;

/**
 * Updates the loading state of the analytics tab and its loading and error
 * placeholders.
 * @param {HTMLElement} content - Analytics content container.
 * @param {string} state - New state.
 * @returns {void}
 */
const setAnalyticsState = (content, state) => {
  content.dataset.analyticsState = state;
  content.setAttribute("aria-busy", state === ANALYTICS_STATE.loading ? "true" : "false");
  setElementHidden(content.querySelector("#analytics-loading"), state !== ANALYTICS_STATE.loading);
  setElementHidden(content.querySelector("#analytics-error"), state !== ANALYTICS_STATE.error);
};
