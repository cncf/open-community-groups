/**
 * Updates the results container in the DOM with new content.
 * @param {string} content - The HTML content to insert into the results container
 */
export const updateResults = (content) => {
  const results = document.getElementById("results");
  results.innerHTML = content;
};

/**
 * Fetches events or groups data from the API based on entity type and search parameters.
 * @param {string} entity - The type of entity to fetch ('events' or 'groups')
 * @param {string} params - URL search parameters as a string
 * @returns {Promise<object>} The JSON response data
 */
export async function fetchData(entity, params) {
  const url = `/explore/${entity}/search?${params}`;
  try {
    const response = await fetch(url);
    if (!response.ok) {
      throw new Error(`Response status: ${response.status}`);
    }

    const json = await response.json();
    return json;
  } catch (error) {
    // TODO - Handle error
  }
}
