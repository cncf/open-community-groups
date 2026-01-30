import { toggleModalVisibility, unlockBodyScroll } from "/static/js/common/common.js";

const ROOT_ID = "cfs-modal-root";
const MODAL_ID = "cfs-modal";
const DATA_KEY = "cfsModalReady";

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

const handleModalSwap = (event) => {
  if (event?.target?.id !== ROOT_ID) {
    return;
  }
  initializeCfsModal();
  unlockBodyScroll();
  toggleModalVisibility(MODAL_ID);
};

if (document.body) {
  document.body.addEventListener("htmx:afterSwap", handleModalSwap);
}
