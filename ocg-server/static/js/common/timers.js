/**
 * Clears a timeout id and returns the empty timer value.
 * @param {number|null|undefined} timeoutId Timeout id to clear.
 * @returns {number} Empty timeout id.
 */
export const clearTimeoutId = (timeoutId) => {
  if (timeoutId) {
    window.clearTimeout(timeoutId);
  }
  return 0;
};

/**
 * Replaces an existing timeout with a new one.
 * @param {number|null|undefined} timeoutId Existing timeout id.
 * @param {Function} callback Callback to run after the delay.
 * @param {number} delay Delay in milliseconds.
 * @returns {number} New timeout id.
 */
export const replaceTimeout = (timeoutId, callback, delay) => {
  clearTimeoutId(timeoutId);
  return window.setTimeout(callback, delay);
};
