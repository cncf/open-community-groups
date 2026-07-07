import { parseJsonText } from "/static/js/common/utils.js";
import { getAttendanceControlLabel } from "/static/js/event/attendance-dom.js";
import {
  ATTEND_EVENT_LABEL,
  BUY_TICKET_LABEL,
  JOIN_WAITLIST_LABEL,
  renderMeetingDetails,
  REQUEST_INVITATION_LABEL,
  showSignedOutAttendanceState,
} from "/static/js/event/attendance-view.js";

export const PRIMARY_REQUEST_ROLES = new Set([
  "attend-btn",
  "checkout-cancel-btn",
  "leave-btn",
  "refund-btn",
]);
export const QUESTIONS_CONTINUE_ACTION_ATTEND = "attend";
export const QUESTIONS_CONTINUE_ACTION_TICKET = "ticket";

/**
 * Attempts to parse a JSON response body.
 * @param {XMLHttpRequest|undefined} xhr - HTMX request object
 * @returns {Object|null} Parsed JSON response
 */
export const parseJsonResponse = (xhr) => {
  if (!xhr?.responseText) {
    return null;
  }

  return parseJsonText(xhr.responseText, null);
};

/**
 * Applies the signed-out fallback UI for a container.
 * @param {HTMLElement} container - Attendance container element
 * @param {object} meta Attendance metadata.
 * @returns {void}
 */
export const showSignedOutFallback = (container, meta) => {
  showSignedOutAttendanceState(container, meta);
  renderMeetingDetails(false, meta);
};

/**
 * Returns the sign-in alert action text for a control label.
 * @param {string} label - Visible control label
 * @returns {string} Human-readable action text
 */
export const getSigninActionText = (label) => {
  if (label === JOIN_WAITLIST_LABEL) {
    return "join the waiting list";
  }

  if (label === REQUEST_INVITATION_LABEL) {
    return "request an invitation";
  }

  if (label === BUY_TICKET_LABEL) {
    return "buy a ticket for this event";
  }

  return "attend this event";
};

/**
 * Resolves the action text for a sign-in control.
 * @param {HTMLElement} control - Sign-in control.
 * @returns {string} Human-readable action text.
 */
export const getSigninControlActionText = (control) => {
  const label = getAttendanceControlLabel(control) || ATTEND_EVENT_LABEL;
  return getSigninActionText(label);
};
