import {
  closestElement,
  getElementById,
  initializeMatchingRoots,
  initializeOnReadyAndHtmxLoad,
  isElementHidden,
  markDatasetReady,
} from "/static/js/common/dom.js";
import { isEscapeEvent } from "/static/js/common/keyboard.js";
import { toggleModalVisibility, trapModalFocus } from "/static/js/common/modals/modal-lifecycle.js";

const ALWAYS_SENT_MODAL_CLOSE_SELECTOR = "[data-always-sent-modal-close]";
const ALWAYS_SENT_MODAL_ID = "always-sent-modal";
const ALWAYS_SENT_MODAL_OPEN_SELECTOR = "[data-always-sent-modal-open]";
const NOTIFICATION_PREFERENCES_READY_KEY = "notificationPreferencesReady";
const PREFERENCE_TOGGLE_SELECTOR = "[data-preference-input]";

/**
 * Initializes notification preference toggles and the always-sent modal under
 * a page or swapped fragment.
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

  // Document-level delegation keeps working after dashboard HTMX swaps.
  document.addEventListener("change", handleNotificationPreferenceChange);
  document.addEventListener("click", handleAlwaysSentModalClick);
  document.addEventListener("keydown", handleAlwaysSentModalKeydown);
};

/**
 * Closes the always-sent modal when it is open.
 * @param {Element} modal Always-sent modal.
 * @returns {void}
 */
const closeAlwaysSentModal = (modal) => {
  if (!isElementHidden(modal)) {
    toggleModalVisibility(modal);
  }
};

/**
 * Opens and closes the always-sent modal from its declarative controls.
 * @param {MouseEvent} event Click event.
 * @returns {void}
 */
const handleAlwaysSentModalClick = (event) => {
  const modal = getElementById(document, ALWAYS_SENT_MODAL_ID);
  if (!modal) {
    return;
  }

  const opener = closestElement(event.target, ALWAYS_SENT_MODAL_OPEN_SELECTOR);
  if (opener instanceof HTMLElement) {
    if (isElementHidden(modal)) {
      // Pass the opener so the shared lifecycle restores focus on close.
      toggleModalVisibility(modal, opener);
    }
    return;
  }

  if (closestElement(event.target, ALWAYS_SENT_MODAL_CLOSE_SELECTOR)) {
    closeAlwaysSentModal(modal);
  }
};

/**
 * Closes the always-sent modal on Escape and keeps Tab focus inside it.
 * @param {KeyboardEvent} event Keydown event.
 * @returns {void}
 */
const handleAlwaysSentModalKeydown = (event) => {
  const modal = getElementById(document, ALWAYS_SENT_MODAL_ID);
  if (!modal || isElementHidden(modal) || event.defaultPrevented) {
    return;
  }

  if (isEscapeEvent(event)) {
    event.preventDefault();
    closeAlwaysSentModal(modal);
    return;
  }

  trapModalFocus(event, modal);
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
