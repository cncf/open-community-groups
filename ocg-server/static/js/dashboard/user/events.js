import { handleHtmxResponse } from "/static/js/common/alerts.js";
import { isSuccessfulXHRStatus, toggleModalVisibility } from "/static/js/common/common.js";

const getModal = (trigger) => {
  const modalId = trigger?.dataset?.userEventQuestionsModal;
  return modalId ? document.getElementById(modalId) : null;
};

const closeModal = (modal) => {
  if (modal instanceof HTMLElement && !modal.classList.contains("hidden")) {
    toggleModalVisibility(modal.id);
  }
};

const clearQuestionValidity = (form) => {
  form.querySelectorAll("[data-question-answer]").forEach((control) => {
    if (control instanceof HTMLInputElement || control instanceof HTMLTextAreaElement) {
      control.setCustomValidity("");
    }
  });
};

const setQuestionValidity = (fieldset, message) => {
  const control = fieldset.querySelector("[data-question-answer]");
  if (control instanceof HTMLInputElement || control instanceof HTMLTextAreaElement) {
    control.setCustomValidity(message);
  }
};

const collectAnswers = (form) => {
  clearQuestionValidity(form);
  const answers = [];

  form.querySelectorAll("[data-question-id]").forEach((fieldset) => {
    if (!(fieldset instanceof HTMLFieldSetElement)) {
      return;
    }

    const questionId = fieldset.dataset.questionId;
    const kind = fieldset.dataset.questionKind;
    const required = fieldset.dataset.questionRequired === "true";
    if (!questionId || !kind) {
      return;
    }

    if (kind === "free-text") {
      const input = fieldset.querySelector("[data-question-answer]");
      if (!(input instanceof HTMLTextAreaElement)) {
        return;
      }

      const value = input.value.trim();
      if (value || required) {
        answers.push({ question_id: questionId, value });
      }
      return;
    }

    if (kind === "single-select") {
      const selected = fieldset.querySelector("[data-question-answer]:checked");
      if (selected instanceof HTMLInputElement) {
        answers.push({ question_id: questionId, value: selected.value });
      }
      return;
    }

    const values = Array.from(fieldset.querySelectorAll("[data-question-answer]:checked"))
      .filter((input) => input instanceof HTMLInputElement)
      .map((input) => input.value);
    if (values.length > 0 || required) {
      answers.push({ question_id: questionId, value: values });
    }
    if (required && values.length === 0) {
      setQuestionValidity(fieldset, "Select at least one option.");
    }
  });

  if (!form.reportValidity()) {
    return false;
  }

  const input = form.querySelector("[data-question-answers-input]");
  if (input instanceof HTMLInputElement) {
    input.value = JSON.stringify({ answers });
  }
  return true;
};

const handleClick = (event) => {
  const target = event.target instanceof Element ? event.target : null;
  const trigger = target?.closest("[data-user-event-questions-open]");
  if (trigger instanceof HTMLElement) {
    const modal = getModal(trigger);
    if (modal instanceof HTMLElement && modal.classList.contains("hidden")) {
      toggleModalVisibility(modal.id);
    }
    return;
  }

  const closeTrigger = target?.closest("[data-user-event-questions-close]");
  if (closeTrigger instanceof HTMLElement) {
    closeModal(closeTrigger.closest("[data-user-event-questions-modal]"));
  }
};

const handleSubmit = (event) => {
  const form = event.target;
  if (!(form instanceof HTMLFormElement) || !form.matches("[data-user-event-questions-form]")) {
    return;
  }

  if (!collectAnswers(form)) {
    event.preventDefault();
    event.stopPropagation();
  }
};

const handleAfterRequest = (event) => {
  const form = event.target;
  if (!(form instanceof HTMLFormElement) || !form.matches("[data-user-event-questions-form]")) {
    return;
  }

  const ok = handleHtmxResponse({
    xhr: event.detail?.xhr,
    successMessage: "Registration answers saved.",
    errorMessage: "Something went wrong saving your answers. Please try again later.",
  });
  if (ok || isSuccessfulXHRStatus(event.detail?.xhr?.status)) {
    closeModal(form.closest("[data-user-event-questions-modal]"));
  }
};

const handleKeydown = (event) => {
  if (event.key !== "Escape") {
    return;
  }

  document.querySelectorAll("[data-user-event-questions-modal]").forEach((modal) => {
    closeModal(modal);
  });
};

document.addEventListener("click", handleClick);
document.addEventListener("submit", handleSubmit, true);
document.addEventListener("htmx:afterRequest", handleAfterRequest);
document.addEventListener("keydown", handleKeydown);
