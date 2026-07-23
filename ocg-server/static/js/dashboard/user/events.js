import "/static/js/common/actions-menu.js";
import { handleHtmxResponse } from "/static/js/common/alerts.js";
import { closestElement, getElementById, isElementHidden, markDatasetReady } from "/static/js/common/dom.js";
import { isEscapeEvent } from "/static/js/common/keyboard.js";
import { toggleModalVisibility } from "/static/js/common/modals/modal-lifecycle.js";
import { collectQuestionAnswers, setQuestionAnswersInputValue } from "/static/js/common/question-answers.js";
import { isSuccessfulXHRStatus } from "/static/js/common/utils.js";

const DATA_KEY = "userEventQuestionsReady";

/**
 * Finds the question modal targeted by an open trigger.
 * @param {HTMLElement|null} trigger Modal open trigger
 * @returns {HTMLElement|null} Target modal
 */
const getModal = (trigger) => {
  const modalId = trigger?.dataset?.userEventQuestionsModal;
  return modalId ? getElementById(document, modalId) : null;
};

const closeModal = (modal) => {
  if (modal instanceof HTMLElement && !isElementHidden(modal)) {
    toggleModalVisibility(modal.id);
  }
};

const handleClick = (event) => {
  const trigger = closestElement(event.target, "[data-user-event-questions-open]");
  if (trigger instanceof HTMLElement) {
    const modal = getModal(trigger);
    if (modal instanceof HTMLElement && isElementHidden(modal)) {
      toggleModalVisibility(modal.id);
    }
    return;
  }

  const closeTrigger = closestElement(event.target, "[data-user-event-questions-close]");
  if (closeTrigger instanceof HTMLElement) {
    closeModal(closeTrigger.closest("[data-user-event-questions-modal]"));
  }
};

const handleSubmit = (event) => {
  const form = event.target;
  if (!(form instanceof HTMLFormElement) || !form.matches("[data-user-event-questions-form]")) {
    return;
  }

  const answersPayload = collectQuestionAnswers(form, {
    answerSelector: "[data-question-answer]",
  });
  if (!answersPayload) {
    event.preventDefault();
    event.stopPropagation();
    return;
  }

  setQuestionAnswersInputValue(form, "[data-question-answers-input]", answersPayload);
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
  if (!isEscapeEvent(event)) {
    return;
  }

  document.querySelectorAll("[data-user-event-questions-modal]").forEach((modal) => {
    closeModal(modal);
  });
};

const initializeUserEventQuestions = () => {
  if (!markDatasetReady(document.documentElement, DATA_KEY)) {
    return;
  }

  document.addEventListener("click", handleClick);
  document.addEventListener("submit", handleSubmit, true);
  document.addEventListener("htmx:afterRequest", handleAfterRequest);
  document.addEventListener("keydown", handleKeydown);
};

initializeUserEventQuestions();
