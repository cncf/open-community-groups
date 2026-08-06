import {
  isDatasetReady,
  isElementHidden,
  markDatasetReady,
  setElementHidden,
} from "/static/js/common/dom.js";
import { toggleModalVisibility } from "/static/js/common/modals/modal-lifecycle.js";
import {
  ATTEND_EVENT_LABEL,
  CANCEL_ATTENDANCE_LABEL,
  CANCEL_INVITATION_REQUEST_LABEL,
  CANCELED_EVENT_TITLE,
  CONTINUE_CHECKOUT_LABEL,
  GET_FREE_TICKET_LABEL,
  GET_TICKET_LABEL,
  JOIN_WAITLIST_LABEL,
  LEAVE_WAITLIST_LABEL,
  ON_WAITLIST_LABEL,
  REQUEST_INVITATION_LABEL,
  REQUEST_PENDING_LABEL,
  REQUEST_TICKET_LABEL,
} from "/static/js/event/attendance-copy.js";
import {
  getAttendanceControl,
  getAttendanceMeta,
  getPrimaryControls,
  setAttendanceControlDisabledStyles,
  setAttendanceControlIcon,
  setAttendanceControlLabel,
} from "/static/js/event/attendance-dom.js";
import { initializeTicketModalControls } from "/static/js/event/attendance-ticket-view.js";

const CANCEL_CHECKOUT_LABEL = "Cancel checkout";
const CLAIM_TICKET_LABEL = "Claim ticket";
const COMPLETE_REGISTRATION_LABEL = "Complete registration";
const CONFIRM_RSVP_LABEL = "Confirm RSVP";
const PAID_TICKETS_UNAVAILABLE_LABEL = "Paid tickets temporarily unavailable";
const REFUND_PROCESSING_LABEL = "Refund processing";
const REFUND_REJECTED_LABEL = "Refund rejected";
const REFUND_REQUESTED_LABEL = "Refund requested";
const REFUND_UNAVAILABLE_LABEL = "Refund unavailable";
const REQUEST_REFUND_LABEL = "Request refund";
const REQUEST_REJECTED_LABEL = "Request rejected";
const TICKET_OFFER_EXPIRED_LABEL = "Ticket offer expired";
const TICKETS_BY_INVITATION_LABEL = "Tickets are available by invitation only";
const TICKETS_UNAVAILABLE_LABEL = "Tickets unavailable";

const ON_WAITLIST_CANCEL_ARIA_LABEL = `${ON_WAITLIST_LABEL} – leave waiting list`;
const REQUEST_PENDING_CANCEL_ARIA_LABEL = `${REQUEST_PENDING_LABEL} – cancel request`;

const ATTEND_EVENT_ICON = "icon-user-plus";
const CANCEL_ACTION_ICON = "icon-cancel";
const QUESTIONS_TAB_ICON = "icon-list-check";
const REQUEST_INVITATION_ICON = "icon-request-invitation";

const CANCEL_CHECKOUT_TITLE = "Release this ticket hold and choose again.";
const INVITATION_PENDING_TITLE = "Your invitation request is waiting for organizer review.";
const INVITATION_REJECTED_TITLE = "Your invitation request was rejected.";
const NO_CAPACITY_TITLE = "This event has no attendee capacity.";
const PAST_EVENT_TITLE = "You cannot change attendance because the event has already started.";
const REFUND_CLOSED_TITLE = "Refunds are no longer available for this ticket.";
const REFUND_PENDING_TITLE = "Your refund request is waiting for organizer review.";
const REFUND_PROCESSING_TITLE = "Your refund is being processed.";
const REFUND_REJECTED_TITLE = "Your refund request was rejected. Contact the organizers for help.";
const SOLD_OUT_TITLE = "This event is sold out.";
const TICKETS_BY_INVITATION_TITLE = "Tickets for this event are available by invitation only.";
const TICKETS_UNAVAILABLE_TITLE = "Tickets are not currently available for this event.";

/**
 * Initializes attendance UI elements for a container.
 * @param {HTMLElement} container - Attendance container element
 */
export const initializeAttendanceContainer = (container) => {
  if (!container || isDatasetReady(container, "attendanceReady")) {
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
  markDatasetReady(container, "attendanceReady");
};

/**
 * Closes the event questions modal if it is open.
 * @param {HTMLElement} container - Attendance container element
 */
export const closeQuestionsModal = (container) => {
  const questionsModal = getAttendanceControl(container, "registration-modal");
  if (!(questionsModal instanceof HTMLElement) || !questionsModal.id || isElementHidden(questionsModal)) {
    return;
  }

  toggleModalVisibility(questionsModal.id);
};

/**
 * Closes the refund request modal if it is open.
 * @param {HTMLElement} container - Attendance container element
 */
export const closeRefundModal = (container) => {
  const refundModal = getAttendanceControl(container, "refund-modal");
  if (!(refundModal instanceof HTMLElement) || !refundModal.id || isElementHidden(refundModal)) {
    return;
  }

  toggleModalVisibility(refundModal.id);
};

/**
 * Opens the event questions modal.
 * @param {HTMLElement} container - Attendance container element
 */
export const openQuestionsModal = (container) => {
  const questionsModal = getAttendanceControl(container, "registration-modal");
  if (!(questionsModal instanceof HTMLElement) || !questionsModal.id) {
    return;
  }

  if (isElementHidden(questionsModal)) {
    toggleModalVisibility(questionsModal.id);
  }
};

/**
 * Opens the refund request modal.
 * @param {HTMLElement} container - Attendance container element
 * @param {HTMLElement|null} trigger - Element that opened the modal
 */
export const openRefundModal = (container, trigger = null) => {
  const refundForm = getAttendanceControl(container, "refund-form");
  const refundModal = getAttendanceControl(container, "refund-modal");
  if (!(refundModal instanceof HTMLElement) || !refundModal.id) {
    return;
  }

  if (refundForm instanceof HTMLFormElement) {
    refundForm.reset();
  }
  restoreRefundModalControls(container);
  if (isElementHidden(refundModal)) {
    toggleModalVisibility(refundModal.id, trigger);
  }
};

/**
 * Toggles meeting detail visibility based on attendance status.
 * @param {boolean} isAttendee - Whether the user is attending
 * @param {{attendeeMeetingAccessOpen: boolean, canceled: boolean}} meta - Attendance metadata
 */
export const renderMeetingDetails = (isAttendee, meta) => {
  const sections = document.querySelectorAll("[data-meeting-details]");
  const showAttendeeMeetingAccess = isAttendee && meta.attendeeMeetingAccessOpen && !meta.canceled;

  sections.forEach((section) => {
    const sectionHasRecording = section.dataset?.hasRecording === "true";
    setElementHidden(section, !(sectionHasRecording || showAttendeeMeetingAccess));
    section.querySelectorAll("[data-join-link-always]").forEach((link) => {
      setElementHidden(link, !showAttendeeMeetingAccess);
    });
  });

  const joinLinksLive = document.querySelectorAll("[data-join-link]");
  joinLinksLive.forEach((link) => {
    setElementHidden(link, !showAttendeeMeetingAccess);
    link.classList.toggle("xl:flex", showAttendeeMeetingAccess);
  });

  const joinLinksMenu = document.querySelectorAll("[data-join-link-menu]");
  joinLinksMenu.forEach((link) => {
    setElementHidden(link, !showAttendeeMeetingAccess);
    link.classList.toggle("max-xl:flex", showAttendeeMeetingAccess);
  });
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

  setElementHidden(loadingButton, true);
  if (role === "checkout-cancel-btn") {
    setElementHidden(getAttendanceControl(container, "attend-btn"), false);
    const actionsMenu = getAttendanceControl(container, "actions-menu");
    setElementHidden(actionsMenu, false);
  }
  setElementHidden(targetControl, false);
};

/**
 * Restores the refund modal controls after a request completes.
 * @param {HTMLElement} container - Attendance container element
 */
export const restoreRefundModalControls = (container) => {
  setRefundLoadingState(container, false);
};

/**
 * Shows a link to the dashboard surface that owns an active admission offer.
 * @param {HTMLElement} container - Attendance container element
 * @param {{isPastEvent: boolean}} meta - Attendance metadata
 * @param {{admission_offer_id?: string, event_ticket_type_id?: string}} response - Attendance response
 */
export const showAdmissionOfferState = (container, meta, response) => {
  const offerUrl = `/dashboard/user?tab=invitations#event-offer-${encodeURIComponent(
    response.admission_offer_id,
  )}`;
  showPrimaryAttendanceState(
    container,
    meta,
    "attendButton",
    withEventActionState(meta, {
      icon: "icon-ticket",
      label: meta.isSimpleRsvp ? CONFIRM_RSVP_LABEL : CLAIM_TICKET_LABEL,
      resumeUrl: offerUrl,
    }),
  );
};

/**
 * Shows the attendee state for an active attendee.
 * @param {HTMLElement} container - Attendance container element
 * @param {{isPastEvent: boolean}} meta - Attendance metadata
 * @param {{can_request_refund?: boolean, purchase_amount_minor?: number, refund_rejection_reason?: string, refund_request_status?: string}} response - Attendance response
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
    renderRefundRejectionReason(container, response);
  } else {
    renderControl(
      leaveButton,
      withEventActionState(meta, {
        icon: CANCEL_ACTION_ICON,
        label: CANCEL_ATTENDANCE_LABEL,
      }),
    );
  }

  renderMeetingDetails(true, meta);
};

/**
 * Shows the terminal state for the user's latest expired ticket offer.
 * @param {HTMLElement} container - Attendance container element
 * @param {{isPastEvent: boolean}} meta - Attendance metadata
 */
export const showExpiredOfferState = (container, meta) => {
  showPrimaryAttendanceState(
    container,
    meta,
    "attendButton",
    withEventActionState(meta, {
      disabled: true,
      icon: "icon-ticket",
      label: TICKET_OFFER_EXPIRED_LABEL,
    }),
  );
};

/**
 * Shows the guest state for an authenticated non-attendee.
 * @param {HTMLElement} container - Attendance container element
 * @param {{attendeeApprovalRequired: boolean, isPastEvent: boolean, isSimpleRsvp: boolean, ticketPurchaseAvailable: boolean, waitlistEnabled: boolean}} meta - Attendance metadata
 */
export const showGuestAttendanceState = (container, meta) => {
  showPrimaryAttendanceState(container, meta, "attendButton", getAttendState(meta));
};

/**
 * Shows the approved invitation state for an attendee.
 * @param {HTMLElement} container - Attendance container element
 * @param {{isPastEvent: boolean}} meta - Attendance metadata
 * @param {{manually_invited?: boolean}} response - Attendance response
 */
export const showInvitationApprovedAttendanceState = (container, meta, response = {}) => {
  const allowManualInvitation = response.manually_invited === true;

  if (meta.canceled) {
    showPrimaryAttendanceState(
      container,
      meta,
      "attendButton",
      withEventActionState(meta, {
        icon: ATTEND_EVENT_ICON,
        label: ATTEND_EVENT_LABEL,
      }),
    );
    return;
  }

  if (!meta.registrationWindowOpen) {
    showPrimaryAttendanceState(
      container,
      meta,
      "attendButton",
      withRegistrationWindowState(
        meta,
        {
          icon: ATTEND_EVENT_ICON,
          label: ATTEND_EVENT_LABEL,
        },
        {
          allowManualInvitation,
        },
      ),
    );
    return;
  }

  if (!allowManualInvitation && !meta.isPastEvent && meta.hasNoCapacity) {
    showPrimaryAttendanceState(container, meta, "attendButton", {
      disabled: true,
      icon: ATTEND_EVENT_ICON,
      label: ATTEND_EVENT_LABEL,
      title: NO_CAPACITY_TITLE,
    });
    return;
  }

  if (!allowManualInvitation && !meta.isPastEvent && meta.isSoldOut) {
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
    withRegistrationWindowState(
      meta,
      {
        icon: ATTEND_EVENT_ICON,
        label: ATTEND_EVENT_LABEL,
      },
      {
        allowManualInvitation,
      },
    ),
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
      ariaLabel: REQUEST_PENDING_CANCEL_ARIA_LABEL,
      icon: CANCEL_ACTION_ICON,
      label: REQUEST_PENDING_LABEL,
      title: INVITATION_PENDING_TITLE,
    }),
  );
};

/**
 * Shows the pending-payment state for an attendee.
 * @param {HTMLElement} container - Attendance container element
 * @param {{isPastEvent: boolean}} meta - Attendance metadata
 * @param {{resume_checkout_url?: string}} response - Attendance response
 */
export const showPendingPaymentState = (container, meta, response) => {
  const { actionsMenu, attendButton, checkoutCancelButton } = getPrimaryControls(container);

  resetPrimaryControls(container);
  setControlPriceBadgesHidden(container, true);
  renderControl(actionsMenu);
  renderControl(
    attendButton,
    withEventActionState(meta, {
      icon: "icon-ticket",
      label: CONTINUE_CHECKOUT_LABEL,
      resumeUrl: response.resume_checkout_url || "",
    }),
  );
  renderControl(checkoutCancelButton, {
    icon: "icon-cancel",
    label: CANCEL_CHECKOUT_LABEL,
    title: CANCEL_CHECKOUT_TITLE,
  });
  renderMeetingDetails(false, meta);
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
    setElementHidden(getAttendanceControl(container, "attend-btn"), true);
    const actionsMenu = getAttendanceControl(container, "actions-menu");
    setElementHidden(actionsMenu, true);
    if (actionsMenu instanceof HTMLDetailsElement) {
      actionsMenu.open = false;
    }
  }
  setElementHidden(targetControl, true);
  setElementHidden(loadingButton, false);
};

/**
 * Shows the refund modal loading state before the request starts.
 * @param {HTMLElement} container - Attendance container element
 */
export const showRefundLoadingState = (container) => {
  setRefundLoadingState(container, true);
};

/**
 * Shows the state for attendees promoted from the waitlist who need answers.
 * @param {HTMLElement} container - Attendance container element
 * @param {{canceled: boolean, isPastEvent: boolean}} meta - Attendance metadata
 */
export const showRegistrationQuestionsPendingState = (container, meta, response = {}) => {
  showPrimaryAttendanceState(
    container,
    meta,
    "attendButton",
    withRegistrationWindowState(
      meta,
      {
        icon: QUESTIONS_TAB_ICON,
        label: COMPLETE_REGISTRATION_LABEL,
      },
      {
        allowManualInvitation: response.manually_invited === true,
      },
    ),
  );

  const { attendButton } = getPrimaryControls(container);
  if (attendButton instanceof HTMLButtonElement) {
    attendButton.dataset.registrationQuestionsPending = "true";
  }
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
 * Shows the signed-out state for a container.
 * @param {HTMLElement} container - Attendance container element
 * @param {{attendeeApprovalRequired: boolean, isPastEvent: boolean, isSimpleRsvp: boolean, ticketPurchaseAvailable: boolean, waitlistEnabled: boolean}} meta - Attendance metadata
 */
export const showSignedOutAttendanceState = (container, meta) => {
  const { attendButton, signinButton } = getPrimaryControls(container);
  const attendState = getAttendState(meta);

  resetPrimaryControls(container);
  if (meta.canceled) {
    renderControl(attendButton, attendState);
    return;
  }

  if (!meta.isSimpleRsvp && attendState.disabled) {
    renderControl(attendButton, attendState);
    return;
  }

  if (
    (meta.isSoldOut || isSimpleRsvpSoldOut(meta)) &&
    !meta.waitlistEnabled &&
    !meta.attendeeApprovalRequired
  ) {
    renderControl(attendButton, getAttendState(meta));
    return;
  }

  renderControl(signinButton, getSigninState(meta));
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
    withEventActionState(meta, {
      ariaLabel: ON_WAITLIST_CANCEL_ARIA_LABEL,
      icon: CANCEL_ACTION_ICON,
      label: ON_WAITLIST_LABEL,
    }),
  );
};

/**
 * Computes the primary attend-button state for the current meta.
 * @param {{attendeeApprovalRequired: boolean, isPastEvent: boolean, isSimpleRsvp: boolean, ticketPurchaseAvailable: boolean, waitlistEnabled: boolean}} meta - Attendance metadata
 * @returns {object} Render state
 */
const getAttendState = (meta) => {
  if (meta.canceled) {
    return withEventActionState(meta, {
      icon: meta.attendeeApprovalRequired ? REQUEST_INVITATION_ICON : ATTEND_EVENT_ICON,
      label: getDefaultAttendLabel(meta),
    });
  }

  if (!meta.registrationWindowOpen) {
    return withRegistrationWindowState(meta, {
      icon: meta.attendeeApprovalRequired ? REQUEST_INVITATION_ICON : ATTEND_EVENT_ICON,
      label: getDefaultAttendLabel(meta),
    });
  }

  if (!meta.isSimpleRsvp) {
    if (meta.attendeeApprovalRequired) {
      return withRegistrationWindowState(meta, {
        icon: REQUEST_INVITATION_ICON,
        label: REQUEST_TICKET_LABEL,
      });
    }

    if (!meta.hasVisibleTicketTypes) {
      return {
        disabled: true,
        icon: "icon-ticket",
        label: TICKETS_BY_INVITATION_LABEL,
        title: TICKETS_BY_INVITATION_TITLE,
      };
    }

    if (meta.ticketPurchaseAvailable) {
      return withRegistrationWindowState(meta, {
        icon: "icon-ticket",
        label: getDefaultAttendLabel(meta),
      });
    }

    if (meta.waitlistEnabled && meta.hasSoldOutTicketTypes) {
      return withRegistrationWindowState(meta, {
        icon: "icon-ticket",
        label: JOIN_WAITLIST_LABEL,
      });
    }

    return {
      disabled: true,
      icon: "icon-ticket",
      label: meta.paidCapable ? PAID_TICKETS_UNAVAILABLE_LABEL : TICKETS_UNAVAILABLE_LABEL,
      title: TICKETS_UNAVAILABLE_TITLE,
    };
  }

  if (meta.attendeeApprovalRequired) {
    return withEventActionState(meta, {
      icon: REQUEST_INVITATION_ICON,
      label: REQUEST_INVITATION_LABEL,
    });
  }

  if (meta.hasNoCapacity && !meta.waitlistEnabled && !meta.isPastEvent) {
    return {
      disabled: true,
      icon: ATTEND_EVENT_ICON,
      label: ATTEND_EVENT_LABEL,
      title: NO_CAPACITY_TITLE,
    };
  }

  if (isSimpleRsvpSoldOut(meta) && !meta.isPastEvent) {
    if (meta.waitlistEnabled) {
      return withRegistrationWindowState(meta, {
        label: JOIN_WAITLIST_LABEL,
      });
    }

    return {
      disabled: true,
      label: ATTEND_EVENT_LABEL,
      title: SOLD_OUT_TITLE,
    };
  }

  return withRegistrationWindowState(meta, {
    icon: ATTEND_EVENT_ICON,
    label: getDefaultAttendLabel(meta),
  });
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
 * Returns the default attend label for a container.
 * @param {{attendeeApprovalRequired: boolean, isSimpleRsvp: boolean}} meta - Attendance metadata
 * @returns {string} Label text
 */
const getDefaultAttendLabel = (meta) => {
  if (!meta.isSimpleRsvp) {
    if (meta.attendeeApprovalRequired) {
      return REQUEST_TICKET_LABEL;
    }

    return meta.ticketIsFreeOnly ? GET_FREE_TICKET_LABEL : GET_TICKET_LABEL;
  }

  return meta.attendeeApprovalRequired ? REQUEST_INVITATION_LABEL : ATTEND_EVENT_LABEL;
};

/**
 * Returns the attendee refund-control state for the current response.
 * @param {{isPastEvent: boolean}} meta - Attendance metadata
 * @param {{can_request_refund?: boolean, purchase_amount_minor?: number, refund_rejection_reason?: string, refund_request_status?: string}} response - Attendance response
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
      label: REFUND_REJECTED_LABEL,
      title: REFUND_REJECTED_TITLE,
    };
  }

  if (response.can_request_refund) {
    return { label: REQUEST_REFUND_LABEL };
  }

  return {
    disabled: true,
    label: REFUND_UNAVAILABLE_LABEL,
    title: REFUND_CLOSED_TITLE,
  };
};

/**
 * Returns the default sign-in label for a container.
 * @param {{attendeeApprovalRequired: boolean, isSimpleRsvp: boolean, ticketPurchaseAvailable: boolean, waitlistEnabled: boolean}} meta - Attendance metadata
 * @returns {string} Label text
 */
const getSigninLabel = (meta) => {
  if (!meta.isSimpleRsvp) {
    if (meta.attendeeApprovalRequired) {
      return REQUEST_TICKET_LABEL;
    }

    if (!meta.hasVisibleTicketTypes) {
      return TICKETS_BY_INVITATION_LABEL;
    }

    if (meta.ticketPurchaseAvailable) {
      return meta.ticketIsFreeOnly ? GET_FREE_TICKET_LABEL : GET_TICKET_LABEL;
    }

    if (meta.waitlistEnabled && meta.hasSoldOutTicketTypes) {
      return JOIN_WAITLIST_LABEL;
    }

    return meta.paidCapable ? PAID_TICKETS_UNAVAILABLE_LABEL : TICKETS_UNAVAILABLE_LABEL;
  }

  if (meta.attendeeApprovalRequired) {
    return REQUEST_INVITATION_LABEL;
  }

  return isSimpleRsvpSoldOut(meta) && meta.waitlistEnabled ? JOIN_WAITLIST_LABEL : ATTEND_EVENT_LABEL;
};

/**
 * Returns the sign-in control state for the current attendance metadata.
 * @param {object} meta - Attendance metadata
 * @returns {object} Render state
 */
const getSigninState = (meta) => {
  const state = withEventActionState(meta, { label: getSigninLabel(meta) });
  if (!meta.isSimpleRsvp) {
    return state;
  }

  return {
    ...state,
    icon: meta.attendeeApprovalRequired ? REQUEST_INVITATION_ICON : ATTEND_EVENT_ICON,
  };
};

/**
 * Hides an attendance control.
 * @param {HTMLElement|null} control - Control to hide
 */
const hideControl = (control) => {
  if (!(control instanceof HTMLElement)) {
    return;
  }

  control.classList.remove("opacity-100");
  setElementHidden(control, true);
  control.classList.add("opacity-0", "transition-opacity", "duration-150");
};

/**
 * Returns whether the sole public RSVP tier has no selectable capacity.
 * @param {object} meta - Attendance metadata
 * @param {boolean} meta.hasNoCapacity - Whether the tier has no capacity
 * @param {boolean} meta.hasSoldOutTicketTypes - Whether ticket tiers are sold out
 * @param {boolean} meta.isSimpleRsvp - Whether the event uses simple RSVP
 * @param {boolean} meta.isSoldOut - Whether the event is sold out
 * @param {boolean} meta.ticketPurchaseAvailable - Whether tickets can be selected
 * @param {boolean} meta.waitlistEnabled - Whether the waiting list is enabled
 * @returns {boolean} Whether simple RSVP attendance is sold out
 */
const isSimpleRsvpSoldOut = (meta) =>
  meta.isSimpleRsvp &&
  ((meta.hasNoCapacity && meta.waitlistEnabled) ||
    meta.isSoldOut ||
    (!meta.ticketPurchaseAvailable && meta.hasSoldOutTicketTypes));

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
    ariaLabel = null,
    disabled = false,
    hidePriceBadge = false,
    icon = null,
    label = null,
    resumeUrl = null,
    title = null,
    visible = true,
  } = state;

  if (visible) {
    const wasHidden = isElementHidden(control);
    control.classList.add("opacity-0", "transition-opacity", "duration-150");
    setElementHidden(control, false);
    const showControl = () => {
      control.classList.remove("opacity-0");
      control.classList.add("opacity-100");
    };
    if (wasHidden && typeof window.requestAnimationFrame === "function") {
      window.requestAnimationFrame(showControl);
    } else {
      showControl();
    }
  }
  if (icon !== null) {
    setAttendanceControlIcon(control, icon);
  }
  if (label !== null) {
    setAttendanceControlLabel(control, label);
  }

  // Price badges describe fresh ticket purchase options, not user-specific states.
  const shouldHidePriceBadge =
    hidePriceBadge || (label !== null && label !== GET_TICKET_LABEL && label !== GET_FREE_TICKET_LABEL);
  getControlPriceBadges(control).forEach((priceBadge) => {
    setControlPriceBadgeHidden(priceBadge, shouldHidePriceBadge);
  });

  if (control instanceof HTMLButtonElement) {
    control.disabled = disabled;
  }

  if (ariaLabel) {
    control.setAttribute("aria-label", ariaLabel);
  } else {
    control.removeAttribute("aria-label");
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

  setAttendanceControlDisabledStyles(control, disabled);
};

/**
 * Shows an escaped attendee-visible reason for a rejected refund request.
 * @param {HTMLElement} container - Attendance container element
 * @param {{refund_rejection_reason?: string, refund_request_status?: string}} response - Attendance response
 */
const renderRefundRejectionReason = (container, response) => {
  const reason = getAttendanceControl(container, "refund-rejection-reason");
  const reasonText =
    typeof response.refund_rejection_reason === "string" ? response.refund_rejection_reason.trim() : "";

  if (!(reason instanceof HTMLElement) || response.refund_request_status !== "rejected" || !reasonText) {
    return;
  }

  reason.textContent = `Reason: ${reasonText}`;
  setElementHidden(reason, false);
};

/**
 * Hides all primary attendance controls for a container.
 * @param {HTMLElement} container - Attendance container element
 */
const resetPrimaryControls = (container) => {
  const {
    actionsMenu,
    loadingButton,
    signinButton,
    attendButton,
    checkoutCancelButton,
    checkoutResumeButton,
    leaveButton,
    refundButton,
  } = getPrimaryControls(container);
  const refundRejectionReason = getAttendanceControl(container, "refund-rejection-reason");

  setElementHidden(actionsMenu, false);
  hideControl(loadingButton);
  hideControl(signinButton);
  hideControl(attendButton);
  hideControl(checkoutCancelButton);
  hideControl(checkoutResumeButton);
  hideControl(leaveButton);
  hideControl(refundButton);
  if (refundRejectionReason instanceof HTMLElement) {
    refundRejectionReason.textContent = "";
    setElementHidden(refundRejectionReason, true);
  }
  setControlPriceBadgesHidden(container, false);

  if (attendButton instanceof HTMLButtonElement) {
    delete attendButton.dataset.resumeUrl;
    delete attendButton.dataset.registrationQuestionsPending;
  }
  if (checkoutResumeButton instanceof HTMLButtonElement) {
    delete checkoutResumeButton.dataset.resumeUrl;
  }
  if (actionsMenu instanceof HTMLDetailsElement) {
    actionsMenu.open = false;
  }
};

/**
 * Keeps native and utility-class badge visibility synchronized.
 * @param {HTMLElement} priceBadge Price badge to update.
 * @param {boolean} hidden Whether the badge should be hidden.
 * @returns {void}
 */
const setControlPriceBadgeHidden = (priceBadge, hidden) => {
  priceBadge.hidden = hidden;
  setElementHidden(priceBadge, hidden);
};

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
      setControlPriceBadgeHidden(priceBadge, hidden);
    });
  });
};

/**
 * Toggles the refund form loading affordance.
 * @param {HTMLElement} container - Attendance container element
 * @param {boolean} isLoading - Whether the refund request is loading
 */
const setRefundLoadingState = (container, isLoading) => {
  const refundSubmitButton = getAttendanceControl(container, "refund-modal-submit");
  const refundSubmitLabel = getAttendanceControl(container, "refund-modal-submit-label");
  const refundSubmitSpinner = getAttendanceControl(container, "refund-modal-submit-spinner");

  if (refundSubmitButton instanceof HTMLButtonElement) {
    refundSubmitButton.disabled = isLoading;
    setAttendanceControlDisabledStyles(refundSubmitButton, isLoading);
  }
  setElementHidden(refundSubmitSpinner, !isLoading);
  refundSubmitSpinner?.classList.toggle("flex", isLoading);
  refundSubmitLabel?.classList.toggle("invisible", isLoading);
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
 * Applies registration-window restrictions to attendee registration actions.
 * @param {{registrationWindowOpen: boolean, registrationWindowUnavailableTitle?: string}} meta - Attendance metadata
 * @param {object} state - Base render state
 * @param {{allowManualInvitation?: boolean}} options - Override options
 * @returns {object} Render state
 */
const withRegistrationWindowState = (meta, state, { allowManualInvitation = false } = {}) => {
  const eventState = withEventActionState(meta, state);
  if (eventState.disabled || allowManualInvitation || meta.registrationWindowOpen) {
    return eventState;
  }

  return {
    ...eventState,
    disabled: true,
    title: meta.registrationWindowUnavailableTitle,
  };
};
