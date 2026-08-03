import { isDatasetReady, markDatasetReady } from "/static/js/common/dom.js";
import { collectQuestionAnswers as collectQuestionAnswersFromForm } from "/static/js/common/question-answers.js";
import {
  getAttendanceContainer,
  getAttendanceControl,
  getAttendanceMeta,
} from "/static/js/event/attendance-dom.js";
import {
  closeQuestionsModal,
  closeTicketModal,
  openQuestionsModal,
  openTicketModal,
} from "/static/js/event/attendance-view.js";
import {
  QUESTIONS_CONTINUE_ACTION_ATTEND,
  QUESTIONS_CONTINUE_ACTION_TICKET,
} from "/static/js/event/attendance/shared.js";

/**
 * Opens questions before continuing with attendance or ticket checkout.
 * @param {HTMLElement} container - Attendance container element
 * @param {"attend"|"ticket"} continueAction - Action to resume after questions
 * @returns {void}
 */
export const requestQuestionAnswers = (container, continueAction) => {
  container.dataset.questionsContinueAction = continueAction;
  if (continueAction === QUESTIONS_CONTINUE_ACTION_TICKET) {
    closeTicketModal(container);
  }
  openQuestionsModal(container);
};

/**
 * Blocks attend requests until required registration questions are answered.
 * @param {Event} event - htmx:beforeRequest event
 * @param {HTMLElement} target - Event target
 * @param {HTMLElement} container - Attendance container element
 * @returns {boolean} True when the request was blocked
 */
export const blockAttendanceRequestForQuestions = (event, target, container) => {
  const meta = getAttendanceMeta(container);
  if (!shouldCollectQuestionAnswers(container)) {
    return false;
  }

  if (target.dataset.attendanceRole === "attend-btn") {
    if (
      meta.ticketModalRequired ||
      (isWaitlistJoinAction(meta) && !isCompletingRegistrationQuestions(target))
    ) {
      return false;
    }

    event.preventDefault();
    requestQuestionAnswers(container, QUESTIONS_CONTINUE_ACTION_ATTEND);
    return true;
  }

  if (target.dataset.attendanceRole === "checkout-form") {
    const selectedTicketType = target.querySelector('[data-attendance-role="ticket-type-option"]:checked');
    const isRequest = meta.attendeeApprovalRequired;
    const isWaitlist =
      selectedTicketType instanceof HTMLInputElement && selectedTicketType.dataset.ticketSoldOut === "true";
    if (!isRequest && isWaitlist) {
      return false;
    }

    event.preventDefault();
    requestQuestionAnswers(container, QUESTIONS_CONTINUE_ACTION_TICKET);
    return true;
  }

  return false;
};

/**
 * Dismisses registration questions and restores ticket selection when needed.
 * @param {HTMLElement} container - Attendance container element
 * @returns {void}
 */
export const dismissQuestionAnswers = (container) => {
  const continueAction = container.dataset.questionsContinueAction;
  delete container.dataset.questionsContinueAction;
  closeQuestionsModal(container);

  if (continueAction === QUESTIONS_CONTINUE_ACTION_TICKET) {
    openTicketModal(container);
  }
};

/**
 * Handles the questions modal submit flow.
 * @param {Event} event - Submit event
 * @returns {void}
 */
export const handleAttendanceSubmit = (event) => {
  const target = event.target;
  if (!(target instanceof HTMLFormElement) || target.dataset.attendanceRole !== "registration-form") {
    return;
  }

  event.preventDefault();
  const container = getAttendanceContainer(target);
  if (!container) {
    return;
  }

  const answersPayload = collectQuestionAnswers(container);
  if (!answersPayload) {
    return;
  }

  setQuestionAnswersPayload(container, answersPayload);
  closeQuestionsModal(container);

  const continueAction = container.dataset.questionsContinueAction;
  delete container.dataset.questionsContinueAction;

  if (continueAction === QUESTIONS_CONTINUE_ACTION_TICKET) {
    const checkoutForm = getAttendanceControl(container, "checkout-form");
    if (checkoutForm instanceof HTMLFormElement) {
      openTicketModal(container);
      checkoutForm.requestSubmit();
    }
    return;
  }

  if (continueAction === QUESTIONS_CONTINUE_ACTION_ATTEND) {
    const attendButton = getAttendanceControl(container, "attend-btn");
    if (attendButton instanceof HTMLButtonElement) {
      attendButton.click();
    }
  }
};

/**
 * Returns true when the attendee must complete promoted waitlist questions.
 * @param {HTMLElement|null} button - Primary attend button
 * @returns {boolean} Whether the button is completing pending questions
 */
export const isCompletingRegistrationQuestions = (button) =>
  button instanceof HTMLButtonElement && button.dataset.registrationQuestionsPending === "true";

/**
 * Returns true when the primary attendance action will join the waitlist.
 * @param {object} meta - Attendance metadata
 * @returns {boolean} Whether the action is a waitlist join
 */
export const isWaitlistJoinAction = (meta) =>
  !meta.attendeeApprovalRequired &&
  meta.waitlistEnabled &&
  (meta.isTicketed ? !meta.ticketPurchaseAvailable && meta.hasSoldOutTicketTypes : meta.isSoldOut);

/**
 * Returns true when the attendance container has unanswered event questions.
 * @param {HTMLElement} container - Attendance container element
 * @returns {boolean} Whether answers must be collected before continuing
 */
export const shouldCollectQuestionAnswers = (container) =>
  getAttendanceControl(container, "registration-modal") instanceof HTMLElement &&
  !isDatasetReady(container, "questionAnswersReady");

/**
 * Collects and validates event question answers.
 * @param {HTMLElement} container - Attendance container element
 * @returns {object|null} Answers payload, or null when invalid
 */
const collectQuestionAnswers = (container) => {
  const form = getAttendanceControl(container, "registration-form");
  if (!(form instanceof HTMLFormElement)) {
    return { answers: [] };
  }

  return collectQuestionAnswersFromForm(form, {
    answerSelector: "[data-question-answer]",
  });
};

/**
 * Stores answer JSON in all hidden answer inputs in the attendance container.
 * @param {HTMLElement} container - Attendance container element
 * @param {object} answersPayload - Normalized answers payload
 * @returns {void}
 */
const setQuestionAnswersPayload = (container, answersPayload) => {
  const value = JSON.stringify(answersPayload);
  container.querySelectorAll('[data-attendance-role$="registration-answers-input"]').forEach((input) => {
    if (input instanceof HTMLInputElement) {
      input.value = value;
    }
  });
  markDatasetReady(container, "questionAnswersReady");
};
