import { isSuccessfulXHRStatus } from "/static/js/common/utils.js";
import { getAttendanceMeta } from "/static/js/event/attendance-dom.js";
import {
  showAttendeeState,
  showGuestAttendanceState,
  showInvitationApprovedAttendanceState,
  showPendingApprovalAttendanceState,
  showPendingPaymentState,
  showRegistrationQuestionsPendingState,
  showRejectedInvitationState,
  showWaitlistedAttendanceState,
} from "/static/js/event/attendance-view.js";
import { parseJsonResponse, showSignedOutFallback } from "/static/js/event/attendance/shared.js";

/**
 * Renders the current attendance response for a container.
 * @param {HTMLElement} container - Attendance container element
 * @param {Event} event - HTMX afterRequest event
 * @returns {void}
 */
export const renderAttendanceCheckResponse = (container, event) => {
  if (container.dataset.availabilityHydrated === "false") {
    storePendingAttendanceCheckResponse(container, event);
    return;
  }

  const meta = getAttendanceMeta(container);
  const xhr = event.detail?.xhr;

  if (!isSuccessfulXHRStatus(xhr?.status)) {
    showSignedOutFallback(container, meta);
    return;
  }

  const response = parseJsonResponse(xhr);
  if (!response) {
    showSignedOutFallback(container, meta);
    return;
  }

  // Keep server status handling explicit so each state owns its renderer.
  if (response.status === "attendee") {
    showAttendeeState(container, meta, response);
    return;
  }

  if (response.status === "pending-payment") {
    showPendingPaymentState(container, meta, response);
    return;
  }

  if (response.status === "registration-questions-pending") {
    showRegistrationQuestionsPendingState(container, meta, response);
    return;
  }

  if (response.status === "pending-approval") {
    showPendingApprovalAttendanceState(container, meta);
    return;
  }

  if (response.status === "invitation-approved") {
    showInvitationApprovedAttendanceState(container, meta, response);
    return;
  }

  if (response.status === "rejected") {
    showRejectedInvitationState(container, meta);
    return;
  }

  if (response.status === "waitlisted") {
    showWaitlistedAttendanceState(container, meta);
    return;
  }

  showGuestAttendanceState(container, meta);
};

export const PENDING_ATTENDANCE_CHECK_RESPONSE = "__ocgPendingAttendanceCheckResponse";

/**
 * Keeps the latest attendance status response while public availability loads.
 * @param {HTMLElement} container - Attendance container element
 * @param {Event} event - HTMX afterRequest event
 * @returns {void}
 */
export const storePendingAttendanceCheckResponse = (container, event) => {
  const xhr = event.detail?.xhr;
  container[PENDING_ATTENDANCE_CHECK_RESPONSE] = xhr
    ? {
        responseText: xhr.responseText,
        status: xhr.status,
      }
    : null;
};

/**
 * Renders a stored attendance status response after availability is hydrated.
 * @param {HTMLElement} container - Attendance container element
 * @returns {boolean} Whether a pending response was rendered
 */
export const replayPendingAttendanceCheckResponse = (container) => {
  if (!(PENDING_ATTENDANCE_CHECK_RESPONSE in container)) {
    return false;
  }

  const xhr = container[PENDING_ATTENDANCE_CHECK_RESPONSE];
  delete container[PENDING_ATTENDANCE_CHECK_RESPONSE];
  renderAttendanceCheckResponse(container, { detail: { xhr } });
  return true;
};
