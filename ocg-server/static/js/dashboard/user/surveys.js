import { confirmAction, handleHtmxResponse } from "/static/js/common/alerts.js";
import {
  closestElement,
  getElementById,
  initializeMatchingRoots,
  initializeOnReadyAndHtmxLoad,
  isElementHidden,
  markDatasetReady,
} from "/static/js/common/dom.js";
import { isEscapeEvent } from "/static/js/common/keyboard.js";
import { toggleModalVisibility, trapModalFocus } from "/static/js/common/modals/modal-lifecycle.js";
import { collectQuestionAnswers, setQuestionAnswersInputValue } from "/static/js/common/question-answers.js";

// Dataset key marking the user surveys dashboard as initialized.
const DATA_KEY = "userSurveysReady";
// Query parameter the survey email links use to open a survey.
const REQUESTED_SURVEY_PARAM = "event_survey_id";
// Survey answer form rendered inside the survey modal.
const SURVEY_FORM_SELECTOR = "[data-user-event-survey-form]";
// Container the survey modal content is loaded into.
const SURVEY_MODAL_CONTENT_ID = "user-event-survey-modal-content";
// Survey modal.
const SURVEY_MODAL_ID = "user-event-survey-modal";
// Survey modal rendered to open as soon as the page loads.
const SURVEY_OPEN_ON_LOAD_SELECTOR = "[data-user-event-survey-modal][data-open-on-load]";
// Confirmation shown before closing the survey modal discards answers.
const UNSAVED_SURVEY_ANSWERS_MESSAGE =
  "You have unsaved answers. If you close the survey, they will be lost.";

// Whether the confirmation to discard survey answers is showing.
let surveyCloseConfirmationOpen = false;

/**
 * Opens the survey modal rendered with a survey, as when an opening email
 * links to it.
 * @param {Document|Element} root Dashboard content root.
 * @returns {void}
 */
export const initializeUserSurveyModal = (root = document) => {
  initializeMatchingRoots(root, SURVEY_OPEN_ON_LOAD_SELECTOR, (modal) => {
    if (markDatasetReady(modal, "openOnLoadReady") && isElementHidden(modal)) {
      toggleModalVisibility(modal);
    }
  });
};

/**
 * Removes the survey requested by an opening email link from the address bar,
 * so reloading the page does not open the survey again.
 * @returns {void}
 */
const clearRequestedSurvey = () => {
  const url = new URL(window.location.href);
  if (!url.searchParams.has(REQUESTED_SURVEY_PARAM)) {
    return;
  }

  url.searchParams.delete(REQUESTED_SURVEY_PARAM);
  window.history.replaceState(window.history.state, "", `${url.pathname}${url.search}${url.hash}`);
};

/**
 * Closes the survey modal and forgets the survey requested by the URL.
 * @returns {void}
 */
const closeSurveyModal = () => {
  const modal = getElementById(document, SURVEY_MODAL_ID);
  if (modal instanceof HTMLElement && !isElementHidden(modal)) {
    toggleModalVisibility(modal.id);
  }
  clearRequestedSurvey();
};

/**
 * Reports the survey answers request, closing the modal once they are saved
 * and keeping it open to retry after errors.
 * @param {CustomEvent} event HTMX after-request event.
 * @returns {void}
 */
const handleAfterRequest = (event) => {
  const target = event.target;
  if (!(target instanceof HTMLFormElement) || !target.matches(SURVEY_FORM_SELECTOR)) {
    return;
  }

  const ok = handleHtmxResponse({
    xhr: event.detail?.xhr,
    successMessage: "Survey answers saved.",
    errorMessage: "Something went wrong saving your answers. Please try again later.",
  });
  if (ok) {
    closeSurveyModal();
  }
};

/**
 * Opens the survey modal once its content is loaded.
 * @param {CustomEvent} event HTMX after-swap event.
 * @returns {void}
 */
const handleAfterSwap = (event) => {
  if (event.detail?.target?.id !== SURVEY_MODAL_CONTENT_ID) {
    return;
  }

  const modal = getElementById(document, SURVEY_MODAL_ID);
  if (modal instanceof HTMLElement && isElementHidden(modal)) {
    toggleModalVisibility(modal, event.detail?.requestConfig?.elt ?? null);
  }
};

/**
 * Closes the survey modal from its close controls.
 * @param {MouseEvent} event Click event.
 * @returns {void}
 */
const handleClick = (event) => {
  if (closestElement(event.target, "[data-user-event-survey-close]")) {
    void requestSurveyModalClose();
  }
};

/**
 * Keeps Tab navigation inside the open survey modal and closes it on Escape.
 * Keys are left to the discard confirmation while it shows.
 * @param {KeyboardEvent} event Keydown event.
 * @returns {void}
 */
const handleKeydown = (event) => {
  if (surveyCloseConfirmationOpen) {
    return;
  }

  const modal = getElementById(document, SURVEY_MODAL_ID);
  if (!(modal instanceof HTMLElement) || isElementHidden(modal)) {
    return;
  }

  if (event.key === "Tab") {
    trapModalFocus(event, modal);
    return;
  }

  if (isEscapeEvent(event)) {
    void requestSurveyModalClose();
  }
};

/**
 * Validates and serializes survey answers before HTMX serializes the form.
 *
 * Runs in the capture phase on the document, so invalid answers stop the
 * submission before it reaches the HTMX submit handler of the form.
 * @param {SubmitEvent} event Submit event.
 * @returns {void}
 */
const handleSubmit = (event) => {
  const form = event.target;
  if (!(form instanceof HTMLFormElement) || !form.matches(SURVEY_FORM_SELECTOR)) {
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
 * Checks whether the survey answer form differs from the answers it loaded with.
 * @param {Element|null} form Survey answer form.
 * @returns {boolean} True when an answer was changed.
 */
const hasUnsavedSurveyAnswers = (form) => {
  if (!(form instanceof HTMLFormElement)) {
    return false;
  }

  return Array.from(form.querySelectorAll("[data-question-answer]")).some((field) => {
    if (field instanceof HTMLInputElement && (field.type === "checkbox" || field.type === "radio")) {
      return field.checked !== field.defaultChecked;
    }
    if (field instanceof HTMLInputElement || field instanceof HTMLTextAreaElement) {
      return field.value !== field.defaultValue;
    }
    return false;
  });
};

/**
 * Registers the document listeners once.
 * @returns {void}
 */
const initializeUserSurveys = () => {
  if (!markDatasetReady(document.documentElement, DATA_KEY)) {
    return;
  }

  document.addEventListener("click", handleClick);
  document.addEventListener("submit", handleSubmit, true);
  document.addEventListener("htmx:afterRequest", handleAfterRequest);
  document.addEventListener("htmx:afterSwap", handleAfterSwap);
  document.addEventListener("keydown", handleKeydown);
};

/**
 * Closes the survey modal, asking first when answers would be discarded.
 * @returns {Promise<void>}
 */
const requestSurveyModalClose = async () => {
  if (surveyCloseConfirmationOpen) {
    return;
  }

  // Ask before discarding changed answers
  const modal = getElementById(document, SURVEY_MODAL_ID);
  if (hasUnsavedSurveyAnswers(modal?.querySelector(SURVEY_FORM_SELECTOR) ?? null)) {
    surveyCloseConfirmationOpen = true;
    let confirmed = false;
    try {
      confirmed = await confirmAction({
        message: UNSAVED_SURVEY_ANSWERS_MESSAGE,
        confirmText: "Discard answers",
        cancelText: "Keep answering",
      });
    } finally {
      surveyCloseConfirmationOpen = false;
    }
    if (!confirmed) {
      return;
    }
  }

  closeSurveyModal();
};

initializeUserSurveys();
initializeOnReadyAndHtmxLoad(initializeUserSurveyModal);
