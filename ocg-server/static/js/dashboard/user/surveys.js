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
// Button that opens a survey from its row in the surveys list.
const SURVEY_OPEN_SELECTOR = "[data-user-event-survey-open]";
// Hidden element that reloads the dashboard layout after answers are saved.
const SURVEYS_REFRESH_SELECTOR = "[data-user-surveys-refresh]";
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

// Id of the survey whose open button takes focus once the saved answers
// reload the dashboard layout.
let pendingFocusSurveyId = null;
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
    toggleModalVisibility(modal);
  }
  clearRequestedSurvey();
};

/**
 * Moves focus to the open button of the survey just answered once the saved
 * answers reload the dashboard layout, as the reload replaces the button the
 * closed modal returned focus to.
 * @param {CustomEvent} event HTMX load event.
 * @returns {void}
 */
const focusAnsweredSurvey = (event) => {
  const loaded = event.target;
  if (pendingFocusSurveyId === null || !(loaded instanceof Element)) {
    return;
  }
  if (!loaded.matches(SURVEYS_REFRESH_SELECTOR) && !loaded.querySelector(SURVEYS_REFRESH_SELECTOR)) {
    return;
  }

  const row = loaded.querySelector(`[data-user-event-survey="${CSS.escape(pendingFocusSurveyId)}"]`);
  pendingFocusSurveyId = null;
  const button = row?.querySelector(SURVEY_OPEN_SELECTOR);
  if (button instanceof HTMLElement) {
    button.focus();
  }
};

/**
 * Reports the survey answers request, closing the modal once they are saved
 * and keeping it open to retry after errors. A failed layout reload drops
 * the focus pending for it.
 * @param {CustomEvent} event HTMX after-request event.
 * @returns {void}
 */
const handleAfterRequest = (event) => {
  const target = event.target;
  if (target instanceof Element && target.matches(SURVEYS_REFRESH_SELECTOR)) {
    if (!event.detail?.successful) {
      pendingFocusSurveyId = null;
    }
    return;
  }
  if (!(target instanceof HTMLFormElement) || !target.matches(SURVEY_FORM_SELECTOR)) {
    return;
  }

  const ok = handleHtmxResponse({
    xhr: event.detail?.xhr,
    successMessage: "Survey answers saved.",
    errorMessage: "Something went wrong saving your answers. Please try again later.",
  });
  if (ok) {
    pendingFocusSurveyId = target.dataset.userEventSurveyForm || null;
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
  document.addEventListener("htmx:load", focusAnsweredSurvey);
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
