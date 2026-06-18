import {
  handleHtmxResponse,
  showErrorAlert,
  showConfirmAlert,
  showInfoAlert,
  showSuccessAlert,
} from "/static/js/common/alerts.js";
import { isSuccessfulXHRStatus } from "/static/js/common/common.js";
import {
  closestElement,
  initializeOnReadyAndHtmxLoad,
  isElementHidden,
  isDatasetReady,
  markDatasetReady,
} from "/static/js/common/dom.js";
import { ocgFetch } from "/static/js/common/fetch.js";
import { isEscapeEvent } from "/static/js/common/keyboard.js";
import { collectQuestionAnswers as collectQuestionAnswersFromForm } from "/static/js/common/question-answers.js";
import { parseJsonText } from "/static/js/common/utils.js";

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
  CANCEL_INVITATION_REQUEST_LABEL,
  JOIN_WAITLIST_LABEL,
  LEAVE_WAITLIST_LABEL,
  REQUEST_INVITATION_LABEL,
  closeQuestionsModal,
  closeTicketModal,
  initializeAttendanceContainer,
  openQuestionsModal,
  openTicketModal,
  renderMeetingDetails,
  restoreCheckoutModalControls,
  restorePrimaryRequestControl,
  showCheckoutLoadingState,
  showAttendeeState,
  showGuestAttendanceState,
  showInvitationApprovedAttendanceState,
  showPendingApprovalAttendanceState,
  showPendingPaymentState,
  showPrimaryRequestLoading,
  showRegistrationQuestionsPendingState,
  showRejectedInvitationState,
  showSignedOutAttendanceState,
  showWaitlistedAttendanceState,
} from "/static/js/event/attendance-view.js";
import {
  fetchAttendanceAvailability,
  renderAttendanceAvailability,
} from "/static/js/event/attendance-availability.js";

const PAYMENT_RETURN_PARAM = "payment";
const PAYMENT_RETURN_POLL_ATTEMPTS = 8;
const PAYMENT_RETURN_POLL_INTERVAL_MS = 2000;
const PRIMARY_REQUEST_ROLES = new Set(["attend-btn", "checkout-cancel-btn", "leave-btn", "refund-btn"]);
const QUESTIONS_CONTINUE_ACTION_ATTEND = "attend";
const QUESTIONS_CONTINUE_ACTION_TICKET = "ticket";
const PENDING_ATTENDANCE_CHECK_RESPONSE = "__ocgPendingAttendanceCheckResponse";
const AVAILABILITY_REFRESH_ERROR_MESSAGE =
  "Something went wrong loading event availability. The page is showing the last available event details.";
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
      } else if (response?.status !== "pending-payment") {
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
 * Keeps the latest attendance status response while public availability loads.
 * @param {HTMLElement} container - Attendance container element
 * @param {Event} event - HTMX afterRequest event
 */
const storePendingAttendanceCheckResponse = (container, event) => {
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
const replayPendingAttendanceCheckResponse = (container) => {
  if (!(PENDING_ATTENDANCE_CHECK_RESPONSE in container)) {
    return false;
  }

  const xhr = container[PENDING_ATTENDANCE_CHECK_RESPONSE];
  delete container[PENDING_ATTENDANCE_CHECK_RESPONSE];
  renderAttendanceCheckResponse(container, { detail: { xhr } });
  return true;
};

/**
 * Applies a fresh public availability payload to the event page.
 * @param {HTMLElement} container - Attendance container element
 * @param {Object} availability - Public availability payload
 * @param {{rerenderAttendance?: boolean}} options - Render options
 */
const applyAvailability = (container, availability, options = {}) => {
  renderAttendanceAvailability(container, availability);
  container.dataset.availabilityHydrated = "true";

  if (replayPendingAttendanceCheckResponse(container)) {
    return;
  }

  if (options.rerenderAttendance) {
    document.body.dispatchEvent(new Event("attendance-changed"));
  }
};

/**
 * Falls back to cached event metadata when availability cannot be refreshed.
 * @param {HTMLElement} container - Attendance container element
 * @param {{rerenderAttendance?: boolean}} options - Render options
 */
const handleAvailabilityRefreshFailure = (container, options = {}) => {
  if (container?.dataset?.availabilityHydrated === "false") {
    container.dataset.availabilityHydrated = "true";
    showErrorAlert(AVAILABILITY_REFRESH_ERROR_MESSAGE);
  }

  if (replayPendingAttendanceCheckResponse(container)) {
    return;
  }

  if (options.rerenderAttendance) {
    document.body.dispatchEvent(new Event("attendance-changed"));
  }
};

/**
 * Loads fresh public availability for the event page.
 * @param {HTMLElement} container - Attendance container element
 * @param {{rerenderAttendance?: boolean}} options - Render options
 * @returns {Promise<void>}
 */
const refreshAvailability = async (container, options = {}) => {
  const availability = await fetchAttendanceAvailability(container);
  if (!availability) {
    return;
  }

  applyAvailability(container, availability, options);
};

/**
 * Refreshes public availability before asking HTMX to redraw attendance state.
 * @param {HTMLElement} container - Attendance container element
 */
const refreshAvailabilityAndRenderAttendance = (container) => {
  if (!container?.dataset?.availabilityUrl) {
    document.body.dispatchEvent(new Event("attendance-changed"));
    return;
  }

  refreshAvailability(container, { rerenderAttendance: true }).catch(() => {
    handleAvailabilityRefreshFailure(container, { rerenderAttendance: true });
  });
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

  return parseJsonText(xhr.responseText, null);
};

/**
 * Returns true when the attendance container has unanswered event questions.
 * @param {HTMLElement} container - Attendance container element
 * @returns {boolean} Whether answers must be collected before continuing
 */
const shouldCollectQuestionAnswers = (container) =>
  getAttendanceControl(container, "registration-modal") instanceof HTMLElement &&
  !isDatasetReady(container, "questionAnswersReady");

/**
 * Returns true when the primary attendance action will join the waitlist.
 * @param {object} meta - Attendance metadata
 * @returns {boolean} Whether the action is a waitlist join
 */
const isWaitlistJoinAction = (meta) =>
  !meta.isTicketed && !meta.attendeeApprovalRequired && meta.isSoldOut && meta.waitlistEnabled;

/**
 * Returns true when the attendee must complete promoted waitlist questions.
 * @param {HTMLElement|null} button - Primary attend button
 * @returns {boolean} Whether the button is completing pending questions
 */
const isCompletingRegistrationQuestions = (button) =>
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
const requestQuestionAnswers = (container, continueAction) => {
  container.dataset.questionsContinueAction = continueAction;
  openQuestionsModal(container);
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

  const response = await ocgFetch(attendanceUrl, {
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

    // Handle terminal return outcomes before polling for delayed webhook updates.
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

    // Stripe may redirect before the webhook has updated the attendee state.
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
    showRegistrationQuestionsPendingState(container, meta);
    return;
  }

  if (response.status === "pending-approval") {
    showPendingApprovalAttendanceState(container, meta);
    return;
  }

  if (response.status === "invitation-approved") {
    showInvitationApprovedAttendanceState(container, meta);
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
 * Handles the questions modal submit flow.
 * @param {Event} event - Submit event
 */
const handleAttendanceSubmit = (event) => {
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
 * Blocks attend requests until required registration questions are answered.
 * @param {Event} event - htmx:beforeRequest event
 * @param {HTMLElement} target - Event target
 * @param {HTMLElement} container - Attendance container element
 * @returns {boolean} True when the request was blocked
 */
const blockAttendRequestForQuestions = (event, target, container) => {
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
    showInfoAlert("You have successfully registered for this event.");
  }

  refreshAvailabilityAndRenderAttendance(container);
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
const handleAttendanceKeydown = (event) => {
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

/**
 * Initializes attendance handlers for the current page.
 * @param {Document|Element} root - Root node to search
 */
const initializeAttendance = (root = document) => {
  getAttendanceContainers(root).forEach((container) => {
    initializeAttendanceContainer(container);

    if (markDatasetReady(container, "availabilityReady")) {
      if (container.dataset.availabilityUrl) {
        container.dataset.availabilityHydrated = "false";
      }
      refreshAvailability(container, { rerenderAttendance: true }).catch(() => {
        handleAvailabilityRefreshFailure(container, { rerenderAttendance: true });
      });
    }
  });

  if (markDatasetReady(document.documentElement, "attendanceListenersReady")) {
    document.addEventListener("htmx:configRequest", handleConfigRequest);
    document.addEventListener("htmx:beforeRequest", handleBeforeRequest);
    document.addEventListener("htmx:afterRequest", handleAfterRequest);
    document.addEventListener("click", handleAttendanceClick);
    document.addEventListener("submit", handleAttendanceSubmit);
    document.addEventListener("keydown", handleAttendanceKeydown);
  }

  reconcilePaymentReturn();
};

initializeOnReadyAndHtmxLoad(initializeAttendance);
