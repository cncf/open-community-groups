import { getCommonAlertOptions } from "/static/js/common/alerts.js";
import {
  initializeMatchingRoots,
  initializeOnReadyAndHtmxLoad,
  markDatasetReady,
} from "/static/js/common/dom.js";

export const PROFILE_COMPLETION_URL = "/dashboard/user?tab=account";

const PROFILE_COMPLETE_SELECTOR = "[data-profile-complete]";
const USER_PROFILE_COMPLETE_SELECTOR = "[data-logged-in='true'][data-profile-complete]";
const LOGIN_FORM_SELECTOR = 'form[action^="/log-in"]';
const LOGIN_LINK_SELECTOR = 'a[href^="/log-in/oauth2/"], a[href^="/log-in/oidc/"]';
const LOGIN_PROMPT_READY_KEY = "profileCompletionLoginPromptReady";
const LOGIN_PROMPT_STORAGE_KEY = "ocg.loginProfileCompletionPrompt";
const PROFILE_COMPLETION_TITLE = "Complete your profile";
const PROFILE_COMPLETION_MESSAGE =
  "Add a few more details about you so organizers and community members can recognize you.";

const getLoginPromptPending = () => {
  try {
    return sessionStorage.getItem(LOGIN_PROMPT_STORAGE_KEY) === "true";
  } catch {
    return false;
  }
};

const setLoginPromptPending = () => {
  try {
    sessionStorage.setItem(LOGIN_PROMPT_STORAGE_KEY, "true");
  } catch {
    // Ignore unavailable storage; the profile prompt is only a helpful follow-up.
  }
};

const clearLoginPromptPending = () => {
  try {
    sessionStorage.removeItem(LOGIN_PROMPT_STORAGE_KEY);
  } catch {
    // Ignore unavailable storage; the profile prompt is only a helpful follow-up.
  }
};

const getUserProfileCompleteValue = () => {
  return document.querySelector(USER_PROFILE_COMPLETE_SELECTOR)?.dataset?.profileComplete?.trim();
};

const getProfileCompleteValue = (trigger) => {
  const userConfig = document.querySelector(USER_PROFILE_COMPLETE_SELECTOR);
  const actionConfig = trigger?.closest?.(PROFILE_COMPLETE_SELECTOR);
  return userConfig?.dataset?.profileComplete?.trim() ?? actionConfig?.dataset?.profileComplete?.trim();
};

/**
 * Reads the current profile-completion state from an event action.
 * @param {Element|null|undefined} trigger Action element that owns the flow.
 * @returns {boolean} Whether the action should prompt for profile completion.
 */
export const shouldPromptForProfileCompletion = (trigger) => {
  return getProfileCompleteValue(trigger) === "false";
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
    title: PROFILE_COMPLETION_TITLE,
    text: PROFILE_COMPLETION_MESSAGE,
    icon: "info",
    position: "center",
    backdrop: true,
    allowOutsideClick: false,
    allowEscapeKey: false,
    confirmButtonText: "Complete profile",
    showCancelButton: true,
    cancelButtonText: "Continue anyway",
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
    text: PROFILE_COMPLETION_MESSAGE,
    icon,
    position: "center",
    backdrop: true,
    allowOutsideClick: false,
    allowEscapeKey: false,
    confirmButtonText: "Complete profile",
    showCancelButton: true,
    cancelButtonText: "Maybe later",
    customClass: {
      ...commonOptions.customClass,
      popup: `${commonOptions.customClass.popup} ocg-profile-feedback-swal`,
    },
  }).then((result) => {
    if (result.isConfirmed) {
      navigateTo(PROFILE_COMPLETION_URL);
    }
  });

  return true;
};

/**
 * Shows the login follow-up prompt when the signed-in user has an incomplete profile.
 * @param {object} [options={}] Options.
 * @param {(url: string) => void} [options.navigateTo] Navigation callback.
 * @returns {boolean} Whether the prompt was displayed.
 */
export const showLoginProfileCompletionAlert = ({
  navigateTo = (url) => window.location.assign(url),
} = {}) => {
  if (getUserProfileCompleteValue() !== "false" || typeof globalThis.Swal?.fire !== "function") {
    return false;
  }

  const commonOptions = getCommonAlertOptions();
  Swal.fire({
    ...commonOptions,
    title: PROFILE_COMPLETION_TITLE,
    text: PROFILE_COMPLETION_MESSAGE,
    icon: "info",
    confirmButtonText: "Complete profile",
    showCancelButton: false,
    showConfirmButton: true,
    timer: 5000,
  }).then((result) => {
    if (result.isConfirmed) {
      navigateTo(PROFILE_COMPLETION_URL);
    }
  });

  return true;
};

/**
 * Watches login controls and shows the profile prompt after the next signed-in page.
 * @param {Document|Element} [root=document] Root element containing login controls.
 * @returns {void}
 */
export const initializeLoginProfileCompletionPrompt = (root = document) => {
  initializeMatchingRoots(root, LOGIN_FORM_SELECTOR, (loginForm) => {
    if (markDatasetReady(loginForm, LOGIN_PROMPT_READY_KEY)) {
      loginForm.addEventListener("submit", setLoginPromptPending);
    }
  });

  initializeMatchingRoots(root, LOGIN_LINK_SELECTOR, (loginLink) => {
    if (markDatasetReady(loginLink, LOGIN_PROMPT_READY_KEY)) {
      loginLink.addEventListener("click", setLoginPromptPending);
    }
  });

  if (!getLoginPromptPending()) {
    return;
  }

  const profileCompleteValue = getUserProfileCompleteValue();
  if (!profileCompleteValue) {
    return;
  }

  clearLoginPromptPending();
  if (profileCompleteValue === "false") {
    showLoginProfileCompletionAlert();
  }
};

initializeOnReadyAndHtmxLoad(initializeLoginProfileCompletionPrompt);
