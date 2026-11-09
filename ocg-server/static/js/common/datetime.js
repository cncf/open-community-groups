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
 * Formats Unix seconds as a time of day in a timezone, adding the date when it
 * falls on a different calendar day than the reference instant.
 * @param {number} tsSeconds Unix timestamp in seconds.
 * @param {string} timezone IANA timezone identifier; empty or invalid values use
 * the browser timezone.
 * @param {Date} [now] Reference instant compared in the same timezone.
 * @returns {string} Time such as "6:42 PM", dated time such as
 * "Nov 8, 6:42 PM", or "" when the timestamp is not a finite number.
 */
export const formatTimestampTimeInTz = (tsSeconds, timezone, now = new Date()) => {
  if (!Number.isFinite(tsSeconds)) {
    return "";
  }

  const date = new Date(tsSeconds * 1000);
  if (Number.isNaN(date.getTime())) {
    return "";
  }

  const formatter = createTimeOfDayFormatter(timezone);
  const parts = getDateTimeParts(formatter, date);
  const nowParts = getDateTimeParts(formatter, now);
  // Build the time with an ASCII space; format() separates the day period with
  // U+202F.
  const time = `${parts.hour}:${parts.minute} ${parts.dayPeriod}`;
  const sameDay = ["year", "month", "day"].every((type) => parts[type] === nowParts[type]);
  return sameDay ? time : `${parts.month} ${parts.day}, ${time}`;
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
 * Creates the en-US date and time-of-day formatter, falling back to the browser
 * timezone when the timezone is empty or invalid.
 * @param {string} timezone IANA timezone identifier.
 * @returns {Intl.DateTimeFormat} Formatter.
 */
const createTimeOfDayFormatter = (timezone) => {
  const options = {
    hour: "numeric",
    minute: "2-digit",
    month: "short",
    day: "numeric",
    year: "numeric",
  };
  if (typeof timezone === "string" && timezone.length > 0) {
    try {
      return new Intl.DateTimeFormat("en-US", { ...options, timeZone: timezone });
    } catch (error) {
      if (!(error instanceof RangeError)) throw error;
    }
  }
  return new Intl.DateTimeFormat("en-US", options);
};

/**
 * Maps the formatted parts of a date by part type.
 * @param {Intl.DateTimeFormat} formatter Formatter.
 * @param {Date} date Date instance.
 * @returns {Object<string, string>} Part values keyed by type.
 */
const getDateTimeParts = (formatter, date) =>
  Object.fromEntries(
    formatter
      .formatToParts(date)
      .filter((part) => part.type !== "literal")
      .map((part) => [part.type, part.value]),
  );

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
