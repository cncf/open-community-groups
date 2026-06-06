import { getElementById, initializeOnReadyAndHtmxLoad, markDatasetReady } from "/static/js/common/dom.js";

const OPTIONAL_NOTIFICATIONS_INPUT_ID = "optional_notifications_enabled";
const OPTIONAL_NOTIFICATIONS_TOGGLE_ID = "toggle_optional_notifications_enabled";
const ACCOUNT_SETTINGS_READY_KEY = "userAccountSettingsReady";

/**
 * Syncs the hidden optional notifications input with the checkbox state.
 * @param {HTMLInputElement} toggle - Optional notifications checkbox
 * @param {Document|Element} [root=document] Root page container
 */
const syncOptionalNotificationsInput = (toggle, root = document) => {
  const input = getElementById(root, OPTIONAL_NOTIFICATIONS_INPUT_ID);
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
    syncOptionalNotificationsInput(target, target.form || document);
  }
};

/**
 * Initializes user account settings controls.
 * @param {Document|Element} [root=document] Root page container
 */
export const initializeUserAccountSettings = (root = document) => {
  const toggle = getElementById(root, OPTIONAL_NOTIFICATIONS_TOGGLE_ID);
  if (toggle instanceof HTMLInputElement) {
    syncOptionalNotificationsInput(toggle, root);
  }

  if (!markDatasetReady(document.documentElement, ACCOUNT_SETTINGS_READY_KEY)) {
    return;
  }

  document.addEventListener("change", handleAccountSettingsChange);
};

initializeOnReadyAndHtmxLoad(initializeUserAccountSettings);
