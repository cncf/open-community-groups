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
  CANCEL_INVITATION_REQUEST_LABEL,
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
  showInvitationApprovedAttendanceState,
  showPendingApprovalAttendanceState,
  showPendingPaymentState,
  showPrimaryRequestLoading,
  showRejectedInvitationState,
  showSignedOutAttendanceState,
  showWaitlistedAttendanceState,
} from "/static/js/event/attendance-view.js";
import "/static/js/event/attendance-ticket-card.js";

const PAYMENT_RETURN_PARAM = "payment";
const PAYMENT_RETURN_POLL_ATTEMPTS = 8;
const PAYMENT_RETURN_POLL_INTERVAL_MS = 2000;
const PRIMARY_REQUEST_ROLES = new Set(["attend-btn", "checkout-cancel-btn", "leave-btn", "refund-btn"]);
const TICKET_PRICE_BADGE_CLASSES = [
  "inline-flex",
  "w-fit",
  "shrink-0",
  "self-center",
  "rounded-full",
  "border",
  "border-green-800",
  "bg-green-100",
  "px-2",
  "py-0.5",
  "text-[11px]",
  "font-semibold",
  "text-green-800",
];
const TICKET_STATUS_CLASSES = ["bg-green-500", "bg-red-500", "bg-stone-300"];
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
 * Returns a trimmed string value from an availability payload field.
 * @param {unknown} value - Availability payload field
 * @returns {string} Trimmed field value, or an empty string
 */
const getAvailabilityStringValue = (value) => (typeof value === "string" ? value.trim() : "");

/**
 * Returns true when a payload value is a finite number.
 * @param {unknown} value - Payload value
 * @returns {boolean} Whether the value is numeric
 */
const isFiniteNumberValue = (value) =>
  value !== null && value !== undefined && Number.isFinite(Number(value));

/**
 * Toggles an availability caption's responsive display classes.
 * @param {string} caption - Availability caption key
 * @param {boolean} visible - Whether the caption should be visible
 * @param {string[]} displayClasses - Classes used when visible
 */
const renderAvailabilityCaption = (caption, visible, displayClasses) => {
  document.querySelectorAll(`[data-availability-caption="${caption}"]`).forEach((node) => {
    node.classList.toggle("hidden", !visible);
    displayClasses.forEach((className) => {
      node.classList.toggle(className, visible);
    });
    node.classList.toggle("opacity-0", !visible);
    if (visible) {
      const fadeCaptionIn = () => node.classList.add("opacity-100");
      if (typeof window.requestAnimationFrame === "function") {
        window.requestAnimationFrame(fadeCaptionIn);
      } else {
        fadeCaptionIn();
      }
    } else {
      node.classList.remove("opacity-100");
    }
  });
};

/**
 * Updates the public capacity and waitlist counters from fresh availability.
 * @param {Object} availability - Public availability payload
 */
const renderAvailabilityCaptions = (availability) => {
  const capacity = Number(availability?.capacity);
  const remainingCapacity = Number(availability?.remaining_capacity);
  const waitlistCount = Number(availability?.waitlist_count);
  const hasCapacity = isFiniteNumberValue(availability?.capacity);
  const hasRemainingCapacity = isFiniteNumberValue(availability?.remaining_capacity) && remainingCapacity > 0;
  const hasWaitlistCount =
    isFiniteNumberValue(availability?.remaining_capacity) &&
    remainingCapacity <= 0 &&
    isFiniteNumberValue(availability?.waitlist_count) &&
    waitlistCount > 0;

  document.querySelectorAll("[data-availability-capacity]").forEach((node) => {
    node.textContent = hasCapacity ? String(capacity) : "";
  });
  document.querySelectorAll("[data-availability-remaining]").forEach((node) => {
    node.textContent = hasRemainingCapacity ? String(remainingCapacity) : "";
  });
  document.querySelectorAll("[data-availability-waitlist]").forEach((node) => {
    node.textContent = hasWaitlistCount ? String(waitlistCount) : "";
  });
  renderAvailabilityCaption("capacity", hasCapacity, ["flex"]);
  renderAvailabilityCaption("remaining", hasRemainingCapacity, ["inline"]);
  renderAvailabilityCaption("waitlist", hasWaitlistCount, ["inline"]);
};

/**
 * Updates the public sold-out ribbon from fresh availability.
 * @param {Object} availability - Public availability payload
 */
const renderAvailabilityRibbon = (availability) => {
  const capacity = Number(availability?.capacity);
  const remainingCapacity = Number(availability?.remaining_capacity);
  const isSoldOut =
    availability?.canceled !== true &&
    isFiniteNumberValue(availability?.capacity) &&
    capacity > 0 &&
    isFiniteNumberValue(availability?.remaining_capacity) &&
    remainingCapacity <= 0;

  document.querySelectorAll("[data-availability-sold-out-ribbon]").forEach((node) => {
    node.classList.toggle("hidden", !isSoldOut);
  });
};

/**
 * Updates an attendance container's metadata from fresh availability.
 * @param {HTMLElement} container - Attendance container element
 * @param {Object} availability - Public availability payload
 */
const updateAvailabilityMeta = (container, availability) => {
  container.dataset.attendeeApprovalRequired = String(availability.attendee_approval_required === true);
  container.dataset.attendeeMeetingAccessOpen = String(availability.is_live === true);
  container.dataset.canceled = String(availability.canceled === true);
  container.dataset.isPast = String(availability.is_past === true);
  container.dataset.isTicketed = String(availability.is_ticketed === true);
  container.dataset.ticketPurchaseAvailable = String(availability.has_sellable_ticket_types === true);
  container.dataset.waitlistEnabled = String(availability.waitlist_enabled === true);

  if (isFiniteNumberValue(availability.capacity)) {
    container.dataset.capacity = String(availability.capacity);
  } else {
    delete container.dataset.capacity;
  }

  if (isFiniteNumberValue(availability.remaining_capacity)) {
    container.dataset.remainingCapacity = String(availability.remaining_capacity);
  } else {
    delete container.dataset.remainingCapacity;
  }
};

/**
 * Updates a ticket price badge from fresh availability.
 * @param {HTMLElement|null|undefined} card - Ticket card element
 * @param {Object} ticket - Public ticket availability payload
 * @returns {boolean} True when the card displays a current price badge
 */
const renderTicketPriceBadge = (card, ticket) => {
  const priceLabel = getAvailabilityStringValue(ticket.current_price_label);
  const priceBadge = card?.querySelector('[data-attendance-role="ticket-type-price-badge"]');
  const summary = card?.querySelector('[data-attendance-role="ticket-type-summary"]');

  if (!priceLabel) {
    priceBadge?.remove();
    return false;
  }

  if (priceBadge instanceof HTMLElement) {
    priceBadge.textContent = priceLabel;
    return true;
  }

  if (!(summary instanceof HTMLElement)) {
    return false;
  }

  const nextPriceBadge = document.createElement("div");
  nextPriceBadge.dataset.attendanceRole = "ticket-type-price-badge";
  nextPriceBadge.classList.add(...TICKET_PRICE_BADGE_CLASSES);
  nextPriceBadge.textContent = priceLabel;
  summary.append(nextPriceBadge);
  return true;
};

/**
 * Updates a ticket status label and marker from fresh availability.
 * @param {HTMLInputElement} option - Ticket radio input
 * @param {Object} ticket - Public ticket availability payload
 */
const renderTicketAvailability = (option, ticket) => {
  const card = option.closest('[data-attendance-role="ticket-type-card"]');
  const cardBody = card?.querySelector('[data-attendance-role="ticket-type-card-body"]');
  const statusDot = card?.querySelector('[data-attendance-role="ticket-type-status-dot"]');
  const statusLabel = card?.querySelector('[data-attendance-role="ticket-type-status-label"]');
  const hasCurrentPriceBadge = renderTicketPriceBadge(card, ticket);
  const isSellableNow = ticket.is_sellable_now === true && hasCurrentPriceBadge;

  option.dataset.ticketPurchasable = String(isSellableNow);
  if (!isSellableNow && option.checked) {
    option.checked = false;
  }

  if (cardBody instanceof HTMLElement) {
    cardBody.classList.toggle("bg-white", isSellableNow);
    cardBody.classList.toggle("cursor-pointer", isSellableNow);
    cardBody.classList.toggle("hover:border-primary-300", isSellableNow);
    cardBody.classList.toggle("bg-stone-50", !isSellableNow);
    cardBody.classList.toggle("cursor-not-allowed", !isSellableNow);
    cardBody.classList.toggle("opacity-60", !isSellableNow);
  }

  if (statusDot instanceof HTMLElement) {
    statusDot.classList.remove(...TICKET_STATUS_CLASSES);
    if (ticket.sold_out === true) {
      statusDot.classList.add("bg-red-500");
    } else if (isSellableNow) {
      statusDot.classList.add("bg-green-500");
    } else {
      statusDot.classList.add("bg-stone-300");
    }
  }

  if (statusLabel instanceof HTMLElement) {
    if (ticket.sold_out === true) {
      statusLabel.textContent = "Sold out";
    } else if (isSellableNow) {
      statusLabel.textContent = "Available now";
    } else if (!isSellableNow) {
      statusLabel.textContent = "Not on sale";
    }
  }

  // Keep the radio state aligned with the rendered ticket card state.
  return isSellableNow;
};

/**
 * Creates a ticket card for availability entries missing from cached markup.
 * @param {HTMLElement} container - Attendance container element
 * @param {Object} ticket - Public ticket availability payload
 * @param {{canceled: boolean, ticketPurchaseAvailable: boolean}} meta - Attendance metadata
 * @returns {HTMLInputElement|null} The created ticket option, if any
 */
const createTicketAvailabilityCard = (container, ticket, meta) => {
  if (ticket.active === false) {
    return null;
  }

  const ticketTypeList = getAttendanceControl(container, "ticket-type-list");
  const eventTicketTypeId = getAvailabilityStringValue(ticket.event_ticket_type_id);
  if (!(ticketTypeList instanceof HTMLElement) || !eventTicketTypeId) {
    return null;
  }

  const card = document.createElement("attendance-ticket-card");
  card.ticket = ticket;
  card.canceled = meta.canceled;
  card.ticketPurchaseAvailable = meta.ticketPurchaseAvailable;
  card.addEventListener("change", () => {
    restoreCheckoutModalControls(container);
  });
  ticketTypeList.append(card);
  card.performUpdate?.();

  return card.querySelector('[data-attendance-role="ticket-type-option"]');
};

/**
 * Updates ticket controls from fresh availability.
 * @param {HTMLElement} container - Attendance container element
 * @param {Object[]} ticketTypes - Public ticket availability payloads
 */
const renderTicketAvailabilities = (container, ticketTypes = []) => {
  const meta = getAttendanceMeta(container);
  const ticketsById = new Map(ticketTypes.map((ticket) => [String(ticket.event_ticket_type_id), ticket]));
  const existingTicketIds = new Set(
    Array.from(container.querySelectorAll('[data-attendance-role="ticket-type-option"]'))
      .filter((option) => option instanceof HTMLInputElement)
      .map((option) => option.value),
  );

  ticketTypes.forEach((ticket) => {
    const eventTicketTypeId = getAvailabilityStringValue(ticket.event_ticket_type_id);
    if (eventTicketTypeId && !existingTicketIds.has(eventTicketTypeId)) {
      const option = createTicketAvailabilityCard(container, ticket, meta);
      if (option instanceof HTMLInputElement) {
        existingTicketIds.add(option.value);
      }
    }
  });

  container.querySelectorAll('[data-attendance-role="ticket-type-option"]').forEach((option) => {
    if (!(option instanceof HTMLInputElement)) {
      return;
    }

    const ticket = ticketsById.get(option.value) || {
      event_ticket_type_id: option.value,
      is_sellable_now: false,
      sold_out: false,
    };
    const isSellableNow = renderTicketAvailability(option, ticket);
    option.disabled = meta.canceled || !meta.ticketPurchaseAvailable || !isSellableNow;
  });

  restoreCheckoutModalControls(container);
};

/**
 * Applies a fresh public availability payload to the event page.
 * @param {HTMLElement} container - Attendance container element
 * @param {Object} availability - Public availability payload
 * @param {{rerenderAttendance?: boolean}} options - Render options
 */
const applyAvailability = (container, availability, options = {}) => {
  updateAvailabilityMeta(container, availability);
  renderAvailabilityCaptions(availability);
  renderAvailabilityRibbon(availability);
  renderTicketAvailabilities(container, availability.ticket_types || []);
  container.dataset.availabilityHydrated = "true";

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
  const availabilityUrl = container?.dataset?.availabilityUrl;
  if (!availabilityUrl) {
    return;
  }

  const response = await fetch(availabilityUrl, {
    cache: "no-store",
    credentials: "same-origin",
    headers: {
      Accept: "application/json",
    },
  });
  if (!response.ok) {
    throw new Error("failed to load availability");
  }

  applyAvailability(container, await response.json(), options);
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
  if (container.dataset.availabilityHydrated === "false") {
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

  const checkoutResumeButton = target.closest('[data-attendance-role="checkout-resume-btn"]');
  if (checkoutResumeButton instanceof HTMLButtonElement && checkoutResumeButton.dataset.resumeUrl) {
    event.preventDefault();
    window.location.assign(checkoutResumeButton.dataset.resumeUrl);
    return;
  }

  const leaveButton = target.closest('[data-attendance-role="leave-btn"]');
  if (leaveButton instanceof HTMLElement) {
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

  const checkoutCancelButton = target.closest('[data-attendance-role="checkout-cancel-btn"]');
  if (checkoutCancelButton instanceof HTMLElement) {
    showConfirmAlert(
      "Are you sure you want to cancel this checkout? Your ticket hold will be released.",
      checkoutCancelButton.id,
      "Yes",
    );
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
  getAttendanceContainers(root).forEach((container) => {
    initializeAttendanceContainer(container);

    if (container.dataset.availabilityReady !== "true") {
      container.dataset.availabilityReady = "true";
      if (container.dataset.availabilityUrl) {
        container.dataset.availabilityHydrated = "false";
      }
      refreshAvailability(container, { rerenderAttendance: true }).catch(() => {
        handleAvailabilityRefreshFailure(container, { rerenderAttendance: true });
      });
    }
  });

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
