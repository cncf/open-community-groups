import { isElementHidden } from "/static/js/common/dom.js";
import { isPhoneViewport, PHONE_MEDIA_QUERY } from "/static/js/common/phone-viewport.js";
import { isSuccessfulXHR } from "/static/js/common/utils.js";
import {
  ATTENDANCE_CONTAINER_SELECTOR,
  getAttendanceControl,
  getAttendanceMeta,
} from "/static/js/event/attendance-dom.js";
import {
  showAdmissionOfferState,
  showAttendeeState,
  showExpiredOfferState,
  showGuestAttendanceState,
  showInvitationApprovedAttendanceState,
  showPendingApprovalAttendanceState,
  showPendingPaymentState,
  showRejectedInvitationState,
  showWaitlistedAttendanceState,
} from "/static/js/event/attendance-view.js";
import { parseJsonResponse, showSignedOutFallback } from "/static/js/event/attendance/shared.js";

const PHONE_BAR_CONTROL_ROLES = ["attend-btn", "signin-btn", "leave-btn", "refund-btn"];
const lastAttendanceXhrs = new WeakMap();

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

  const xhr = event.detail?.xhr;

  dispatchAttendanceCheckResponse(container, event);
  lastAttendanceXhrs.set(container, xhr);
  renderPhoneBarState(container, xhr);
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

/**
 * Picks the state renderer for an attendance response.
 * @param {HTMLElement} container - Attendance container element
 * @param {Event} event - HTMX afterRequest event
 * @returns {void}
 */
const dispatchAttendanceCheckResponse = (container, event) => {
  const meta = getAttendanceMeta(container);
  const xhr = event.detail?.xhr;

  if (!isSuccessfulXHR(xhr)) {
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

  if (response.admission_offer_id) {
    showAdmissionOfferState(container, meta, response);
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

  if (response.status === "offer-expired") {
    showExpiredOfferState(container, meta);
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

/**
 * Syncs the phone action bar with the rendered controls. A disabled control keeps its
 * button and shows its reason beside it, and past or canceled events show no bar without
 * a refund state or an action. Off phones it writes nothing.
 * @param {HTMLElement} container - Attendance container element
 * @param {XMLHttpRequest|{responseText: string, status: number}|null|undefined} xhr - Enrollment response
 * @returns {void}
 */
const renderPhoneBarState = (container, xhr) => {
  if (!isPhoneViewport()) {
    return;
  }

  const meta = getAttendanceMeta(container);
  const response = isSuccessfulXHR(xhr) ? parseJsonResponse(xhr) : null;
  const control = PHONE_BAR_CONTROL_ROLES.map((role) => getAttendanceControl(container, role)).find(
    (candidate) => candidate && !isElementHidden(candidate),
  );
  const checkoutCancelButton = getAttendanceControl(container, "checkout-cancel-btn");
  const hasJoinLink = container.querySelector("[data-join-link]:not(.hidden)") !== null;
  const hasEnabledAction =
    hasJoinLink ||
    control?.disabled === false ||
    (checkoutCancelButton !== null && !isElementHidden(checkoutCancelButton));
  // A disabled control keeps its button; its title (when present) replaces the summary
  // details beside it. An expired offer has none: its own label already says why.
  const reason = !hasJoinLink && control?.disabled ? control.title : "";
  const reasonLine = getAttendanceControl(container, "bar-reason");

  if (reasonLine) {
    reasonLine.textContent = reason;
  }
  container.toggleAttribute("data-bar-reason", Boolean(reason));

  if ((meta.canceled || meta.isPastEvent) && !response?.refund_request_status && !hasEnabledAction) {
    container.dataset.phoneBar = "hidden";
  } else {
    delete container.dataset.phoneBar;
  }
};

// The one listener at every width: its body only runs when the query turns true.
window.matchMedia?.(PHONE_MEDIA_QUERY).addEventListener?.("change", (event) => {
  if (!event.matches) {
    return;
  }

  document.querySelectorAll(ATTENDANCE_CONTAINER_SELECTOR).forEach((container) => {
    if (lastAttendanceXhrs.has(container)) {
      renderPhoneBarState(container, lastAttendanceXhrs.get(container));
    }
  });
});
