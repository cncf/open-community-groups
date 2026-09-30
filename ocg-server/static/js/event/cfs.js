import { getElementById, markDatasetReady } from "/static/js/common/dom.js";

const ROOT_ID = "cfs-modal-root";
const SELECT_DATA_KEY = "cfsSubmitReady";

/**
 * Re-runs the submit state logic after the modal content is swapped.
 * @param {CustomEvent} event HTMX after-swap event.
 * @returns {void}
 */
const handleModalSwap = (event) => {
  if (event?.target?.id !== ROOT_ID) {
    return;
  }
  initializeSubmitControls();
};

/**
 * Enables the submit button only while a session proposal is selected.
 * @returns {void}
 */
const initializeSubmitControls = () => {
  const select = getElementById(document, "session_proposal_id");
  const submit = getElementById(document, "cfs-submit-button");
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

if (markDatasetReady(document.documentElement, "cfsModalSwapReady")) {
  document.addEventListener("htmx:afterSwap", handleModalSwap);
}
