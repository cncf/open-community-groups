import { extractDatePart } from "/static/js/dashboard/event/sessions-datetime.js";

/**
 * Creates a new empty session data object.
 * @param {number} id Session id.
 * @returns {Object} Empty session entry.
 */
export const createEmptySession = (id = 0) => ({
  id,
  name: "",
  description: "",
  kind: "",
  starts_at: "",
  ends_at: "",
  cfs_submission_id: "",
  location: "",
  meeting_requested: false,
  meeting_in_sync: false,
  meeting_join_instructions: "",
  meeting_join_url: "",
  meeting_provider_id: "",
  meeting_password: "",
  meeting_error: "",
  meeting_recording_published: false,
  meeting_recording_raw_urls: [],
  meeting_recording_url: "",
  meeting_hosts: [],
  speakers: [],
});

/**
 * Determines the current schedule scenario based on event dates.
 * @param {string} eventStartsAt Event start datetime.
 * @param {string} eventEndsAt Event end datetime.
 * @returns {string} "no-dates" | "single-day" | "multi-day".
 */
export const computeSessionScenario = (eventStartsAt, eventEndsAt) => {
  if (!eventStartsAt || !eventEndsAt) {
    return "no-dates";
  }
  const startDate = extractDatePart(eventStartsAt);
  const endDate = extractDatePart(eventEndsAt);
  return startDate === endDate ? "single-day" : "multi-day";
};

/**
 * Computes all days between event start and end dates.
 * @param {string} eventStartsAt Event start datetime.
 * @param {string} eventEndsAt Event end datetime.
 * @returns {string[]} Date strings.
 */
export const computeEventDays = (eventStartsAt, eventEndsAt) => {
  if (!eventStartsAt || !eventEndsAt) return [];

  const startDate = extractDatePart(eventStartsAt);
  const endDate = extractDatePart(eventEndsAt);
  const days = [];

  let [year, month, day] = startDate.split("-").map(Number);
  const [endYear, endMonth, endDay] = endDate.split("-").map(Number);

  while (
    year < endYear ||
    (year === endYear && month < endMonth) ||
    (year === endYear && month === endMonth && day <= endDay)
  ) {
    const dateStr = `${year}-${String(month).padStart(2, "0")}-${String(day).padStart(2, "0")}`;
    days.push(dateStr);

    day += 1;
    const daysInMonth = new Date(year, month, 0).getDate();
    if (day > daysInMonth) {
      day = 1;
      month += 1;
      if (month > 12) {
        month = 1;
        year += 1;
      }
    }
  }

  return days;
};

/**
 * Returns sessions sorted by start time.
 * @param {Array<Object>} sessions Session payloads.
 * @returns {Array<Object>} Sorted sessions.
 */
export const getSortedSessions = (sessions = []) =>
  [...sessions].sort((a, b) => (a.starts_at || "").localeCompare(b.starts_at || ""));

/**
 * Groups sessions by their date.
 * @param {Array<Object>} sessions Session payloads.
 * @param {string[]} days Event day strings.
 * @returns {Map<string, Array<Object>>} Map of date to sessions.
 */
export const groupSessionsByDay = (sessions = [], days = []) => {
  const map = new Map();
  days.forEach((day) => map.set(day, []));

  sessions.forEach((session) => {
    const dayKey = extractDatePart(session.starts_at);
    if (dayKey && map.has(dayKey)) {
      map.get(dayKey).push(session);
    }
  });

  map.forEach((daySessions) => {
    daySessions.sort((a, b) => (a.starts_at || "").localeCompare(b.starts_at || ""));
  });

  return map;
};

/**
 * Returns sessions outside of the current event date range.
 * @param {Array<Object>} sessions Session payloads.
 * @param {string[]} days Event day strings.
 * @returns {Array<Object>} Sessions outside range.
 */
export const getOutOfRangeSessions = (sessions = [], days = []) => {
  const daySet = new Set(days);
  return getSortedSessions(sessions).filter((session) => !daySet.has(extractDatePart(session.starts_at)));
};

/**
 * Gets the next unique numeric session id.
 * @param {Array<Object>} sessions Session payloads.
 * @returns {number} Next session id.
 */
export const getNextSessionId = (sessions = []) => {
  const maxId = sessions.reduce((currentMax, currentSession) => {
    const currentId = Number(currentSession?.id);
    if (!Number.isFinite(currentId)) return currentMax;
    return Math.max(currentMax, currentId);
  }, -1);
  return maxId + 1;
};
