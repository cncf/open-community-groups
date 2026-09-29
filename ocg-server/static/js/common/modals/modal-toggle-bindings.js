import {
  bindModalDismissListeners,
  setModalCloseCleanup,
  toggleModalVisibility,
  trapModalFocus,
} from "/static/js/common/modals/modal-lifecycle.js";
import { closestElement, getElementById, isElementHidden } from "/static/js/common/dom.js";

const modalToggleSelector = "[data-modal-toggle]";

/**
 * Binds Escape and Tab handling for a modal opened after an HTMX swap. Keys
 * already handled by a nested control, such as Escape closing a dropdown, are
 * left alone. The listeners are removed by the modal close cleanup on every
 * close path.
 * @param {Element} modal Open modal element.
 * @returns {void}
 */
const bindOpenModalKeyboard = (modal) => {
  const removeDismissListeners = bindModalDismissListeners({
    onKeydown: (event) => {
      if (event.defaultPrevented) {
        return;
      }
      if (event.key === "Escape") {
        event.preventDefault();
        toggleModalVisibility(modal);
        return;
      }
      trapModalFocus(event, modal);
    },
  });
  setModalCloseCleanup(modal, removeDismissListeners);
};

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

  event.preventDefault();
  toggleModalVisibility(modalId, trigger);
};

document.addEventListener("click", handleModalToggleClick);
document.addEventListener("htmx:afterSwap", handleModalOpenOnSwap);
