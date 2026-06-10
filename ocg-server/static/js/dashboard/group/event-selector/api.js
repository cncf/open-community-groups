import { ocgFetch } from "/static/js/common/fetch.js";
import { buildEventSearchUrl } from "/static/js/dashboard/group/event-selector/utils.js";

/**
 * Requests event selector search results.
 * @param {Object} config Event search configuration.
 * @param {Function} eventSearchFetch Fetch implementation.
 * @returns {Promise<Object[]>}
 */
export const requestEventSelectorEvents = async (config, eventSearchFetch = ocgFetch) => {
  const response = await eventSearchFetch(buildEventSearchUrl(config), {
    headers: {
      Accept: "application/json",
    },
  });
  if (!response.ok) {
    throw new Error("Failed to search events");
  }
  const payload = await response.json();
  return Array.isArray(payload?.events) ? payload.events : [];
};
