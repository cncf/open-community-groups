/**
 * Parses a timestamp value safely.
 * @param {*} value Timestamp value.
 * @returns {number|null} Parsed timestamp, or null when invalid.
 */
export const parseEventTimestamp = (value) => {
  if (value === null || value === undefined) {
    return null;
  }
  const timestamp = Number(value);
  return Number.isFinite(timestamp) ? timestamp : null;
};

/**
 * Returns the first occurrence of each event id.
 * @param {object[]} events Event payloads.
 * @returns {object[]} De-duplicated event payloads.
 */
export const uniqueEventsById = (events) => {
  const seenEventIds = new Set();
  return events.filter((event) => {
    const eventId = event?.event_id;
    if (!eventId) {
      return true;
    }
    const normalizedEventId = String(eventId);
    if (seenEventIds.has(normalizedEventId)) {
      return false;
    }
    seenEventIds.add(normalizedEventId);
    return true;
  });
};

/**
 * Formats an event date with month, day, year, time, and zone.
 * @param {object} event Event payload.
 * @returns {{text: string, isPlaceholder: boolean}} Formatted date state.
 */
export const formatEventDate = (event) => {
  if (!event || !event.starts_at) {
    return { text: "TBD", isPlaceholder: true };
  }
  try {
    const date = new Date(Number(event.starts_at) * 1000);
    const formatter = new Intl.DateTimeFormat("en-US", {
      month: "long",
      day: "numeric",
      year: "numeric",
      hour: "numeric",
      minute: "numeric",
      hour12: true,
      timeZone: event.timezone || "UTC",
      timeZoneName: "short",
    });
    const parts = formatter.formatToParts(date);
    const pick = (type) => parts.find((part) => part.type === type)?.value ?? "";
    const month = pick("month");
    const day = pick("day");
    const year = pick("year");
    const hour = pick("hour");
    const minute = pick("minute");
    const dayPeriod = pick("dayPeriod");
    const timeZoneName = pick("timeZoneName");

    const dateLabel = [month, day].filter(Boolean).join(" ");
    const dateWithYear = year ? `${dateLabel}${dateLabel ? ", " : ""}${year}` : dateLabel || year;
    const minuteLabel = minute ? minute.padStart(2, "0") : "00";
    const timeLabel = hour ? `${hour}:${minuteLabel}${dayPeriod ? ` ${dayPeriod}` : ""}` : "";
    const timeWithZone = [timeLabel, timeZoneName].filter(Boolean).join(" ");
    const text = [dateWithYear, timeWithZone].filter(Boolean).join(" · ");

    return { text: text || formatter.format(date), isPlaceholder: false };
  } catch (_error) {
    return { text: "-", isPlaceholder: false };
  }
};
