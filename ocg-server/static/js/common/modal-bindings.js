import { toggleModalVisibility } from "/static/js/common/common.js";
import { closestElement } from "/static/js/common/dom.js";

const modalToggleSelector = "[data-modal-toggle]";

document.addEventListener("click", (event) => {
  const trigger = closestElement(event.target, modalToggleSelector);
  if (!trigger) {
    return;
  }

  const modalId = trigger.dataset.modalToggle;
  if (!modalId) {
    return;
  }

  event.preventDefault();
  toggleModalVisibility(modalId);
});
