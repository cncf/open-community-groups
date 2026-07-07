import { isDatasetReady, markDatasetReady } from "/static/js/common/dom.js";
import { collectQuestionAnswers as collectQuestionAnswersFromForm } from "/static/js/common/question-answers.js";
import {
  getAttendanceContainer,
  getAttendanceControl,
  getAttendanceMeta,
} from "/static/js/event/attendance-dom.js";
import {
  closeQuestionsModal,
  openQuestionsModal,
  openTicketModal,
} from "/static/js/event/attendance-view.js";
import {
  QUESTIONS_CONTINUE_ACTION_ATTEND,
  QUESTIONS_CONTINUE_ACTION_TICKET,
} from "/static/js/event/attendance/shared.js";

/**
 * Returns true when the attendance container has unanswered event questions.
 * @param {HTMLElement} container - Attendance container element
 * @returns {boolean} Whether answers must be collected before continuing
 */
export const shouldCollectQuestionAnswers = (container) =>
  getAttendanceControl(container, "registration-modal") instanceof HTMLElement &&
  !isDatasetReady(container, "questionAnswersReady");

/**
 * Returns true when the primary attendance action will join the waitlist.
 * @param {object} meta - Attendance metadata
 * @returns {boolean} Whether the action is a waitlist join
 */
export const isWaitlistJoinAction = (meta) =>
  !meta.isTicketed && !meta.attendeeApprovalRequired && meta.isSoldOut && meta.waitlistEnabled;

/**
 * Returns true when the attendee must complete promoted waitlist questions.
 * @param {HTMLElement|null} button - Primary attend button
 * @returns {boolean} Whether the button is completing pending questions
 */
export const isCompletingRegistrationQuestions = (button) =>
  button instanceof HTMLButtonElement && button.dataset.registrationQuestionsPending === "true";

/**
 * Stores answer JSON in all hidden answer inputs in the attendance container.
 * @param {HTMLElement} container - Attendance container element
 * @param {object} answersPayload - Normalized answers payload
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
 * Opens questions before continuing with attendance or ticket checkout.
 * @param {HTMLElement} container - Attendance container element
 * @param {"attend"|"ticket"} continueAction - Action to resume after questions
 */
export const requestQuestionAnswers = (container, continueAction) => {
  container.dataset.questionsContinueAction = continueAction;
  openQuestionsModal(container);
};

/**
 * Handles the questions modal submit flow.
 * @param {Event} event - Submit event
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
    openTicketModal(container);
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
 * Blocks attend requests until required registration questions are answered.
 * @param {Event} event - htmx:beforeRequest event
 * @param {HTMLElement} target - Event target
 * @param {HTMLElement} container - Attendance container element
 * @returns {boolean} True when the request was blocked
 */
export const blockAttendRequestForQuestions = (event, target, container) => {
  const meta = getAttendanceMeta(container);
  if (
    target.dataset.attendanceRole !== "attend-btn" ||
    (isWaitlistJoinAction(meta) && !isCompletingRegistrationQuestions(target)) ||
    !shouldCollectQuestionAnswers(container)
  ) {
    return false;
  }

  event.preventDefault();
  const continueAction = meta.isTicketed
    ? QUESTIONS_CONTINUE_ACTION_TICKET
    : QUESTIONS_CONTINUE_ACTION_ATTEND;
  requestQuestionAnswers(container, continueAction);
  return true;
};
