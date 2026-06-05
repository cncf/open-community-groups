/**
 * Search locations through the browser-safe Nominatim endpoint.
 * @param {string} query Location search query.
 * @param {AbortSignal} signal Abort signal for the request.
 * @returns {Promise<Array>} Search results.
 */
export const searchNominatimLocations = async (query, signal) => {
  const params = new URLSearchParams({
    q: query,
    format: "json",
    addressdetails: "1",
    limit: "10",
    dedupe: "1",
  });

  const response = await fetch(`https://nominatim.openstreetmap.org/search?${params.toString()}`, {
    signal,
    headers: {
      Accept: "application/json",
    },
  });

  if (!response.ok) {
    throw new Error(`HTTP error! status: ${response.status}`);
  }

  return response.json();
};
