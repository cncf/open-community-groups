import { bindHtmxResponseAlert, showConfirmAlert } from "/static/js/common/alerts.js";
import { toggleModalVisibility } from "/static/js/common/common.js";
import {
  ensureElementId,
  getElementById,
  initializeOnReadyAndHtmxLoad,
  isElementHidden,
  markDatasetReady,
} from "/static/js/common/dom.js";
import { bindModalControlClicks } from "/static/js/common/modals/modal-lifecycle.js";

const ACTION_REQUIRED_MODAL_ID = "action-required-modal";
const ACTION_REQUIRED_MODAL_MESSAGE_ID = "action-required-modal-message";
const ACTION_REQUIRED_MODAL_CLOSE_ID = "close-action-required-modal";
const ACTION_REQUIRED_MODAL_CANCEL_ID = "cancel-action-required-modal";
const ACTION_REQUIRED_MODAL_OVERLAY_ID = "overlay-action-required-modal";
const ACTION_REQUIRED_TRIGGER_SELECTOR = '[data-action="open-action-required-modal"]';

/**
 * Gets the action-required modal from the provided root.
 * @param {Document|Element} root - Root element to search from.
 * @returns {Element|null} Action-required modal when present.
 */
const getActionRequiredModal = (root = document) => getElementById(root, ACTION_REQUIRED_MODAL_ID);

/**
 * Initializes the action-required modal controls and trigger buttons.
 * @param {Document|Element} root - Root element to search from.
 * @returns {void}
 */
const initializeActionRequiredModal = (root = document) => {
  const modal = getActionRequiredModal(root) || getActionRequiredModal(document);
  const message =
    getElementById(root, ACTION_REQUIRED_MODAL_MESSAGE_ID) ||
    getElementById(document, ACTION_REQUIRED_MODAL_MESSAGE_ID);
  if (!modal || !message) {
    return;
  }

  const closeModal = () => {
    if (!isElementHidden(modal)) {
      toggleModalVisibility(ACTION_REQUIRED_MODAL_ID);
    }
  };

  if (markDatasetReady(modal, "bound")) {
    bindModalControlClicks(
      [
        getElementById(document, ACTION_REQUIRED_MODAL_CLOSE_ID),
        getElementById(document, ACTION_REQUIRED_MODAL_CANCEL_ID),
        getElementById(document, ACTION_REQUIRED_MODAL_OVERLAY_ID),
      ],
      closeModal,
    );
  }

  root.querySelectorAll?.(ACTION_REQUIRED_TRIGGER_SELECTOR).forEach((button) => {
    if (!markDatasetReady(button, "bound")) {
      return;
    }

    button.addEventListener("click", () => {
      message.textContent = button.dataset.actionRequiredMessage || "";
      if (isElementHidden(modal)) {
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
      showConfirmAlert(
        "Are you sure you want to withdraw this submission?<br><br>This action cannot be undone.",
        ensureElementId(button, `withdraw-submission-${button.dataset.submissionId}`),
        "Withdraw",
        "Cancel",
        true,
      );
    });
    bindHtmxResponseAlert(button, {
      successMessage: "",
      errorMessage: "Unable to withdraw this submission. Please try again later.",
    });
  });

  root.querySelectorAll?.('[data-action="resubmit-submission"]').forEach((button) => {
    if (!markDatasetReady(button, "bound")) {
      return;
    }
    button.addEventListener("click", () => {
      showConfirmAlert(
        "Before resubmitting, please make sure all required changes have been addressed.<br><br>You can see more details about the information requested by clicking on the info icon next to the badge.",
        ensureElementId(button, `resubmit-submission-${button.dataset.submissionId}`),
        "Resubmit",
        "Cancel",
        true,
      );
    });
    bindHtmxResponseAlert(button, {
      successMessage: "",
      errorMessage: "Unable to resubmit this submission. Please try again later.",
    });
  });

  initializeActionRequiredModal(root);
};

initializeOnReadyAndHtmxLoad(initializeSubmissionActions);
