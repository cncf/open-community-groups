import "/static/js/common/location-search-field.js";
import { getElementById, initializeOnReadyAndHtmxLoad } from "/static/js/common/dom.js";

const CLEAR_LOCATION_BUTTON_ID = "clear-location-fields";
const LOCATION_SEARCH_FIELD_ID = "group-location-search";
const LOCATION_CLEAR_BOUND_KEY = "locationClearBound";

/**
 * Initializes the shared dashboard location clear button.
 * @param {Document|Element} root - Root element to search from.
 * @returns {void}
 */
export const initializeLocationClearButton = (root = document) => {
  const clearLocationButton = getElementById(root, CLEAR_LOCATION_BUTTON_ID);
  const locationSearchField = getElementById(root, LOCATION_SEARCH_FIELD_ID);
  if (
    !clearLocationButton ||
    !locationSearchField ||
    typeof locationSearchField.clearLocationFields !== "function" ||
    clearLocationButton.dataset[LOCATION_CLEAR_BOUND_KEY] === "true"
  ) {
    return;
  }

  clearLocationButton.dataset[LOCATION_CLEAR_BOUND_KEY] = "true";
  clearLocationButton.addEventListener("click", () => {
    locationSearchField.clearLocationFields();
  });
};

initializeOnReadyAndHtmxLoad(initializeLocationClearButton);
