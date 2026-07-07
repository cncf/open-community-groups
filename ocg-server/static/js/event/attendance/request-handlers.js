import { handleHtmxResponse, showInfoAlert } from "/static/js/common/alerts.js";
import { getAttendanceContainer, getAttendanceControl } from "/static/js/event/attendance-dom.js";
import {
  closeTicketModal,
  restoreCheckoutModalControls,
  restorePrimaryRequestControl,
  showCheckoutLoadingState,
  showPrimaryRequestLoading,
} from "/static/js/event/attendance-view.js";
import { refreshAvailabilityAndRenderAttendance } from "/static/js/event/attendance/availability-refresh.js";
import { showProfileAwareInfoAlert } from "/static/js/event/attendance/feedback.js";
import { blockAttendRequestForQuestions } from "/static/js/event/attendance/questions.js";
import { renderAttendanceCheckResponse } from "/static/js/event/attendance/status-renderer.js";
import { parseJsonResponse, PRIMARY_REQUEST_ROLES } from "/static/js/event/attendance/shared.js";

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
  "refund-btn": {
    errorMessage: "Something went wrong requesting your refund. Please try again later.",
    onSuccess: () => {
      showInfoAlert("Your refund request has been sent to the organizers.");
      return true;
    },
  },
};

/**
 * Normalizes optional checkout parameters before HTMX submits the request.
 * @param {Event} event - htmx:configRequest event
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

  const discountCodeInput = getAttendanceControl(container, "discount-code-input");
  if (!(discountCodeInput instanceof HTMLInputElement)) {
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

  delete params.discount_code;
  if (event.detail?.unfilteredParameters && typeof event.detail.unfilteredParameters === "object") {
    delete event.detail.unfilteredParameters.discount_code;
  }
};

/**
 * Handles the shared afterRequest flow for primary attendance actions.
 * @param {Event} event - HTMX afterRequest event
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
 * Handles checkout form afterRequest state.
 * @param {Event} event - htmx:afterRequest event
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

  const xhr = event.detail?.xhr;
  const ok = handleHtmxResponse({
    xhr,
    successMessage: "",
    errorMessage: "Something went wrong starting checkout. Please try again later.",
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

  if (response?.status !== "pending-payment") {
    showProfileAwareInfoAlert(target, "You have successfully registered for this event.");
  }

  refreshAvailabilityAndRenderAttendance(container);
};

/**
 * Handles htmx:beforeRequest events for attendance controls.
 * @param {Event} event - htmx:beforeRequest event
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

  if (blockAttendRequestForQuestions(event, target, container)) {
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

  if (PRIMARY_REQUEST_ROLES.has(target.dataset.attendanceRole)) {
    handlePrimaryActionAfterRequest(event);
    return;
  }

  handleCheckoutAfterRequest(event);
};

/**
 * Handles htmx:configRequest events for attendance components.
 * @param {Event} event - htmx:configRequest event
 */
export const handleConfigRequest = (event) => {
  handleCheckoutConfigRequest(event);
};
