/**
 * Reads server-rendered HTML from an existing trusted template node.
 * @param {Element|null|undefined} element Element to read.
 * @returns {string} Trusted HTML string.
 */
export const readTrustedHtml = (element) => String(element?.innerHTML || "");

/**
 * Replaces an element's contents with server-sanitized trusted HTML.
 * @param {Element|null|undefined} element Element to update.
 * @param {string|null|undefined} html Trusted HTML string.
 * @returns {void}
 */
export const setTrustedHtml = (element, html) => {
  if (element) {
    element.innerHTML = String(html ?? "");
  }
};

/**
 * Inserts server-sanitized trusted HTML into an element.
 * @param {Element|null|undefined} element Element to update.
 * @param {InsertPosition} position Insert position.
 * @param {string|null|undefined} html Trusted HTML string.
 * @returns {void}
 */
export const insertTrustedHtml = (element, position, html) => {
  element?.insertAdjacentHTML?.(position, String(html ?? ""));
};

/**
 * Escapes user-controlled text before it is inserted into HTML.
 * @param {string} value Text to escape.
 * @returns {string} HTML-safe text.
 */
export const escapeHtml = (value) =>
  value.replace(
    /[&<>"']/g,
    (character) =>
      ({
        "&": "&amp;",
        "<": "&lt;",
        ">": "&gt;",
        '"': "&quot;",
        "'": "&#39;",
      })[character],
  );
