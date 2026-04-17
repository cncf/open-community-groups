import { toTrimmedString } from "/static/js/dashboard/event/ticketing/shared.js";

/**
 * Resolves the event timezone from the shared event form.
 * @param {HTMLInputElement|HTMLSelectElement|HTMLTextAreaElement|null} [timezoneField]
 * @returns {string}
 */
export const resolveEventTimezone = (timezoneField = document.querySelector('[name="timezone"]')) => {
  return typeof timezoneField?.value === "string" ? timezoneField.value.trim() : "";
};

/**
 * Builds a datetime-local string from an ISO timestamp in the selected timezone.
 * @param {string} value ISO timestamp
 * @param {string} timezone IANA timezone
 * @returns {string}
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
    const formatter = new Intl.DateTimeFormat("en-CA", {
      timeZone: timezone,
      year: "numeric",
      month: "2-digit",
      day: "2-digit",
      hour: "2-digit",
      minute: "2-digit",
      hourCycle: "h23",
    });
    const parts = formatter.formatToParts(date);
    const byType = Object.fromEntries(
      parts.filter((part) => part.type !== "literal").map((part) => [part.type, part.value]),
    );
    return `${byType.year}-${byType.month}-${byType.day}T${byType.hour}:${byType.minute}`;
  } catch (_) {
    return value.slice(0, 16);
  }
};

/**
 * Converts a datetime-local value into UTC ISO using the selected timezone.
 * @param {string} value Datetime-local string
 * @param {string} timezone IANA timezone
 * @returns {string|null}
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
 * @param {Date} date Date instance
 * @param {string} timezone IANA timezone
 * @returns {number}
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
