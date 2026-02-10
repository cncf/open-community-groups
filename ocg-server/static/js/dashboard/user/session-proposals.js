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

const applyDescriptionHtml = (button, sessionProposal) => {
  const payload = button?.dataset?.proposalDescriptionHtml;
  if (!payload || !sessionProposal) {
    return;
  }

  try {
    const descriptionHtml = JSON.parse(payload);
    if (typeof descriptionHtml === "string") {
      sessionProposal.description_html = descriptionHtml;
    }
  } catch (error) {
    console.error("Invalid proposal description html payload", error);
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
      applyDescriptionHtml(button, sessionProposal);
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
      applyDescriptionHtml(button, sessionProposal);
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
      showConfirmAlert("Are you sure you want to delete this session proposal?", button.id, "Delete");
    });

    button.addEventListener("htmx:afterRequest", (event) => {
      handleHtmxResponse({
        xhr: event.detail?.xhr,
        successMessage: "",
        errorMessage: "Unable to delete this proposal. Please try again later.",
      });
    });
  });

  document.querySelectorAll('[data-action="accept-co-speaker-invitation"]').forEach((button) => {
    if (button.dataset.bound === "true") {
      return;
    }

    button.dataset.bound = "true";
    button.addEventListener("htmx:afterRequest", (event) => {
      handleHtmxResponse({
        xhr: event.detail?.xhr,
        successMessage: "",
        errorMessage: "Unable to accept this invitation. Please try again later.",
      });
    });
  });

  document.querySelectorAll('[data-action="reject-co-speaker-invitation"]').forEach((button) => {
    if (button.dataset.bound === "true") {
      return;
    }

    button.dataset.bound = "true";
    button.addEventListener("click", () => {
      if (button.disabled) {
        return;
      }

      if (!button.id) {
        button.id = `reject-co-speaker-invitation-${button.dataset.sessionProposalId}`;
      }

      showConfirmAlert("Are you sure you want to decline this co-speaker invitation?", button.id, "Decline");
    });

    button.addEventListener("htmx:afterRequest", (event) => {
      handleHtmxResponse({
        xhr: event.detail?.xhr,
        successMessage: "",
        errorMessage: "Unable to decline this invitation. Please try again later.",
      });
    });
  });
};

initializeSessionProposals();

if (document.body) {
  document.body.addEventListener("htmx:load", initializeSessionProposals);
}
