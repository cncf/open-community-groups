import { handleHtmxResponse, showErrorAlert, showInfoAlert } from "/static/js/common/alerts.js";
import {
  getAttendanceContainer,
  getAttendanceControl,
  getAttendanceMeta,
} from "/static/js/event/attendance-dom.js";
import {
  closeTicketModal,
  restoreCheckoutModalControls,
  showCheckoutLoadingState,
} from "/static/js/event/attendance-ticket-view.js";
import {
  closeRefundModal,
  restorePrimaryRequestControl,
  restoreRefundModalControls,
  showPrimaryRequestLoading,
  showRefundLoadingState,
} from "/static/js/event/attendance-view.js";
import { refreshAvailabilityAndRenderAttendance } from "/static/js/event/attendance/availability-refresh.js";
import { showProfileAwareInfoAlert } from "/static/js/event/attendance/feedback.js";
import {
  blockAttendanceRequestForQuestions,
  isCompletingRegistrationQuestions,
  requestQuestionAnswers,
  shouldCollectQuestionAnswers,
} from "/static/js/event/attendance/questions.js";
import { renderAttendanceCheckResponse } from "/static/js/event/attendance/status-renderer.js";
import {
  parseJsonResponse,
  PRIMARY_REQUEST_ROLES,
  QUESTIONS_CONTINUE_ACTION_ATTEND,
  QUESTIONS_CONTINUE_ACTION_TICKET,
} from "/static/js/event/attendance/shared.js";

// Actionable guidance shown when registration must go through a pending invitation.
const ADMISSION_OFFER_REQUIRED_MESSAGE =
  "You have a pending invitation for this event. Please claim it from the Event Invitations section in your dashboard to register.";

const CHECKOUT_ACTION_ERROR_MESSAGES = {
  checkout: "Something went wrong starting checkout. Please try again later.",
  request: "Something went wrong requesting this ticket. Please try again later.",
  waitlist: "Something went wrong joining the ticket waiting list. Please try again later.",
};

const PRIMARY_ACTION_CONFIG = {
  "attend-btn": {
    errorMessage: "Something went wrong registering for this event. Please try again later.",
    onSuccess: (response, target) => {
      if (response?.redirect_url) {
        window.location.assign(response.redirect_url);
        return false;
      }

      if (response?.status === "waitlisted") {
        showProfileAwareInfoAlert(target, "You have joined the waiting list for this event.");
      } else if (response?.status === "pending-approval") {
        showProfileAwareInfoAlert(target, "Your invitation request has been sent to the organizers.");
      } else if (response?.status !== "pending-payment") {
        showProfileAwareInfoAlert(target, "You have successfully registered for this event.");
      }

      return true;
    },
  },
  "leave-btn": {
    errorMessage: "Something went wrong canceling your attendance. Please try again later.",
    onSuccess: (response) => {
      if (response?.left_status === "waitlisted") {
        showInfoAlert("You have left the waiting list for this event.");
      } else if (response?.left_status === "pending-approval") {
        showInfoAlert("Your invitation request has been canceled.");
      } else {
        showInfoAlert("You have successfully canceled your attendance.");
      }

      return true;
    },
  },
  "checkout-cancel-btn": {
    errorMessage: "Something went wrong canceling your checkout. Please try again later.",
    onSuccess: () => {
      showInfoAlert("Your checkout has been canceled. You can choose a different ticket.");
      return true;
    },
  },
};

/**
 * Reopens registration questions after authoritative inventory becomes available.
 * @param {HTMLElement} container - Attendance container element
 * @param {XMLHttpRequest|undefined} xhr - HTMX request object
 * @param {"attend"|"ticket"} continueAction - Action to retry after answers
 * @returns {boolean} Whether the conflict was handled
 */
const recoverRegistrationAnswers = (container, xhr, continueAction) => {
  if (xhr?.status !== 409 || parseJsonResponse(xhr)?.conflict !== "registration-answers-required") {
    return false;
  }

  requestQuestionAnswers(container, continueAction);
  return true;
};

/**
 * Shows invitation-claim guidance when registration requires a pending offer.
 * @param {XMLHttpRequest|undefined} xhr - HTMX request object
 * @returns {boolean} Whether the conflict was handled
 */
const notifyAdmissionOfferRequired = (xhr) => {
  if (xhr?.status !== 409 || parseJsonResponse(xhr)?.conflict !== "admission-offer-required") {
    return false;
  }

  showErrorAlert(ADMISSION_OFFER_REQUIRED_MESSAGE);
  return true;
};

/**
 * Normalizes optional checkout parameters before HTMX submits the request.
 * @param {Event} event - htmx:configRequest event
 * @returns {void}
 */
const handleCheckoutConfigRequest = (event) => {
  const target = event.target;
  if (!(target instanceof HTMLElement) || target.dataset.attendanceRole !== "checkout-form") {
    return;
  }

  const container = getAttendanceContainer(target);
  const params = event.detail?.parameters;
  if (!container || !params || typeof params !== "object") {
    return;
  }

  const selectedTicketType = container.querySelector('[data-attendance-role="ticket-type-option"]:checked');
  const isRequest = getAttendanceMeta(container).attendeeApprovalRequired;
  const isWaitlist =
    selectedTicketType instanceof HTMLInputElement && selectedTicketType.dataset.ticketSoldOut === "true";
  if (isRequest || isWaitlist) {
    event.detail.path = target.dataset.attendUrl || event.detail.path;
    deleteRequestParameter(event, "discount_code");

    if (isWaitlist && !isRequest) {
      deleteRequestParameter(event, "registration_answers");
    }
    return;
  }

  event.detail.path = target.dataset.checkoutUrl || event.detail.path;
  const discountCodeInput = getAttendanceControl(container, "discount-code-input");
  if (!(discountCodeInput instanceof HTMLInputElement)) {
    return;
  }
  if (discountCodeInput.disabled) {
    deleteRequestParameter(event, "discount_code");
    return;
  }

  const normalizedDiscountCode = discountCodeInput.value.trim();
  discountCodeInput.value = normalizedDiscountCode;

  if (normalizedDiscountCode) {
    params.discount_code = normalizedDiscountCode;
    if (event.detail?.unfilteredParameters && typeof event.detail.unfilteredParameters === "object") {
      event.detail.unfilteredParameters.discount_code = normalizedDiscountCode;
    }
    return;
  }

  deleteRequestParameter(event, "discount_code");
};

/**
 * Removes a request parameter from HTMX's filtered and unfiltered payloads.
 * @param {Event} event HTMX configuration event.
 * @param {string} parameterName Request parameter name.
 * @returns {void}
 */
const deleteRequestParameter = (event, parameterName) => {
  const parameters = event.detail?.parameters;
  if (parameters && typeof parameters === "object") {
    delete parameters[parameterName];
  }

  const unfilteredParameters = event.detail?.unfilteredParameters;
  if (unfilteredParameters && typeof unfilteredParameters === "object") {
    delete unfilteredParameters[parameterName];
  }
};

/**
 * Normalizes the optional refund reason before HTMX submits the request.
 * @param {Event} event - htmx:configRequest event
 * @returns {void}
 */
const handleRefundConfigRequest = (event) => {
  const target = event.target;
  if (!(target instanceof HTMLElement) || target.dataset.attendanceRole !== "refund-form") {
    return;
  }

  const container = getAttendanceContainer(target);
  const params = event.detail?.parameters;
  if (!container || !params || typeof params !== "object") {
    return;
  }

  const refundReasonInput = getAttendanceControl(container, "refund-reason-input");
  if (!(refundReasonInput instanceof HTMLTextAreaElement)) {
    return;
  }

  const normalizedReason = refundReasonInput.value.trim();
  refundReasonInput.value = normalizedReason;
  const parameterSets = [params, event.detail?.unfilteredParameters].filter(
    (parameters) => parameters && typeof parameters === "object",
  );

  parameterSets.forEach((parameters) => {
    if (normalizedReason) {
      parameters.requested_reason = normalizedReason;
    } else {
      delete parameters.requested_reason;
    }
  });
};

/**
 * Handles the shared afterRequest flow for primary attendance actions.
 * @param {Event} event - HTMX afterRequest event
 * @returns {void}
 */
const handlePrimaryActionAfterRequest = (event) => {
  const target = event.target;
  if (!(target instanceof HTMLElement)) {
    return;
  }

  const role = target.dataset.attendanceRole;
  if (!PRIMARY_REQUEST_ROLES.has(role)) {
    return;
  }

  const container = getAttendanceContainer(target);
  if (!container) {
    return;
  }

  const config = PRIMARY_ACTION_CONFIG[role];
  if (!config) {
    return;
  }

  const xhr = event.detail?.xhr;
  if (role === "attend-btn" && recoverRegistrationAnswers(container, xhr, QUESTIONS_CONTINUE_ACTION_ATTEND)) {
    restorePrimaryRequestControl(container, role);
    return;
  }
  if (role === "attend-btn" && notifyAdmissionOfferRequired(xhr)) {
    restorePrimaryRequestControl(container, role);
    return;
  }
  const ok = handleHtmxResponse({
    xhr,
    successMessage: "",
    errorMessage: config.errorMessage,
  });

  if (!ok) {
    restorePrimaryRequestControl(container, role);
    return;
  }

  const response = parseJsonResponse(xhr);
  if (config.onSuccess(response, target) !== false) {
    refreshAvailabilityAndRenderAttendance(container);
  }
};

/**
 * Handles checkout form beforeRequest state.
 * @param {HTMLElement} target - Event target
 * @returns {void}
 */
const handleCheckoutBeforeRequest = (target) => {
  if (target.dataset.attendanceRole !== "checkout-form") {
    return;
  }

  const container = getAttendanceContainer(target);
  if (!container) {
    return;
  }

  showCheckoutLoadingState(container);
};

/**
 * Blocks attend-button HTMX requests when click handling owns the action.
 * @param {Event} event - htmx:beforeRequest event
 * @param {HTMLElement} target - Event target
 * @param {HTMLElement} container - Attendance container element
 * @returns {boolean} True when the request was blocked
 */
const blockInterceptedAttendRequest = (event, target, container) => {
  if (!(target instanceof HTMLButtonElement) || target.dataset.attendanceRole !== "attend-btn") {
    return false;
  }

  const meta = getAttendanceMeta(container);
  if (isCompletingRegistrationQuestions(target) && !shouldCollectQuestionAnswers(container)) {
    return false;
  }
  if (!meta.ticketModalRequired && !target.dataset.resumeUrl) {
    return false;
  }

  event.preventDefault();
  return true;
};

/**
 * Handles checkout form afterRequest state.
 * @param {Event} event - htmx:afterRequest event
 * @returns {void}
 */
const handleCheckoutAfterRequest = (event) => {
  const target = event.target;
  if (!(target instanceof HTMLElement) || target.dataset.attendanceRole !== "checkout-form") {
    return;
  }

  const container = getAttendanceContainer(target);
  if (!container) {
    return;
  }

  const selectedTicketType = container.querySelector('[data-attendance-role="ticket-type-option"]:checked');
  const meta = getAttendanceMeta(container);
  const actionMode = meta.attendeeApprovalRequired
    ? "request"
    : selectedTicketType?.dataset.ticketSoldOut === "true"
      ? "waitlist"
      : "checkout";
  const xhr = event.detail?.xhr;
  if (recoverRegistrationAnswers(container, xhr, QUESTIONS_CONTINUE_ACTION_TICKET)) {
    restoreCheckoutModalControls(container);
    return;
  }
  if (notifyAdmissionOfferRequired(xhr)) {
    restoreCheckoutModalControls(container);
    closeTicketModal(container);
    return;
  }
  const ok = handleHtmxResponse({
    xhr,
    successMessage: "",
    errorMessage: CHECKOUT_ACTION_ERROR_MESSAGES[actionMode],
  });

  if (!ok) {
    restoreCheckoutModalControls(container);
    if (xhr?.status !== 422) {
      closeTicketModal(container);
    }
    return;
  }

  const response = parseJsonResponse(xhr);
  closeTicketModal(container);

  if (response?.redirect_url) {
    window.location.assign(response.redirect_url);
    return;
  }

  if (response?.status === "waitlisted") {
    showProfileAwareInfoAlert(target, "You have joined the waiting list for this ticket.");
  } else if (response?.status === "pending-approval") {
    showProfileAwareInfoAlert(target, "Your ticket request has been sent to the organizers.");
  } else if (response?.status !== "pending-payment") {
    showProfileAwareInfoAlert(target, "You have successfully registered for this event.");
  }

  refreshAvailabilityAndRenderAttendance(container);
};

/**
 * Handles refund form afterRequest state.
 * @param {Event} event - htmx:afterRequest event
 * @returns {void}
 */
const handleRefundAfterRequest = (event) => {
  const target = event.target;
  if (!(target instanceof HTMLFormElement) || target.dataset.attendanceRole !== "refund-form") {
    return;
  }

  const container = getAttendanceContainer(target);
  if (!container) {
    return;
  }

  restoreRefundModalControls(container);
  const ok = handleHtmxResponse({
    xhr: event.detail?.xhr,
    successMessage: "",
    errorMessage: "Something went wrong requesting your refund. Please try again later.",
  });
  if (!ok) {
    return;
  }

  closeRefundModal(container);
  target.reset();
  showInfoAlert("Your refund request has been sent to the organizers.");
  refreshAvailabilityAndRenderAttendance(container);
};

/**
 * Handles htmx:beforeRequest events for attendance controls.
 * @param {Event} event - htmx:beforeRequest event
 * @returns {void}
 */
export const handleBeforeRequest = (event) => {
  const target = event.target;
  if (!(target instanceof HTMLElement)) {
    return;
  }

  const container = getAttendanceContainer(target);
  if (!container) {
    return;
  }

  if (blockInterceptedAttendRequest(event, target, container)) {
    return;
  }

  if (blockAttendanceRequestForQuestions(event, target, container)) {
    return;
  }

  if (target.dataset.attendanceRole === "refund-form") {
    showRefundLoadingState(container);
    return;
  }

  if (PRIMARY_REQUEST_ROLES.has(target.dataset.attendanceRole)) {
    showPrimaryRequestLoading(container, target.dataset.attendanceRole);
    return;
  }

  handleCheckoutBeforeRequest(target);
};

/**
 * Handles htmx:afterRequest events for attendance components.
 * @param {Event} event - htmx:afterRequest event
 * @returns {void}
 */
export const handleAfterRequest = (event) => {
  const target = event.target;
  if (!(target instanceof HTMLElement)) {
    return;
  }

  if (target.dataset.attendanceRole === "attendance-checker") {
    const container = getAttendanceContainer(target);
    if (container) {
      renderAttendanceCheckResponse(container, event);
    }
    return;
  }

  if (target.dataset.attendanceRole === "refund-form") {
    handleRefundAfterRequest(event);
    return;
  }

  if (PRIMARY_REQUEST_ROLES.has(target.dataset.attendanceRole)) {
    handlePrimaryActionAfterRequest(event);
    return;
  }

  handleCheckoutAfterRequest(event);
};

/**
 * Handles htmx:configRequest events for attendance components.
 * @param {Event} event - htmx:configRequest event
 * @returns {void}
 */
export const handleConfigRequest = (event) => {
  handleCheckoutConfigRequest(event);
  handleRefundConfigRequest(event);
};
