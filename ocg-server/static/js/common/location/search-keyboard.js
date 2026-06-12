import { isEscapeEvent } from "/static/js/common/keyboard.js";

/**
 * Gets the keyboard action for the location search results list.
 * @param {Object} state Keyboard state.
 * @param {KeyboardEvent|Object} state.event Keyboard event.
 * @param {number} state.resultsCount Number of available results.
 * @param {number} state.highlightedIndex Current highlighted result index.
 * @param {string} state.query Current search query.
 * @returns {Object} Keyboard action and next highlighted index.
 */
export const getLocationSearchKeyAction = ({ event, resultsCount, highlightedIndex, query }) => {
  if (event.key === "Enter" && resultsCount === 0) {
    return {
      action: query.trim().length < 3 ? "hide" : "search",
      highlightedIndex,
      preventDefault: true,
    };
  }

  if (resultsCount === 0) {
    return { action: "none", highlightedIndex, preventDefault: false };
  }

  if (isEscapeEvent(event)) {
    return { action: "clear", highlightedIndex, preventDefault: true };
  }

  if (event.key === "ArrowDown") {
    return {
      action: "highlight",
      highlightedIndex: Math.min(highlightedIndex + 1, resultsCount - 1),
      preventDefault: true,
    };
  }

  if (event.key === "ArrowUp") {
    return {
      action: "highlight",
      highlightedIndex: Math.max(highlightedIndex - 1, 0),
      preventDefault: true,
    };
  }

  if (event.key === "Enter") {
    return { action: "select", highlightedIndex, preventDefault: true };
  }

  return { action: "none", highlightedIndex, preventDefault: false };
};
