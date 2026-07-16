import { initializeOnReadyAndHtmxLoad, markDatasetReady } from "/static/js/common/dom.js";
import { getAttendanceContainers } from "/static/js/event/attendance-dom.js";
import { initializeAttendanceContainer } from "/static/js/event/attendance-view.js";
import {
  handleAvailabilityRefreshFailure,
  refreshAvailability,
} from "/static/js/event/attendance/availability-refresh.js";
import { handleAttendanceClick, handleAttendanceKeydown } from "/static/js/event/attendance/interactions.js";
import { reconcilePaymentReturn } from "/static/js/event/attendance/payment-return.js";
import { handleAttendanceSubmit } from "/static/js/event/attendance/questions.js";
import {
  handleAfterRequest,
  handleBeforeRequest,
  handleConfigRequest,
} from "/static/js/event/attendance/request-handlers.js";

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
