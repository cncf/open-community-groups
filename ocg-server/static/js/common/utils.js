/**
 * Checks if the provided value is a string.
 * @param {*} value Incoming value
 * @returns {boolean} True when the value is a string
 */
const isString = (value) => typeof value === "string";

/**
 * Trims the provided value when it is a string.
 * @param {*} value Incoming value
 * @returns {string} Trimmed string or empty string
 */
const toTrimmedString = (value) => (isString(value) ? value.trim() : "");

/**
 * Coerces any value to a string, empty when nullish.
 * @param {*} value Incoming value
 * @returns {string} Optional string value
 */
const toOptionalString = (value) =>
  value === null || value === undefined ? "" : typeof value === "string" ? value : String(value);

/**
 * Filters arrays to trimmed string values only.
 * @param {*} list Candidate list
 * @returns {string[]} Sanitized string array
 */
const sanitizeStringArray = (list) => {
  if (!Array.isArray(list)) {
    return [];
  }
  return list.map((value) => toTrimmedString(value)).filter((value) => value.length > 0);
};

/**
 * Normalizes users array by lifting nested user objects.
 * @param {*} list Raw users list
 * @returns {object[]} Normalized user entries
 */
const normalizeUsers = (list) => {
  if (!Array.isArray(list)) {
    return [];
  }
  return list
    .map((item) => {
      if (item && typeof item === "object" && item.user && typeof item.user === "object") {
        return { ...item.user };
      }
      return item;
    })
    .filter((user) => user && (user.user_id || user.username));
};

/**
 * Sets text input value and dispatches input event.
 * @param {string} id Element id
 * @param {*} value New value
 */
const setTextValue = (id, value) => {
  const input = document.getElementById(id);
  if (!input) {
    return;
  }
  const nextValue = toOptionalString(value);
  input.value = nextValue;
  input.dispatchEvent(new Event("input", { bubbles: true }));
};

/**
 * Sets select value when an option exists and fires change event.
 * @param {string} id Element id
 * @param {*} value New value
 */
const setSelectValue = (id, value) => {
  const select = document.getElementById(id);
  if (!select) {
    return;
  }
  const options = Array.from(select.options || []);
  const normalized = toOptionalString(value);
  const hasMatch = options.some((option) => option.value === normalized);
  select.value = hasMatch ? normalized : "";
  select.dispatchEvent(new Event("change", { bubbles: true }));
};

/**
 * Sets image field value using internal setter when available.
 * @param {string} fieldName Field name attribute
 * @param {*} url Image URL value
 */
const setImageFieldValue = (fieldName, url) => {
  const field = document.querySelector(`image-field[name="${fieldName}"]`);
  if (!field) {
    return;
  }
  if (typeof field._setValue === "function") {
    field._setValue(toOptionalString(url));
    return;
  }
  field.value = toOptionalString(url);
  field.requestUpdate?.();
};

export {
  isString,
  normalizeUsers,
  sanitizeStringArray,
  setImageFieldValue,
  setSelectValue,
  setTextValue,
  toOptionalString,
  toTrimmedString,
};
