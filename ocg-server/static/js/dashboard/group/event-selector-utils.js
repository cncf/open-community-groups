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
 * Builds selected-event state from copied event details.
 * @param {Object} details Copied event details.
 * @returns {Object|null} Selected event state, or null when missing.
 */
export const buildSelectedEventFromDetails = (details) => {
  if (!details) {
    return null;
  }

  return {
    event_id: String(details.event_id ?? ""),
    name: details.name || "",
    starts_at: parseEventTimestamp(details.starts_at),
    timezone: String(details.timezone || ""),
  };
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
 * Gets the selected event matching the current selection.
 * @param {Object} state Selector state.
 * @returns {Object|null}
 */
export const getSelectedEvent = ({ selectedEvent, selectedEventId, results }) => {
  if (!selectedEventId) {
    return selectedEvent;
  }

  const selectedId = String(selectedEventId ?? "");
  const matchesSelected = (event) => String(event?.event_id || "") === selectedId;
  if (selectedEvent && matchesSelected(selectedEvent)) {
    return selectedEvent;
  }

  return results.find((event) => matchesSelected(event)) || selectedEvent;
};

/**
 * Finds a matching event in a list by id.
 * @param {object[]} events Event payloads.
 * @param {string} selectedEventId Selected event id.
 * @returns {object|null} Matching event payload.
 */
export const findEventById = (events, selectedEventId) => {
  const selectedId = String(selectedEventId || "");
  if (!selectedId) return null;
  return events.find((event) => String(event?.event_id || "") === selectedId) || null;
};

/**
 * Builds primary dropdown results from upcoming and past event lists.
 * @param {Object} payload Primary result payload.
 * @returns {Object[]} Primary event results.
 */
export const buildPrimaryEventResults = ({ upcomingEvents = [], pastEvents = [], limit = 10 }) => {
  const result = [];
  result.push(...upcomingEvents.slice(0, 5).reverse());
  result.push(...pastEvents.slice(0, 5));

  const uniquePrimaryResults = uniqueEventsById(result);
  if (uniquePrimaryResults.length < limit) {
    const remainingSlots = limit - uniquePrimaryResults.length;
    const extraUpcoming = upcomingEvents.slice(5, 5 + remainingSlots).reverse();
    const extraPast = pastEvents.slice(5, 5 + remainingSlots);
    result.push(...extraUpcoming, ...extraPast);
  }

  return uniqueEventsById(result).slice(0, limit);
};

/**
 * Gets the empty event selector search state.
 * @returns {Object}
 */
export const getEmptyEventSearchState = () => ({
  activeIndex: -1,
  error: "",
  results: [],
});

/**
 * Gets the selector state when no group is available.
 * @returns {Object}
 */
export const getNoGroupEventSearchState = () => ({
  _activeIndex: -1,
  _error: "",
  _loading: false,
  _primaryResults: [],
  _results: [],
});

/**
 * Gets the selector state for loaded primary results.
 * @param {Object[]} primaryResults Primary event results.
 * @returns {Object}
 */
export const getLoadedPrimaryEventSearchState = (primaryResults) => ({
  _activeIndex: -1,
  _error: "",
  _hasFetched: true,
  _loading: false,
  _results: primaryResults,
});

/**
 * Gets the selector state for loaded query results.
 * @param {Object[]} events Search result events.
 * @returns {Object}
 */
export const getLoadedQueryEventSearchState = (events) => ({
  _activeIndex: -1,
  _hasFetched: true,
  _results: uniqueEventsById(events),
});

/**
 * Gets the group dashboard selection context from DOM.
 * @param {Element} element Selector element.
 * @param {Document|Element} documentRoot Document fallback root.
 * @returns {{community: string, groupSlug: string}}
 */
export const getDashboardSelectionContext = (element, documentRoot = document) => {
  const container =
    element?.closest?.("#dashboard-content") || documentRoot?.querySelector?.("#dashboard-content");

  return {
    community: container?.dataset?.community || "",
    groupSlug: container?.dataset?.groupSlug || "",
  };
};

/**
 * Resolves event search context from selector attributes and dashboard fallback.
 * @param {Object} context Search context values.
 * @returns {{communityName: string, groupSlug: string}}
 */
export const resolveEventSearchContext = ({
  community = "",
  dashboardSelection = {},
  groupSlug = "",
} = {}) => ({
  communityName: community || dashboardSelection.community || "",
  groupSlug: groupSlug || dashboardSelection.groupSlug || "",
});

/**
 * Builds the search URL for event selector queries.
 * @param {Object} config Search configuration.
 * @returns {string} Event search URL.
 */
export const buildEventSearchUrl = ({
  communityName = "",
  dateFrom = "",
  dateTo = "",
  groupSlug = "",
  limit = 10,
  query = "",
  sortDirection = "",
}) => {
  const params = new URLSearchParams();
  params.set("limit", String(limit));
  if (dateFrom) params.set("date_from", dateFrom);
  if (dateTo) params.set("date_to", dateTo);
  if (sortDirection) params.set("sort_direction", sortDirection);
  if (query) params.set("ts_query", query);
  if (groupSlug) params.append("group[]", groupSlug);
  if (communityName) params.append("community[]", communityName);
  return `/explore/events/search?${params.toString()}`;
};

/**
 * Gets event option visual state for the dropdown.
 * @param {Object} state Option state.
 * @returns {{isSelected: boolean, statusClass: string}}
 */
export const getEventOptionState = ({ activeIndex, event, index, selectedEventId }) => {
  const eventId = String(event?.event_id || "");
  const isSelected = Boolean(selectedEventId && String(selectedEventId) === eventId);
  const isActive = index === activeIndex;
  if (isSelected) {
    return { isSelected, statusClass: "bg-stone-100" };
  }
  if (isActive) {
    return { isSelected, statusClass: "bg-stone-50" };
  }
  return { isSelected, statusClass: "" };
};

/**
 * Resolves keyboard action for the event selector search input.
 * @param {Object} state Keyboard state.
 * @returns {Object} Keyboard action and next active index.
 */
export const getEventSelectorKeyAction = ({ activeIndex, getNextIndex, isEscape, key, resultsLength }) => {
  const currentIndex = activeIndex < 0 ? null : activeIndex;
  if (key === "ArrowDown") {
    return {
      action: "highlight",
      activeIndex: getNextIndex(currentIndex, resultsLength, 1),
      preventDefault: true,
    };
  }
  if (key === "ArrowUp") {
    return {
      action: "highlight",
      activeIndex: getNextIndex(currentIndex, resultsLength, -1, resultsLength - 1),
      preventDefault: true,
    };
  }
  if (key === "Enter") {
    return { action: "select", activeIndex, preventDefault: true };
  }
  if (isEscape) {
    return { action: "close", activeIndex, preventDefault: true };
  }
  return { action: "none", activeIndex, preventDefault: false };
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
