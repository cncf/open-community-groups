/**
 * Dashboard common utilities
 */

/**
 * Generates a URL-safe slug from a given name using the same pattern as the database
 * This mimics PostgreSQL's: regexp_replace(lower(name), '[^\w]+', '-', 'g')
 * @param {string} name - The name to convert to a slug
 * @returns {string} - A URL-safe slug
 */
export function generateSlug(name) {
  if (!name || !name.trim()) return "";

  return name
    .toLowerCase() // Convert to lowercase (matches database)
    .trim() // Remove leading/trailing whitespace
    .normalize("NFD") // Normalize unicode characters
    .replace(/[\u0300-\u036f]/g, "") // Remove accents/diacritics
    .replace(/[^\w]+/g, "-") // Replace sequences of non-word chars with single hyphen (matches database regex)
    .replace(/^-+|-+$/g, ""); // Remove leading/trailing hyphens
}

/**
 * Triggers a change event on the specified form using htmx.
 * @param {string} formId - The ID of the form to trigger change on
 */
export function triggerChangeOnForm(formId) {
  const form = document.getElementById(formId);
  if (form) {
    // Trigger change event using htmx
    htmx.trigger(form, "change");
  }
}

/**
 * Computes initials from a user's name, with username fallback.
 *
 * - If `name` exists: returns first letter of first and last words (or just
 *   the first letter if only one word) depending on `count` (1 or 2).
 * - If `name` is empty: falls back to the first letter of `username`.
 *
 * @param {string|null|undefined} name - Full name (may be null/undefined)
 * @param {string} username - Username (used as fallback)
 * @param {number} count - Initials count (1 or 2). Defaults to 2.
 * @returns {string} Initials string (uppercase)
 */
export const computeUserInitials = (name, username, count = 2) => {
  const cleanName = (name || "").trim();
  if (cleanName.length === 0) {
    return (username || "").charAt(0).toUpperCase();
  }

  const parts = cleanName.split(/\s+/);
  let initials = "";
  if (parts.length > 0 && parts[0].length > 0) {
    initials += parts[0][0].toUpperCase();
  }
  if (count >= 2 && parts.length > 1 && parts[parts.length - 1].length > 0) {
    initials += parts[parts.length - 1][0].toUpperCase();
  }
  return initials;
};
