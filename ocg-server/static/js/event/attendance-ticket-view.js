import { isElementHidden, markDatasetReady, setElementHidden } from "/static/js/common/dom.js";
import { toggleModalVisibility } from "/static/js/common/modals/modal-lifecycle.js";
import {
  CANCELED_EVENT_TITLE,
  CHOOSE_TICKET_TITLE,
  CONTINUE_CHECKOUT_LABEL,
  GET_FREE_TICKET_LABEL,
  JOIN_WAITLIST_LABEL,
  PAST_CHECKOUT_TITLE,
  REQUEST_TICKET_LABEL,
} from "/static/js/event/attendance-copy.js";
import {
  getAttendanceControl,
  getAttendanceMeta,
  getSelectedTicketTypeOption,
  isTicketModalOpen,
  setAttendanceControlDisabledStyles,
} from "/static/js/event/attendance-dom.js";
import { applyTicketCardState, readTicketCardState } from "/static/js/event/attendance-ticket-state.js";

/**
 * Closes the ticket purchase modal if it is open.
 * @param {HTMLElement} container Attendance container element.
 * @returns {void}
 */
export const closeTicketModal = (container) => {
  const ticketModal = getAttendanceControl(container, "ticket-modal");
  if (!(ticketModal instanceof HTMLElement) || !isTicketModalOpen(ticketModal)) {
    return;
  }

  toggleModalVisibility(ticketModal.id);
};

/**
 * Registers one-time listeners for ticket modal form controls.
 * @param {HTMLElement} container Attendance container element.
 * @returns {void}
 */
export const initializeTicketModalControls = (container) => {
  if (!markDatasetReady(container, "ticketModalReady")) {
    syncTicketModalState(container);
    return;
  }

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
 * @param {HTMLElement} container Attendance container element.
 * @returns {void}
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
 * Restores modal checkout controls after a request completes or is canceled.
 * @param {HTMLElement} container Attendance container element.
 * @returns {void}
 */
export const restoreCheckoutModalControls = (container) => {
  setCheckoutLoadingState(container, false);
  updateCheckoutButtonState(container);
};

/**
 * Shows the modal checkout loading state before a request starts.
 * @param {HTMLElement} container Attendance container element.
 * @returns {void}
 */
export const showCheckoutLoadingState = (container) => {
  const checkoutButton = getAttendanceControl(container, "checkout-btn");
  if (!(checkoutButton instanceof HTMLButtonElement)) {
    return;
  }

  checkoutButton.disabled = true;
  setAttendanceControlDisabledStyles(checkoutButton, true);
  setCheckoutLoadingState(container, true);
};

/**
 * Toggles the checkout button loading affordance.
 * @param {HTMLElement} container Attendance container element.
 * @param {boolean} isLoading Whether checkout is loading.
 * @returns {void}
 */
const setCheckoutLoadingState = (container, isLoading) => {
  const checkoutSpinner = getAttendanceControl(container, "checkout-btn-spinner");
  const checkoutLabel = getAttendanceControl(container, "checkout-btn-label");

  setElementHidden(checkoutSpinner, !isLoading);
  checkoutSpinner?.classList.toggle("flex", isLoading);
  checkoutLabel?.classList.toggle("invisible", isLoading);
};

/**
 * Synchronizes modal controls from canonical server or refreshed ticket data.
 * @param {HTMLElement} container Attendance container element.
 * @returns {void}
 */
const syncTicketModalState = (container) => {
  const ticketModalForm = getAttendanceControl(container, "ticket-modal-form");
  const ticketTypeOptions = container.querySelectorAll('[data-attendance-role="ticket-type-option"]');

  setElementHidden(ticketModalForm, false);
  setCheckoutLoadingState(container, false);

  ticketTypeOptions.forEach((ticketTypeOption) => {
    if (ticketTypeOption instanceof HTMLInputElement) {
      applyTicketCardState(ticketTypeOption, readTicketCardState(ticketTypeOption));
    }
  });

  updateCheckoutButtonState(container);
};

/**
 * Updates the enabled state and action label for the modal checkout button.
 * @param {HTMLElement} container Attendance container element.
 * @returns {void}
 */
const updateCheckoutButtonState = (container) => {
  const meta = getAttendanceMeta(container);
  const checkoutButton = getAttendanceControl(container, "checkout-btn");
  const checkoutLabel = getAttendanceControl(container, "checkout-btn-label");
  const checkoutSpinner = getAttendanceControl(container, "checkout-btn-spinner");
  const discountCodeInput = getAttendanceControl(container, "discount-code-input");
  if (!(checkoutButton instanceof HTMLButtonElement)) {
    return;
  }

  const selectedTicketType = getSelectedTicketTypeOption(container);
  const isRequest = selectedTicketType && meta.attendeeApprovalRequired;
  const isWaitlist =
    selectedTicketType &&
    !meta.attendeeApprovalRequired &&
    meta.waitlistEnabled &&
    selectedTicketType.dataset.ticketSoldOut === "true";
  const isCheckout = meta.ticketPurchaseAvailable && selectedTicketType?.dataset.ticketPurchasable === "true";
  const isSelectedTicketAction = isRequest || isWaitlist || isCheckout;
  const shouldDisable =
    meta.canceled || !meta.registrationWindowOpen || meta.isPastEvent || !isSelectedTicketAction;

  checkoutButton.disabled = shouldDisable;
  setAttendanceControlDisabledStyles(checkoutButton, shouldDisable);

  if (meta.canceled) {
    checkoutButton.title = CANCELED_EVENT_TITLE;
  } else if (!meta.registrationWindowOpen) {
    checkoutButton.title = meta.registrationWindowUnavailableTitle;
  } else if (meta.isPastEvent) {
    checkoutButton.title = PAST_CHECKOUT_TITLE;
  } else if (!isSelectedTicketAction) {
    checkoutButton.title = CHOOSE_TICKET_TITLE;
  } else {
    checkoutButton.removeAttribute("title");
  }

  if (checkoutSpinner instanceof HTMLElement && !isElementHidden(checkoutSpinner)) {
    checkoutButton.disabled = true;
  }

  if (checkoutLabel instanceof HTMLElement) {
    if (isRequest) {
      checkoutLabel.textContent = REQUEST_TICKET_LABEL;
    } else if (isWaitlist) {
      checkoutLabel.textContent = JOIN_WAITLIST_LABEL;
    } else if (selectedTicketType?.dataset.ticketPriceMinor === "0") {
      checkoutLabel.textContent = GET_FREE_TICKET_LABEL;
    } else {
      checkoutLabel.textContent = CONTINUE_CHECKOUT_LABEL;
    }
  }

  if (discountCodeInput instanceof HTMLInputElement) {
    discountCodeInput.disabled =
      meta.canceled ||
      !meta.registrationWindowOpen ||
      meta.attendeeApprovalRequired ||
      selectedTicketType?.dataset.ticketPurchasable !== "true" ||
      selectedTicketType?.dataset.ticketPriceMinor === "0";
  }
};
