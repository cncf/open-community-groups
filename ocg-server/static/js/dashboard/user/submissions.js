import { handleHtmxResponse, showConfirmAlert } from "/static/js/common/alerts.js";
import { toggleModalVisibility } from "/static/js/common/common.js";
import {
  getElementById,
  initializeOnReadyAndHtmxLoad,
  markDatasetReady,
} from "/static/js/common/dom.js";

const ACTION_REQUIRED_MODAL_ID = "action-required-modal";
const ACTION_REQUIRED_MODAL_MESSAGE_ID = "action-required-modal-message";
const ACTION_REQUIRED_MODAL_CLOSE_ID = "close-action-required-modal";
const ACTION_REQUIRED_MODAL_CANCEL_ID = "cancel-action-required-modal";
const ACTION_REQUIRED_MODAL_OVERLAY_ID = "overlay-action-required-modal";
const ACTION_REQUIRED_TRIGGER_SELECTOR = '[data-action="open-action-required-modal"]';

const initializeActionRequiredModal = (root = document) => {
  const modal = getElementById(root, ACTION_REQUIRED_MODAL_ID);
  const message = getElementById(root, ACTION_REQUIRED_MODAL_MESSAGE_ID);
  if (!modal || !message) {
    return;
  }

  const closeModal = () => {
    if (!modal.classList.contains("hidden")) {
      toggleModalVisibility(ACTION_REQUIRED_MODAL_ID);
    }
  };

  if (markDatasetReady(modal, "bound")) {
    getElementById(root, ACTION_REQUIRED_MODAL_CLOSE_ID)?.addEventListener("click", closeModal);
    getElementById(root, ACTION_REQUIRED_MODAL_CANCEL_ID)?.addEventListener("click", closeModal);
    getElementById(root, ACTION_REQUIRED_MODAL_OVERLAY_ID)?.addEventListener("click", closeModal);
  }

  root.querySelectorAll?.(ACTION_REQUIRED_TRIGGER_SELECTOR).forEach((button) => {
    if (!markDatasetReady(button, "bound")) {
      return;
    }

    button.addEventListener("click", () => {
      message.textContent = button.dataset.actionRequiredMessage || "";
      if (modal.classList.contains("hidden")) {
        toggleModalVisibility(ACTION_REQUIRED_MODAL_ID);
      }
    });
  });
};

const initializeSubmissionActions = (root = document) => {
  root.querySelectorAll?.('[data-action="withdraw-submission"]').forEach((button) => {
    if (!markDatasetReady(button, "bound")) {
      return;
    }
    button.addEventListener("click", () => {
      if (!button.id) {
        button.id = `withdraw-submission-${button.dataset.submissionId}`;
      }
      showConfirmAlert(
        "Are you sure you want to withdraw this submission?<br><br>This action cannot be undone.",
        button.id,
        "Withdraw",
        "Cancel",
        true,
      );
    });
    button.addEventListener("htmx:afterRequest", (event) => {
      handleHtmxResponse({
        xhr: event.detail?.xhr,
        successMessage: "",
        errorMessage: "Unable to withdraw this submission. Please try again later.",
      });
    });
  });

  root.querySelectorAll?.('[data-action="resubmit-submission"]').forEach((button) => {
    if (!markDatasetReady(button, "bound")) {
      return;
    }
    button.addEventListener("click", () => {
      if (!button.id) {
        button.id = `resubmit-submission-${button.dataset.submissionId}`;
      }
      showConfirmAlert(
        "Before resubmitting, please make sure all required changes have been addressed.<br><br>You can see more details about the information requested by clicking on the info icon next to the badge.",
        button.id,
        "Resubmit",
        "Cancel",
        true,
      );
    });
    button.addEventListener("htmx:afterRequest", (event) => {
      handleHtmxResponse({
        xhr: event.detail?.xhr,
        successMessage: "",
        errorMessage: "Unable to resubmit this submission. Please try again later.",
      });
    });
  });

  initializeActionRequiredModal(root);
};

initializeOnReadyAndHtmxLoad(initializeSubmissionActions);
