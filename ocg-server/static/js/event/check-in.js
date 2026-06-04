import { handleHtmxResponse } from "/static/js/common/alerts.js";

const CHECK_IN_FORM_ID = "event-check-in-form";
const SUCCESS_CARD_ID = "check-in-success-card";
const FORM_CONTAINER_ID = "check-in-form-container";
const VIEW_DETAILS_BUTTON_ID = "view-event-details-button";
const CHECK_IN_READY_KEY = "checkInReady";

/**
 * Shows the checked-in state after a successful event check-in.
 */
const showCheckedInState = () => {
  document.getElementById(SUCCESS_CARD_ID)?.classList.remove("hidden");
  document.getElementById(FORM_CONTAINER_ID)?.classList.add("hidden");
  document.getElementById(CHECK_IN_FORM_ID)?.classList.add("hidden");
  document.getElementById(VIEW_DETAILS_BUTTON_ID)?.classList.remove("hidden");
};

/**
 * Handles the HTMX response for the event check-in form.
 * @param {CustomEvent} event - HTMX after-request event
 */
const handleCheckInResponse = (event) => {
  const ok = handleHtmxResponse({
    xhr: event.detail?.xhr,
    successMessage: "You're all checked in! Enjoy the event.",
    errorMessage: "Check-in failed. Please try again later.",
  });
  if (ok) {
    showCheckedInState();
  }
};

/**
 * Initializes the event check-in form response behavior.
 * @param {Document|Element} root - Root element containing the check-in form
 */
export const initializeEventCheckIn = (root = document) => {
  const form = root.querySelector(`#${CHECK_IN_FORM_ID}`);
  if (!form || form.dataset[CHECK_IN_READY_KEY] === "true") {
    return;
  }

  form.dataset[CHECK_IN_READY_KEY] = "true";
  form.addEventListener("htmx:afterRequest", handleCheckInResponse);
};

initializeEventCheckIn();
