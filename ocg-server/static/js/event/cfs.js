import { toggleModalVisibility } from "/static/js/common/common.js";
import { closestElement, getElementById, isElementHidden, markDatasetReady } from "/static/js/common/dom.js";
import {
  shouldPromptForProfileCompletion,
  showProfileCompletionAlert,
} from "/static/js/common/profile-completion-alert.js";

const ROOT_ID = "cfs-modal-root";
const MODAL_ID = "cfs-modal";
const DATA_KEY = "cfsModalReady";
const SELECT_DATA_KEY = "cfsSubmitReady";
const PROFILE_COMPLETION_TRIGGER_KEY = "__ocgProfileCompletionTrigger";
const PROFILE_COMPLETION_TRIGGER_KIND_KEY = "__ocgProfileCompletionTriggerKind";

const isCfsProfileCompletionAction = (target) =>
  target instanceof HTMLElement && (target.id === "open-cfs-modal" || target.id === "cfs-submission-form");

const handleBeforeRequest = (event) => {
  const target = event.target;
  if (!isCfsProfileCompletionAction(target)) {
    return;
  }

  if (target.id === "open-cfs-modal") {
    document[PROFILE_COMPLETION_TRIGGER_KEY] = target;
    document[PROFILE_COMPLETION_TRIGGER_KIND_KEY] = "open";
    return;
  }

  document[PROFILE_COMPLETION_TRIGGER_KEY] = target;
  document[PROFILE_COMPLETION_TRIGGER_KIND_KEY] = "submit";
};

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

  const trigger = document[PROFILE_COMPLETION_TRIGGER_KEY];
  const triggerKind = document[PROFILE_COMPLETION_TRIGGER_KIND_KEY];
  delete document[PROFILE_COMPLETION_TRIGGER_KEY];
  delete document[PROFILE_COMPLETION_TRIGGER_KIND_KEY];

  if (triggerKind === "submit" && !event.target.querySelector("[data-cfs-submission-notice]")) {
    return;
  }

  if (shouldPromptForProfileCompletion(trigger)) {
    showProfileCompletionAlert({ trigger });
  }
};

if (markDatasetReady(document.documentElement, "cfsModalSwapReady")) {
  document.addEventListener("htmx:afterSwap", handleModalSwap);
  document.addEventListener("htmx:beforeRequest", handleBeforeRequest);
}
