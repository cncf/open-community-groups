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

// -----------------------------------------------------------------------------
// Date helpers
// -----------------------------------------------------------------------------

/**
 * Parses a datetime-local string into a Date.
 * @param {string} value - Datetime-local string (YYYY-MM-DDTHH:MM)
 * @returns {Date|null} Date instance or null when invalid/empty
 */
export const parseLocalDate = (value) => {
  if (!value) return null;
  const parsed = new Date(value);
  return Number.isNaN(parsed.getTime()) ? null : parsed;
};

const reportWithSection = (input, message, onSection) => {
  if (!input) return false;
  input.setCustomValidity(message);
  onSection?.();
  const show = () => {
    // Small async delay stabilizes native validity tooltip after DOM/tab changes.
    input.blur();
    input.focus({ preventScroll: true });
    input.reportValidity();
  };
  if (typeof requestAnimationFrame === "function") {
    // This prevent to hide custom validity tooltip when called inside an event handler.
    requestAnimationFrame(() => setTimeout(show, 0));
  } else {
    setTimeout(show, 0);
  }
  return false;
};

/**
 * Validates event-level start/end dates.
 * Sets custom validity messages on provided inputs.
 * @param {Object} params - Validation params
 * @param {HTMLInputElement|null} params.startsInput - Start datetime input
 * @param {HTMLInputElement|null} params.endsInput - End datetime input
 * @param {boolean} [params.allowPastDates=false] - Allow past dates (updates)
 * @param {Function} [params.onDateSection] - Callback to show date tab
 * @returns {boolean} True when valid
 */
export const validateEventDates = ({
  startsInput,
  endsInput,
  allowPastDates = false,
  onDateSection,
} = {}) => {
  if (startsInput) startsInput.setCustomValidity("");
  if (endsInput) endsInput.setCustomValidity("");

  const startsAtDate = parseLocalDate(startsInput?.value);
  const endsAtDate = parseLocalDate(endsInput?.value);

  if (endsInput?.value && !startsInput?.value) {
    return reportWithSection(startsInput, "Start date is required when end date is set.", onDateSection);
  }

  if (!allowPastDates) {
    const now = new Date();
    if (startsAtDate && startsAtDate < now) {
      return reportWithSection(startsInput, "Start date cannot be in the past.", onDateSection);
    }
    if (endsAtDate && endsAtDate < now) {
      return reportWithSection(endsInput, "End date cannot be in the past.", onDateSection);
    }
  }

  if (startsAtDate && endsAtDate && endsAtDate <= startsAtDate) {
    return reportWithSection(endsInput, "End date must be after start date.", onDateSection);
  }

  return true;
};

/**
 * Builds a map of session date inputs grouped by index.
 * @param {HTMLElement|Document} root - Root element to query
 * @returns {Object} Map keyed by session index
 */
const buildSessionDateMap = (root) => {
  const sessionDateInputs = root.querySelectorAll(
    'input[name^="sessions"][name$="[starts_at]"],' + 'input[name^="sessions"][name$="[ends_at]"]',
  );

  const map = {};
  sessionDateInputs.forEach((input) => {
    const match = input.name.match(/^sessions\[(\d+)\]\[(starts_at|ends_at)\]$/);
    if (!match) return;
    const [, idx, field] = match;
    if (!map[idx]) map[idx] = {};
    map[idx][field] = input;
  });
  return map;
};

/**
 * Validates that session dates fall within event bounds and are ordered.
 * @param {Object} params - Validation params
 * @param {Date|null} params.eventStartsAt - Event start date
 * @param {Date|null} params.eventEndsAt - Event end date
 * @param {HTMLElement} [params.sessionForm=document] - Root element for inputs
 * @param {Function} [params.onSessionsSection] - Callback to show sessions tab
 * @returns {boolean} True when valid
 */
export const validateSessionDateBounds = ({
  eventStartsAt,
  eventEndsAt,
  sessionForm = document,
  onSessionsSection,
} = {}) => {
  const sessionsMap = buildSessionDateMap(sessionForm);
  const sessionEntries = Object.values(sessionsMap);
  if (sessionEntries.length === 0) return true;

  sessionEntries.forEach(({ starts_at, ends_at }) => {
    if (starts_at) starts_at.setCustomValidity("");
    if (ends_at) ends_at.setCustomValidity("");
  });

  for (const session of sessionEntries) {
    const startDate = parseLocalDate(session.starts_at?.value);
    const endDate = parseLocalDate(session.ends_at?.value);

    if (eventStartsAt && startDate && startDate < eventStartsAt) {
      return reportWithSection(
        session.starts_at,
        "Session start cannot be before the event start.",
        onSessionsSection,
      );
    }

    if (eventEndsAt && startDate && startDate > eventEndsAt) {
      return reportWithSection(
        session.starts_at,
        "Session start cannot be after the event end.",
        onSessionsSection,
      );
    }

    if (eventStartsAt && endDate && endDate < eventStartsAt) {
      return reportWithSection(
        session.ends_at,
        "Session end cannot be before the event start.",
        onSessionsSection,
      );
    }

    if (eventEndsAt && endDate && endDate > eventEndsAt) {
      return reportWithSection(
        session.ends_at,
        "Session end cannot be after the event end.",
        onSessionsSection,
      );
    }

    if (startDate && endDate && endDate < startDate) {
      return reportWithSection(
        session.ends_at,
        "Session end must be after the session start.",
        onSessionsSection,
      );
    }
  }

  return true;
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
