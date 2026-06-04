import { toggleModalVisibility } from "/static/js/common/common.js";

const modalToggleSelector = "[data-modal-toggle]";

document.addEventListener("click", (event) => {
  if (!(event.target instanceof Element)) {
    return;
  }

  const trigger = event.target.closest(modalToggleSelector);
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
