export const ATTENDANCE_CONTAINER_SELECTOR = "[data-attendance-container]";

/**
 * Finds an attendance control inside a container.
 * @param {HTMLElement|null} container - Attendance container element
 * @param {string} role - Attendance control role
 * @returns {HTMLElement|null} Matching attendance control
 */
export const getAttendanceControl = (container, role) =>
  container?.querySelector(`[data-attendance-role="${role}"]`) ?? null;

/**
 * Returns the primary attendance status checker for the current page.
 * @returns {HTMLElement|null} Attendance checker element
 */
export const getAttendanceChecker = () =>
  document.querySelector('[data-attendance-role="attendance-checker"]') ?? null;

/**
 * Returns the nearest attendance container for an element.
 * @param {Element|null} target - Event target
 * @returns {HTMLElement|null} Attendance container
 */
export const getAttendanceContainer = (target) => {
  const container = target?.closest?.(ATTENDANCE_CONTAINER_SELECTOR);
  return container instanceof HTMLElement ? container : null;
};

/**
 * Returns all attendance containers within a root node.
 * @param {Document|HTMLElement} root - Root node to search
 * @returns {HTMLElement[]} Attendance containers
 */
export const getAttendanceContainers = (root) => {
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
 * Returns the primary controls for a container.
 * @param {HTMLElement} container - Attendance container element
 * @returns {{actionsMenu: HTMLElement|null, attendButton: HTMLElement|null, checkoutCancelButton: HTMLElement|null, checkoutResumeButton: HTMLElement|null, leaveButton: HTMLElement|null, loadingButton: HTMLElement|null, refundButton: HTMLElement|null, signinButton: HTMLElement|null}}
 */
export const getPrimaryControls = (container) => ({
  actionsMenu: getAttendanceControl(container, "actions-menu"),
  loadingButton: getAttendanceControl(container, "loading-btn"),
  signinButton: getAttendanceControl(container, "signin-btn"),
  attendButton: getAttendanceControl(container, "attend-btn"),
  checkoutCancelButton: getAttendanceControl(container, "checkout-cancel-btn"),
  checkoutResumeButton: getAttendanceControl(container, "checkout-resume-btn"),
  leaveButton: getAttendanceControl(container, "leave-btn"),
  refundButton: getAttendanceControl(container, "refund-btn"),
});

/**
 * Sets the visible label for an attendance control.
 * @param {HTMLElement|null} button - Attendance control button
 * @param {string} label - Label to display
 */
export const setAttendanceControlLabel = (button, label) => {
  const labelNode = button?.querySelector("[data-attendance-label]");
  if (labelNode) {
    labelNode.textContent = label;
  }
};

/**
 * Sets the visible icon for an attendance control.
 * @param {HTMLElement|null} button - Attendance control button
 * @param {string} iconClass - Icon class to apply
 */
export const setAttendanceControlIcon = (button, iconClass) => {
  const iconNode = button?.querySelector("[data-attendance-icon]");
  if (!iconNode) {
    return;
  }

  [...iconNode.classList].forEach((className) => {
    if (className.startsWith("icon-")) {
      iconNode.classList.remove(className);
    }
  });
  iconNode.classList.add(iconClass);
};

/**
 * Returns the visible label for an attendance control.
 * @param {HTMLElement|null} button - Attendance control button
 * @returns {string} Current label text
 */
export const getAttendanceControlLabel = (button) =>
  button?.querySelector("[data-attendance-label]")?.textContent?.trim() ?? "";

/**
 * Returns true when the ticket purchase modal is currently visible.
 * @param {HTMLElement|null} modal - Ticket modal element
 * @returns {boolean} True when the modal is open
 */
export const isTicketModalOpen = (modal) =>
  modal instanceof HTMLElement && !modal.classList.contains("hidden");

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
 * Returns the refreshed past-event state when availability has hydrated it.
 * @param {HTMLElement} container - Attendance container element
 * @returns {boolean|null} Parsed past-event state, or null if unavailable
 */
const parseHydratedIsPast = (container) => {
  const isPastAttr = container?.dataset?.isPast;
  if (isPastAttr === "true") {
    return true;
  }
  if (isPastAttr === "false") {
    return false;
  }

  return null;
};

/**
 * Computes attendance metadata for the current event.
 * @param {HTMLElement} container - Attendance container element
 * @returns {{attendeeApprovalRequired: boolean, attendeeMeetingAccessOpen: boolean, canceled: boolean, isPastEvent: boolean, isSoldOut: boolean, isTicketed: boolean, ticketPurchaseAvailable: boolean, waitlistEnabled: boolean}}
 */
export const getAttendanceMeta = (container) => {
  const startsAtValue = container?.dataset?.starts ?? null;
  const capacity = parseCapacity(container);
  const remainingCapacity = parseRemainingCapacity(container);
  const isSoldOut = capacity !== null && remainingCapacity !== null && remainingCapacity <= 0;
  const attendeeApprovalRequired = container?.dataset?.attendeeApprovalRequired === "true";
  const attendeeMeetingAccessOpen = container?.dataset?.attendeeMeetingAccessOpen === "true";
  const canceled = container?.dataset?.canceled === "true";
  const hydratedIsPast = parseHydratedIsPast(container);
  const isTicketed = container?.dataset?.isTicketed === "true";
  const ticketPurchaseAvailable = container?.dataset?.ticketPurchaseAvailable === "true";
  const waitlistEnabled = container?.dataset?.waitlistEnabled === "true";
  const isPastEvent = (() => {
    if (hydratedIsPast !== null) {
      return hydratedIsPast;
    }

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
    attendeeApprovalRequired,
    attendeeMeetingAccessOpen,
    canceled,
    isSoldOut,
    isPastEvent,
    ticketPurchaseAvailable,
    waitlistEnabled,
    isTicketed,
  };
};

/**
 * Returns the selected ticket type value from the ticket modal.
 * @param {HTMLElement} container - Attendance container element
 * @returns {string} Selected ticket type id, or an empty string
 */
export const getSelectedTicketTypeValue = (container) => {
  const selectedTicketType = container.querySelector('[data-attendance-role="ticket-type-option"]:checked');

  return selectedTicketType instanceof HTMLInputElement ? selectedTicketType.value : "";
};
