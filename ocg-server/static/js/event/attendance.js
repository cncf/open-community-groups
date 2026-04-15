import {
  handleHtmxResponse,
  showConfirmAlert,
  showInfoAlert,
  showSuccessAlert,
} from "/static/js/common/alerts.js";
import { isSuccessfulXHRStatus } from "/static/js/common/common.js";

const ATTENDANCE_CONTAINER_SELECTOR = "[data-attendance-container]";
const PAYMENT_RETURN_PARAM = "payment";
const PAYMENT_RETURN_POLL_ATTEMPTS = 8;
const PAYMENT_RETURN_POLL_INTERVAL_MS = 2000;

/**
 * Finds an attendance control inside a container.
 * @param {HTMLElement|null} container - Attendance container element
 * @param {string} role - Attendance control role
 * @returns {HTMLElement|null} Matching attendance control
 */
const getAttendanceControl = (container, role) =>
  container?.querySelector(`[data-attendance-role="${role}"]`) ?? null;

/**
 * Returns the primary attendance status checker for the current page.
 * @returns {HTMLElement|null} Attendance checker element
 */
const getAttendanceChecker = () =>
  document.querySelector('[data-attendance-role="attendance-checker"]') ?? null;

/**
 * Sets the visible label for an attendance control.
 * @param {HTMLElement|null} button - Attendance control button
 * @param {string} label - Label to display
 */
const setAttendanceControlLabel = (button, label) => {
  const labelNode = button?.querySelector("[data-attendance-label]");
  if (labelNode) {
    labelNode.textContent = label;
  }
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
    // Fall back to the normal event page state if return reconciliation cannot be loaded
  } finally {
    clearPaymentReturnOutcome();
  }
};

/**
 * Returns all attendance containers within a root node.
 * @param {Document|HTMLElement} root - Root node to search
 * @returns {HTMLElement[]} Attendance containers
 */
const getAttendanceContainers = (root) => {
  if (!root) {
    return [];
  }

  const containers = new Set();
  if (root instanceof HTMLElement && root.matches(ATTENDANCE_CONTAINER_SELECTOR)) {
    containers.add(root);
  }

  root.querySelectorAll?.(ATTENDANCE_CONTAINER_SELECTOR).forEach((container) => {
    containers.add(container);
  });

  return Array.from(containers);
};

/**
 * Parses capacity from container data attributes.
 * @param {HTMLElement} container - Attendance container element
 * @returns {number|null} Parsed capacity, or null if unavailable
 */
const parseCapacity = (container) => {
  const capacityAttr = container?.dataset?.capacity;
  if (!capacityAttr) {
    return null;
  }

  const parsedCapacity = Number(capacityAttr);
  return Number.isFinite(parsedCapacity) ? parsedCapacity : null;
};

/**
 * Parses remaining capacity from container data attributes.
 * @param {HTMLElement} container - Attendance container element
 * @returns {number|null} Parsed remaining capacity, or null if unavailable
 */
const parseRemainingCapacity = (container) => {
  const remainingCapacityAttr = container?.dataset?.remainingCapacity;
  if (!remainingCapacityAttr) {
    return null;
  }

  const parsedCapacity = Number(remainingCapacityAttr);
  return Number.isFinite(parsedCapacity) ? parsedCapacity : null;
};

/**
 * Updates the sign-in control label.
 * @param {HTMLButtonElement|null} button - Sign-in control button
 * @param {{isSoldOut: boolean, isTicketed: boolean, ticketPurchaseAvailable: boolean, waitlistEnabled: boolean}} meta - Attendance metadata
 */
const updateSigninButtonLabel = (button, meta) => {
  if (!button) {
    return;
  }

  let label = meta.isSoldOut && meta.waitlistEnabled ? "Join waiting list" : "Attend event";
  if (meta.isTicketed) {
    label = meta.ticketPurchaseAvailable ? "Choose ticket" : "Tickets unavailable";
  }
  setAttendanceControlLabel(button, label);
  button.dataset.defaultLabel = label;
};

/**
 * Computes attendance metadata for the current event.
 * @param {HTMLElement} container - Attendance container element
 * @returns {{eventIsLive: boolean, isPastEvent: boolean, isSoldOut: boolean, isTicketed: boolean, ticketPurchaseAvailable: boolean, waitlistEnabled: boolean}}
 */
const getAttendanceMeta = (container) => {
  const startsAtValue = container?.dataset?.starts ?? null;
  const capacity = parseCapacity(container);
  const remainingCapacity = parseRemainingCapacity(container);
  const isSoldOut = capacity !== null && remainingCapacity !== null && remainingCapacity <= 0;
  const eventIsLive = container?.dataset?.isLive === "true";
  const isTicketed = container?.dataset?.isTicketed === "true";
  const ticketPurchaseAvailable = container?.dataset?.ticketPurchaseAvailable === "true";
  const waitlistEnabled = container?.dataset?.waitlistEnabled === "true";
  const isPastEvent = (() => {
    if (!startsAtValue) {
      return false;
    }
    const parsedDate = new Date(startsAtValue);
    if (Number.isNaN(parsedDate.valueOf())) {
      return false;
    }
    return parsedDate < new Date();
  })();

  return {
    isSoldOut,
    isPastEvent,
    eventIsLive,
    ticketPurchaseAvailable,
    waitlistEnabled,
    isTicketed,
  };
};

/**
 * Applies the unavailable-ticket state to an attendance button.
 * @param {HTMLButtonElement|null} button - Button to update
 */
const applyUnavailableTicketState = (button) => {
  if (!button) {
    return;
  }

  button.disabled = true;
  button.title = "Tickets are not currently available for this event.";
  button.classList.add("cursor-not-allowed", "opacity-50");
  setAttendanceControlLabel(button, button.dataset.unavailableLabel || "Tickets unavailable");
};

/**
 * Updates button disabled state based on event timing.
 * @param {HTMLButtonElement|null} button - Button to update
 * @param {{isPastEvent: boolean}} meta - Attendance metadata
 */
const updateButtonStateForEventDate = (button, meta) => {
  if (!button) {
    return;
  }
  if (meta.isPastEvent) {
    button.disabled = true;
    button.title = "You cannot change attendance because the event has already started.";
    button.classList.add("cursor-not-allowed", "opacity-50");
  } else {
    button.disabled = false;
    button.removeAttribute("title");
    button.classList.remove("cursor-not-allowed", "opacity-50");
  }
};

/**
 * Applies sold-out state to the attend button when needed.
 * @param {HTMLButtonElement|null} button - Button to update
 * @param {{isSoldOut: boolean, isPastEvent: boolean, isTicketed: boolean, waitlistEnabled: boolean}} meta - Attendance metadata
 */
const applySoldOutState = (button, meta) => {
  if (!button) {
    return;
  }
  if (meta.isTicketed) {
    return;
  }
  if (meta.isPastEvent) {
    return;
  }
  if (meta.isSoldOut) {
    if (meta.waitlistEnabled) {
      button.disabled = false;
      button.removeAttribute("title");
      button.classList.remove("cursor-not-allowed", "opacity-50");
      setAttendanceControlLabel(button, button.dataset.waitlistLabel || "Join waiting list");
    } else {
      button.disabled = true;
      button.title = "This event is sold out.";
      button.classList.add("cursor-not-allowed", "opacity-50");
    }
  } else if (!meta.isPastEvent) {
    button.removeAttribute("title");
    button.classList.remove("cursor-not-allowed", "opacity-50");
    setAttendanceControlLabel(button, button.dataset.attendLabel || "Attend event");
  }
};

/**
 * Shows the appropriate unauthenticated attendance control for an event.
 * @param {HTMLButtonElement|null} attendButton - Attend control button
 * @param {HTMLButtonElement|null} signinButton - Sign-in control button
 * @param {{isSoldOut: boolean, isPastEvent: boolean, isTicketed: boolean, ticketPurchaseAvailable: boolean, waitlistEnabled: boolean}} meta - Attendance metadata
 */
const showSignedOutAttendanceState = (attendButton, signinButton, meta) => {
  if (meta.isTicketed && !meta.ticketPurchaseAvailable && !meta.isPastEvent) {
    attendButton?.classList.remove("hidden");
    applyUnavailableTicketState(attendButton);
    return;
  }

  if (meta.isSoldOut && !meta.waitlistEnabled) {
    attendButton?.classList.remove("hidden");
    updateButtonStateForEventDate(attendButton, meta);
    applySoldOutState(attendButton, meta);
    return;
  }

  signinButton?.classList.remove("hidden");
  updateButtonStateForEventDate(signinButton, meta);
  updateSigninButtonLabel(signinButton, meta);
};

/**
 * Toggles meeting detail visibility based on attendance status.
 * @param {boolean} isAttendee - Whether the user is attending
 * @param {{eventIsLive: boolean}} meta - Attendance metadata
 */
const toggleMeetingDetailsVisibility = (isAttendee, meta) => {
  const sections = document.querySelectorAll("[data-meeting-details]");

  sections.forEach((section) => {
    const sectionHasRecording = section.dataset?.hasRecording === "true";
    const showSection = sectionHasRecording || isAttendee;
    section.classList.toggle("hidden", !showSection);
  });

  const joinLinksAlways = document.querySelectorAll("[data-join-link-always]");
  joinLinksAlways.forEach((link) => {
    link.classList.toggle("hidden", !isAttendee);
  });

  const joinLinksLive = document.querySelectorAll("[data-join-link]");
  joinLinksLive.forEach((link) => {
    link.classList.toggle("hidden", !(isAttendee && meta.eventIsLive));
  });
};

/**
 * Initializes attendance UI elements for a container.
 * @param {HTMLElement} container - Attendance container element
 */
const initializeAttendanceContainer = (container) => {
  if (!container || container.dataset.attendanceReady === "true") {
    return;
  }

  const meta = getAttendanceMeta(container);
  const attendButton = getAttendanceControl(container, "attend-btn");
  const leaveButton = getAttendanceControl(container, "leave-btn");
  const refundButton = getAttendanceControl(container, "refund-btn");
  const signinButton = getAttendanceControl(container, "signin-btn");

  updateButtonStateForEventDate(attendButton, meta);
  applySoldOutState(attendButton, meta);
  updateButtonStateForEventDate(leaveButton, meta);
  setAttendanceControlLabel(leaveButton, leaveButton?.dataset.attendeeLabel || "Cancel attendance");
  updateButtonStateForEventDate(refundButton, meta);
  setAttendanceControlLabel(refundButton, refundButton?.dataset.refundLabel || "Request refund");
  updateButtonStateForEventDate(signinButton, meta);
  updateSigninButtonLabel(signinButton, meta);

  container.dataset.attendanceReady = "true";
};

/**
 * Handles attendance check responses.
 * @param {Event} event - htmx:afterRequest event
 */
const handleAttendanceCheckResponse = (event) => {
  const target = event.target;
  if (!(target instanceof HTMLElement) || target.dataset.attendanceRole !== "attendance-checker") {
    return;
  }

  const container = target.closest(ATTENDANCE_CONTAINER_SELECTOR);
  if (!container) {
    return;
  }

  const loadingButton = getAttendanceControl(container, "loading-btn");
  const signinButton = getAttendanceControl(container, "signin-btn");
  const attendButton = getAttendanceControl(container, "attend-btn");
  const leaveButton = getAttendanceControl(container, "leave-btn");
  const refundButton = getAttendanceControl(container, "refund-btn");

  if (!loadingButton || !signinButton || !attendButton || !leaveButton || !refundButton) {
    return;
  }

  loadingButton.classList.add("hidden");
  signinButton.classList.add("hidden");
  attendButton.classList.add("hidden");
  leaveButton.classList.add("hidden");
  refundButton.classList.add("hidden");
  delete attendButton.dataset.resumeUrl;

  const meta = getAttendanceMeta(container);
  const xhr = event.detail?.xhr;

  if (isSuccessfulXHRStatus(xhr?.status)) {
    try {
      const response = JSON.parse(xhr.responseText);

      if (response.status === "attendee") {
        if (response.refund_request_status === "pending") {
          refundButton.classList.remove("hidden");
          refundButton.disabled = true;
          refundButton.title = "Your refund request is waiting for organizer review.";
          refundButton.classList.add("cursor-not-allowed", "opacity-50");
          setAttendanceControlLabel(refundButton, refundButton.dataset.pendingLabel || "Refund requested");
        } else if (response.refund_request_status === "approving") {
          refundButton.classList.remove("hidden");
          refundButton.disabled = true;
          refundButton.title = "Your refund is being processed.";
          refundButton.classList.add("cursor-not-allowed", "opacity-50");
          setAttendanceControlLabel(refundButton, refundButton.dataset.approvingLabel || "Refund processing");
        } else if (response.refund_request_status === "rejected") {
          refundButton.classList.remove("hidden");
          refundButton.disabled = true;
          refundButton.title = "Your refund request was rejected. Contact the organizers for help.";
          refundButton.classList.add("cursor-not-allowed", "opacity-50");
          setAttendanceControlLabel(refundButton, refundButton.dataset.rejectedLabel || "Refund unavailable");
        } else if (response.can_request_refund) {
          refundButton.classList.remove("hidden");
          setAttendanceControlLabel(refundButton, refundButton.dataset.refundLabel || "Request refund");
          updateButtonStateForEventDate(refundButton, meta);
        } else if ((response.purchase_amount_minor || 0) > 0) {
          refundButton.classList.remove("hidden");
          refundButton.disabled = true;
          refundButton.title = "Refunds are no longer available for this ticket.";
          refundButton.classList.add("cursor-not-allowed", "opacity-50");
          setAttendanceControlLabel(refundButton, refundButton.dataset.rejectedLabel || "Refund unavailable");
        } else {
          leaveButton.classList.remove("hidden");
          setAttendanceControlLabel(leaveButton, leaveButton.dataset.attendeeLabel || "Cancel attendance");
          updateButtonStateForEventDate(leaveButton, meta);
        }
        toggleMeetingDetailsVisibility(true, meta);
      } else if (response.status === "pending-payment") {
        attendButton.classList.remove("hidden");
        attendButton.dataset.resumeUrl = response.resume_checkout_url || "";
        setAttendanceControlLabel(attendButton, attendButton.dataset.completeLabel || "Complete payment");
        updateButtonStateForEventDate(attendButton, meta);
        toggleMeetingDetailsVisibility(false, meta);
      } else if (response.status === "waitlisted") {
        leaveButton.classList.remove("hidden");
        setAttendanceControlLabel(leaveButton, leaveButton.dataset.waitlistLabel || "Leave waiting list");
        updateButtonStateForEventDate(leaveButton, meta);
        toggleMeetingDetailsVisibility(false, meta);
      } else {
        attendButton.classList.remove("hidden");
        if (meta.isTicketed && !meta.ticketPurchaseAvailable && !meta.isPastEvent) {
          applyUnavailableTicketState(attendButton);
        } else if (meta.isSoldOut) {
          applySoldOutState(attendButton, meta);
        } else {
          updateButtonStateForEventDate(attendButton, meta);
        }
        toggleMeetingDetailsVisibility(false, meta);
      }
      return;
    } catch (error) {
      showSignedOutAttendanceState(attendButton, signinButton, meta);
      toggleMeetingDetailsVisibility(false, meta);
      return;
    }
  }

  showSignedOutAttendanceState(attendButton, signinButton, meta);
  toggleMeetingDetailsVisibility(false, meta);
};

/**
 * Handles attend button beforeRequest state.
 * @param {HTMLElement} target - Event target
 */
const handleAttendBeforeRequest = (target) => {
  if (target.dataset.attendanceRole !== "attend-btn") {
    return;
  }

  const container = target.closest(ATTENDANCE_CONTAINER_SELECTOR);
  const loadingButton = getAttendanceControl(container, "loading-btn");
  if (!loadingButton) {
    return;
  }

  target.classList.add("hidden");
  loadingButton.classList.remove("hidden");
};

/**
 * Handles leave button beforeRequest state.
 * @param {HTMLElement} target - Event target
 */
const handleLeaveBeforeRequest = (target) => {
  if (target.dataset.attendanceRole !== "leave-btn") {
    return;
  }

  const container = target.closest(ATTENDANCE_CONTAINER_SELECTOR);
  const loadingButton = getAttendanceControl(container, "loading-btn");
  if (!loadingButton) {
    return;
  }

  target.classList.add("hidden");
  loadingButton.classList.remove("hidden");
};

/**
 * Handles refund button beforeRequest state.
 * @param {HTMLElement} target - Event target
 */
const handleRefundBeforeRequest = (target) => {
  if (target.dataset.attendanceRole !== "refund-btn") {
    return;
  }

  const container = target.closest(ATTENDANCE_CONTAINER_SELECTOR);
  const loadingButton = getAttendanceControl(container, "loading-btn");
  if (!loadingButton) {
    return;
  }

  target.classList.add("hidden");
  loadingButton.classList.remove("hidden");
};

/**
 * Handles attend button afterRequest state.
 * @param {Event} event - htmx:afterRequest event
 */
const handleAttendAfterRequest = (event) => {
  const target = event.target;
  if (!(target instanceof HTMLElement) || target.dataset.attendanceRole !== "attend-btn") {
    return;
  }

  const container = target.closest(ATTENDANCE_CONTAINER_SELECTOR);
  if (!container) {
    return;
  }

  const loadingButton = getAttendanceControl(container, "loading-btn");
  const attendButton = getAttendanceControl(container, "attend-btn");
  if (!loadingButton || !attendButton) {
    return;
  }

  const xhr = event.detail?.xhr;
  const ok = handleHtmxResponse({
    xhr,
    successMessage: "",
    errorMessage: "Something went wrong registering for this event. Please try again later.",
  });

  if (ok) {
    try {
      const response = JSON.parse(xhr.responseText);
      if (response.redirect_url) {
        window.location.assign(response.redirect_url);
        return;
      }
      if (response.status === "waitlisted") {
        showInfoAlert("You have joined the waiting list for this event.");
      } else if (response.status === "pending-payment") {
        showInfoAlert("Your checkout is ready. Redirecting you to Stripe now.");
      } else {
        showInfoAlert("You have successfully registered for this event.");
      }
    } catch {
      showInfoAlert("You have successfully registered for this event.");
    }
    document.body.dispatchEvent(new Event("attendance-changed"));
  } else {
    loadingButton.classList.add("hidden");
    attendButton.classList.remove("hidden");
  }
};

/**
 * Handles leave button afterRequest state.
 * @param {Event} event - htmx:afterRequest event
 */
const handleLeaveAfterRequest = (event) => {
  const target = event.target;
  if (!(target instanceof HTMLElement) || target.dataset.attendanceRole !== "leave-btn") {
    return;
  }

  const container = target.closest(ATTENDANCE_CONTAINER_SELECTOR);
  if (!container) {
    return;
  }

  const loadingButton = getAttendanceControl(container, "loading-btn");
  const leaveButton = getAttendanceControl(container, "leave-btn");
  if (!loadingButton || !leaveButton) {
    return;
  }

  const xhr = event.detail?.xhr;
  const ok = handleHtmxResponse({
    xhr,
    successMessage: "",
    errorMessage: "Something went wrong canceling your attendance. Please try again later.",
  });

  if (ok) {
    try {
      const response = JSON.parse(xhr.responseText);
      if (response.left_status === "waitlisted") {
        showInfoAlert("You have left the waiting list for this event.");
      } else {
        showInfoAlert("You have successfully canceled your attendance.");
      }
    } catch {
      showInfoAlert("You have successfully canceled your attendance.");
    }
    document.body.dispatchEvent(new Event("attendance-changed"));
  } else {
    loadingButton.classList.add("hidden");
    leaveButton.classList.remove("hidden");
  }
};

/**
 * Handles refund button afterRequest state.
 * @param {Event} event - htmx:afterRequest event
 */
const handleRefundAfterRequest = (event) => {
  const target = event.target;
  if (!(target instanceof HTMLElement) || target.dataset.attendanceRole !== "refund-btn") {
    return;
  }

  const container = target.closest(ATTENDANCE_CONTAINER_SELECTOR);
  if (!container) {
    return;
  }

  const loadingButton = getAttendanceControl(container, "loading-btn");
  const refundButton = getAttendanceControl(container, "refund-btn");
  if (!loadingButton || !refundButton) {
    return;
  }

  const xhr = event.detail?.xhr;
  const ok = handleHtmxResponse({
    xhr,
    successMessage: "",
    errorMessage: "Something went wrong requesting your refund. Please try again later.",
  });

  if (ok) {
    showInfoAlert("Your refund request has been sent to the organizers.");
    document.body.dispatchEvent(new Event("attendance-changed"));
  } else {
    loadingButton.classList.add("hidden");
    refundButton.classList.remove("hidden");
  }
};

/**
 * Handles htmx:beforeRequest events for attendance buttons.
 * @param {Event} event - htmx:beforeRequest event
 */
const handleBeforeRequest = (event) => {
  const target = event.target;
  if (!(target instanceof HTMLElement)) {
    return;
  }

  if (!target.closest(ATTENDANCE_CONTAINER_SELECTOR)) {
    return;
  }

  handleAttendBeforeRequest(target);
  handleLeaveBeforeRequest(target);
  handleRefundBeforeRequest(target);
};

/**
 * Handles htmx:afterRequest events for attendance components.
 * @param {Event} event - htmx:afterRequest event
 */
const handleAfterRequest = (event) => {
  handleAttendanceCheckResponse(event);
  handleAttendAfterRequest(event);
  handleLeaveAfterRequest(event);
  handleRefundAfterRequest(event);
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

  if (!target.closest(ATTENDANCE_CONTAINER_SELECTOR)) {
    return;
  }

  const signinButton = target.closest('[data-attendance-role="signin-btn"]');
  if (signinButton) {
    const path = signinButton.dataset.path || window.location.pathname;
    const label = signinButton.querySelector("[data-attendance-label]")?.textContent || "Attend event";
    let actionText = label === "Join waiting list" ? "join the waiting list" : "attend this event";
    if (label === "Choose ticket") {
      actionText = "buy a ticket for this event";
    }
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

  const leaveButton = target.closest('[data-attendance-role="leave-btn"]');
  if (leaveButton) {
    const label = leaveButton.querySelector("[data-attendance-label]")?.textContent || "Cancel attendance";
    const message =
      label === "Leave waiting list"
        ? "Are you sure you want to leave the waiting list?"
        : "Are you sure you want to cancel your attendance?";
    showConfirmAlert(message, leaveButton.id, "Yes");
    return;
  }

  const refundButton = target.closest('[data-attendance-role="refund-btn"]');
  if (refundButton) {
    showConfirmAlert("Are you sure you want to request a refund for this ticket?", refundButton.id, "Yes");
  }
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
  document.body.addEventListener("htmx:beforeRequest", handleBeforeRequest);
  document.body.addEventListener("htmx:afterRequest", handleAfterRequest);
  document.body.addEventListener("click", handleAttendanceClick);
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
