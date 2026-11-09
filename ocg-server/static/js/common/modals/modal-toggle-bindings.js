import { bindOpenModalKeyboard, toggleModalVisibility } from "/static/js/common/modals/modal-lifecycle.js";
import { closestElement, getElementById, isElementHidden } from "/static/js/common/dom.js";

const modalToggleSelector = "[data-modal-toggle]";

/**
 * Opens the modal named by data-modal-open-on-swap when HTMX swaps content
 * into an element carrying that attribute. Focus returns to the element that
 * issued the request when the modal closes.
 * @param {CustomEvent} event HTMX after-swap event.
 * @returns {void}
 */
const handleModalOpenOnSwap = (event) => {
  const swapped = event.target;
  if (!(swapped instanceof HTMLElement)) {
    return;
  }

  // Resolve the modal named by the swapped element
  const modalId = swapped.dataset.modalOpenOnSwap;
  if (!modalId) {
    return;
  }
  const modal = getElementById(document, modalId);
  if (!modal || !isElementHidden(modal)) {
    return;
  }

  // Open the modal and bind its keyboard handling until it closes
  const opener = event.detail?.requestConfig?.elt;
  toggleModalVisibility(modal, opener instanceof HTMLElement ? opener : null);
  bindOpenModalKeyboard(modal);
};

/**
 * Delegates clicks for server-rendered controls with data-modal-toggle.
 * The attribute value must match the id of the modal whose visibility toggles.
 * A modal opened this way closes with Escape and keeps Tab focus inside it.
 * @param {MouseEvent} event Click event.
 * @returns {void}
 */
const handleModalToggleClick = (event) => {
  const trigger = closestElement(event.target, modalToggleSelector);
  if (!trigger) {
    return;
  }

  const modalId = trigger.dataset.modalToggle;
  if (!modalId) {
    return;
  }

  // Resolve the modal named by the control
  event.preventDefault();
  const modal = getElementById(document, modalId);
  if (!modal) {
    return;
  }

  // Toggle the modal and bind its keyboard handling when it opens
  const willOpen = isElementHidden(modal);
  toggleModalVisibility(modal, trigger);
  if (willOpen) {
    bindOpenModalKeyboard(modal);
  }
};

document.addEventListener("click", handleModalToggleClick);
document.addEventListener("htmx:afterSwap", handleModalOpenOnSwap);
