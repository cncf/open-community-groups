import { isEscapeEvent } from "/static/js/common/keyboard.js";

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
 * Binds document-level modal dismissal listeners.
 * @param {Object} handlers Dismissal handlers.
 * @param {(event: KeyboardEvent) => void} handlers.onKeydown Keydown handler.
 * @param {(event: MouseEvent) => void} [handlers.onOutsideClick] Outside click handler.
 * @returns {() => void} Cleanup callback that removes the listeners.
 */
export const bindModalDismissListeners = ({ onKeydown, onOutsideClick }) => {
  document.addEventListener("keydown", onKeydown);
  if (onOutsideClick) {
    document.addEventListener("mousedown", onOutsideClick);
  }

  return () => {
    document.removeEventListener("keydown", onKeydown);
    if (onOutsideClick) {
      document.removeEventListener("mousedown", onOutsideClick);
    }
  };
};
