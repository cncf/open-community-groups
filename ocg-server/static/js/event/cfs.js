import { toggleModalVisibility } from "/static/js/common/common.js";
import { closestElement, getElementById, isElementHidden, markDatasetReady } from "/static/js/common/dom.js";

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
  if (!markDatasetReady(select, SELECT_DATA_KEY)) {
    return;
  }

  select.addEventListener("change", syncSubmitState);
};

const initializeCfsModal = () => {
  const modal = getElementById(document, MODAL_ID);
  if (!modal) {
    return;
  }

  if (markDatasetReady(modal, DATA_KEY)) {
    const closeButton = getElementById(modal, "close-cfs-modal");
    const overlay = getElementById(modal, "overlay-cfs-modal");
    const toggleModal = () => toggleModalVisibility(MODAL_ID);

    closeButton?.addEventListener("click", toggleModal);
    overlay?.addEventListener("click", toggleModal);
    modal.addEventListener("click", (event) => {
      if (closestElement(event.target, "#cancel-cfs-modal")) {
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
  if (isElementHidden(modal)) {
    toggleModalVisibility(MODAL_ID);
  }
};

if (markDatasetReady(document.documentElement, "cfsModalSwapReady")) {
  document.addEventListener("htmx:afterSwap", handleModalSwap);
}
