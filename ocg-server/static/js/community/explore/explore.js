import { handleHtmxResponse } from "/static/js/common/alerts.js";

/**
 * Updates the results container in the DOM with new content.
 * @param {string} content - The HTML content to insert into the results container
 */
export const updateResults = (content) => {
  const results = document.getElementById("results");
  if (results) {
    results.innerHTML = content;
  }
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
  const baseMessage = "Something went wrong loading results. Please try again later.";

  /** @type {Response} */
  let response;
  try {
    response = await fetch(url, { headers: { Accept: "application/json" } });
  } catch (error) {
    handleHtmxResponse({ xhr: null, successMessage: "", errorMessage: baseMessage });
    throw error;
  }

  if (!response.ok) {
    const responseText = await response.text().catch(() => "");
    handleHtmxResponse({
      xhr: { status: response.status, responseText },
      successMessage: "",
      errorMessage: baseMessage,
    });
    throw new Error(`Failed to fetch ${entity} data (status ${response.status})`);
  }

  try {
    return await response.json();
  } catch (error) {
    handleHtmxResponse({ xhr: null, successMessage: "", errorMessage: baseMessage });
    throw error;
  }
}
