import { toggleModalVisibility } from "/static/js/common/common.js";

import {
  getAttendanceControl,
  getAttendanceMeta,
  getPrimaryControls,
  getSelectedTicketTypeValue,
  isTicketModalOpen,
  setAttendanceControlIcon,
  setAttendanceControlLabel,
} from "/static/js/event/attendance-dom.js";

export const ATTEND_EVENT_LABEL = "Attend event";
export const BUY_TICKET_LABEL = "Buy ticket";
export const TICKETS_UNAVAILABLE_LABEL = "Tickets unavailable";
export const JOIN_WAITLIST_LABEL = "Join waiting list";
export const REQUEST_INVITATION_LABEL = "Request invitation";
export const COMPLETE_PAYMENT_LABEL = "Complete payment";
export const CANCEL_ATTENDANCE_LABEL = "Cancel attendance";
export const CANCEL_CHECKOUT_LABEL = "Cancel checkout";
export const CANCEL_INVITATION_REQUEST_LABEL = "Cancel request";
export const INVITATION_REQUESTED_LABEL = "Invitation requested";
export const REQUEST_REJECTED_LABEL = "Request rejected";
export const LEAVE_WAITLIST_LABEL = "Leave waiting list";
export const REQUEST_REFUND_LABEL = "Request refund";
export const REFUND_REQUESTED_LABEL = "Refund requested";
export const REFUND_PROCESSING_LABEL = "Refund processing";
export const REFUND_UNAVAILABLE_LABEL = "Refund unavailable";

const ATTEND_EVENT_ICON = "icon-user-plus";
const REQUEST_INVITATION_ICON = "icon-request-invitation";
const CANCELED_EVENT_TITLE = "This event has been canceled.";
const PAST_EVENT_TITLE = "You cannot change attendance because the event has already started.";
const TICKETS_UNAVAILABLE_TITLE = "Tickets are not currently available for this event.";
const SOLD_OUT_TITLE = "This event is sold out.";
const CHOOSE_TICKET_TITLE = "Choose a ticket to continue.";
const REFUND_PENDING_TITLE = "Your refund request is waiting for organizer review.";
const REFUND_PROCESSING_TITLE = "Your refund is being processed.";
const REFUND_REJECTED_TITLE = "Your refund request was rejected. Contact the organizers for help.";
const REFUND_CLOSED_TITLE = "Refunds are no longer available for this ticket.";
const PAST_CHECKOUT_TITLE = "You cannot buy tickets because the event has already started.";
const INVITATION_PENDING_TITLE = "Your invitation request is waiting for organizer review.";
const INVITATION_REJECTED_TITLE = "Your invitation request was rejected.";
const CANCEL_CHECKOUT_TITLE = "Release this ticket hold and choose again.";

/**
 * Returns the attendee refund-control state for the current response.
 * @param {{isPastEvent: boolean}} meta - Attendance metadata
 * @param {{can_request_refund?: boolean, purchase_amount_minor?: number, refund_request_status?: string}} response - Attendance response
 * @returns {{disabled?: boolean, label?: string|null, title?: string|null}} Render state
 */
const getRefundState = (meta, response) => {
  if (response.refund_request_status === "pending") {
    return {
      disabled: true,
      label: REFUND_REQUESTED_LABEL,
      title: REFUND_PENDING_TITLE,
    };
  }

  if (response.refund_request_status === "approving") {
    return {
      disabled: true,
      label: REFUND_PROCESSING_LABEL,
      title: REFUND_PROCESSING_TITLE,
    };
  }

  if (response.refund_request_status === "rejected") {
    return {
      disabled: true,
      label: REFUND_UNAVAILABLE_LABEL,
      title: REFUND_REJECTED_TITLE,
    };
  }

  if (response.can_request_refund) {
    return withEventActionState(meta, { label: REQUEST_REFUND_LABEL });
  }

  return {
    disabled: true,
    label: REFUND_UNAVAILABLE_LABEL,
    title: REFUND_CLOSED_TITLE,
  };
};

/**
 * Updates the disabled styling for a control.
 * @param {HTMLElement|null} control - Control to update
 * @param {boolean} disabled - Whether the control is disabled
 */
const setDisabledStyles = (control, disabled) => {
  control?.classList.toggle("cursor-not-allowed", disabled);
  control?.classList.toggle("opacity-50", disabled);
};

/**
 * Hides an attendance control.
 * @param {HTMLElement|null} control - Control to hide
 */
const hideControl = (control) => {
  control?.classList.add("hidden");
};

/**
 * Returns event price badges rendered inside a primary attendance control.
 * @param {HTMLElement} control - Attendance control to inspect
 * @returns {HTMLElement[]} Matching price badges
 */
const getControlPriceBadges = (control) =>
  Array.from(control.children).filter(
    (child) =>
      child instanceof HTMLElement &&
      child.tagName === "SPAN" &&
      !child.hasAttribute("data-attendance-label") &&
      (child.dataset.attendanceRole === "control-price-badge" ||
        (child.classList.contains("absolute") && child.classList.contains("left-1/2"))),
  );

/**
 * Toggles event price badges rendered inside primary attendance controls.
 * @param {HTMLElement} container - Attendance container element
 * @param {boolean} hidden - Whether the badges should be hidden
 */
const setControlPriceBadgesHidden = (container, hidden) => {
  const { signinButton, attendButton } = getPrimaryControls(container);
  [signinButton, attendButton].forEach((control) => {
    if (!(control instanceof HTMLElement)) {
      return;
    }

    getControlPriceBadges(control).forEach((priceBadge) => {
      priceBadge.hidden = hidden;
      priceBadge.classList.toggle("hidden", hidden);
      priceBadge.style.display = hidden ? "none" : "";
    });
  });
};

/**
 * Applies a rendered state to a control.
 * @param {HTMLElement|null} control - Control to update
 * @param {object} state - Render state
 */
const renderControl = (control, state = {}) => {
  if (!(control instanceof HTMLElement)) {
    return;
  }

  const {
    disabled = false,
    hidePriceBadge = false,
    icon = null,
    label = null,
    resumeUrl = null,
    title = null,
    visible = true,
  } = state;

  if (visible) {
    control.classList.remove("hidden");
  }
  if (icon !== null) {
    setAttendanceControlIcon(control, icon);
  }
  if (label !== null) {
    setAttendanceControlLabel(control, label);
  }

  // Price badges describe fresh ticket purchase options, not user-specific states.
  const shouldHidePriceBadge = hidePriceBadge || (label !== null && label !== BUY_TICKET_LABEL);
  getControlPriceBadges(control).forEach((priceBadge) => {
    priceBadge.hidden = shouldHidePriceBadge;
    priceBadge.classList.toggle("hidden", shouldHidePriceBadge);
    priceBadge.style.display = shouldHidePriceBadge ? "none" : "";
  });

  if (control instanceof HTMLButtonElement) {
    control.disabled = disabled;
  }

  if (title) {
    control.title = title;
  } else {
    control.removeAttribute("title");
  }

  if (control instanceof HTMLButtonElement) {
    if (resumeUrl) {
      control.dataset.resumeUrl = resumeUrl;
    } else {
      delete control.dataset.resumeUrl;
    }
  }

  setDisabledStyles(control, disabled);
};

/**
 * Applies event-level action restrictions when needed.
 * @param {{canceled: boolean, isPastEvent: boolean}} meta - Attendance metadata
 * @param {object} state - Base render state
 * @returns {object} Render state
 */
const withEventActionState = (meta, state) => {
  if (meta.canceled) {
    return {
      ...state,
      disabled: true,
      title: CANCELED_EVENT_TITLE,
    };
  }

  if (!meta.isPastEvent) {
    return state;
  }

  return {
    ...state,
    disabled: true,
    title: PAST_EVENT_TITLE,
  };
};

/**
 * Returns the default sign-in label for a container.
 * @param {{attendeeApprovalRequired: boolean, isSoldOut: boolean, isTicketed: boolean, ticketPurchaseAvailable: boolean, waitlistEnabled: boolean}} meta - Attendance metadata
 * @returns {string} Label text
 */
const getSigninLabel = (meta) => {
  if (meta.isTicketed) {
    return meta.ticketPurchaseAvailable ? BUY_TICKET_LABEL : TICKETS_UNAVAILABLE_LABEL;
  }

  if (meta.attendeeApprovalRequired) {
    return REQUEST_INVITATION_LABEL;
  }

  return meta.isSoldOut && meta.waitlistEnabled ? JOIN_WAITLIST_LABEL : ATTEND_EVENT_LABEL;
};

const getSigninState = (meta) => {
  const state = withEventActionState(meta, { label: getSigninLabel(meta) });
  if (meta.isTicketed) {
    return state;
  }

  return {
    ...state,
    icon: meta.attendeeApprovalRequired ? REQUEST_INVITATION_ICON : ATTEND_EVENT_ICON,
  };
};

/**
 * Returns the default attend label for a container.
 * @param {{attendeeApprovalRequired: boolean, isTicketed: boolean}} meta - Attendance metadata
 * @returns {string} Label text
 */
const getDefaultAttendLabel = (meta) => {
  if (meta.isTicketed) {
    return BUY_TICKET_LABEL;
  }

  return meta.attendeeApprovalRequired ? REQUEST_INVITATION_LABEL : ATTEND_EVENT_LABEL;
};

/**
 * Computes the primary attend-button state for the current meta.
 * @param {{attendeeApprovalRequired: boolean, isPastEvent: boolean, isSoldOut: boolean, isTicketed: boolean, ticketPurchaseAvailable: boolean, waitlistEnabled: boolean}} meta - Attendance metadata
 * @returns {object} Render state
 */
const getAttendState = (meta) => {
  if (meta.canceled) {
    return withEventActionState(meta, {
      icon: meta.attendeeApprovalRequired ? REQUEST_INVITATION_ICON : ATTEND_EVENT_ICON,
      label: getDefaultAttendLabel(meta),
    });
  }

  if (meta.isTicketed && !meta.ticketPurchaseAvailable && !meta.isPastEvent) {
    return {
      disabled: true,
      label: TICKETS_UNAVAILABLE_LABEL,
      title: TICKETS_UNAVAILABLE_TITLE,
    };
  }

  if (meta.attendeeApprovalRequired) {
    return withEventActionState(meta, {
      icon: REQUEST_INVITATION_ICON,
      label: REQUEST_INVITATION_LABEL,
    });
  }

  if (!meta.isTicketed && meta.isSoldOut && !meta.isPastEvent) {
    if (meta.waitlistEnabled) {
      return {
        label: JOIN_WAITLIST_LABEL,
      };
    }

    return {
      disabled: true,
      label: ATTEND_EVENT_LABEL,
      title: SOLD_OUT_TITLE,
    };
  }

  return withEventActionState(meta, {
    icon: ATTEND_EVENT_ICON,
    label: getDefaultAttendLabel(meta),
  });
};

/**
 * Hides all primary attendance controls for a container.
 * @param {HTMLElement} container - Attendance container element
 */
export const resetPrimaryControls = (container) => {
  const { loadingButton, signinButton, attendButton, checkoutCancelButton, leaveButton, refundButton } =
    getPrimaryControls(container);

  hideControl(loadingButton);
  hideControl(signinButton);
  hideControl(attendButton);
  hideControl(checkoutCancelButton);
  hideControl(leaveButton);
  hideControl(refundButton);
  setControlPriceBadgesHidden(container, false);

  if (attendButton instanceof HTMLButtonElement) {
    delete attendButton.dataset.resumeUrl;
  }
};

/**
 * Toggles meeting detail visibility based on attendance status.
 * @param {boolean} isAttendee - Whether the user is attending
 * @param {{eventIsLive: boolean}} meta - Attendance metadata
 */
export const renderMeetingDetails = (isAttendee, meta) => {
  const sections = document.querySelectorAll("[data-meeting-details]");
  const showAttendeeMeetingAccess = isAttendee && meta.attendeeMeetingAccessOpen;

  sections.forEach((section) => {
    const sectionHasRecording = section.dataset?.hasRecording === "true";
    section.classList.toggle("hidden", !(sectionHasRecording || showAttendeeMeetingAccess));
  });

  const joinLinksAlways = document.querySelectorAll("[data-join-link-always]");
  joinLinksAlways.forEach((link) => {
    link.classList.toggle("hidden", !showAttendeeMeetingAccess);
  });

  const joinLinksLive = document.querySelectorAll("[data-join-link]");
  joinLinksLive.forEach((link) => {
    link.classList.toggle("hidden", !showAttendeeMeetingAccess);
    link.classList.toggle("xl:flex", showAttendeeMeetingAccess);
  });
};

/**
 * Shows the signed-out state for a container.
 * @param {HTMLElement} container - Attendance container element
 * @param {{attendeeApprovalRequired: boolean, isPastEvent: boolean, isSoldOut: boolean, isTicketed: boolean, ticketPurchaseAvailable: boolean, waitlistEnabled: boolean}} meta - Attendance metadata
 */
export const showSignedOutAttendanceState = (container, meta) => {
  const { attendButton, signinButton } = getPrimaryControls(container);

  resetPrimaryControls(container);
  if (meta.canceled) {
    renderControl(attendButton, getAttendState(meta));
    return;
  }

  if (meta.isTicketed && !meta.ticketPurchaseAvailable && !meta.isPastEvent) {
    renderControl(attendButton, getAttendState(meta));
    return;
  }

  if (meta.isSoldOut && !meta.waitlistEnabled && !meta.attendeeApprovalRequired) {
    renderControl(attendButton, getAttendState(meta));
    return;
  }

  renderControl(signinButton, getSigninState(meta));
};

/**
 * Shows a single primary attendance control and updates meeting details.
 * @param {HTMLElement} container - Attendance container element
 * @param {object} meta - Attendance metadata
 * @param {"attendButton"|"checkoutCancelButton"|"leaveButton"|"refundButton"} controlName - Primary control key
 * @param {object} state - Render state
 * @param {boolean} [isAttendee=false] Whether meeting access should be attendee-scoped
 */
const showPrimaryAttendanceState = (container, meta, controlName, state, isAttendee = false) => {
  const controls = getPrimaryControls(container);

  resetPrimaryControls(container);
  renderControl(controls[controlName], state);
  renderMeetingDetails(isAttendee, meta);
};

/**
 * Shows the guest state for an authenticated non-attendee.
 * @param {HTMLElement} container - Attendance container element
 * @param {{attendeeApprovalRequired: boolean, isPastEvent: boolean, isSoldOut: boolean, isTicketed: boolean, ticketPurchaseAvailable: boolean, waitlistEnabled: boolean}} meta - Attendance metadata
 */
export const showGuestAttendanceState = (container, meta) => {
  showPrimaryAttendanceState(container, meta, "attendButton", getAttendState(meta));
};

/**
 * Shows the approved invitation state for an attendee.
 * @param {HTMLElement} container - Attendance container element
 * @param {{isPastEvent: boolean}} meta - Attendance metadata
 */
export const showInvitationApprovedAttendanceState = (container, meta) => {
  if (!meta.isPastEvent && meta.isSoldOut) {
    showPrimaryAttendanceState(container, meta, "attendButton", {
      disabled: true,
      icon: ATTEND_EVENT_ICON,
      label: ATTEND_EVENT_LABEL,
      title: SOLD_OUT_TITLE,
    });
    return;
  }

  showPrimaryAttendanceState(
    container,
    meta,
    "attendButton",
    withEventActionState(meta, {
      icon: ATTEND_EVENT_ICON,
      label: ATTEND_EVENT_LABEL,
    }),
  );
};

/**
 * Shows the waitlist state for an attendee.
 * @param {HTMLElement} container - Attendance container element
 * @param {{isPastEvent: boolean}} meta - Attendance metadata
 */
export const showWaitlistedAttendanceState = (container, meta) => {
  showPrimaryAttendanceState(
    container,
    meta,
    "leaveButton",
    withEventActionState(meta, { label: LEAVE_WAITLIST_LABEL }),
  );
};

/**
 * Shows the pending invitation request state for an attendee.
 * @param {HTMLElement} container - Attendance container element
 * @param {{isPastEvent: boolean}} meta - Attendance metadata
 */
export const showPendingApprovalAttendanceState = (container, meta) => {
  showPrimaryAttendanceState(
    container,
    meta,
    "leaveButton",
    withEventActionState(meta, {
      label: CANCEL_INVITATION_REQUEST_LABEL,
      title: INVITATION_PENDING_TITLE,
    }),
  );
};

/**
 * Shows the rejected invitation request state for an attendee.
 * @param {HTMLElement} container - Attendance container element
 */
export const showRejectedInvitationState = (container, meta) => {
  showPrimaryAttendanceState(container, meta, "attendButton", {
    disabled: true,
    label: REQUEST_REJECTED_LABEL,
    title: INVITATION_REJECTED_TITLE,
  });
};

/**
 * Shows the pending-payment state for an attendee.
 * @param {HTMLElement} container - Attendance container element
 * @param {{isPastEvent: boolean}} meta - Attendance metadata
 * @param {{resume_checkout_url?: string}} response - Attendance response
 */
export const showPendingPaymentState = (container, meta, response) => {
  const { checkoutCancelButton } = getPrimaryControls(container);

  showPrimaryAttendanceState(
    container,
    meta,
    "attendButton",
    withEventActionState(meta, {
      hidePriceBadge: true,
      label: COMPLETE_PAYMENT_LABEL,
      resumeUrl: response.resume_checkout_url || "",
    }),
  );
  setControlPriceBadgesHidden(container, true);
  renderControl(checkoutCancelButton, {
    icon: "icon-cancel",
    label: CANCEL_CHECKOUT_LABEL,
    title: CANCEL_CHECKOUT_TITLE,
  });
  renderMeetingDetails(false, meta);
};

/**
 * Shows the attendee state for an active attendee.
 * @param {HTMLElement} container - Attendance container element
 * @param {{isPastEvent: boolean}} meta - Attendance metadata
 * @param {{can_request_refund?: boolean, purchase_amount_minor?: number, refund_request_status?: string}} response - Attendance response
 */
export const showAttendeeState = (container, meta, response) => {
  const { leaveButton, refundButton } = getPrimaryControls(container);

  resetPrimaryControls(container);

  if (
    response.refund_request_status ||
    response.can_request_refund ||
    (response.purchase_amount_minor || 0) > 0
  ) {
    renderControl(refundButton, getRefundState(meta, response));
  } else {
    renderControl(leaveButton, withEventActionState(meta, { label: CANCEL_ATTENDANCE_LABEL }));
  }

  renderMeetingDetails(true, meta);
};

/**
 * Updates the enabled state for the modal checkout button.
 * @param {HTMLElement} container - Attendance container element
 */
export const updateCheckoutButtonState = (container) => {
  const meta = getAttendanceMeta(container);
  const checkoutButton = getAttendanceControl(container, "checkout-btn");
  const checkoutSpinner = getAttendanceControl(container, "checkout-btn-spinner");
  if (!(checkoutButton instanceof HTMLButtonElement)) {
    return;
  }

  const selectedTicketType = getSelectedTicketTypeValue(container);
  const shouldDisable =
    meta.canceled || !meta.ticketPurchaseAvailable || meta.isPastEvent || !selectedTicketType;

  checkoutButton.disabled = shouldDisable;
  setDisabledStyles(checkoutButton, shouldDisable);

  if (meta.canceled) {
    checkoutButton.title = CANCELED_EVENT_TITLE;
  } else if (!meta.ticketPurchaseAvailable) {
    checkoutButton.title = TICKETS_UNAVAILABLE_TITLE;
  } else if (meta.isPastEvent) {
    checkoutButton.title = PAST_CHECKOUT_TITLE;
  } else if (!selectedTicketType) {
    checkoutButton.title = CHOOSE_TICKET_TITLE;
  } else {
    checkoutButton.removeAttribute("title");
  }

  if (checkoutSpinner instanceof HTMLElement && !checkoutSpinner.classList.contains("hidden")) {
    checkoutButton.disabled = true;
  }
};

/**
 * Toggles the checkout button loading affordance.
 * @param {HTMLElement} container - Attendance container element
 * @param {boolean} isLoading - Whether checkout is loading
 */
const setCheckoutLoadingState = (container, isLoading) => {
  const checkoutSpinner = getAttendanceControl(container, "checkout-btn-spinner");
  const checkoutLabel = getAttendanceControl(container, "checkout-btn-label");

  checkoutSpinner?.classList.toggle("hidden", !isLoading);
  checkoutSpinner?.classList.toggle("flex", isLoading);
  checkoutLabel?.classList.toggle("invisible", isLoading);
};

/**
 * Synchronizes the ticket modal controls for the current modal mode.
 * @param {HTMLElement} container - Attendance container element
 */
const syncTicketModalState = (container) => {
  const discountCodeInput = getAttendanceControl(container, "discount-code-input");
  const ticketModalForm = getAttendanceControl(container, "ticket-modal-form");
  const meta = getAttendanceMeta(container);
  const ticketTypeOptions = container.querySelectorAll('[data-attendance-role="ticket-type-option"]');

  ticketModalForm?.classList.remove("hidden");
  setCheckoutLoadingState(container, false);

  ticketTypeOptions.forEach((ticketTypeOption) => {
    if (ticketTypeOption instanceof HTMLInputElement) {
      ticketTypeOption.disabled =
        meta.canceled ||
        !meta.ticketPurchaseAvailable ||
        ticketTypeOption.dataset.ticketPurchasable !== "true";
    }
  });

  if (discountCodeInput instanceof HTMLInputElement) {
    discountCodeInput.disabled = meta.canceled || !meta.ticketPurchaseAvailable;
  }

  updateCheckoutButtonState(container);
};

/**
 * Restores the modal checkout controls after a request completes or is canceled.
 * @param {HTMLElement} container - Attendance container element
 */
export const restoreCheckoutModalControls = (container) => {
  setCheckoutLoadingState(container, false);
  updateCheckoutButtonState(container);
};

/**
 * Shows the modal checkout loading state before the checkout request starts.
 * @param {HTMLElement} container - Attendance container element
 */
export const showCheckoutLoadingState = (container) => {
  const checkoutButton = getAttendanceControl(container, "checkout-btn");
  if (!(checkoutButton instanceof HTMLButtonElement)) {
    return;
  }

  checkoutButton.disabled = true;
  setDisabledStyles(checkoutButton, true);
  setCheckoutLoadingState(container, true);
};

/**
 * Registers one-time listeners for ticket modal form controls.
 * @param {HTMLElement} container - Attendance container element
 */
const initializeTicketModalControls = (container) => {
  if (container.dataset.ticketModalReady === "true") {
    syncTicketModalState(container);
    return;
  }

  container.dataset.ticketModalReady = "true";

  container.querySelectorAll('[data-attendance-role="ticket-type-option"]').forEach((ticketTypeOption) => {
    if (ticketTypeOption instanceof HTMLInputElement) {
      ticketTypeOption.addEventListener("change", () => {
        updateCheckoutButtonState(container);
      });
    }
  });

  syncTicketModalState(container);
};

/**
 * Opens the ticket purchase modal.
 * @param {HTMLElement} container - Attendance container element
 */
export const openTicketModal = (container) => {
  const ticketModal = getAttendanceControl(container, "ticket-modal");
  if (!(ticketModal instanceof HTMLElement)) {
    return;
  }

  syncTicketModalState(container);
  if (!isTicketModalOpen(ticketModal)) {
    toggleModalVisibility(ticketModal.id);
  }
};

/**
 * Closes the ticket purchase modal if it is open.
 * @param {HTMLElement} container - Attendance container element
 */
export const closeTicketModal = (container) => {
  const ticketModal = getAttendanceControl(container, "ticket-modal");
  if (!(ticketModal instanceof HTMLElement) || !isTicketModalOpen(ticketModal)) {
    return;
  }

  toggleModalVisibility(ticketModal.id);
};

/**
 * Shows the loading state for a primary attendance action.
 * @param {HTMLElement} container - Attendance container element
 * @param {string} role - Attendance control role
 */
export const showPrimaryRequestLoading = (container, role) => {
  const loadingButton = getAttendanceControl(container, "loading-btn");
  const targetControl = getAttendanceControl(container, role);
  if (!loadingButton || !targetControl) {
    return;
  }

  if (role === "checkout-cancel-btn") {
    getAttendanceControl(container, "attend-btn")?.classList.add("hidden");
  }
  targetControl.classList.add("hidden");
  loadingButton.classList.remove("hidden");
};

/**
 * Restores a primary control after a failed request.
 * @param {HTMLElement} container - Attendance container element
 * @param {string} role - Attendance control role
 */
export const restorePrimaryRequestControl = (container, role) => {
  const loadingButton = getAttendanceControl(container, "loading-btn");
  const targetControl = getAttendanceControl(container, role);
  if (!loadingButton || !targetControl) {
    return;
  }

  loadingButton.classList.add("hidden");
  if (role === "checkout-cancel-btn") {
    getAttendanceControl(container, "attend-btn")?.classList.remove("hidden");
  }
  targetControl.classList.remove("hidden");
};

/**
 * Initializes attendance UI elements for a container.
 * @param {HTMLElement} container - Attendance container element
 */
export const initializeAttendanceContainer = (container) => {
  if (!container || container.dataset.attendanceReady === "true") {
    return;
  }

  const meta = getAttendanceMeta(container);
  const { attendButton, leaveButton, refundButton, signinButton } = getPrimaryControls(container);

  renderControl(attendButton, { ...getAttendState(meta), visible: false });
  renderControl(leaveButton, {
    ...withEventActionState(meta, { label: CANCEL_ATTENDANCE_LABEL }),
    visible: false,
  });
  renderControl(refundButton, {
    ...withEventActionState(meta, { label: REQUEST_REFUND_LABEL }),
    visible: false,
  });
  renderControl(signinButton, {
    ...withEventActionState(meta, { label: getSigninLabel(meta) }),
    visible: false,
  });
  initializeTicketModalControls(container);

  container.dataset.attendanceReady = "true";
};
