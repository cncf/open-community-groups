import { getElementById } from "/static/js/common/dom.js";

/**
 * Shows a loading spinner by adding the is-loading class to the element.
 * @param {string} id ID of the element to show loading state for.
 * @returns {void}
 */
export const showLoadingSpinner = (id) => {
  const content = getElementById(document, id);
  if (content) {
    content.classList.add("is-loading");
  }
};

/**
 * Hides a loading spinner by removing the is-loading class from the element.
 * @param {string} id ID of the element to hide loading state for.
 * @returns {void}
 */
export const hideLoadingSpinner = (id) => {
  const content = getElementById(document, id);
  if (content) {
    content.classList.remove("is-loading");
  }
};
