import {
  handleHtmxResponse,
  showConfirmAlert,
  showInfoAlert,
  showSuccessAlert,
} from "/static/js/common/alerts.js";
import { isSuccessfulXHRStatus } from "/static/js/common/common.js";

import {
  ATTENDANCE_CONTAINER_SELECTOR,
  getAttendanceChecker,
  getAttendanceContainer,
  getAttendanceContainers,
  getAttendanceControl,
  getAttendanceControlLabel,
  getAttendanceMeta,
} from "/static/js/event/attendance-dom.js";
import {
  ATTEND_EVENT_LABEL,
  BUY_TICKET_LABEL,
  CANCEL_ATTENDANCE_LABEL,
  JOIN_WAITLIST_LABEL,
  LEAVE_WAITLIST_LABEL,
  REQUEST_INVITATION_LABEL,
  closeTicketModal,
  initializeAttendanceContainer,
  openTicketModal,
  renderMeetingDetails,
  restoreCheckoutModalControls,
  restorePrimaryRequestControl,
  showCheckoutLoadingState,
  showAttendeeState,
  showGuestAttendanceState,
  showPendingApprovalAttendanceState,
  showPendingPaymentState,
  showPrimaryRequestLoading,
  showRejectedInvitationState,
  showSignedOutAttendanceState,
  showWaitlistedAttendanceState,
} from "/static/js/event/attendance-view.js";

const PAYMENT_RETURN_PARAM = "payment";
const PAYMENT_RETURN_POLL_ATTEMPTS = 8;
const PAYMENT_RETURN_POLL_INTERVAL_MS = 2000;
const PRIMARY_REQUEST_ROLES = new Set(["attend-btn", "leave-btn", "refund-btn"]);
const PRIMARY_ACTION_CONFIG = {
  "attend-btn": {
    errorMessage: "Something went wrong registering for this event. Please try again later.",
    onSuccess: (response) => {
      if (response?.redirect_url) {
        window.location.assign(response.redirect_url);
        return false;
      }

      if (response?.status === "waitlisted") {
        showInfoAlert("You have joined the waiting list for this event.");
      } else if (response?.status === "pending-approval") {
        showInfoAlert("Your invitation request has been sent to the organizers.");
      } else if (response?.status === "pending-payment") {
        showInfoAlert("Your checkout is ready. Redirecting you to Stripe now.");
      } else {
        showInfoAlert("You have successfully registered for this event.");
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
  "refund-btn": {
    errorMessage: "Something went wrong requesting your refund. Please try again later.",
    onSuccess: () => {
      showInfoAlert("Your refund request has been sent to the organizers.");
      return true;
    },
  },
};

/**
 * Applies the signed-out fallback UI for a container.
 * @param {HTMLElement} container - Attendance container element
 * @param {ReturnType<typeof getAttendanceMeta>} meta - Attendance metadata
 */
const showSignedOutFallback = (container, meta) => {
  showSignedOutAttendanceState(container, meta);
  renderMeetingDetails(false, meta);
};

/**
 * Returns the sign-in alert action text for a control label.
 * @param {string} label - Visible control label
 * @returns {string} Human-readable action text
 */
const getSigninActionText = (label) => {
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
 * Reads the payment outcome returned by the checkout provider.
 * @returns {"canceled"|"success"|null} Supported payment outcome
 */
const getPaymentReturnOutcome = () => {
  const paymentOutcome = new URLSearchParams(window.location.search).get(PAYMENT_RETURN_PARAM);

  if (paymentOutcome === "canceled" || paymentOutcome === "success") {
    return paymentOutcome;
  }

  return null;
};

/**
 * Removes the payment outcome query parameter from the current URL.
 */
const clearPaymentReturnOutcome = () => {
  const nextUrl = new URL(window.location.href);
  nextUrl.searchParams.delete(PAYMENT_RETURN_PARAM);
  const query = nextUrl.searchParams.toString();
  const normalizedUrl = `${nextUrl.pathname}${query ? `?${query}` : ""}${nextUrl.hash}`;

  window.history.replaceState({}, "", normalizedUrl);
};

/**
 * Attempts to parse a JSON response body.
 * @param {XMLHttpRequest|undefined} xhr - HTMX request object
 * @returns {Object|null} Parsed JSON response
 */
const parseJsonResponse = (xhr) => {
  if (!xhr?.responseText) {
    return null;
  }

  try {
    return JSON.parse(xhr.responseText);
  } catch {
    return null;
  }
};

/**
 * Loads the current attendance status for the event page.
 * @returns {Promise<Object|null>} Attendance payload or null if unavailable
 */
const fetchAttendanceStatus = async () => {
  const attendanceChecker = getAttendanceChecker();
  const attendanceUrl = attendanceChecker?.getAttribute("hx-get");
  if (!attendanceUrl) {
    return null;
  }

  const response = await fetch(attendanceUrl, {
    credentials: "same-origin",
    headers: {
      Accept: "application/json",
    },
  });
  if (!response.ok) {
    throw new Error("failed to load attendance status");
  }

  return response.json();
};

/**
 * Waits before the next payment reconciliation poll.
 * @param {number} durationMs - Delay in milliseconds
 * @returns {Promise<void>}
 */
const waitForPoll = (durationMs) =>
  new Promise((resolve) => {
    window.setTimeout(resolve, durationMs);
  });

/**
 * Handles Stripe's attendee return flow after checkout redirects back to the event page.
 * Polls for webhook reconciliation when checkout succeeded and shows attendee feedback
 * for canceled or delayed returns.
 */
const reconcilePaymentReturn = async () => {
  const paymentOutcome = getPaymentReturnOutcome();
  if (!paymentOutcome || !getAttendanceChecker()) {
    return;
  }

  try {
    const attendance = await fetchAttendanceStatus();

    if (paymentOutcome === "canceled") {
      if (attendance?.status === "pending-payment") {
        showInfoAlert(
          "Checkout was canceled. You can resume payment while your ticket hold is still active.",
        );
      } else {
        showInfoAlert("Checkout was canceled.");
      }
      return;
    }

    if (attendance?.status === "attendee") {
      document.body.dispatchEvent(new Event("attendance-changed"));
      showSuccessAlert("Your payment is complete. You're registered for this event.");
      return;
    }

    if (attendance?.status !== "pending-payment") {
      return;
    }

    showInfoAlert("Confirming your payment. This can take a few seconds.");

    for (let attempt = 0; attempt < PAYMENT_RETURN_POLL_ATTEMPTS; attempt += 1) {
      await waitForPoll(PAYMENT_RETURN_POLL_INTERVAL_MS);

      const nextAttendance = await fetchAttendanceStatus();
      if (nextAttendance?.status === "attendee") {
        document.body.dispatchEvent(new Event("attendance-changed"));
        showSuccessAlert("Your payment is complete. You're registered for this event.");
        return;
      }

      if (nextAttendance?.status !== "pending-payment") {
        return;
      }
    }

    showInfoAlert(
      "Your payment is still being confirmed. If the page still shows Complete payment, wait a few seconds and refresh.",
    );
  } catch (_) {
    if (paymentOutcome === "success") {
      showInfoAlert(
        "Your payment was submitted. If the page still shows Complete payment, wait a few seconds and refresh.",
      );
    }
  } finally {
    clearPaymentReturnOutcome();
  }
};

/**
 * Renders the current attendance response for a container.
 * @param {HTMLElement} container - Attendance container element
 * @param {Event} event - HTMX afterRequest event
 */
const renderAttendanceCheckResponse = (container, event) => {
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

  if (response.status === "attendee") {
    showAttendeeState(container, meta, response);
    return;
  }

  if (response.status === "pending-payment") {
    showPendingPaymentState(container, meta, response);
    return;
  }

  if (response.status === "pending-approval") {
    showPendingApprovalAttendanceState(container, meta);
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
  if (config.onSuccess(response) !== false) {
    document.body.dispatchEvent(new Event("attendance-changed"));
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
    return;
  }

  const response = parseJsonResponse(xhr);
  closeTicketModal(container);

  if (response?.redirect_url) {
    showInfoAlert("Your checkout is ready. Redirecting you to Stripe now.");
    window.location.assign(response.redirect_url);
    return;
  }

  if (response?.status === "pending-payment") {
    showInfoAlert("Your checkout is ready. Redirecting you to Stripe now.");
  } else {
    showInfoAlert("You have successfully registered for this event.");
  }

  document.body.dispatchEvent(new Event("attendance-changed"));
};

/**
 * Handles htmx:beforeRequest events for attendance controls.
 * @param {Event} event - htmx:beforeRequest event
 */
const handleBeforeRequest = (event) => {
  const target = event.target;
  if (!(target instanceof HTMLElement)) {
    return;
  }

  const container = getAttendanceContainer(target);
  if (!container) {
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
const handleAfterRequest = (event) => {
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
const handleConfigRequest = (event) => {
  handleCheckoutConfigRequest(event);
};

/**
 * Handles click events for attendance actions.
 * @param {MouseEvent} event - Click event
 */
const handleAttendanceClick = (event) => {
  const target = event.target;
  if (!(target instanceof Element)) {
    return;
  }

  const container = getAttendanceContainer(target);
  if (!container) {
    return;
  }

  const signinButton = target.closest('[data-attendance-role="signin-btn"]');
  if (signinButton instanceof HTMLElement) {
    const path = signinButton.dataset.path || window.location.pathname;
    const label = getAttendanceControlLabel(signinButton) || ATTEND_EVENT_LABEL;
    const actionText = getSigninActionText(label);

    showInfoAlert(
      `You need to be <a href='/log-in?next_url=${path}' class='underline font-medium' hx-boost='true'>logged in</a> to ${actionText}.`,
      true,
    );
    return;
  }

  const attendButton = target.closest('[data-attendance-role="attend-btn"]');
  if (attendButton instanceof HTMLButtonElement && attendButton.dataset.resumeUrl) {
    event.preventDefault();
    window.location.assign(attendButton.dataset.resumeUrl);
    return;
  }

  if (attendButton instanceof HTMLButtonElement && getAttendanceMeta(container).isTicketed) {
    event.preventDefault();
    openTicketModal(container);
    return;
  }

  const leaveButton = target.closest('[data-attendance-role="leave-btn"]');
  if (leaveButton instanceof HTMLElement) {
    const label = getAttendanceControlLabel(leaveButton) || CANCEL_ATTENDANCE_LABEL;
    const message =
      label === LEAVE_WAITLIST_LABEL
        ? "Are you sure you want to leave the waiting list?"
        : "Are you sure you want to cancel your attendance?";
    showConfirmAlert(message, leaveButton.id, "Yes");
    return;
  }

  const refundButton = target.closest('[data-attendance-role="refund-btn"]');
  if (refundButton instanceof HTMLElement) {
    showConfirmAlert("Are you sure you want to request a refund for this ticket?", refundButton.id, "Yes");
  }

  const closeTicketModalTrigger = target.closest(
    '[data-attendance-role="ticket-modal-close"], [data-attendance-role="ticket-modal-cancel"], [data-attendance-role="ticket-modal-overlay"]',
  );
  if (closeTicketModalTrigger) {
    restoreCheckoutModalControls(container);
    closeTicketModal(container);
  }
};

/**
 * Handles keyboard shortcuts for attendance modals.
 * @param {KeyboardEvent} event - Keyboard event
 */
const handleAttendanceKeydown = (event) => {
  if (event.key !== "Escape") {
    return;
  }

  document.querySelectorAll(ATTENDANCE_CONTAINER_SELECTOR).forEach((container) => {
    if (!(container instanceof HTMLElement)) {
      return;
    }

    const ticketModal = getAttendanceControl(container, "ticket-modal");
    if (ticketModal && !ticketModal.classList.contains("hidden")) {
      restoreCheckoutModalControls(container);
      closeTicketModal(container);
    }
  });
};

/**
 * Initializes attendance handlers for the current page.
 * @param {Document|HTMLElement} root - Root node to search
 */
const initializeAttendance = (root = document) => {
  getAttendanceContainers(root).forEach(initializeAttendanceContainer);

  if (document.body?.dataset.attendanceListenersReady === "true") {
    return;
  }

  document.body.dataset.attendanceListenersReady = "true";
  document.body.addEventListener("htmx:configRequest", handleConfigRequest);
  document.body.addEventListener("htmx:beforeRequest", handleBeforeRequest);
  document.body.addEventListener("htmx:afterRequest", handleAfterRequest);
  document.body.addEventListener("click", handleAttendanceClick);
  document.addEventListener("keydown", handleAttendanceKeydown);
  reconcilePaymentReturn();
};

if (document.readyState === "loading") {
  document.addEventListener("DOMContentLoaded", () => initializeAttendance(document));
} else {
  initializeAttendance(document);
}

if (window.htmx && typeof htmx.onLoad === "function") {
  htmx.onLoad((element) => {
    if (element) {
      initializeAttendance(element);
    }
  });
}
