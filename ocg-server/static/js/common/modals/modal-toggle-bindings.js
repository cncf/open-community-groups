import { toggleModalVisibility } from "/static/js/common/common.js";
import { closestElement } from "/static/js/common/dom.js";

const modalToggleSelector = "[data-modal-toggle]";

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
