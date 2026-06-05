import { handleHtmxResponse } from "/static/js/common/alerts.js";
import { isSuccessfulXHRStatus, toggleModalVisibility } from "/static/js/common/common.js";
import { closestElement, getElementById, isElementHidden, markDatasetReady } from "/static/js/common/dom.js";
import { isEscapeEvent } from "/static/js/common/keyboard.js";
import { collectQuestionAnswers, setQuestionAnswersInputValue } from "/static/js/common/question-answers.js";

const DATA_KEY = "userEventQuestionsReady";
const ACTIONS_DROPDOWN_SELECTOR = "[data-user-event-actions-dropdown]";

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

const closeActionDropdowns = (exceptDropdown = null) => {
  document.querySelectorAll(`${ACTIONS_DROPDOWN_SELECTOR}[open]`).forEach((dropdown) => {
    if (dropdown !== exceptDropdown) {
      dropdown.open = false;
    }
  });
};

const handleClick = (event) => {
  const actionsSummary = closestElement(event.target, `${ACTIONS_DROPDOWN_SELECTOR} > summary`);
  const actionsDropdown = actionsSummary?.closest(ACTIONS_DROPDOWN_SELECTOR);
  if (actionsDropdown instanceof HTMLDetailsElement && !actionsDropdown.open) {
    closeActionDropdowns(actionsDropdown);
  }

  if (!closestElement(event.target, ACTIONS_DROPDOWN_SELECTOR)) {
    closeActionDropdowns();
  }

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
