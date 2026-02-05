import { toggleModalVisibility, unlockBodyScroll } from "/static/js/common/common.js";

const ROOT_ID = "cfs-modal-root";
const MODAL_ID = "cfs-modal";
const DATA_KEY = "cfsModalReady";
const OPEN_BUTTON_ID = "open-cfs-modal";
const OPEN_BUTTON_DATA_KEY = "cfsModalOpenReady";
const BODY_DATA_KEY = "cfsModalBodyReady";

/**
 * Opens the CFS modal only when it is present and currently hidden.
 */
const openModal = () => {
  const modal = document.getElementById(MODAL_ID);
  if (!modal || !modal.classList.contains("hidden")) {
    return;
  }
  toggleModalVisibility(MODAL_ID);
};

/**
 * Wires close and form-state behavior for the CFS modal once per modal swap.
 */
const initializeCfsModal = () => {
  const modal = document.getElementById(MODAL_ID);
  if (!modal || modal.dataset[DATA_KEY] === "true") {
    return;
  }
  modal.dataset[DATA_KEY] = "true";

  const closeButton = modal.querySelector("#close-cfs-modal");
  const cancelButton = modal.querySelector("#cancel-cfs-modal");
  const overlay = modal.querySelector("#overlay-cfs-modal");
  const toggleModal = () => toggleModalVisibility(MODAL_ID);

  closeButton?.addEventListener("click", toggleModal);
  cancelButton?.addEventListener("click", toggleModal);
  overlay?.addEventListener("click", toggleModal);

  const select = modal.querySelector("#session_proposal_id");
  const submit = modal.querySelector("#cfs-submit-button");
  if (select && submit) {
    const syncSubmitState = () => {
      const disabled = !select.value;
      submit.disabled = disabled;
      submit.classList.toggle("opacity-50", disabled);
      submit.classList.toggle("cursor-not-allowed", disabled);
    };
    syncSubmitState();
    select.addEventListener("change", syncSubmitState);
  }
};

/**
 * Binds open-button behavior once so reopen uses the cached modal content.
 */
const bindOpenButton = () => {
  const openButton = document.getElementById(OPEN_BUTTON_ID);
  if (!openButton || openButton.dataset[OPEN_BUTTON_DATA_KEY] === "true") {
    return;
  }

  openButton.dataset[OPEN_BUTTON_DATA_KEY] = "true";
  openButton.addEventListener("click", (event) => {
    const modal = document.getElementById(MODAL_ID);
    if (!modal || !modal.classList.contains("hidden")) {
      return;
    }

    event.preventDefault();
    event.stopPropagation();
    event.stopImmediatePropagation();
    openModal();
  });

  openButton.addEventListener("htmx:configRequest", (event) => {
    const modal = document.getElementById(MODAL_ID);
    if (!modal) {
      return;
    }

    // Reopen uses cached modal markup, so block duplicate fetches once present.
    event.preventDefault();
  });
};

/**
 * Handles modal content swaps and opens the modal after htmx injects it.
 * @param {Event} event - The htmx:afterSwap event.
 */
const handleModalSwap = (event) => {
  if (event?.target?.id !== ROOT_ID) {
    return;
  }
  initializeCfsModal();
  unlockBodyScroll();
  openModal();
};

if (document.body && document.body.dataset[BODY_DATA_KEY] !== "true") {
  document.body.dataset[BODY_DATA_KEY] = "true";
  document.body.addEventListener("htmx:afterSwap", handleModalSwap);
}

bindOpenButton();
