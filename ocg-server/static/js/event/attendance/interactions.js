import { showConfirmAlert, showInfoAlert } from "/static/js/common/alerts.js";
import { closestElement, isElementHidden } from "/static/js/common/dom.js";
import { isEscapeEvent } from "/static/js/common/keyboard.js";
import {
  ATTENDANCE_CONTAINER_SELECTOR,
  getAttendanceContainer,
  getAttendanceControl,
  getAttendanceControlLabel,
  getAttendanceMeta,
} from "/static/js/event/attendance-dom.js";
import {
  ATTEND_EVENT_LABEL,
  CANCEL_ATTENDANCE_LABEL,
  CANCEL_INVITATION_REQUEST_LABEL,
  closeQuestionsModal,
  closeTicketModal,
  LEAVE_WAITLIST_LABEL,
  openTicketModal,
  restoreCheckoutModalControls,
} from "/static/js/event/attendance-view.js";
import {
  isCompletingRegistrationQuestions,
  isWaitlistJoinAction,
  requestQuestionAnswers,
  shouldCollectQuestionAnswers,
} from "/static/js/event/attendance/questions.js";
import {
  getSigninActionText,
  QUESTIONS_CONTINUE_ACTION_ATTEND,
  QUESTIONS_CONTINUE_ACTION_TICKET,
} from "/static/js/event/attendance/shared.js";

/**
 * Handles click events for attendance actions.
 * @param {MouseEvent} event - Click event
 */
export const handleAttendanceClick = (event) => {
  const target = event.target;
  if (!(target instanceof Element)) {
    return;
  }

  document.querySelectorAll("[data-event-actions-menu][open]").forEach((actionsMenu) => {
    if (actionsMenu instanceof HTMLDetailsElement && !actionsMenu.contains(target)) {
      actionsMenu.open = false;
    }
  });

  const container = getAttendanceContainer(target);
  if (!container) {
    return;
  }

  // Signed-out actions do not submit; they show the login path for this page.
  const signinButton = closestElement(event.target, '[data-attendance-role="signin-btn"]');
  if (signinButton instanceof HTMLElement) {
    const path = signinButton.dataset.path || window.location.pathname;
    const nextUrl = encodeURIComponent(path);
    const label = getAttendanceControlLabel(signinButton) || ATTEND_EVENT_LABEL;
    const actionText = getSigninActionText(label);

    showInfoAlert(
      `You need to be <a href='/log-in?next_url=${nextUrl}' class='underline font-medium' hx-boost='true'>logged in</a> to ${actionText}.`,
      true,
    );
    return;
  }

  const attendButton = closestElement(event.target, '[data-attendance-role="attend-btn"]');
  if (attendButton instanceof HTMLButtonElement && attendButton.dataset.resumeUrl) {
    event.preventDefault();
    window.location.assign(attendButton.dataset.resumeUrl);
    return;
  }

  const meta = getAttendanceMeta(container);
  const completingRegistrationQuestions = isCompletingRegistrationQuestions(attendButton);

  // Ticketed attendance may need questions before opening the checkout modal.
  if (
    attendButton instanceof HTMLButtonElement &&
    shouldCollectQuestionAnswers(container) &&
    (!isWaitlistJoinAction(meta) || completingRegistrationQuestions)
  ) {
    event.preventDefault();
    const continueAction = meta.isTicketed
      ? QUESTIONS_CONTINUE_ACTION_TICKET
      : QUESTIONS_CONTINUE_ACTION_ATTEND;
    requestQuestionAnswers(container, continueAction);
    return;
  }

  if (attendButton instanceof HTMLButtonElement && meta.isTicketed) {
    event.preventDefault();
    openTicketModal(container);
    return;
  }

  const checkoutResumeButton = closestElement(event.target, '[data-attendance-role="checkout-resume-btn"]');
  if (checkoutResumeButton instanceof HTMLButtonElement && checkoutResumeButton.dataset.resumeUrl) {
    event.preventDefault();
    window.location.assign(checkoutResumeButton.dataset.resumeUrl);
    return;
  }

  const leaveButton = closestElement(event.target, '[data-attendance-role="leave-btn"]');
  if (leaveButton instanceof HTMLElement) {
    // Destructive actions keep the real button id as the SweetAlert target.
    const label = getAttendanceControlLabel(leaveButton) || CANCEL_ATTENDANCE_LABEL;
    let message = "Are you sure you want to cancel your attendance?";
    if (label === LEAVE_WAITLIST_LABEL) {
      message = "Are you sure you want to leave the waiting list?";
    } else if (label === CANCEL_INVITATION_REQUEST_LABEL) {
      message = "Are you sure you want to cancel your invitation request?";
    }
    showConfirmAlert(message, leaveButton.id, "Yes");
    return;
  }

  const checkoutCancelButton = closestElement(event.target, '[data-attendance-role="checkout-cancel-btn"]');
  if (checkoutCancelButton instanceof HTMLElement) {
    showConfirmAlert(
      "Are you sure you want to cancel this checkout? Your ticket hold will be released.",
      checkoutCancelButton.id,
      "Yes",
    );
    return;
  }

  const refundButton = closestElement(event.target, '[data-attendance-role="refund-btn"]');
  if (refundButton instanceof HTMLElement) {
    showConfirmAlert("Are you sure you want to request a refund for this ticket?", refundButton.id, "Yes");
  }

  const closeTicketModalTrigger = closestElement(
    event.target,
    '[data-attendance-role="ticket-modal-close"], [data-attendance-role="ticket-modal-cancel"], [data-attendance-role="ticket-modal-overlay"]',
  );
  if (closeTicketModalTrigger) {
    restoreCheckoutModalControls(container);
    closeTicketModal(container);
    return;
  }

  const closeQuestionsModalTrigger = closestElement(
    event.target,
    '[data-attendance-role="registration-modal-close"], [data-attendance-role="registration-modal-cancel"], [data-attendance-role="registration-modal-overlay"]',
  );
  if (closeQuestionsModalTrigger) {
    delete container.dataset.questionsContinueAction;
    closeQuestionsModal(container);
  }
};

/**
 * Handles keyboard shortcuts for attendance modals.
 * @param {KeyboardEvent} event - Keyboard event
 */
export const handleAttendanceKeydown = (event) => {
  if (!isEscapeEvent(event)) {
    return;
  }

  document.querySelectorAll(ATTENDANCE_CONTAINER_SELECTOR).forEach((container) => {
    if (!(container instanceof HTMLElement)) {
      return;
    }

    const ticketModal = getAttendanceControl(container, "ticket-modal");
    if (ticketModal && !isElementHidden(ticketModal)) {
      restoreCheckoutModalControls(container);
      closeTicketModal(container);
    }

    const questionsModal = getAttendanceControl(container, "registration-modal");
    if (questionsModal && !isElementHidden(questionsModal)) {
      delete container.dataset.questionsContinueAction;
      closeQuestionsModal(container);
    }
  });
};
