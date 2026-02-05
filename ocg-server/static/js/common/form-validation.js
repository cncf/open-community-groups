/**
 * Form validation module for enforcing trimmed values and password confirmation.
 * Auto-wires all forms on the page.
 * @module form-validation
 */

import { isDashboardPath, isElementInView } from "/static/js/common/common.js";
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

/**
 * Finds the nearest visible element for scrolling.
 * @param {HTMLElement} field - The invalid form field
 * @returns {HTMLElement|null} Visible element to scroll into view
 */
const getVisibleScrollTarget = (field) => {
  if (!field) {
    return null;
  }

  if (field.getClientRects().length > 0) {
    return field;
  }

  let current = field.parentElement;
  while (current) {
    if (current.getClientRects().length > 0) {
      return current;
    }
    current = current.parentElement;
  }

  return null;
};

/**
 * Returns the header height when it is sticky or fixed.
 * @returns {number} Header height in pixels
 */
const getStickyHeaderOffset = () => {
  const header =
    document.querySelector('nav[role="banner"]') || document.querySelector("#header")?.closest("nav");

  if (!header) {
    return 0;
  }

  const style = window.getComputedStyle(header);
  if (style.position !== "fixed" && style.position !== "sticky") {
    return 0;
  }

  const rect = header.getBoundingClientRect();
  return rect.height || 0;
};

/**
 * Adjusts scroll position so the target isn't hidden behind the header.
 * @param {HTMLElement} element - Target element
 */
const adjustScrollForHeader = (element) => {
  if (!element || typeof element.getBoundingClientRect !== "function") {
    return;
  }

  const headerOffset = getStickyHeaderOffset();
  if (!headerOffset || typeof window.scrollBy !== "function") {
    return;
  }

  const gap = 50; // Extra gap between header and target
  const rect = element.getBoundingClientRect();
  if (rect.top < headerOffset + gap) {
    window.scrollBy({
      top: rect.top - headerOffset - gap,
      left: 0,
      behavior: "auto",
    });
  }
};

/**
 * Scrolls the invalid field into view on dashboard pages.
 * @param {HTMLElement} field - The invalid form field
 */
const scrollToInvalidField = (field) => {
  if (!isDashboardPath()) {
    return;
  }

  if (!field || typeof field.scrollIntoView !== "function") {
    return;
  }

  const target = getVisibleScrollTarget(field);
  if (!target) {
    return;
  }

  if (!isElementInView(target)) {
    target.scrollIntoView({ behavior: "auto", block: "start" });
  }

  adjustScrollForHeader(target);
};

let invalidScrollPending = false;

/**
 * Handles invalid events and scrolls to the first invalid field.
 * @param {Event} event - Invalid event fired by the browser
 */
const handleInvalidEvent = (event) => {
  if (invalidScrollPending) {
    return;
  }

  const field = event.target;
  if (!(field instanceof HTMLElement)) {
    return;
  }

  invalidScrollPending = true;

  /**
   * Runs the deferred scroll adjustment for the first invalid field.
   * @returns {void}
   */
  const runScroll = () => {
    scrollToInvalidField(field);
    invalidScrollPending = false;
  };

  if (typeof requestAnimationFrame === "function") {
    requestAnimationFrame(() => setTimeout(runScroll, 0));
  } else {
    setTimeout(runScroll, 0);
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
 * @param {Date|null} [params.latestDate=null] - Latest allowed date
 * @param {Function} [params.onDateSection] - Callback to show date tab
 * @returns {boolean} True when valid
 */
export const validateEventDates = ({
  startsInput,
  endsInput,
  allowPastDates = false,
  latestDate = null,
  onDateSection,
} = {}) => {
  if (startsInput) startsInput.setCustomValidity("");
  if (endsInput) endsInput.setCustomValidity("");

  const startsAtDate = parseLocalDate(startsInput?.value);
  const endsAtDate = parseLocalDate(endsInput?.value);
  const latestAllowed = latestDate instanceof Date && !Number.isNaN(latestDate.getTime()) ? latestDate : null;

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

  if (latestAllowed) {
    if (startsAtDate && startsAtDate > latestAllowed) {
      return reportWithSection(startsInput, "Start date cannot be in the future.", onDateSection);
    }
    if (endsAtDate && endsAtDate > latestAllowed) {
      return reportWithSection(endsInput, "End date cannot be in the future.", onDateSection);
    }
  }

  if (startsAtDate && endsAtDate && endsAtDate <= startsAtDate) {
    return reportWithSection(endsInput, "End date must be after start date.", onDateSection);
  }

  return true;
};

/**
 * Clears CFS custom validity state.
 * @param {Object} params - Inputs to clear
 * @param {HTMLInputElement|null} params.cfsStartsInput - CFS start input
 * @param {HTMLInputElement|null} params.cfsEndsInput - CFS end input
 */
export const clearCfsWindowValidity = ({ cfsStartsInput, cfsEndsInput } = {}) => {
  if (cfsStartsInput) cfsStartsInput.setCustomValidity("");
  if (cfsEndsInput) cfsEndsInput.setCustomValidity("");
};

/**
 * Validates CFS date window against the event start date.
 * @param {Object} params - Validation params
 * @param {HTMLInputElement|null} params.cfsEnabledInput - CFS enabled input
 * @param {HTMLInputElement|null} params.cfsStartsInput - CFS start input
 * @param {HTMLInputElement|null} params.cfsEndsInput - CFS end input
 * @param {HTMLInputElement|null} params.eventStartsInput - Event start input
 * @param {Function} [params.onDateSection] - Callback to show date tab
 * @param {Function} [params.onCfsSection] - Callback to show CFS tab
 * @returns {boolean} True when valid
 */
export const validateCfsWindow = ({
  cfsEnabledInput,
  cfsStartsInput,
  cfsEndsInput,
  eventStartsInput,
  onDateSection,
  onCfsSection,
} = {}) => {
  clearCfsWindowValidity({ cfsStartsInput, cfsEndsInput });

  // Treat any non-true value as disabled to avoid accidental validation errors.
  const enabledValue = String(cfsEnabledInput?.value || "")
    .trim()
    .toLowerCase();
  if (enabledValue !== "true") {
    return true;
  }

  const eventStartsAt = parseLocalDate(eventStartsInput?.value);
  const cfsStartsAt = parseLocalDate(cfsStartsInput?.value);
  const cfsEndsAt = parseLocalDate(cfsEndsInput?.value);

  // CFS window depends on the event start date to enforce DB constraints.
  if (!eventStartsAt) {
    return reportWithSection(
      eventStartsInput || cfsStartsInput,
      "Event start date is required when CFS is enabled.",
      onDateSection,
    );
  }

  if (cfsStartsAt && cfsEndsAt && cfsEndsAt <= cfsStartsAt) {
    return reportWithSection(cfsEndsInput, "CFS close date must be after CFS open date.", onCfsSection);
  }

  if (cfsStartsAt && cfsStartsAt >= eventStartsAt) {
    return reportWithSection(
      cfsStartsInput,
      "CFS open date must be before the event start date.",
      onCfsSection,
    );
  }

  if (cfsEndsAt && cfsEndsAt >= eventStartsAt) {
    return reportWithSection(
      cfsEndsInput,
      "CFS close date must be before the event start date.",
      onCfsSection,
    );
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
 * Clears session date custom validity state.
 * @param {Object} params - Validation params
 * @param {HTMLElement|Document} [params.sessionForm=document] - Root element for inputs
 * @returns {void}
 */
export const clearSessionDateBoundsValidity = ({ sessionForm = document } = {}) => {
  const sessionsMap = buildSessionDateMap(sessionForm);
  Object.values(sessionsMap).forEach(({ starts_at, ends_at }) => {
    if (starts_at) starts_at.setCustomValidity("");
    if (ends_at) ends_at.setCustomValidity("");
  });
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

  clearSessionDateBoundsValidity({ sessionForm });

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
    const requestElement = event.detail?.elt;
    if (requestElement?.id === "cancel-button" || requestElement?.dataset?.skipValidation === "true") {
      return;
    }
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
  document.addEventListener("invalid", handleInvalidEvent, true);
};

if (document.readyState === "loading") {
  document.addEventListener("DOMContentLoaded", init);
} else {
  init();
}
