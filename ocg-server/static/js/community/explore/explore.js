import { handleHtmxResponse } from "/static/js/common/alerts.js";
import { ocgFetch } from "/static/js/common/fetch.js";

const RESULTS_ID = "results";
const RESULTS_SUMMARY_SELECTOR = "[data-results-summary]";
const RESULTS_ERROR_MESSAGE = "Something went wrong loading results. Please try again later.";

/**
 * Updates the results container in the DOM with new content.
 * @param {string} content - The text content to insert into the results container
 */
export const updateResults = (content) => {
  const results = document.getElementById(RESULTS_ID);
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
export const initializeExploreResults = (root = document) => {
  updateResultsFromSummary(root);
  root.body?.addEventListener("htmx:afterSwap", (event) => {
    const target = event.target;
    if (target instanceof HTMLElement) {
      updateResultsFromSummary(target);
    }
  });
};

/**
 * Fetches events or groups data from the API based on entity type and search parameters.
 * @param {string} entity - The type of entity to fetch ('events' or 'groups')
 * @param {string} params - URL search parameters as a string
 * @returns {Promise<object>} The JSON response data
 * @throws {Error} When the request fails or the server responds with an error
 */
export async function fetchData(entity, params) {
  const url = `/explore/${entity}/search?${params}`;

  /** @type {Response} */
  let response;
  try {
    response = await ocgFetch(url, { headers: { Accept: "application/json" } });
  } catch (error) {
    handleHtmxResponse({ xhr: null, successMessage: "", errorMessage: RESULTS_ERROR_MESSAGE });
    throw error;
  }

  if (!response.ok) {
    const responseText = await response.text().catch(() => "");
    handleHtmxResponse({
      xhr: { status: response.status, responseText },
      successMessage: "",
      errorMessage: RESULTS_ERROR_MESSAGE,
    });
    throw new Error(`Failed to fetch ${entity} data (status ${response.status})`);
  }

  try {
    return await response.json();
  } catch (error) {
    handleHtmxResponse({ xhr: null, successMessage: "", errorMessage: RESULTS_ERROR_MESSAGE });
    throw error;
  }
}

initializeExploreResults();
