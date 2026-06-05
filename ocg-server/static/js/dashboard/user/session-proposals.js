import { bindHtmxResponseAlert, showConfirmAlert } from "/static/js/common/alerts.js";
import {
  ensureElementId,
  getElementById,
  initializeOnReadyAndHtmxLoad,
  markDatasetReady,
} from "/static/js/common/dom.js";
import { parseJsonText } from "/static/js/common/utils.js";
import "/static/js/dashboard/user/session-proposal-modal.js";

const MODAL_COMPONENT_ID = "session-proposal-modal-component";
const DATA_KEY = "sessionProposalReady";

const getModalComponent = (root = document) => getElementById(root, MODAL_COMPONENT_ID);

const parseSessionProposal = (payload) => {
  return parseJsonText(payload, null, (error) => {
    console.error("Invalid proposal payload", error);
  });
};

const applyDescriptionHtml = (button, sessionProposal) => {
  const payload = button?.dataset?.proposalDescriptionHtml;
  if (!payload || !sessionProposal) {
    return;
  }

  const descriptionHtml = parseJsonText(payload, null, (error) => {
    console.error("Invalid proposal description html payload", error);
  });
  if (typeof descriptionHtml === "string") {
    sessionProposal.description_html = descriptionHtml;
  }
};

const initializeSessionProposals = (root = document) => {
  const modalComponent = getModalComponent(root);
  if (!modalComponent) {
    return;
  }

  markDatasetReady(modalComponent, DATA_KEY);

  const openButton = getElementById(root, "open-session-proposal-modal");
  if (markDatasetReady(openButton, "bound")) {
    openButton.addEventListener("click", () => modalComponent.openCreate());
  }

  root.querySelectorAll?.('[data-action="edit-session-proposal"]').forEach((button) => {
    if (!markDatasetReady(button, "bound")) {
      return;
    }

    button.addEventListener("click", () => {
      const sessionProposal = parseSessionProposal(button.dataset.sessionProposal);
      if (!sessionProposal) {
        return;
      }
      applyDescriptionHtml(button, sessionProposal);
      modalComponent.openEdit(sessionProposal);
    });
  });

  root.querySelectorAll?.('[data-action="view-session-proposal"]').forEach((button) => {
    if (!markDatasetReady(button, "bound")) {
      return;
    }

    button.addEventListener("click", () => {
      const sessionProposal = parseSessionProposal(button.dataset.sessionProposal);
      if (!sessionProposal) {
        return;
      }
      if (button.dataset.speakerName) {
        sessionProposal.speaker_name = button.dataset.speakerName;
      }
      if (button.dataset.speakerPhotoUrl) {
        sessionProposal.speaker_photo_url = button.dataset.speakerPhotoUrl;
      }
      applyDescriptionHtml(button, sessionProposal);
      modalComponent.openView(sessionProposal);
    });
  });

  root.querySelectorAll?.('[data-action="view-pending-session-proposal"]').forEach((button) => {
    if (!markDatasetReady(button, "bound")) {
      return;
    }

    button.addEventListener("click", () => {
      const sessionProposal = parseSessionProposal(button.dataset.sessionProposal);
      if (!sessionProposal) {
        return;
      }
      if (button.dataset.speakerName) {
        sessionProposal.speaker_name = button.dataset.speakerName;
      }
      if (button.dataset.speakerPhotoUrl) {
        sessionProposal.speaker_photo_url = button.dataset.speakerPhotoUrl;
      }
      applyDescriptionHtml(button, sessionProposal);
      modalComponent.openView(sessionProposal);
    });
  });

  root.querySelectorAll?.('[data-action="delete-session-proposal"]').forEach((button) => {
    if (!markDatasetReady(button, "bound")) {
      return;
    }

    button.addEventListener("click", () => {
      if (button.disabled) {
        return;
      }

      showConfirmAlert(
        "Are you sure you want to delete this session proposal?",
        ensureElementId(button, `delete-session-proposal-${button.dataset.sessionProposalId}`),
        "Delete",
      );
    });

    bindHtmxResponseAlert(button, {
      successMessage: "",
      errorMessage: "Unable to delete this proposal. Please try again later.",
    });
  });

  root.querySelectorAll?.('[data-action="accept-co-speaker-invitation"]').forEach((button) => {
    if (!markDatasetReady(button, "bound")) {
      return;
    }

    bindHtmxResponseAlert(button, {
      successMessage: "",
      errorMessage: "Unable to accept this invitation. Please try again later.",
    });
  });

  root.querySelectorAll?.('[data-action="reject-co-speaker-invitation"]').forEach((button) => {
    if (!markDatasetReady(button, "bound")) {
      return;
    }

    button.addEventListener("click", () => {
      if (button.disabled) {
        return;
      }

      showConfirmAlert(
        "Are you sure you want to decline this co-speaker invitation?",
        ensureElementId(button, `reject-co-speaker-invitation-${button.dataset.sessionProposalId}`),
        "Decline",
        "Cancel",
      );
    });

    bindHtmxResponseAlert(button, {
      successMessage: "",
      errorMessage: "Unable to decline this invitation. Please try again later.",
    });
  });
};

initializeOnReadyAndHtmxLoad(initializeSessionProposals);
