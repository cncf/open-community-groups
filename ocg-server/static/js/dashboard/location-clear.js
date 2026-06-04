import "/static/js/common/location-search-field.js";

const CLEAR_LOCATION_BUTTON_ID = "clear-location-fields";
const LOCATION_SEARCH_FIELD_ID = "group-location-search";
const LOCATION_CLEAR_BOUND_KEY = "locationClearBound";

/**
 * Returns an element by ID from a document or element root.
 * @param {Document|Element} root - Root element to search from.
 * @param {string} id - Element ID.
 * @returns {HTMLElement|null} Matching element.
 */
const getElementById = (root, id) => {
  if (root instanceof HTMLElement && root.id === id) {
    return root;
  }

  const element = root.getElementById?.(id) || root.querySelector?.(`#${id}`);
  return element instanceof HTMLElement ? element : null;
};

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

const initializeLocationClearButtonWhenReady = () => {
  // Initialize current location controls on first load and after HTMX swaps.
  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", () => initializeLocationClearButton(document), {
      once: true,
    });
  } else {
    initializeLocationClearButton(document);
  }

  document.addEventListener("htmx:load", (event) => {
    const root = event.target instanceof Element ? event.target : document;
    initializeLocationClearButton(root);
  });
};

initializeLocationClearButtonWhenReady();
