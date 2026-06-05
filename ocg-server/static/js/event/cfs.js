import { toggleModalVisibility } from "/static/js/common/common.js";
import { getElementById } from "/static/js/common/dom.js";

const ROOT_ID = "cfs-modal-root";
const MODAL_ID = "cfs-modal";
const DATA_KEY = "cfsModalReady";
const SELECT_DATA_KEY = "cfsSubmitReady";

const initializeSubmitControls = (modal) => {
  const select = getElementById(modal, "session_proposal_id");
  const submit = getElementById(modal, "cfs-submit-button");
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
  const modal = getElementById(document, MODAL_ID);
  if (!modal) {
    return;
  }

  if (modal.dataset[DATA_KEY] !== "true") {
    modal.dataset[DATA_KEY] = "true";

    const closeButton = getElementById(modal, "close-cfs-modal");
    const overlay = getElementById(modal, "overlay-cfs-modal");
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

  const modal = getElementById(document, MODAL_ID);
  if (modal?.classList.contains("hidden")) {
    toggleModalVisibility(MODAL_ID);
  }
};

if (document.documentElement.dataset.cfsModalSwapReady !== "true") {
  document.documentElement.dataset.cfsModalSwapReady = "true";
  document.addEventListener("htmx:afterSwap", handleModalSwap);
}
