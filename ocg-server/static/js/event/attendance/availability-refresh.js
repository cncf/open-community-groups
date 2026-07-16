import { showErrorAlert } from "/static/js/common/alerts.js";
import {
  fetchAttendanceAvailability,
  renderAttendanceAvailability,
} from "/static/js/event/attendance-availability.js";
import { replayPendingAttendanceCheckResponse } from "/static/js/event/attendance/status-renderer.js";

const AVAILABILITY_REFRESH_ERROR_MESSAGE =
  "Something went wrong loading event availability. The page is showing the last available event details.";

/**
 * Applies a fresh public availability payload to the event page.
 * @param {HTMLElement} container - Attendance container element
 * @param {Object} availability - Public availability payload
 * @param {{rerenderAttendance?: boolean}} options - Render options
 * @returns {void}
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
 * @returns {void}
 */
export const handleAvailabilityRefreshFailure = (container, options = {}) => {
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
export const refreshAvailability = async (container, options = {}) => {
  const availability = await fetchAttendanceAvailability(container);
  if (!availability) {
    return;
  }

  applyAvailability(container, availability, options);
};

/**
 * Refreshes public availability before asking HTMX to redraw attendance state.
 * @param {HTMLElement} container - Attendance container element
 * @returns {void}
 */
export const refreshAvailabilityAndRenderAttendance = (container) => {
  if (!container?.dataset?.availabilityUrl) {
    document.body.dispatchEvent(new Event("attendance-changed"));
    return;
  }

  refreshAvailability(container, { rerenderAttendance: true }).catch(() => {
    handleAvailabilityRefreshFailure(container, { rerenderAttendance: true });
  });
};
