import { getCommonAlertOptions } from "/static/js/common/alerts.js";

export const PROFILE_COMPLETION_URL = "/dashboard/user?tab=account";

const PROFILE_COMPLETE_SELECTOR = "[data-profile-complete]";

/**
 * Reads the current profile-completion state from an event action.
 * @param {Element|null|undefined} trigger Action element that owns the flow.
 * @returns {boolean} Whether the action should prompt for profile completion.
 */
export const shouldPromptForProfileCompletion = (trigger) => {
  const config = trigger?.closest?.(PROFILE_COMPLETE_SELECTOR);
  return config?.dataset?.profileComplete === "false";
};

/**
 * Shows the profile-completion prompt without blocking the original action.
 * @param {object} options Options.
 * @param {Element|null|undefined} options.trigger Action element that owns the flow.
 * @param {(url: string) => void} [options.navigateTo] Navigation callback.
 * @returns {boolean} Whether the prompt was displayed.
 */
export const showProfileCompletionAlert = ({
  trigger,
  navigateTo = (url) => window.location.assign(url),
} = {}) => {
  if (!shouldPromptForProfileCompletion(trigger) || typeof globalThis.Swal?.fire !== "function") {
    return false;
  }

  const commonOptions = getCommonAlertOptions();
  Swal.fire({
    ...commonOptions,
    title: "Make your profile yours",
    text:
      "Your profile is used across events, waitlists, proposals, and community spaces. " +
      "Add a few details so organizers and community members can recognize you.",
    icon: "info",
    confirmButtonText: "Complete profile",
    showCancelButton: true,
    cancelButtonText: "Continue anyway",
    position: "center",
    backdrop: true,
  }).then((result) => {
    if (result.isConfirmed) {
      navigateTo(PROFILE_COMPLETION_URL);
    }
  });

  return true;
};

/**
 * Shows action feedback with a profile-completion CTA when the profile is incomplete.
 * Used for successful attendance actions so one alert contains both messages.
 * @param {object} options Options.
 * @param {Element|null|undefined} options.trigger Action element that owns the flow.
 * @param {string} options.message Action feedback message.
 * @param {"info"|"success"} [options.icon="info"] Alert icon.
 * @param {(url: string) => void} [options.navigateTo] Navigation callback.
 * @returns {boolean} Whether the combined prompt was displayed.
 */
export const showProfileCompletionFeedbackAlert = ({
  trigger,
  message,
  icon = "info",
  navigateTo = (url) => window.location.assign(url),
} = {}) => {
  if (!message || !shouldPromptForProfileCompletion(trigger) || typeof globalThis.Swal?.fire !== "function") {
    return false;
  }

  const commonOptions = getCommonAlertOptions();
  Swal.fire({
    ...commonOptions,
    title: message,
    text: "Add a few profile details so organizers and community members can recognize you.",
    icon,
    confirmButtonText: "Complete profile",
    showCancelButton: true,
    cancelButtonText: "Maybe later",
    position: "center",
    backdrop: true,
  }).then((result) => {
    if (result.isConfirmed) {
      navigateTo(PROFILE_COMPLETION_URL);
    }
  });

  return true;
};
