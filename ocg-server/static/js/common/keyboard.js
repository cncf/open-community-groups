/** Selector for elements that activate via click on unmodified Enter keydown. */
const ENTER_ACTIVATION_SELECTOR = "[data-enter-activates]";
/** Event roots already wired so repeated registration stays idempotent. */
const enterActivationRoots = new WeakSet();

/**
 * Moves an active index through a fixed-size list with wraparound.
 * @param {number|null|undefined} currentIndex Current active index.
 * @param {number} itemCount Number of items in the list.
 * @param {number} offset Direction and size of the move.
 * @param {number} [fallbackIndex=0] Index to use when no item is active.
 * @returns {number|null} Next active index, or null for empty lists.
 */
export const getNextLoopedIndex = (currentIndex, itemCount, offset, fallbackIndex = 0) => {
  if (itemCount <= 0) {
    return null;
  }

  if (currentIndex === null || currentIndex === undefined) {
    return fallbackIndex;
  }

  return (currentIndex + offset + itemCount) % itemCount;
};

/**
 * Activates a focused element marked with data-enter-activates when Enter is pressed.
 * @param {KeyboardEvent} event Keydown event.
 * @returns {void}
 */
export const handleEnterActivationKeydown = (event) => {
  if (
    event.defaultPrevented ||
    event.key !== "Enter" ||
    event.isComposing ||
    event.repeat ||
    event.altKey ||
    event.ctrlKey ||
    event.metaKey ||
    event.shiftKey
  ) {
    return;
  }

  const target = event.target;
  if (!(target instanceof HTMLElement) || !target.matches(ENTER_ACTIVATION_SELECTOR)) {
    return;
  }

  event.preventDefault();
  target.click();
};

/**
 * Checks whether a keyboard event is the Escape key.
 * @param {KeyboardEvent|Event} event Keyboard event.
 * @returns {boolean} True when the event is Escape.
 */
export const isEscapeEvent = (event) => event?.key === "Escape";

/**
 * Registers delegated Enter-key click activation on the given event root once.
 * @param {Document|HTMLElement|undefined|null} [root=document] Event listener root.
 * @returns {void}
 */
export const registerEnterActivationHandler = (root = document) => {
  if (!root || typeof root.addEventListener !== "function" || enterActivationRoots.has(root)) {
    return;
  }

  root.addEventListener("keydown", handleEnterActivationKeydown);
  enterActivationRoots.add(root);
};
