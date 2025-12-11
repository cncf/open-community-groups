/**
 * Form validation module for enforcing trimmed values and password confirmation.
 * Auto-wires all forms on the page.
 * @module form-validation
 */

import { trimmedNonEmpty, passwordsMatch } from "/static/js/common/validators.js";

// -----------------------------------------------------------------------------
// Constants
// -----------------------------------------------------------------------------

const FIELD_SELECTOR =
  'input:not([type="hidden"]):not([type="file"]):not([type="checkbox"]):not([type="radio"]), textarea';

// -----------------------------------------------------------------------------
// Helper Functions
// -----------------------------------------------------------------------------

/**
 * Checks if a field is a password input.
 * @param {HTMLElement} field - The form field element
 * @returns {boolean} True if field is a password input
 */
const isPasswordField = (field) => field instanceof HTMLInputElement && field.type === "password";

/**
 * Normalizes a non-required field by trimming whitespace.
 * Skips password fields to preserve intentional spaces.
 * @param {HTMLInputElement|HTMLTextAreaElement} field - The form field
 */
const normalizeField = (field) => {
  if (isPasswordField(field)) return;

  const trimmed = field.value.trim();
  if (trimmed !== field.value) {
    field.value = trimmed;
  }
};

// -----------------------------------------------------------------------------
// Validators
// -----------------------------------------------------------------------------

/**
 * Validates a required field is not empty or whitespace-only.
 * Also trims non-password fields on success.
 * @param {HTMLInputElement|HTMLTextAreaElement} field - The form field
 * @returns {boolean} True if valid
 */
const validateRequiredField = (field) => {
  field.setCustomValidity("");

  const error = trimmedNonEmpty(field.value);
  if (error) {
    field.setCustomValidity(error);
    field.reportValidity();
    return false;
  }

  if (!isPasswordField(field)) {
    const trimmed = field.value.trim();
    if (trimmed !== field.value) {
      field.value = trimmed;
    }
  }

  if (!field.checkValidity()) {
    field.reportValidity();
    return false;
  }

  return true;
};

/**
 * Validates password and confirmation fields match.
 * Uses data-password and data-password-confirmation attributes.
 * @param {HTMLFormElement} form - The form element
 * @returns {boolean} True if valid or no password fields exist
 */
const validatePasswordConfirmation = (form) => {
  const password = form.querySelector("[data-password]");
  const confirmation = form.querySelector("[data-password-confirmation]");

  if (!password || !confirmation) return true;

  const error = passwordsMatch(password.value, confirmation.value);
  if (error) {
    confirmation.setCustomValidity(error);
    confirmation.reportValidity();
    return false;
  }

  confirmation.setCustomValidity("");
  return true;
};

/**
 * Keeps password confirmation validity in sync while typing.
 * @param {HTMLFormElement} form - The form element
 */
const wirePasswordInputs = (form) => {
  const password = form.querySelector("[data-password]");
  const confirmation = form.querySelector("[data-password-confirmation]");

  if (!password || !confirmation) return;

  const syncValidity = () => {
    if (!password.value || !confirmation.value) {
      confirmation.setCustomValidity("");
      return;
    }

    const error = passwordsMatch(password.value, confirmation.value);
    confirmation.setCustomValidity(error ?? "");
  };

  password.addEventListener("input", syncValidity);
  confirmation.addEventListener("input", syncValidity);
};

/**
 * Clears custom validity on input for required fields.
 * @param {HTMLFormElement} form - The form element
 */
const wireRequiredInputs = (form) => {
  const fields = form.querySelectorAll(FIELD_SELECTOR);

  fields.forEach((field) => {
    if (!field.required) return;
    field.addEventListener("input", () => {
      field.setCustomValidity("");
    });
  });
};

/**
 * Validates all fields in a form.
 * @param {HTMLFormElement} form - The form element
 * @returns {boolean} True if all fields are valid
 */
const validateForm = (form) => {
  const fields = form.querySelectorAll(FIELD_SELECTOR);

  for (const field of fields) {
    if (field.disabled) continue;

    if (!field.required) {
      normalizeField(field);
      continue;
    }

    if (!validateRequiredField(field)) {
      return false;
    }
  }

  return validatePasswordConfirmation(form);
};

/**
 * Validates forms included via hx-include attribute.
 * @param {HTMLElement} elt - The element with hx-include
 * @returns {boolean} True if all included forms are valid
 */
const validateIncludedForms = (elt) => {
  const includeAttr = elt.getAttribute("hx-include");
  if (!includeAttr) return true;

  const selectors = includeAttr
    .split(",")
    .map((s) => s.trim())
    .filter(Boolean);

  for (const selector of selectors) {
    const target = document.querySelector(selector);
    if (target?.matches("form") && !validateForm(target)) {
      return false;
    }
  }

  return true;
};

// -----------------------------------------------------------------------------
// Event Handlers
// -----------------------------------------------------------------------------

/**
 * Wires validation event listeners to a form.
 * Prevents double-wiring with data-trimmed-ready attribute.
 * @param {HTMLFormElement} form - The form element
 */
const wireForm = (form) => {
  if (form.dataset.trimmedReady === "true") return;
  form.dataset.trimmedReady = "true";

  wirePasswordInputs(form);
  wireRequiredInputs(form);

  form.addEventListener("submit", (event) => {
    if (!validateForm(form)) {
      event.preventDefault();
      event.stopPropagation();
    }
  });

  form.addEventListener("htmx:configRequest", (event) => {
    if (!validateForm(form)) {
      event.preventDefault();
    }
  });
};

/**
 * Handles htmx:configRequest events for form validation.
 * @param {Event} event - The htmx config request event
 */
const handleConfigRequest = (event) => {
  const target = event.target;

  if (target.matches("form") && !validateForm(target)) {
    event.preventDefault();
    return;
  }

  if (!validateIncludedForms(target)) {
    event.preventDefault();
  }
};

// -----------------------------------------------------------------------------
// Initialization
// -----------------------------------------------------------------------------

/**
 * Initializes form validation on all matching forms.
 */
const init = () => {
  console.log("Initializing form validation module");
  document.querySelectorAll("form").forEach(wireForm);

  if (window.htmx && typeof htmx.onLoad === "function") {
    htmx.onLoad((elt) => {
      if (!elt) return;
      if (elt instanceof HTMLFormElement) {
        wireForm(elt);
      }
      elt.querySelectorAll?.("form").forEach(wireForm);
    });
  }

  document.body?.addEventListener("htmx:configRequest", handleConfigRequest);
};

if (document.readyState === "loading") {
  document.addEventListener("DOMContentLoaded", init);
} else {
  init();
}
