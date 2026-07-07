import { showInfoAlert, showSuccessAlert } from "/static/js/common/alerts.js";
import { showProfileCompletionFeedbackAlert } from "/static/js/common/profile-completion-alert.js";

export const showProfileAwareInfoAlert = (trigger, message) => {
  if (!showProfileCompletionFeedbackAlert({ trigger, message })) {
    showInfoAlert(message);
  }
};

export const showSuccessAlertWithProfileCompletionCta = (trigger, message) => {
  if (!showProfileCompletionFeedbackAlert({ trigger, message, icon: "success" })) {
    showSuccessAlert(message);
  }
};
