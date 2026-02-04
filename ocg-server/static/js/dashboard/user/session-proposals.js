import { handleHtmxResponse, showConfirmAlert } from "/static/js/common/alerts.js";
import "/static/js/dashboard/user/session-proposal-modal.js";

const MODAL_COMPONENT_ID = "session-proposal-modal-component";
const DATA_KEY = "sessionProposalReady";

const getModalComponent = () => document.getElementById(MODAL_COMPONENT_ID);

const parseSessionProposal = (payload) => {
  if (!payload) {
    return null;
  }

  try {
    return JSON.parse(payload);
  } catch (error) {
    console.error("Invalid proposal payload", error);
    return null;
  }
};

const initializeSessionProposals = () => {
  const modalComponent = getModalComponent();
  if (!modalComponent) {
    return;
  }

  if (modalComponent.dataset[DATA_KEY] !== "true") {
    modalComponent.dataset[DATA_KEY] = "true";
  }

  const openButton = document.getElementById("open-session-proposal-modal");
  if (openButton && openButton.dataset.bound !== "true") {
    openButton.dataset.bound = "true";
    openButton.addEventListener("click", () => modalComponent.openCreate());
  }

  document.querySelectorAll('[data-action="edit-session-proposal"]').forEach((button) => {
    if (button.dataset.bound === "true") {
      return;
    }

    button.dataset.bound = "true";
    button.addEventListener("click", () => {
      const sessionProposal = parseSessionProposal(button.dataset.sessionProposal);
      if (!sessionProposal) {
        return;
      }
      modalComponent.openEdit(sessionProposal);
    });
  });

  document.querySelectorAll('[data-action="view-session-proposal"]').forEach((button) => {
    if (button.dataset.bound === "true") {
      return;
    }

    button.dataset.bound = "true";
    button.addEventListener("click", () => {
      const sessionProposal = parseSessionProposal(button.dataset.sessionProposal);
      if (!sessionProposal) {
        return;
      }
      modalComponent.openView(sessionProposal);
    });
  });

  document.querySelectorAll('[data-action="delete-session-proposal"]').forEach((button) => {
    if (button.dataset.bound === "true") {
      return;
    }

    button.dataset.bound = "true";
    button.addEventListener("click", () => {
      if (button.disabled) {
        return;
      }

      if (!button.id) {
        button.id = `delete-session-proposal-${button.dataset.sessionProposalId}`;
      }
      showConfirmAlert("Delete this session proposal?", button.id, "Delete");
    });

    button.addEventListener("htmx:afterRequest", (event) => {
      handleHtmxResponse({
        xhr: event.detail?.xhr,
        successMessage: "",
        errorMessage: "Unable to delete this proposal. Please try again later.",
      });
    });
  });
};

initializeSessionProposals();

if (document.body) {
  document.body.addEventListener("htmx:load", initializeSessionProposals);
}
