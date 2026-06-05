import { isEscapeEvent } from "/static/js/common/keyboard.js";
import { lockBodyScroll, unlockBodyScroll } from "/static/js/common/common.js";

/**
 * Checks whether a keyboard event should dismiss a modal.
 * @param {KeyboardEvent|Event} event Keyboard event.
 * @returns {boolean} True when the event is Escape.
 */
export const isModalEscapeEvent = (event) => isEscapeEvent(event);

/**
 * Checks whether an event target is the shared modal overlay.
 * @param {EventTarget|null|undefined} target Event target.
 * @returns {boolean} True when the target is a modal overlay.
 */
export const isModalOverlayTarget = (target) => target?.classList?.contains?.("modal-overlay") === true;

/**
 * Locks body scroll when a modal transitions from closed to open.
 * @param {boolean} isOpen Current modal open state.
 * @returns {boolean} Open modal state.
 */
export const openModalBodyScroll = (isOpen) => {
  if (!isOpen) {
    lockBodyScroll();
  }
  return true;
};

/**
 * Unlocks body scroll when a modal transitions from open to closed.
 * @param {boolean} isOpen Current modal open state.
 * @returns {boolean} Closed modal state.
 */
export const closeModalBodyScroll = (isOpen) => {
  if (isOpen) {
    unlockBodyScroll();
  }
  return false;
};

/**
 * Binds document-level modal dismissal listeners.
 * @param {Object} handlers Dismissal handlers.
 * @param {(event: KeyboardEvent) => void} handlers.onKeydown Keydown handler.
 * @param {(event: MouseEvent) => void} [handlers.onOutsideClick] Outside click handler.
 * @param {Document|Element} [handlers.target=document] Listener target.
 * @returns {() => void} Cleanup callback that removes the listeners.
 */
export const bindModalDismissListeners = ({ onKeydown, onOutsideClick, target = document }) => {
  target.addEventListener("keydown", onKeydown);
  if (onOutsideClick) {
    target.addEventListener("mousedown", onOutsideClick);
  }

  return () => {
    target.removeEventListener("keydown", onKeydown);
    if (onOutsideClick) {
      target.removeEventListener("mousedown", onOutsideClick);
    }
  };
};
