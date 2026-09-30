import {
  getElementById,
  initializeMatchingRoots,
  initializeOnReadyAndHtmxLoad,
  markDatasetReady,
} from "/static/js/common/dom.js";

const NOTIFICATION_PREFERENCES_READY_KEY = "notificationPreferencesReady";
const PREFERENCE_TOGGLE_SELECTOR = "[data-preference-input]";

/**
 * Initializes notification preference toggles under a page or swapped fragment.
 * @param {Document|Element} [root=document] Root page container.
 */
export const initializeNotificationPreferences = (root = document) => {
  initializeMatchingRoots(root, PREFERENCE_TOGGLE_SELECTOR, (toggle) => {
    if (toggle instanceof HTMLInputElement) {
      syncPreferenceInput(toggle, root);
    }
  });

  if (!markDatasetReady(document.documentElement, NOTIFICATION_PREFERENCES_READY_KEY)) {
    return;
  }

  document.addEventListener("change", handleNotificationPreferenceChange);
};

/**
 * Handles notification preference toggle changes.
 * @param {Event} event Change event.
 * @returns {void}
 */
const handleNotificationPreferenceChange = (event) => {
  const target = event.target;
  if (target instanceof HTMLInputElement && target.matches(PREFERENCE_TOGGLE_SELECTOR)) {
    syncPreferenceInput(target, target.form || document);
  }
};

/**
 * Syncs a preference hidden input with its controlling checkbox state.
 * @param {HTMLInputElement} toggle Preference checkbox.
 * @param {Document|Element} root Root used to resolve the hidden input.
 * @returns {void}
 */
const syncPreferenceInput = (toggle, root) => {
  const inputId = toggle.dataset.preferenceInput;
  if (!inputId) {
    return;
  }

  const input = getElementById(root, inputId);
  if (input instanceof HTMLInputElement) {
    input.value = String(toggle.checked);
  }
};

initializeOnReadyAndHtmxLoad(initializeNotificationPreferences);
