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
  if (!name || !name.trim()) return '';
  
  return name
    .toLowerCase()                        // Convert to lowercase (matches database)
    .trim()                              // Remove leading/trailing whitespace
    .normalize('NFD')                    // Normalize unicode characters
    .replace(/[\u0300-\u036f]/g, '')    // Remove accents/diacritics
    .replace(/[^\w]+/g, '-')            // Replace sequences of non-word chars with single hyphen (matches database regex)
    .replace(/^-+|-+$/g, '');           // Remove leading/trailing hyphens
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