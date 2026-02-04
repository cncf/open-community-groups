import { handleHtmxResponse, showConfirmAlert } from "/static/js/common/alerts.js";
import { toggleModalVisibility } from "/static/js/common/common.js";

const ACTION_REQUIRED_MODAL_ID = "action-required-modal";
const ACTION_REQUIRED_MODAL_MESSAGE_ID = "action-required-modal-message";
const ACTION_REQUIRED_MODAL_CLOSE_ID = "close-action-required-modal";
const ACTION_REQUIRED_MODAL_CANCEL_ID = "cancel-action-required-modal";
const ACTION_REQUIRED_MODAL_OVERLAY_ID = "overlay-action-required-modal";
const ACTION_REQUIRED_TRIGGER_SELECTOR = '[data-action="open-action-required-modal"]';

const initializeActionRequiredModal = () => {
  const modal = document.getElementById(ACTION_REQUIRED_MODAL_ID);
  const message = document.getElementById(ACTION_REQUIRED_MODAL_MESSAGE_ID);
  if (!modal || !message) {
    return;
  }

  const closeModal = () => {
    if (!modal.classList.contains("hidden")) {
      toggleModalVisibility(ACTION_REQUIRED_MODAL_ID);
    }
  };

  if (modal.dataset.bound !== "true") {
    modal.dataset.bound = "true";
    document.getElementById(ACTION_REQUIRED_MODAL_CLOSE_ID)?.addEventListener("click", closeModal);
    document.getElementById(ACTION_REQUIRED_MODAL_CANCEL_ID)?.addEventListener("click", closeModal);
    document.getElementById(ACTION_REQUIRED_MODAL_OVERLAY_ID)?.addEventListener("click", closeModal);
  }

  document.querySelectorAll(ACTION_REQUIRED_TRIGGER_SELECTOR).forEach((button) => {
    if (button.dataset.bound === "true") {
      return;
    }
    button.dataset.bound = "true";

    button.addEventListener("click", () => {
      message.textContent = button.dataset.actionRequiredMessage || "";
      if (modal.classList.contains("hidden")) {
        toggleModalVisibility(ACTION_REQUIRED_MODAL_ID);
      }
    });
  });
};

const initializeSubmissionActions = () => {
  document.querySelectorAll('[data-action="withdraw-submission"]').forEach((button) => {
    if (button.dataset.bound === "true") {
      return;
    }
    button.dataset.bound = "true";
    button.addEventListener("click", () => {
      if (!button.id) {
        button.id = `withdraw-submission-${button.dataset.submissionId}`;
      }
      showConfirmAlert("Withdraw this submission?", button.id, "Withdraw");
    });
    button.addEventListener("htmx:afterRequest", (event) => {
      handleHtmxResponse({
        xhr: event.detail?.xhr,
        successMessage: "",
        errorMessage: "Unable to withdraw this submission. Please try again later.",
      });
    });
  });

  document.querySelectorAll('[data-action="resubmit-submission"]').forEach((button) => {
    if (button.dataset.bound === "true") {
      return;
    }
    button.dataset.bound = "true";
    button.addEventListener("htmx:afterRequest", (event) => {
      handleHtmxResponse({
        xhr: event.detail?.xhr,
        successMessage: "",
        errorMessage: "Unable to resubmit this submission. Please try again later.",
      });
    });
  });

  initializeActionRequiredModal();
};

initializeSubmissionActions();

if (document.body) {
  document.body.addEventListener("htmx:load", initializeSubmissionActions);
}
