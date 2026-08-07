import { showConfirmAlert, showInfoAlert } from "/static/js/common/alerts.js";
import { closestElement, isElementHidden } from "/static/js/common/dom.js";
import { isEscapeEvent } from "/static/js/common/keyboard.js";
import { trapModalFocus } from "/static/js/common/modals/modal-lifecycle.js";
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
  LEAVE_WAITLIST_LABEL,
  REQUEST_PENDING_LABEL,
} from "/static/js/event/attendance-copy.js";
import {
  closeTicketModal,
  openTicketModal,
  restoreCheckoutModalControls,
} from "/static/js/event/attendance-ticket-view.js";
import { closeRefundModal, openRefundModal } from "/static/js/event/attendance-view.js";
import {
  dismissQuestionAnswers,
  isCompletingRegistrationQuestions,
  isWaitlistJoinAction,
  requestQuestionAnswers,
  shouldCollectQuestionAnswers,
} from "/static/js/event/attendance/questions.js";
import { getSigninActionText, QUESTIONS_CONTINUE_ACTION_ATTEND } from "/static/js/event/attendance/shared.js";

/**
 * Handles click events for attendance actions.
 * @param {MouseEvent} event - Click event
 * @returns {void}
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

  // Promoted attendees answer questions before completing their reserved place
  if (
    attendButton instanceof HTMLButtonElement &&
    shouldCollectQuestionAnswers(container) &&
    completingRegistrationQuestions
  ) {
    event.preventDefault();
    requestQuestionAnswers(container, QUESTIONS_CONTINUE_ACTION_ATTEND);
    return;
  }

  // Ticketed actions choose a tier before deciding whether answers are required
  if (
    attendButton instanceof HTMLButtonElement &&
    meta.ticketModalRequired &&
    !completingRegistrationQuestions
  ) {
    event.preventDefault();
    openTicketModal(container);
    return;
  }

  // Direct RSVP and private request flows collect answers before submission
  if (
    attendButton instanceof HTMLButtonElement &&
    shouldCollectQuestionAnswers(container) &&
    !isWaitlistJoinAction(meta)
  ) {
    event.preventDefault();
    requestQuestionAnswers(container, QUESTIONS_CONTINUE_ACTION_ATTEND);
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
    } else if (label === REQUEST_PENDING_LABEL || label === CANCEL_INVITATION_REQUEST_LABEL) {
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
    event.preventDefault();
    openRefundModal(container, refundButton);
    return;
  }

  const closeRefundModalTrigger = closestElement(
    event.target,
    '[data-attendance-role="refund-modal-close"], [data-attendance-role="refund-modal-cancel"], [data-attendance-role="refund-modal-overlay"]',
  );
  if (closeRefundModalTrigger) {
    closeRefundModal(container);
    return;
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
    dismissQuestionAnswers(container);
  }
};

/**
 * Handles keyboard shortcuts for attendance modals.
 * @param {KeyboardEvent} event - Keyboard event
 * @returns {void}
 */
export const handleAttendanceKeydown = (event) => {
  if (event.key === "Tab") {
    for (const container of document.querySelectorAll(ATTENDANCE_CONTAINER_SELECTOR)) {
      if (!(container instanceof HTMLElement)) {
        continue;
      }

      for (const role of ["registration-modal", "refund-modal", "ticket-modal"]) {
        const modal = getAttendanceControl(container, role);
        if (modal && !isElementHidden(modal)) {
          trapModalFocus(event, modal);
          return;
        }
      }
    }
    return;
  }

  if (!isEscapeEvent(event)) {
    return;
  }

  document.querySelectorAll(ATTENDANCE_CONTAINER_SELECTOR).forEach((container) => {
    if (!(container instanceof HTMLElement)) {
      return;
    }

    const questionsModal = getAttendanceControl(container, "registration-modal");
    if (questionsModal && !isElementHidden(questionsModal)) {
      dismissQuestionAnswers(container);
      return;
    }

    const refundModal = getAttendanceControl(container, "refund-modal");
    if (refundModal && !isElementHidden(refundModal)) {
      closeRefundModal(container);
      return;
    }

    const ticketModal = getAttendanceControl(container, "ticket-modal");
    if (ticketModal && !isElementHidden(ticketModal)) {
      restoreCheckoutModalControls(container);
      closeTicketModal(container);
    }
  });
};
