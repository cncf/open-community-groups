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

const applySpeakerDataset = (button, sessionProposal) => {
  if (button.dataset.speakerName) {
    sessionProposal.speaker_name = button.dataset.speakerName;
  }
  if (button.dataset.speakerPhotoUrl) {
    sessionProposal.speaker_photo_url = button.dataset.speakerPhotoUrl;
  }
};

const bindSessionProposalButtons = (root, selector, handler) => {
  root.querySelectorAll?.(selector).forEach((button) => {
    if (!markDatasetReady(button, "bound")) {
      return;
    }

    button.addEventListener("click", () => {
      const sessionProposal = parseSessionProposal(button.dataset.sessionProposal);
      if (!sessionProposal) {
        return;
      }
      handler(button, sessionProposal);
    });
  });
};

const initializeSessionProposals = (root = document) => {
  const modalComponent = getModalComponent(root) || getModalComponent(document);

  if (modalComponent) {
    markDatasetReady(modalComponent, DATA_KEY);
  }

  const openButton = getElementById(root, "open-session-proposal-modal");
  if (modalComponent && markDatasetReady(openButton, "bound")) {
    openButton.addEventListener("click", () => modalComponent.openCreate());
  }

  if (modalComponent) {
    bindSessionProposalButtons(root, '[data-action="edit-session-proposal"]', (button, sessionProposal) => {
      applyDescriptionHtml(button, sessionProposal);
      modalComponent.openEdit(sessionProposal);
    });

    const openView = (button, sessionProposal) => {
      applySpeakerDataset(button, sessionProposal);
      applyDescriptionHtml(button, sessionProposal);
      modalComponent.openView(sessionProposal);
    };
    bindSessionProposalButtons(root, '[data-action="view-session-proposal"]', openView);
    bindSessionProposalButtons(root, '[data-action="view-pending-session-proposal"]', openView);
  }

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
