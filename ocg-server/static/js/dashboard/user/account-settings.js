import { getElementById } from "/static/js/common/dom.js";

const OPTIONAL_NOTIFICATIONS_INPUT_ID = "optional_notifications_enabled";
const OPTIONAL_NOTIFICATIONS_TOGGLE_ID = "toggle_optional_notifications_enabled";
const ACCOUNT_SETTINGS_READY_KEY = "userAccountSettingsReady";

/**
 * Syncs the hidden optional notifications input with the checkbox state.
 * @param {HTMLInputElement} toggle - Optional notifications checkbox
 */
const syncOptionalNotificationsInput = (toggle) => {
  const input = getElementById(document, OPTIONAL_NOTIFICATIONS_INPUT_ID);
  if (input instanceof HTMLInputElement) {
    input.value = String(toggle.checked);
  }
};

/**
 * Handles user account setting changes.
 * @param {Event} event - Change event
 */
const handleAccountSettingsChange = (event) => {
  const target = event.target;
  if (target instanceof HTMLInputElement && target.id === OPTIONAL_NOTIFICATIONS_TOGGLE_ID) {
    syncOptionalNotificationsInput(target);
  }
};

/**
 * Initializes user account settings controls.
 */
export const initializeUserAccountSettings = () => {
  if (document.documentElement.dataset[ACCOUNT_SETTINGS_READY_KEY] === "true") {
    return;
  }

  document.documentElement.dataset[ACCOUNT_SETTINGS_READY_KEY] = "true";
  document.addEventListener("change", handleAccountSettingsChange);
};

initializeUserAccountSettings();
