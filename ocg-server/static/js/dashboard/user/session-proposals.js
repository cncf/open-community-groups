import { toggleModalVisibility } from "/static/js/common/common.js";
import { handleHtmxResponse, showConfirmAlert } from "/static/js/common/alerts.js";
import "/static/js/common/user-search-field.js";

const MODAL_ID = "session-proposal-modal";
const DATA_KEY = "sessionProposalReady";

const initializeSessionProposals = () => {
  const modal = document.getElementById(MODAL_ID);
  if (!modal) {
    return;
  }

  if (modal.dataset[DATA_KEY] !== "true") {
    modal.dataset[DATA_KEY] = "true";

    const closeButton = modal.querySelector("#close-session-proposal-modal");
    const cancelButton = modal.querySelector("#session-proposal-cancel");
    const overlay = modal.querySelector("#overlay-session-proposal-modal");
    const toggleModal = () => toggleModalVisibility(MODAL_ID);

    closeButton?.addEventListener("click", toggleModal);
    cancelButton?.addEventListener("click", toggleModal);
    overlay?.addEventListener("click", toggleModal);
  }

  const form = modal.querySelector("#session-proposal-form");
  const titleInput = modal.querySelector("#session-proposal-title");
  const levelSelect = modal.querySelector("#session-proposal-level");
  const durationInput = modal.querySelector("#session-proposal-duration");
  const coSpeakerInput = modal.querySelector("#session-proposal-co-speaker");
  const coSpeakerPreview = modal.querySelector("#session-proposal-co-speaker-preview");
  const coSpeakerSearch = modal.querySelector("#session-proposal-co-speaker-search");
  const submitButton = modal.querySelector("#session-proposal-submit");
  const modalTitle = modal.querySelector("#session-proposal-modal-title");

  const updateMarkdownContent = (value) => {
    const editor = modal.querySelector("markdown-editor#session-proposal-description");
    if (!editor) {
      return;
    }
    const textarea = editor.querySelector("textarea");
    if (textarea) {
      textarea.value = value || "";
      textarea.dispatchEvent(new Event("input", { bubbles: true }));
    }
  };

  const renderCoSpeaker = (user) => {
    if (!coSpeakerPreview) {
      return;
    }
    if (!user) {
      coSpeakerPreview.innerHTML = "";
      return;
    }
    const name = user.name || user.username;
    coSpeakerPreview.innerHTML = `
      <div class="inline-flex items-center gap-2 bg-stone-100 rounded-full px-3 py-1">
        <span class="text-sm text-stone-700">${name}</span>
        <button type="button" class="p-1 hover:bg-stone-200 rounded-full" aria-label="Remove co-speaker">
          <div class="svg-icon size-3 icon-close bg-stone-600"></div>
        </button>
      </div>
    `;
    const removeButton = coSpeakerPreview.querySelector("button");
    removeButton?.addEventListener("click", () => setCoSpeaker(null));
  };

  const setCoSpeaker = (user) => {
    if (coSpeakerInput) {
      coSpeakerInput.value = user?.user_id || "";
    }
    if (coSpeakerSearch) {
      coSpeakerSearch.excludeUsernames = user ? [user.username] : [];
    }
    renderCoSpeaker(user);
  };

  const resetForm = () => {
    form?.reset();
    updateMarkdownContent("");
    setCoSpeaker(null);
    if (form) {
      form.setAttribute("hx-post", "/dashboard/user/session-proposals");
      form.removeAttribute("hx-put");
    }
    if (submitButton) {
      submitButton.textContent = "Save";
    }
    if (modalTitle) {
      modalTitle.textContent = "New session proposal";
    }
  };

  const openForEdit = (sessionProposal) => {
    if (!sessionProposal || !form) {
      return;
    }
    if (titleInput) {
      titleInput.value = sessionProposal.title || "";
    }
    if (levelSelect) {
      levelSelect.value = sessionProposal.session_proposal_level_id || "";
    }
    if (durationInput) {
      durationInput.value = sessionProposal.duration_minutes ?? "";
    }
    updateMarkdownContent(sessionProposal.description || "");
    setCoSpeaker(sessionProposal.co_speaker || null);

    form.setAttribute("hx-put", `/dashboard/user/session-proposals/${sessionProposal.session_proposal_id}`);
    form.removeAttribute("hx-post");

    if (submitButton) {
      submitButton.textContent = "Update";
    }
    if (modalTitle) {
      modalTitle.textContent = "Edit session proposal";
    }
  };

  const openModal = (sessionProposal = null) => {
    if (sessionProposal) {
      openForEdit(sessionProposal);
    } else {
      resetForm();
    }
    toggleModalVisibility(MODAL_ID);
  };

  const openButton = document.getElementById("open-session-proposal-modal");
  if (openButton && openButton.dataset.bound !== "true") {
    openButton.dataset.bound = "true";
    openButton.addEventListener("click", () => openModal());
  }

  document.querySelectorAll('[data-action="edit-session-proposal"]').forEach((button) => {
    if (button.dataset.bound === "true") {
      return;
    }
    button.dataset.bound = "true";
    button.addEventListener("click", () => {
      const sessionProposalPayload = button.dataset.sessionProposal;
      if (!sessionProposalPayload) {
        return;
      }
      try {
        const sessionProposal = JSON.parse(sessionProposalPayload);
        openModal(sessionProposal);
      } catch (error) {
        console.error("Invalid proposal payload", error);
      }
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

  if (form && form.dataset.bound !== "true") {
    form.dataset.bound = "true";
    form.addEventListener("htmx:afterRequest", (event) => {
      const ok = handleHtmxResponse({
        xhr: event.detail?.xhr,
        successMessage: "",
        errorMessage: "Unable to save this proposal. Please try again later.",
      });
      if (ok) {
        toggleModalVisibility(MODAL_ID);
      }
    });
  }

  if (coSpeakerSearch && coSpeakerSearch.dataset.bound !== "true") {
    coSpeakerSearch.dataset.bound = "true";
    coSpeakerSearch.addEventListener("user-selected", (event) => {
      const user = event.detail?.user;
      if (!user) {
        return;
      }
      setCoSpeaker(user);
    });
  }
};

initializeSessionProposals();

if (document.body) {
  document.body.addEventListener("htmx:load", initializeSessionProposals);
}
