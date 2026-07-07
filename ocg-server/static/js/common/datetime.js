import { toTrimmedString } from "/static/js/common/utils.js";

/**
 * Converts a datetime-local value to the timestamp string expected by PostgreSQL.
 * @param {string} dateTimeLocal Datetime-local value.
 * @returns {string|null} Timestamp string, or null when input is empty.
 */
export const convertDateTimeLocalToISO = (dateTimeLocal) => {
  if (!dateTimeLocal) return null;
  return `${dateTimeLocal}:00`;
};

/**
 * Converts Unix seconds into the value used by datetime-local inputs.
 * @param {number} tsSeconds Unix timestamp in seconds.
 * @returns {string} Datetime string in YYYY-MM-DDTHH:MM format, or "".
 */
export const convertTimestampToDateTimeLocal = (tsSeconds) => {
  if (typeof tsSeconds !== "number" || !Number.isFinite(tsSeconds)) {
    return "";
  }

  const date = new Date(tsSeconds * 1000);
  return date.toISOString().slice(0, 16);
};

/**
 * Converts a Unix timestamp to datetime-local using a timezone.
 * @param {number} tsSeconds Unix timestamp in seconds.
 * @param {string} timezone IANA timezone identifier.
 * @returns {string} Datetime string in YYYY-MM-DDTHH:MM or "".
 */
export const convertTimestampToDateTimeLocalInTz = (tsSeconds, timezone) => {
  if (
    typeof tsSeconds !== "number" ||
    !Number.isFinite(tsSeconds) ||
    typeof timezone !== "string" ||
    timezone.length === 0
  ) {
    return "";
  }

  const dtf = new Intl.DateTimeFormat("en-CA", {
    timeZone: timezone,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    hourCycle: "h23",
  });

  const parts = dtf.formatToParts(new Date(tsSeconds * 1000));
  const get = (type) => parts.find((p) => p.type === type)?.value || "";
  const y = get("year");
  const m = get("month");
  const d = get("day");
  const h = get("hour");
  const min = get("minute");
  if (!y || !m || !d || !h || !min) return "";
  return `${y}-${m}-${d}T${h}:${min}`;
};

/**
 * Converts a Date value to datetime-local using a timezone.
 * @param {Date|null} dateValue Date instance to convert.
 * @param {string} timezone IANA timezone identifier.
 * @returns {string} Datetime string in YYYY-MM-DDTHH:MM or "".
 */
export const convertDateToDateTimeLocalInTz = (dateValue, timezone) => {
  if (!(dateValue instanceof Date) || Number.isNaN(dateValue.getTime())) {
    return "";
  }

  return convertTimestampToDateTimeLocalInTz(dateValue.getTime() / 1000, timezone);
};

/**
 * Resolves the event timezone from the shared event form.
 * @param {HTMLInputElement|HTMLSelectElement|HTMLTextAreaElement|null} [timezoneField]
 * @returns {string} Trimmed IANA timezone identifier or "".
 */
export const resolveEventTimezone = (timezoneField = document.querySelector('[name="timezone"]')) => {
  return typeof timezoneField?.value === "string" ? timezoneField.value.trim() : "";
};

/**
 * Builds a datetime-local string from an ISO timestamp in the selected timezone.
 * @param {string} value ISO timestamp.
 * @param {string} timezone IANA timezone.
 * @returns {string} Datetime-local string or "".
 */
export const toDateTimeLocalInTimezone = (value, timezone) => {
  if (typeof value !== "string" || value.trim().length === 0) {
    return "";
  }

  const date = new Date(value);
  if (Number.isNaN(date.getTime())) {
    return "";
  }

  if (typeof timezone !== "string" || timezone.trim().length === 0) {
    return value.slice(0, 16);
  }

  try {
    return convertDateToDateTimeLocalInTz(date, timezone) || value.slice(0, 16);
  } catch (_) {
    return value.slice(0, 16);
  }
};

/**
 * Converts a datetime-local value into UTC ISO using the selected timezone.
 * @param {string} value Datetime-local string.
 * @param {string} timezone IANA timezone.
 * @returns {string|null} UTC ISO string, original trimmed value, or null.
 */
export const toUtcIsoInTimezone = (value, timezone) => {
  const trimmedValue = toTrimmedString(value);
  if (!trimmedValue) {
    return null;
  }

  if (typeof timezone !== "string" || timezone.trim().length === 0) {
    return trimmedValue;
  }

  const [datePart, timePart] = trimmedValue.split("T");
  if (!datePart || !timePart) {
    return trimmedValue;
  }

  const [year, month, day] = datePart.split("-").map((part) => Number.parseInt(part, 10));
  const [hour, minute] = timePart.split(":").map((part) => Number.parseInt(part, 10));
  if ([year, month, day, hour, minute].some((part) => Number.isNaN(part))) {
    return trimmedValue;
  }

  try {
    const guessMs = Date.UTC(year, month - 1, day, hour, minute, 0);
    const guessDate = new Date(guessMs);
    const offsetMs = getTimeZoneOffsetMs(guessDate, timezone);
    return new Date(guessMs - offsetMs).toISOString();
  } catch (_) {
    return trimmedValue;
  }
};

/**
 * Resolves the offset between UTC and a target timezone for a given date.
 * @param {Date} date Date instance.
 * @param {string} timezone IANA timezone identifier.
 * @returns {number} Offset in milliseconds.
 */
const getTimeZoneOffsetMs = (date, timezone) => {
  const formatter = new Intl.DateTimeFormat("en-CA", {
    timeZone: timezone,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit",
    hourCycle: "h23",
  });
  const parts = formatter.formatToParts(date);
  const byType = Object.fromEntries(
    parts.filter((part) => part.type !== "literal").map((part) => [part.type, part.value]),
  );
  const utcMs = Date.UTC(
    Number.parseInt(byType.year, 10),
    Number.parseInt(byType.month, 10) - 1,
    Number.parseInt(byType.day, 10),
    Number.parseInt(byType.hour, 10),
    Number.parseInt(byType.minute, 10),
    Number.parseInt(byType.second, 10),
  );

  return utcMs - date.getTime();
};
