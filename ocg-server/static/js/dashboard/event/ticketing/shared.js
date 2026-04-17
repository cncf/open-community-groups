export const DEFAULT_CURRENCY_PLACEHOLDER = "USD";

/**
 * Safely parses a JSON attribute.
 * @param {*} value Raw attribute value
 * @param {*} fallback Fallback value
 * @returns {*}
 */
export const parseJsonAttribute = (value, fallback) => {
  if (Array.isArray(value)) {
    return value;
  }

  if (typeof value !== "string" || value.trim().length === 0) {
    return fallback;
  }

  try {
    return JSON.parse(value);
  } catch (_) {
    return fallback;
  }
};

/**
 * Safely parses a colocated JSON seed block.
 * @param {Element} root Seed container root.
 * @param {string} seedName Seed identifier.
 * @param {*} fallback Fallback value.
 * @returns {*} Parsed JSON value or fallback.
 */
export const parseJsonSeed = (root, seedName, fallback) => {
  if (!(root instanceof Element) || typeof seedName !== "string" || seedName.trim().length === 0) {
    return fallback;
  }

  const seedElement = root.querySelector(
    `script[type="application/json"][data-ticketing-seed="${seedName}"]`,
  );

  if (!seedElement) {
    return fallback;
  }

  return parseJsonAttribute(seedElement.textContent, fallback);
};

/**
 * Normalizes a boolean value.
 * @param {*} value Raw value
 * @param {boolean} fallback Fallback value
 * @returns {boolean}
 */
export const toBoolean = (value, fallback = false) => {
  if (typeof value === "boolean") {
    return value;
  }

  if (typeof value === "string") {
    const normalized = value.trim().toLowerCase();
    if (normalized === "true") {
      return true;
    }
    if (normalized === "false") {
      return false;
    }
  }

  return fallback;
};

/**
 * Normalizes a trimmed string.
 * @param {*} value Raw value
 * @returns {string}
 */
export const toTrimmedString = (value) => String(value || "").trim();

/**
 * Escapes a string for safe HTML interpolation.
 * @param {*} value Raw value
 * @returns {string}
 */
export const escapeHtml = (value) =>
  String(value ?? "")
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#39;");
