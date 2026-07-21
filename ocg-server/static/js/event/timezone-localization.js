import { markDatasetReady, setElementHidden } from "/static/js/common/dom.js";

const LOCALIZED_TIME_SELECTOR = "[data-localized-time][data-starts-at][data-event-timezone]";
const USER_MENU_BUTTON_SELECTOR =
  '#user-dropdown-button[data-logged-in="true"][data-user-timezone]';
const LISTENER_READY_KEY = "eventTimezoneLocalizationReady";
const DEFAULT_PREFIX = "Your time";

const formatterCache = new Map();

const getUserPreferredTimezone = () => {
  const button = document.querySelector(USER_MENU_BUTTON_SELECTOR);
  const timezone = button?.dataset?.userTimezone;
  return typeof timezone === "string" ? timezone.trim() : "";
};

const parseIsoDate = (value) => {
  if (typeof value !== "string" || value.trim().length === 0) {
    return null;
  }

  const parsed = new Date(value);
  return Number.isNaN(parsed.getTime()) ? null : parsed;
};

const getDateTimeFormatter = (timeZone) => {
  if (!formatterCache.has(timeZone)) {
    formatterCache.set(
      timeZone,
      new Intl.DateTimeFormat(undefined, {
        timeZone,
        month: "short",
        day: "numeric",
        year: "numeric",
        hour: "numeric",
        minute: "2-digit",
        timeZoneName: "short",
      }),
    );
  }

  return formatterCache.get(timeZone);
};

export const buildLocalizedTimeLabel = ({
  end,
  prefix = DEFAULT_PREFIX,
  start,
  timezone,
}) => {
  if (!(start instanceof Date) || Number.isNaN(start.getTime())) {
    return "";
  }
  if (typeof timezone !== "string" || timezone.trim().length === 0) {
    return "";
  }

  const formattedStart = getDateTimeFormatter(timezone).format(start);
  if (!(end instanceof Date) || Number.isNaN(end.getTime())) {
    return `${prefix}: ${formattedStart}`;
  }

  const formattedEnd = getDateTimeFormatter(timezone).format(end);
  return `${prefix}: ${formattedStart} - ${formattedEnd}`;
};

export const applyUserTimezoneToEventTimes = (root = document) => {
  const userTimezone = getUserPreferredTimezone();
  if (!userTimezone) {
    return 0;
  }

  let updatedCount = 0;
  root.querySelectorAll(LOCALIZED_TIME_SELECTOR).forEach((element) => {
    const eventTimezone = (element.dataset.eventTimezone || "").trim();
    const startsAt = parseIsoDate(element.dataset.startsAt);
    const endsAt = parseIsoDate(element.dataset.endsAt);
    const prefix = (element.dataset.localizedTimePrefix || DEFAULT_PREFIX).trim() || DEFAULT_PREFIX;

    if (!eventTimezone || eventTimezone === userTimezone || !startsAt) {
      element.textContent = "";
      setElementHidden(element, true);
      return;
    }

    const localizedLabel = buildLocalizedTimeLabel({
      start: startsAt,
      end: endsAt,
      prefix,
      timezone: userTimezone,
    });
    if (!localizedLabel) {
      element.textContent = "";
      setElementHidden(element, true);
      return;
    }

    element.textContent = `(${localizedLabel})`;
    setElementHidden(element, false);
    updatedCount += 1;
  });

  return updatedCount;
};

const shouldRefreshTimezoneLabels = (target) => {
  if (target === document || target === document.body) {
    return true;
  }
  if (!(target instanceof Element)) {
    return false;
  }

  return target.matches(USER_MENU_BUTTON_SELECTOR) || Boolean(target.querySelector(USER_MENU_BUTTON_SELECTOR));
};

const handleAfterSwap = (event) => {
  const target = event?.detail?.target || event?.target;
  if (!shouldRefreshTimezoneLabels(target)) {
    return;
  }

  applyUserTimezoneToEventTimes();
};

const initializeTimezoneLocalization = () => {
  applyUserTimezoneToEventTimes();
  if (!markDatasetReady(document.documentElement, LISTENER_READY_KEY)) {
    return;
  }

  document.addEventListener("htmx:afterSwap", handleAfterSwap);
};

if (document.readyState === "loading") {
  document.addEventListener("DOMContentLoaded", initializeTimezoneLocalization, { once: true });
} else {
  initializeTimezoneLocalization();
}
