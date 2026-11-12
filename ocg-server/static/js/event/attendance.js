import { initializeOnReadyAndHtmxLoad, markDatasetReady } from "/static/js/common/dom.js";
import { resolveUserLoggedIn } from "/static/js/common/user-session.js";
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
import { renderAttendanceCheckResponse } from "/static/js/event/attendance/status-renderer.js";
import "/static/js/event/directions-link.js";

/** Containers whose logged-out state was already looked up. */
const sessionCheckedContainers = new WeakSet();

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
    showSignedOutStateWhenLoggedOut(container);
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

/**
 * Shows the signed-out state once the login state is known. Logged-out visitors
 * send no enrollment check, so nothing else would end the loading state.
 * @param {HTMLElement} container - Attendance container element
 * @returns {void}
 */
const showSignedOutStateWhenLoggedOut = (container) => {
  if (sessionCheckedContainers.has(container)) {
    return;
  }

  sessionCheckedContainers.add(container);
  resolveUserLoggedIn().then((loggedIn) => {
    if (loggedIn === false && container.isConnected) {
      renderAttendanceCheckResponse(container, { detail: { xhr: null } });
    }
  });
};

initializeOnReadyAndHtmxLoad(initializeAttendance);
