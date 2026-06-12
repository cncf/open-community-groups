/**
 * Checks whether a keyboard event is the Escape key.
 * @param {KeyboardEvent|Event} event Keyboard event.
 * @returns {boolean} True when the event is Escape.
 */
export const isEscapeEvent = (event) => event?.key === "Escape";

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
