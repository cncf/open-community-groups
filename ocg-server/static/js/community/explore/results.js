import { handleHtmxResponse } from "/static/js/common/alerts.js";
import { getElementById } from "/static/js/common/dom.js";
import { ocgFetch } from "/static/js/common/fetch.js";

const RESULTS_ID = "results";
const RESULTS_SUMMARY_SELECTOR = "[data-results-summary]";
const RESULTS_ERROR_MESSAGE = "Something went wrong loading results. Please try again later.";
const ENTITY_SECTION_ID = "entity-section";

/**
 * Error raised when explore widget data cannot be loaded.
 */
export class ExploreFetchError extends Error {
  /**
   * @param {string} message - Error message
   * @param {object} [details] - Failure details
   * @param {unknown} [details.cause] - Underlying error
   * @param {string} [details.responseText] - Response body of a failed request
   * @param {number|null} [details.status] - HTTP status of a failed request
   */
  constructor(message, { cause, responseText = "", status = null } = {}) {
    super(message, { cause });
    this.name = "ExploreFetchError";
    this.responseText = responseText;
    this.status = status;
  }
}

/**
 * Creates the tracker of a widget's latest data request.
 * Starting a request aborts and invalidates the previous one, so only the
 * latest request can apply its results.
 * @returns {{cancel: () => void, isCurrent: (id: number) => boolean, start: () => {id: number, signal: AbortSignal}}} Request tracker
 */
export const createLatestRequest = () => {
  let abortController = null;
  let currentId = 0;

  return {
    cancel() {
      currentId += 1;
      abortController?.abort();
      abortController = null;
    },
    isCurrent: (id) => id === currentId,
    start() {
      this.cancel();
      abortController = new AbortController();
      return { id: currentId, signal: abortController.signal };
    },
  };
};

/**
 * Fetches the minimal events or groups drawn by the explore map and calendar.
 * Never alerts; callers report failures of their current request only.
 * @param {string} entity - The type of entity to fetch ('events' or 'groups')
 * @param {string} params - URL search parameters as a string
 * @param {object} [options] - Request options
 * @param {AbortSignal} [options.signal] - Signal aborting the request
 * @returns {Promise<object>} Search response envelope
 * @throws {DOMException} When the request is aborted
 * @throws {ExploreFetchError} When the request, status, or JSON body fails
 */
export const fetchWidgetData = async (entity, params, { signal } = {}) => {
  const url = `/explore/${entity}/search?${params}`;

  // Request the widget data
  /** @type {Response} */
  let response;
  try {
    response = await ocgFetch(url, { headers: { Accept: "application/json" }, signal });
  } catch (error) {
    if (isAbortError(error)) throw error;
    throw new ExploreFetchError(`Failed to fetch ${entity} data`, { cause: error });
  }

  // Reject unsuccessful responses with their status
  if (!response.ok) {
    const responseText = await response.text().catch(() => "");
    throw new ExploreFetchError(`Failed to fetch ${entity} data (status ${response.status})`, {
      responseText,
      status: response.status,
    });
  }

  // Parse the response envelope
  try {
    return await response.json();
  } catch (error) {
    if (isAbortError(error)) throw error;
    throw new ExploreFetchError(`Failed to parse ${entity} data`, { cause: error });
  }
};

/**
 * Checks whether an error comes from an aborted request.
 * @param {unknown} error - Error to check
 * @returns {boolean} Whether the request was aborted
 */
export const isAbortError = (error) => error?.name === "AbortError";

/**
 * Shows the results error alert for a failed widget data request.
 * Aborted requests are ignored because a newer request replaced them.
 * @param {unknown} error - Error raised by fetchWidgetData
 */
export const reportFetchError = (error) => {
  if (isAbortError(error)) return;
  const xhr = error?.status ? { status: error.status, responseText: error.responseText || "" } : null;
  handleHtmxResponse({ xhr, successMessage: "", errorMessage: RESULTS_ERROR_MESSAGE });
};

/**
 * Updates the results container in the DOM with new content.
 * @param {string} content - The text content to insert into the results container
 */
export const updateResults = (content) => {
  const results = getElementById(document, RESULTS_ID);
  if (results) {
    results.textContent = content;
  }
};

/**
 * Updates the results summary from swapped explore markup.
 * @param {Document|HTMLElement} root - Root node to search for a summary marker
 */
export const updateResultsFromSummary = (root = document) => {
  const summary = root.querySelector?.(RESULTS_SUMMARY_SELECTOR);
  if (summary) {
    updateResults(summary.textContent.trim());
  }
};

/**
 * Initializes result summary updates for initial render and HTMX swaps.
 * @param {Document} root - Document root used for event binding
 */
const initializeExploreResults = (root = document) => {
  updateResultsFromSummary(root);
  root.addEventListener("htmx:afterSwap", (event) => {
    const target = event.target;
    if (target instanceof HTMLElement) {
      updateResultsFromSummary(target);
      if (target.id === ENTITY_SECTION_ID) {
        window.scrollTo({ top: 0, behavior: "instant" });
      }
    }
  });
};

initializeExploreResults();
