/**
 * Extracts date part from datetime-local string.
 * @param {string} datetimeLocal Datetime string, for example "2025-01-15T10:00".
 * @returns {string} Date part, for example "2025-01-15".
 */
export const extractDatePart = (datetimeLocal) => {
  if (!datetimeLocal) return "";
  return datetimeLocal.slice(0, 10);
};

/**
 * Extracts time part from datetime-local string.
 * @param {string} datetimeLocal Datetime string, for example "2025-01-15T10:00".
 * @returns {string} Time part, for example "10:00".
 */
export const extractTimePart = (datetimeLocal) => {
  if (!datetimeLocal || datetimeLocal.length < 16) return "";
  return datetimeLocal.slice(11, 16);
};

/**
 * Combines date and time into datetime-local format.
 * @param {string} date Date part, for example "2025-01-15".
 * @param {string} time Time part, for example "10:00".
 * @returns {string} Combined datetime, for example "2025-01-15T10:00".
 */
export const combineDateAndTime = (date, time) => {
  if (!date || !time) return "";
  return `${date}T${time}`;
};

/**
 * Formats a time string for display in 24-hour format.
 * @param {string} datetimeLocal Datetime string.
 * @returns {string} Formatted time, for example "10:00".
 */
export const formatTimeDisplay = (datetimeLocal) => {
  if (!datetimeLocal) return "";
  return extractTimePart(datetimeLocal);
};

/**
 * Formats a date string for display as a day header.
 * @param {string} dateStr Date string, for example "2025-01-15".
 * @returns {string} Formatted date, for example "Wednesday, January 15, 2025".
 */
export const formatDayHeader = (dateStr) => {
  if (!dateStr) return "";
  const date = new Date(`${dateStr}T12:00:00`);
  return date.toLocaleDateString(undefined, {
    weekday: "long",
    year: "numeric",
    month: "long",
    day: "numeric",
  });
};
