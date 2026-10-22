import "/static/js/common/actions-menu.js";
import { handleHtmxResponse } from "/static/js/common/alerts.js";
import {
  closestElement,
  getElementById,
  initializeMatchingRoots,
  initializeOnReadyAndHtmxLoad,
  isElementHidden,
  markDatasetReady,
  setElementHidden,
} from "/static/js/common/dom.js";
import { ocgFetch } from "/static/js/common/fetch.js";
import { isEscapeEvent } from "/static/js/common/keyboard.js";
import { toggleModalVisibility } from "/static/js/common/modals/modal-lifecycle.js";
import { collectQuestionAnswers, setQuestionAnswersInputValue } from "/static/js/common/question-answers.js";
import { isSuccessfulXHR } from "/static/js/common/utils.js";

// Dataset key marking the user events dashboard as initialized.
const DATA_KEY = "userEventsReady";
// Registration questions answer form.
const QUESTIONS_FORM_SELECTOR = "[data-user-event-questions-form]";
// Registration questions modal.
const QUESTIONS_MODAL_SELECTOR = "[data-user-event-questions-modal]";
// Paid event rows whose refund eligibility is loaded on demand.
const REFUND_ACTION_SELECTOR = "[data-user-event-refund-action]";

/**
 * Loads exact refund eligibility for paid rows in the current dashboard fragment.
 * @param {Document|Element} root Dashboard content root.
 * @returns {void}
 */
export const initializeUserEventRefundActions = (root = document) => {
  initializeMatchingRoots(root, REFUND_ACTION_SELECTOR, (action) => {
    void loadRefundActionEligibility(action);
  });
};

/**
 * Closes an open dashboard modal.
 * @param {Element|null} modal Modal element.
 * @returns {void}
 */
const closeModal = (modal) => {
  if (modal instanceof HTMLElement && !isElementHidden(modal)) {
    toggleModalVisibility(modal.id);
  }
};

/**
 * Finds the question modal targeted by an open trigger.
 * @param {HTMLElement|null} trigger Modal open trigger
 * @returns {HTMLElement|null} Target modal
 */
const getQuestionsModal = (trigger) => {
  const modalId = trigger?.dataset?.userEventQuestionsModal;
  return modalId ? getElementById(document, modalId) : null;
};

/**
 * Handles HTMX request results of the checkout and registration answers
 * actions.
 * @param {CustomEvent} event HTMX after-request event.
 * @returns {void}
 */
const handleAfterRequest = (event) => {
  const target = event.target;
  if (closestElement(target, "[data-user-event-checkout-cancel]")) {
    // Shared confirmation handling owns feedback for this action.
    if (isSuccessfulXHR(event.detail?.xhr)) {
      window.htmx?.trigger?.("#dashboard-content", "refresh-user-dashboard-content");
    }
    return;
  }

  if (!(target instanceof HTMLFormElement)) {
    return;
  }

  // Report registration answers
  if (!target.matches(QUESTIONS_FORM_SELECTOR)) {
    return;
  }

  const ok = handleHtmxResponse({
    xhr: event.detail?.xhr,
    successMessage: "Registration answers saved.",
    errorMessage: "Something went wrong saving your answers. Please try again later.",
  });
  if (ok || isSuccessfulXHR(event.detail?.xhr)) {
    closeModal(target.closest(QUESTIONS_MODAL_SELECTOR));
  }
};

/**
 * Opens and closes the registration questions modals.
 * @param {MouseEvent} event Click event.
 * @returns {void}
 */
const handleClick = (event) => {
  const trigger = closestElement(event.target, "[data-user-event-questions-open]");
  if (trigger instanceof HTMLElement) {
    const modal = getQuestionsModal(trigger);
    if (modal instanceof HTMLElement && isElementHidden(modal)) {
      toggleModalVisibility(modal.id);
    }
    return;
  }

  const closeTrigger = closestElement(event.target, "[data-user-event-questions-close]");
  if (closeTrigger instanceof HTMLElement) {
    closeModal(closeTrigger.closest(QUESTIONS_MODAL_SELECTOR));
  }
};

/**
 * Closes the open registration questions modals on Escape.
 * @param {KeyboardEvent} event Keydown event.
 * @returns {void}
 */
const handleKeydown = (event) => {
  if (!isEscapeEvent(event)) {
    return;
  }

  document.querySelectorAll(QUESTIONS_MODAL_SELECTOR).forEach((modal) => {
    closeModal(modal);
  });
};

/**
 * Validates and serializes registration answers before HTMX serializes the
 * form.
 *
 * Runs in the capture phase on the document, so invalid answers stop the
 * submission before it reaches the HTMX submit handler of the form.
 * @param {SubmitEvent} event Submit event.
 * @returns {void}
 */
const handleSubmit = (event) => {
  const form = event.target;
  if (!(form instanceof HTMLFormElement) || !form.matches(QUESTIONS_FORM_SELECTOR)) {
    return;
  }

  // Block submissions with incomplete required answers
  const answersPayload = collectQuestionAnswers(form, {
    answerSelector: "[data-question-answer]",
  });
  if (!answersPayload) {
    event.preventDefault();
    event.stopPropagation();
    return;
  }

  // Send the answers as the JSON payload the server expects
  setQuestionAnswersInputValue(form, "[data-question-answers-input]", answersPayload);
};

/**
 * Registers the document listeners once.
 * @returns {void}
 */
const initializeUserEvents = () => {
  if (!markDatasetReady(document.documentElement, DATA_KEY)) {
    return;
  }

  document.addEventListener("click", handleClick);
  document.addEventListener("submit", handleSubmit, true);
  document.addEventListener("htmx:afterRequest", handleAfterRequest);
  document.addEventListener("keydown", handleKeydown);
};

/**
 * Shows a refund action only when the enrollment endpoint confirms eligibility.
 * @param {Element} action Refund action wrapper.
 * @returns {Promise<void>}
 */
const loadRefundActionEligibility = async (action) => {
  if (!(action instanceof HTMLElement) || !markDatasetReady(action, "refundEligibilityReady")) {
    return;
  }

  const enrollmentUrl = action.dataset.enrollmentUrl;
  if (!enrollmentUrl) {
    return;
  }

  try {
    const response = await ocgFetch(enrollmentUrl, {
      cache: "no-store",
      credentials: "same-origin",
      headers: { Accept: "application/json" },
    });
    if (!response.ok) {
      return;
    }

    const enrollment = await response.json();
    if (action.isConnected) {
      setElementHidden(action, enrollment?.can_request_refund !== true);
    }
  } catch (_) {
    setElementHidden(action, true);
  }
};

initializeUserEvents();
initializeOnReadyAndHtmxLoad(initializeUserEventRefundActions);
