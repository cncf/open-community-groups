import { showInfoAlert, showSuccessAlert } from "/static/js/common/alerts.js";
import { showProfileCompletionFeedbackAlert } from "/static/js/common/profile-completion-alert.js";

/**
 * Shows an info alert with a profile-completion CTA when available.
 * @param {HTMLElement|null} trigger Alert trigger context.
 * @param {string} message Alert message.
 * @returns {void}
 */
export const showProfileAwareInfoAlert = (trigger, message) => {
  if (!showProfileCompletionFeedbackAlert({ trigger, message })) {
    showInfoAlert(message);
  }
};

/**
 * Shows a success alert with a profile-completion CTA when available.
 * @param {HTMLElement|null} trigger Alert trigger context.
 * @param {string} message Alert message.
 * @returns {void}
 */
export const showSuccessAlertWithProfileCompletionCta = (trigger, message) => {
  if (!showProfileCompletionFeedbackAlert({ trigger, message, icon: "success" })) {
    showSuccessAlert(message);
  }
};
