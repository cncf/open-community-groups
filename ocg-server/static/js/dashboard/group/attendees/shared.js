import { closestElementWithinRoot, getElementById, isElementHidden } from "/static/js/common/dom.js";
import { isEscapeEvent } from "/static/js/common/keyboard.js";
import { toggleModalVisibility } from "/static/js/common/modals/modal-lifecycle.js";

export const attendeesRootSelector = "#attendees-content";

export const resolveAttendeesRoot = (root = document) => {
  if (root instanceof Element && root.matches(attendeesRootSelector)) {
    return root;
  }

  if (root instanceof Element) {
    return root.closest(attendeesRootSelector) || getElementById(root, "attendees-content") || root;
  }

  return getElementById(root, "attendees-content") || root.body || root;
};

/**
 * Set a scoped modal visible or hidden only when its current state differs.
 * @param {Document|Element} root Query root.
 * @param {string} targetModalId Modal element id.
 * @param {boolean} visible Whether the modal should be visible.
 * @returns {void}
 */
export const setScopedModalVisibility = (root, targetModalId, visible) => {
  const modal = getElementById(root, targetModalId);
  if (!modal) return;

  const isHidden = isElementHidden(modal);
  if ((visible && isHidden) || (!visible && !isHidden)) {
    toggleModalVisibility(targetModalId);
  }
};

/**
 * Closes a scoped modal when an event target matches its dismiss controls.
 * @param {Event} event Event to inspect.
 * @param {Document|Element} root Query root.
 * @param {string} closeSelector Close, cancel, and overlay selector.
 * @param {Function} closeModal Modal close callback.
 * @returns {boolean} True when the event closed the modal.
 */
export const closeScopedModalFromEvent = (event, root, closeSelector, closeModal) => {
  if (!closestElementWithinRoot(event.target, closeSelector, root)) {
    return false;
  }

  event.stopPropagation();
  closeModal(root);
  return true;
};

/**
 * Binds Escape handling for a scoped modal.
 * @param {Document|Element} root Query root.
 * @param {Function} closeModal Modal close callback.
 * @returns {void}
 */
export const bindScopedModalEscape = (root, closeModal) => {
  root.addEventListener("keydown", (event) => {
    if (isEscapeEvent(event)) {
      closeModal(root);
    }
  });
};
