import { showConfirmAlert, showInfoAlert, handleHtmxResponse } from "/static/js/common/alerts.js";
import { isSuccessfulXHRStatus } from "/static/js/common/common.js";

const ATTENDANCE_CONTAINER_SELECTOR = "#attendance-container";

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
 * Computes attendance metadata for the current event.
 * @param {HTMLElement} container - Attendance container element
 * @returns {{isSoldOut: boolean, isPastEvent: boolean, eventIsLive: boolean}}
 */
const getAttendanceMeta = (container) => {
  const startsAtValue = container?.dataset?.starts ?? null;
  const remainingCapacity = parseRemainingCapacity(container);
  const isSoldOut = remainingCapacity !== null && remainingCapacity <= 0;
  const eventIsLive = container?.dataset?.isLive === "true";
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
  };
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
 * @param {{isSoldOut: boolean, isPastEvent: boolean}} meta - Attendance metadata
 */
const applySoldOutState = (button, meta) => {
  if (!button) {
    return;
  }
  if (meta.isSoldOut) {
    button.disabled = true;
    button.title = "This event is sold out.";
    button.classList.add("cursor-not-allowed", "opacity-50");
  } else if (!meta.isPastEvent) {
    button.removeAttribute("title");
    button.classList.remove("cursor-not-allowed", "opacity-50");
  }
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
  const attendButton = container.querySelector("#attend-btn");
  const leaveButton = container.querySelector("#leave-btn");

  updateButtonStateForEventDate(attendButton, meta);
  applySoldOutState(attendButton, meta);
  updateButtonStateForEventDate(leaveButton, meta);

  container.dataset.attendanceReady = "true";
};

/**
 * Handles attendance check responses.
 * @param {Event} event - htmx:afterRequest event
 */
const handleAttendanceCheckResponse = (event) => {
  const target = event.target;
  if (!(target instanceof HTMLElement) || target.id !== "attendance-checker") {
    return;
  }

  const container = target.closest(ATTENDANCE_CONTAINER_SELECTOR);
  if (!container) {
    return;
  }

  const loadingButton = container.querySelector("#loading-btn");
  const signinButton = container.querySelector("#signin-btn");
  const attendButton = container.querySelector("#attend-btn");
  const leaveButton = container.querySelector("#leave-btn");

  if (!loadingButton || !signinButton || !attendButton || !leaveButton) {
    return;
  }

  loadingButton.classList.add("hidden");
  signinButton.classList.add("hidden");
  attendButton.classList.add("hidden");
  leaveButton.classList.add("hidden");

  const meta = getAttendanceMeta(container);
  const xhr = event.detail?.xhr;

  if (isSuccessfulXHRStatus(xhr?.status)) {
    try {
      const response = JSON.parse(xhr.responseText);

      if (response.is_attendee) {
        leaveButton.classList.remove("hidden");
        updateButtonStateForEventDate(leaveButton, meta);
        toggleMeetingDetailsVisibility(true, meta);
      } else {
        attendButton.classList.remove("hidden");
        if (meta.isSoldOut) {
          applySoldOutState(attendButton, meta);
        } else {
          updateButtonStateForEventDate(attendButton, meta);
        }
        toggleMeetingDetailsVisibility(false, meta);
      }
      return;
    } catch (error) {
      if (meta.isSoldOut) {
        attendButton.classList.remove("hidden");
        applySoldOutState(attendButton, meta);
      } else {
        signinButton.classList.remove("hidden");
        updateButtonStateForEventDate(signinButton, meta);
      }
      toggleMeetingDetailsVisibility(false, meta);
      return;
    }
  }

  if (meta.isSoldOut) {
    attendButton.classList.remove("hidden");
    applySoldOutState(attendButton, meta);
  } else {
    signinButton.classList.remove("hidden");
    updateButtonStateForEventDate(signinButton, meta);
  }
  toggleMeetingDetailsVisibility(false, meta);
};

/**
 * Handles attend button beforeRequest state.
 * @param {HTMLElement} target - Event target
 */
const handleAttendBeforeRequest = (target) => {
  if (target.id !== "attend-btn") {
    return;
  }

  const container = target.closest(ATTENDANCE_CONTAINER_SELECTOR);
  const loadingButton = container?.querySelector("#loading-btn");
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
  if (target.id !== "leave-btn") {
    return;
  }

  const container = target.closest(ATTENDANCE_CONTAINER_SELECTOR);
  const loadingButton = container?.querySelector("#loading-btn");
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
  if (!(target instanceof HTMLElement) || target.id !== "attend-btn") {
    return;
  }

  const container = target.closest(ATTENDANCE_CONTAINER_SELECTOR);
  if (!container) {
    return;
  }

  const loadingButton = container.querySelector("#loading-btn");
  const attendButton = container.querySelector("#attend-btn");
  if (!loadingButton || !attendButton) {
    return;
  }

  const xhr = event.detail?.xhr;
  const ok = handleHtmxResponse({
    xhr,
    successMessage: "You have successfully registered for this event.",
    errorMessage: "Something went wrong registering for this event. Please try again later.",
  });

  if (ok) {
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
  if (!(target instanceof HTMLElement) || target.id !== "leave-btn") {
    return;
  }

  const container = target.closest(ATTENDANCE_CONTAINER_SELECTOR);
  if (!container) {
    return;
  }

  const loadingButton = container.querySelector("#loading-btn");
  const leaveButton = container.querySelector("#leave-btn");
  if (!loadingButton || !leaveButton) {
    return;
  }

  const xhr = event.detail?.xhr;
  const ok = handleHtmxResponse({
    xhr,
    successMessage: "You have successfully canceled your attendance.",
    errorMessage: "Something went wrong canceling your attendance. Please try again later.",
  });

  if (ok) {
    document.body.dispatchEvent(new Event("attendance-changed"));
  } else {
    loadingButton.classList.add("hidden");
    leaveButton.classList.remove("hidden");
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
};

/**
 * Handles htmx:afterRequest events for attendance components.
 * @param {Event} event - htmx:afterRequest event
 */
const handleAfterRequest = (event) => {
  handleAttendanceCheckResponse(event);
  handleAttendAfterRequest(event);
  handleLeaveAfterRequest(event);
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

  const signinButton = target.closest("#signin-btn");
  if (signinButton) {
    const path = signinButton.dataset.path || window.location.pathname;
    showInfoAlert(
      `You need to be <a href='/log-in?next_url=${path}' class='underline font-medium' hx-boost='true'>logged in</a> to attend this event.`,
      true,
    );
    return;
  }

  const leaveButton = target.closest("#leave-btn");
  if (leaveButton) {
    showConfirmAlert("Are you sure you want to cancel your attendance?", "leave-btn", "Yes");
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
