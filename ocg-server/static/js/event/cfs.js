import { toggleModalVisibility } from "/static/js/common/common.js";

const ROOT_ID = "cfs-modal-root";
const MODAL_ID = "cfs-modal";
const DATA_KEY = "cfsModalReady";
const SELECT_DATA_KEY = "cfsSubmitReady";

const initializeSubmitControls = (modal) => {
  const select = modal.querySelector("#session_proposal_id");
  const submit = modal.querySelector("#cfs-submit-button");
  if (!select || !submit) {
    return;
  }

  const syncSubmitState = () => {
    const disabled = !select.value;
    submit.disabled = disabled;
    submit.classList.toggle("opacity-50", disabled);
    submit.classList.toggle("cursor-not-allowed", disabled);
  };

  syncSubmitState();
  if (select.dataset[SELECT_DATA_KEY] === "true") {
    return;
  }

  select.dataset[SELECT_DATA_KEY] = "true";
  select.addEventListener("change", syncSubmitState);
};

const initializeCfsModal = () => {
  const modal = document.getElementById(MODAL_ID);
  if (!modal) {
    return;
  }

  if (modal.dataset[DATA_KEY] !== "true") {
    modal.dataset[DATA_KEY] = "true";

    const closeButton = modal.querySelector("#close-cfs-modal");
    const overlay = modal.querySelector("#overlay-cfs-modal");
    const toggleModal = () => toggleModalVisibility(MODAL_ID);

    closeButton?.addEventListener("click", toggleModal);
    overlay?.addEventListener("click", toggleModal);
    modal.addEventListener("click", (event) => {
      if (event.target instanceof Element && event.target.closest("#cancel-cfs-modal")) {
        toggleModal();
      }
    });
  }

  initializeSubmitControls(modal);
};

const handleModalSwap = (event) => {
  if (event?.target?.id !== ROOT_ID) {
    return;
  }
  initializeCfsModal();

  const modal = document.getElementById(MODAL_ID);
  if (modal?.classList.contains("hidden")) {
    toggleModalVisibility(MODAL_ID);
  }
};

if (document.body) {
  document.body.addEventListener("htmx:afterSwap", handleModalSwap);
}
