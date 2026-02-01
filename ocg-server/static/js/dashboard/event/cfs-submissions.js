import { toggleModalVisibility } from "/static/js/common/common.js";
import { handleHtmxResponse } from "/static/js/common/alerts.js";

const MODAL_ID = "cfs-submission-modal";
const DATA_KEY = "cfsSubmissionReady";

const initializeCfsSubmissions = () => {
  const modal = document.getElementById(MODAL_ID);
  if (!modal) {
    return;
  }

  if (modal.dataset[DATA_KEY] !== "true") {
    modal.dataset[DATA_KEY] = "true";

    const closeButton = modal.querySelector("#close-cfs-submission-modal");
    const cancelButton = modal.querySelector("#cfs-submission-cancel");
    const overlay = modal.querySelector("#overlay-cfs-submission-modal");
    const toggleModal = () => toggleModalVisibility(MODAL_ID);

    closeButton?.addEventListener("click", toggleModal);
    cancelButton?.addEventListener("click", toggleModal);
    overlay?.addEventListener("click", toggleModal);
  }

  const form = modal.querySelector("#cfs-submission-form");
  const statusSelect = modal.querySelector("#cfs-submission-status");
  const messageInput = modal.querySelector("#cfs-submission-message");
  const speakerName = modal.querySelector("#cfs-submission-speaker-name");
  const speakerUsername = modal.querySelector("#cfs-submission-speaker-username");
  const proposalTitle = modal.querySelector("#cfs-submission-proposal-title");
  const proposalMeta = modal.querySelector("#cfs-submission-proposal-meta");
  const proposalDescription = modal.querySelector("#cfs-submission-proposal-description");
  const coSpeakerBlock = modal.querySelector("#cfs-submission-co-speaker");
  const coSpeakerName = modal.querySelector("#cfs-submission-co-speaker-name");

  const eventId = modal.dataset.eventId;

  const setDetails = (submission) => {
    if (!submission) {
      return;
    }
    if (speakerName) {
      speakerName.textContent = submission.speaker?.name || submission.speaker?.username || "";
    }
    if (speakerUsername) {
      speakerUsername.textContent = submission.speaker?.username ? `@${submission.speaker.username}` : "";
    }
    if (proposalTitle) {
      proposalTitle.textContent = submission.session_proposal?.title || "";
    }
    if (proposalMeta) {
      const meta = [];
      if (submission.session_proposal?.session_proposal_level_name) {
        meta.push(submission.session_proposal.session_proposal_level_name);
      }
      if (submission.session_proposal?.duration_minutes) {
        meta.push(`${submission.session_proposal.duration_minutes} min`);
      }
      proposalMeta.textContent = meta.join(" · ");
    }
    if (proposalDescription) {
      proposalDescription.textContent = submission.session_proposal?.description || "";
    }

    const coSpeaker = submission.session_proposal?.co_speaker;
    if (coSpeaker && coSpeakerName && coSpeakerBlock) {
      const name = coSpeaker.name || coSpeaker.username;
      coSpeakerName.textContent = `${name} (@${coSpeaker.username})`;
      coSpeakerBlock.classList.remove("hidden");
    } else if (coSpeakerBlock) {
      coSpeakerBlock.classList.add("hidden");
    }

    if (statusSelect) {
      statusSelect.value = submission.status_id || "";
    }
    if (messageInput) {
      messageInput.value = submission.action_required_message || "";
    }

    if (form && eventId && submission.cfs_submission_id) {
      form.setAttribute(
        "hx-put",
        `/dashboard/group/events/${eventId}/submissions/${submission.cfs_submission_id}`,
      );
      if (window.htmx && typeof window.htmx.process === "function") {
        window.htmx.process(form);
      }
    }
  };

  document.querySelectorAll('[data-action="open-cfs-submission-modal"]').forEach((button) => {
    if (button.dataset.bound === "true") {
      return;
    }
    button.dataset.bound = "true";
    button.addEventListener("click", () => {
      const payload = button.dataset.submission;
      if (!payload) {
        return;
      }
      try {
        const submission = JSON.parse(payload);
        setDetails(submission);
        toggleModalVisibility(MODAL_ID);
      } catch (error) {
        console.error("Invalid submission payload", error);
      }
    });
  });

  if (form && form.dataset.bound !== "true") {
    form.dataset.bound = "true";
    form.addEventListener("htmx:afterRequest", (event) => {
      const ok = handleHtmxResponse({
        xhr: event.detail?.xhr,
        successMessage: "",
        errorMessage: "Unable to update this submission. Please try again later.",
      });
      if (ok) {
        toggleModalVisibility(MODAL_ID);
      }
    });
  }
};

initializeCfsSubmissions();

if (document.body) {
  document.body.addEventListener("htmx:load", initializeCfsSubmissions);
}
