import { getElementById, isElementHidden, setElementHidden } from "/static/js/common/dom.js";

const MODAL_AUTOFOCUS_SELECTOR = "[autofocus]";
const MODAL_FOCUS_SELECTOR =
  "button:not([disabled]), [href], input:not([disabled]), select:not([disabled]), " +
  'textarea:not([disabled]), [tabindex]:not([tabindex="-1"])';
const modalFocusOrigins = new WeakMap();

/**
 * Returns the focus target for an opened modal.
 * @param {Element} modal Modal element.
 * @returns {HTMLElement|null} Element that can receive focus.
 */
const getModalFocusTarget = (modal) => {
  const focusTarget =
    modal.querySelector(MODAL_AUTOFOCUS_SELECTOR) ?? modal.querySelector(MODAL_FOCUS_SELECTOR);
  if (focusTarget instanceof HTMLElement) {
    return focusTarget;
  }

  if (modal instanceof HTMLElement) {
    if (!modal.hasAttribute("tabindex")) {
      modal.setAttribute("tabindex", "-1");
    }
    return modal;
  }

  return null;
};

/**
 * Moves focus into an opened modal.
 * @param {Element} modal Modal element.
 * @returns {void}
 */
const focusOpenedModal = (modal) => {
  getModalFocusTarget(modal)?.focus();
};

/**
 * Restores focus to the element that opened a modal.
 * @param {Element} modal Modal element.
 * @returns {void}
 */
const restoreModalFocus = (modal) => {
  const focusOrigin = modalFocusOrigins.get(modal);
  modalFocusOrigins.delete(modal);
  if (focusOrigin instanceof HTMLElement && document.contains(focusOrigin)) {
    focusOrigin.focus();
  }
};

/**
 * Locks body scroll while a modal is open.
 * @returns {void}
 */
export const lockBodyScroll = () => {
  const body = document.body;
  const current = Number.parseInt(body.dataset.modalOpenCount || "0", 10);
  const next = Number.isNaN(current) ? 1 : current + 1;
  body.dataset.modalOpenCount = String(next);
  if (next === 1) {
    const scrollbarWidth = window.innerWidth - document.documentElement.clientWidth;
    body.dataset.modalOverflow = body.style.overflow || "";
    body.dataset.modalPaddingRight = body.style.paddingRight || "";
    if (scrollbarWidth > 0) {
      const currentPaddingRight = Number.parseFloat(window.getComputedStyle(body).paddingRight || "0");
      const nextPaddingRight = currentPaddingRight + scrollbarWidth;
      body.style.paddingRight = `${nextPaddingRight}px`;
    }
    body.style.overflow = "hidden";
  }
};

/**
 * Unlocks body scroll when all tracked modals are closed.
 * @returns {void}
 */
export const unlockBodyScroll = () => {
  const body = document.body;
  const current = Number.parseInt(body.dataset.modalOpenCount || "0", 10);
  const next = Number.isNaN(current) ? 0 : Math.max(0, current - 1);
  body.dataset.modalOpenCount = String(next);
  if (next === 0) {
    const previousOverflow = body.dataset.modalOverflow ?? "";
    const previousPaddingRight = body.dataset.modalPaddingRight ?? "";
    body.style.overflow = previousOverflow;
    body.style.paddingRight = previousPaddingRight;
  }
};

/**
 * Restores body scroll state after a cached page snapshot is restored.
 * @returns {void}
 */
export const resetBodyScrollLock = () => {
  const body = document.body;
  body.style.overflow = body.dataset.modalOverflow ?? "";
  body.style.paddingRight = body.dataset.modalPaddingRight ?? "";
  delete body.dataset.modalOpenCount;
  delete body.dataset.modalOverflow;
  delete body.dataset.modalPaddingRight;
};

/**
 * Toggles a modal and manages aria-hidden, body scroll, and focus.
 * @param {string} modalId ID of the modal element to toggle.
 * @param {HTMLElement|null} [trigger=null] Element that opened the modal.
 * @returns {void}
 */
export const toggleModalVisibility = (modalId, trigger = null) => {
  const modal = getElementById(document, modalId);
  if (!modal) {
    return;
  }

  const willOpen = isElementHidden(modal);
  const activeElement = document.activeElement;
  setElementHidden(modal, !willOpen);
  modal.setAttribute("aria-hidden", String(!willOpen));
  if (willOpen) {
    modalFocusOrigins.set(
      modal,
      trigger instanceof HTMLElement ? trigger : activeElement instanceof HTMLElement ? activeElement : null,
    );
    lockBodyScroll();
    focusOpenedModal(modal);
  } else {
    unlockBodyScroll();
    restoreModalFocus(modal);
  }
};

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

/**
 * Binds the same click handler to modal controls that may or may not exist.
 * @param {Array<Element|null|undefined>} controls Modal controls.
 * @param {(event: MouseEvent) => void} handler Click handler.
 * @returns {void}
 */
export const bindModalControlClicks = (controls, handler) => {
  controls.forEach((control) => {
    control?.addEventListener?.("click", handler);
  });
};

/**
 * Closes declarative modals and clears scroll locks after history restoration.
 * @param {Document|Element} root Root restored by the browser or HTMX.
 * @returns {void}
 */
export const resetRestoredModalState = (root = document) => {
  const triggers =
    root instanceof Element && root.matches("[data-modal-toggle]")
      ? [root, ...root.querySelectorAll("[data-modal-toggle]")]
      : [...(root.querySelectorAll?.("[data-modal-toggle]") || [])];

  triggers.forEach((trigger) => {
    const modalId = trigger.dataset.modalToggle;
    if (!modalId) {
      return;
    }

    const modal = getElementById(document, modalId);
    setElementHidden(modal, true);
    modal?.setAttribute("aria-hidden", "true");
  });

  resetBodyScrollLock();
};
