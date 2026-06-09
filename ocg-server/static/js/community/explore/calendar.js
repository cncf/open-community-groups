import { hideLoadingSpinner, showLoadingSpinner, navigateWithHtmx } from "/static/js/common/common.js";
import { getElementById, loadScriptOnce, setElementHidden } from "/static/js/common/dom.js";
import { insertTrustedHtml } from "/static/js/common/trusted-html.js";
import { parseJsonText } from "/static/js/common/utils.js";
import { fetchData } from "/static/js/community/explore/explore.js";
import {
  getFirstAndLastDayOfMonth,
  hasActiveCalendarFilters,
  updateDateInput,
} from "/static/js/community/explore/filters.js";

const FULLCALENDAR_SCRIPT_SRC = "/static/vendor/js/fullcalendar.v6.1.19.min.js";
const MAIN_LOADING_CALENDAR_ID = "main-loading-calendar";
const LOADING_CALENDAR_ID = "loading-calendar";
const CALENDAR_ELEMENT_ID = "calendar-box";
const CALENDAR_DATE_ID = "calendar-date";
const EVENTS_FORM_ID = "events-form";
const DATE_TO_INPUT_SELECTOR = 'input[name="date_to"]';
const NO_RESULTS_SELECTOR = ".no-results-default, .no-results-filtered";
const DEFAULT_NO_RESULTS_SELECTOR = ".no-results-default";
const FILTERED_NO_RESULTS_SELECTOR = ".no-results-filtered";
const POPOVER_OPEN_DELAY_MS = 300;
const RIGHT_ALIGNED_COLUMN_THRESHOLD = 3;
const TOP_ALIGNED_ROW_THRESHOLD = 4;
const PAST_EVENT_COLOR_ALPHA = 0.35;
const UPCOMING_COLOR_VARIABLES = {
  background: "--color-primary-50",
  border: "--color-primary-200",
};
const POPOVER_BASE_CLASSES =
  "absolute z-10 invisible inline-block text-sm text-stone-500 transition-opacity duration-300 opacity-0 tooltip-with-arrow";
const POPOVER_BOTTOM_CLASSES = "pt-1.5";
const POPOVER_TOP_CLASSES = "top-0 -translate-y-full pb-1.5";

/**
 * Reads the initially selected calendar date from the hidden date input.
 * @returns {Date} Initial calendar date
 */
const getInitialCalendarDate = () => {
  const dateToInput = document.querySelector(DATE_TO_INPUT_SELECTOR);
  return dateToInput ? new Date(dateToInput.value) : new Date();
};

/**
 * Shows or hides the main calendar loading state.
 * @param {boolean} visible - Whether the loading indicator should be visible
 */
const setMainCalendarLoading = (visible) => {
  const mainLoading = getElementById(document, MAIN_LOADING_CALENDAR_ID);
  setElementHidden(mainLoading, !visible);
};

/**
 * Loads the FullCalendar script when needed.
 * @returns {Promise<void>} Promise resolved when FullCalendar is available
 */
const loadFullCalendarScript = () =>
  loadScriptOnce(FULLCALENDAR_SCRIPT_SRC, {
    isLoaded: () => typeof window.FullCalendar !== "undefined",
  });

/**
 * Gets the URL for an event page.
 * @param {object} event - Explore event payload
 * @returns {string|undefined} Event URL when required slugs are present
 */
const getEventUrl = (event) => {
  if (!event.group_slug || !event.slug) {
    return undefined;
  }

  return `/${event.community_name}/group/${event.group_slug_pretty || event.group_slug}/event/${event.slug}`;
};

/**
 * Builds popover alignment data from the FullCalendar segment.
 * @param {object} info - FullCalendar event mount info
 * @returns {object} Popover alignment data
 */
const getPopoverAlignment = (info) => ({
  id: `popover-${info.event.extendedProps.event.slug}`,
  horizontal: info.el.fcSeg.firstCol > RIGHT_ALIGNED_COLUMN_THRESHOLD ? "right" : "left",
  vertical: info.el.fcSeg.row >= TOP_ALIGNED_ROW_THRESHOLD ? "top" : "bottom",
});

/**
 * Reads popover alignment data stored on a calendar event parent.
 * @param {HTMLElement} parent - Event parent element
 * @returns {object|null} Popover alignment data
 */
const readPopoverAlignment = (parent) => {
  if (!parent.dataset.popoverAlign) {
    return null;
  }

  return parseJsonText(parent.dataset.popoverAlign, null);
};

/**
 * Removes an existing popover by id.
 * @param {string} id - Popover element id
 */
const removePopoverById = (id) => {
  getElementById(document, id)?.remove();
};

/**
 * Clears popover data and DOM for an event parent.
 * @param {HTMLElement} parent - Event parent element
 */
const clearPopover = (parent) => {
  const alignData = readPopoverAlignment(parent);
  if (alignData) {
    removePopoverById(alignData.id);
  }
  delete parent.dataset.popoverAlign;
  parent.removeAttribute("popovertarget");
};

/**
 * Stores popover alignment data on an event parent.
 * @param {HTMLElement} parent - Event parent element
 * @param {object} info - FullCalendar event mount info
 */
const setPopoverAlignment = (parent, info) => {
  parent.dataset.popoverAlign = JSON.stringify(getPopoverAlignment(info));
};

/**
 * Reads primary colors used by upcoming calendar events.
 * @returns {object} Calendar color tokens
 */
const getCalendarColors = () => {
  const styles = getComputedStyle(document.documentElement);
  return {
    upcomingBg: styles.getPropertyValue(UPCOMING_COLOR_VARIABLES.background).trim(),
    upcomingBorder: styles.getPropertyValue(UPCOMING_COLOR_VARIABLES.border).trim(),
  };
};

/**
 * Formats one event for FullCalendar.
 * @param {object} event - Explore event payload
 * @param {object} colors - Calendar color tokens
 * @returns {object|undefined} FullCalendar event data
 */
const formatCalendarEvent = (event, colors) => {
  if (!event.starts_at) {
    return undefined;
  }

  const startDate = new Date(event.starts_at * 1000);
  const endDate = event.ends_at ? new Date(event.ends_at * 1000) : startDate;
  const isPast = new Date().getTime() - endDate.getTime() > 0;
  const backgroundColor = isPast ? updateColor(event.group_color) : colors.upcomingBg;
  const borderColor = isPast ? event.group_color : colors.upcomingBorder;

  return {
    title: event.name,
    start: convertDate(startDate),
    end: convertDate(endDate),
    className: `cursor-pointer ${isPast ? "opacity-40" : ""}`,
    backgroundColor,
    borderColor,
    extendedProps: {
      event,
    },
  };
};

/**
 * Hides no-results placeholders inside the calendar wrapper.
 * @param {HTMLElement|null} wrapper - Calendar wrapper element
 */
const hideNoResultsPlaceholders = (wrapper) => {
  wrapper?.querySelectorAll(NO_RESULTS_SELECTOR).forEach((container) => {
    setElementHidden(container, true);
  });
};

/**
 * Shows the matching no-results placeholder for the current filter state.
 * @param {HTMLElement|null} wrapper - Calendar wrapper element
 * @param {object} fullCalendar - FullCalendar instance
 */
const showNoResultsPlaceholder = (wrapper, fullCalendar) => {
  const selector = hasActiveCalendarFilters(EVENTS_FORM_ID, fullCalendar.getDate())
    ? FILTERED_NO_RESULTS_SELECTOR
    : DEFAULT_NO_RESULTS_SELECTOR;
  setElementHidden(wrapper?.querySelector(selector), false);
};

/**
 * FullCalendar-backed community explore calendar controller.
 */
export class Calendar {
  /**
   * Initializes the calendar with FullCalendar library.
   * Uses singleton pattern to ensure only one calendar instance exists.
   * @param {object} data - Initial calendar data containing events
   */
  constructor(data) {
    // Check if calendar is already initialized
    if (Calendar._instance) {
      Calendar._instance.setup(data);
      return Calendar._instance;
    }

    this.popoverTimers = new WeakMap();

    setMainCalendarLoading(true);

    loadFullCalendarScript()
      .then(() => this.setup(data))
      .catch(() => setMainCalendarLoading(false));

    // Save calendar instance
    Calendar._instance = this;
  }

  /**
   * Sets up the FullCalendar instance with configuration and event handlers.
   * @param {object} data - Calendar data containing events to display
   */
  setup(data) {
    const calendarEl = getElementById(document, CALENDAR_ELEMENT_ID);
    const initialDate = getInitialCalendarDate();

    this.fullCalendar = new FullCalendar.Calendar(calendarEl, {
      timeZone: "local",
      initialView: "dayGridMonth",
      displayEventTime: false,
      eventDisplay: "block",
      events: [],
      selectable: false,
      showNonCurrentDates: false,
      headerToolbar: false,
      dayMaxEventRows: 4,
      moreLinkClick: "popover",
      initialDate: initialDate,

      // Handle event clicks to navigate to event page
      eventClick: (info) => {
        const event = info.event.extendedProps.event;
        const url = getEventUrl(event);
        if (url) {
          navigateWithHtmx(url);
        }
      },

      // Store alignment data on element for later popover creation
      eventDidMount: (info) => {
        const parent = info.el.parentNode;
        if (!parent) {
          return;
        }

        if (info.event.extendedProps.event.popover_html) {
          setPopoverAlignment(parent, info);
        } else {
          clearPopover(parent);
        }
      },

      // Start 300ms timer to show popover on mouse enter
      eventMouseEnter: (info) => {
        const parent = info.el.parentNode;
        if (!parent || !parent.dataset.popoverAlign) return;

        clearTimeout(this.popoverTimers.get(parent));
        const timer = setTimeout(() => {
          createPopoverIfNeeded(parent, info.event.extendedProps.event);
        }, POPOVER_OPEN_DELAY_MS);
        this.popoverTimers.set(parent, timer);
      },

      // Cancel popover timer on mouse leave
      eventMouseLeave: (info) => {
        const parent = info.el.parentNode;
        if (!parent) return;
        clearTimeout(this.popoverTimers.get(parent));
      },

      // Clean up timers when events are unmounted (e.g., month navigation)
      eventWillUnmount: (info) => {
        const parent = info.el.parentNode;
        if (!parent) return;
        clearTimeout(this.popoverTimers.get(parent));
        this.popoverTimers.delete(parent);
        clearPopover(parent);
      },
    });

    // Refresh calendar with initial data and render it
    this.refresh(data);
    this.fullCalendar.render();
  }

  /**
   * Refreshes the calendar by updating the title and loading new events.
   * @param {object} data - Optional data object containing events to display
   */
  async refresh(data) {
    // Update calendar title
    const el = getElementById(document, CALENDAR_DATE_ID);
    if (el) {
      el.textContent = this.fullCalendar.currentData.viewTitle;
    }

    // Refresh calendar events
    let events;
    // If data is provided, use it to set events
    // Otherwise, fetch events for the current month
    if (data) {
      events = data.events;
    } else {
      // Show loading spinner
      showLoadingSpinner(LOADING_CALENDAR_ID);

      // Fetch events
      try {
        events = await this.fetchEvents();
      } catch (error) {
        // If fetch fails, hide loading and ignore error
        hideLoadingSpinner(LOADING_CALENDAR_ID);
        return;
      }
    }

    // Toggle placeholder visibility and calendar opacity
    const calendarEl = getElementById(document, CALENDAR_ELEMENT_ID);
    const wrapper = calendarEl ? calendarEl.parentElement : null;
    hideNoResultsPlaceholders(wrapper);

    if (events && events.length > 0) {
      // Ensure calendar is fully visible
      if (calendarEl) {
        calendarEl.classList.remove("opacity-30");
      }
      this.addEvents(events);
    } else {
      // Show placeholder overlay if present and dim calendar
      if (calendarEl) {
        calendarEl.classList.add("opacity-30");
      }
      this.addEvents([]);
      showNoResultsPlaceholder(wrapper, this.fullCalendar);
    }
  }

  /**
   * Fetches events for the currently displayed month from the server.
   * @returns {Promise<Array>} Array of event objects for the current month
   */
  async fetchEvents() {
    // Prepare query params
    const params = new URLSearchParams(location.search);

    // Update view mode and date range in query params
    params.set("view_mode", "calendar");
    params.delete("date_from");
    params.delete("date_to");

    // Add date range for the month displayed
    const date = this.fullCalendar.getDate();
    const { first, last } = getFirstAndLastDayOfMonth(date);

    params.set("date_from", first);
    params.set("date_to", last);

    // Update inputs
    updateDateInput(date);
    updateCalendarUrl(params);

    // Fetch events
    const data = await fetchData("events", params.toString());

    return data.events;
  }

  /**
   * Adds events to the calendar after formatting them for FullCalendar.
   * @param {Array} events - Array of event objects to add to the calendar
   */
  addEvents(events) {
    const colors = getCalendarColors();
    const formattedEvents = events.map((event) => formatCalendarEvent(event, colors)).filter(Boolean);

    // Remove all previous events from calendar
    this.fullCalendar.removeAllEvents();

    // Add new events to calendar
    this.fullCalendar.addEventSource(formattedEvents);

    // Hide loading spinner
    hideLoadingSpinner(LOADING_CALENDAR_ID);
  }

  /**
   * Navigates to and loads data for the current month.
   */
  currentMonth() {
    const today = document.querySelector(".fc-day-today");
    if (today) {
      return;
    }

    this.fullCalendar.today();
    this.refresh();
  }

  /**
   * Navigates to and loads data for the next month.
   */
  nextMonth() {
    this.fullCalendar.next();
    this.refresh();
  }

  /**
   * Navigates to and loads data for the previous month.
   */
  previousMonth() {
    this.fullCalendar.prev();
    this.refresh();
  }
}

/**
 * Converts a hexadecimal color to RGB with opacity for calendar events.
 * @param {string} color - The hexadecimal color string
 * @returns {string|undefined} The RGBA color string with 0.35 opacity
 */
function updateColor(color) {
  if (!color) {
    return;
  }
  return hexToRgb(color, PAST_EVENT_COLOR_ALPHA);
}

/**
 * Converts a hexadecimal color value to RGBA format.
 * @param {string} hex - The hexadecimal color string (with or without #)
 * @param {number} alpha - The alpha/opacity value (0-1)
 * @returns {string} The RGBA color string
 */
function hexToRgb(hex, alpha = 1) {
  // Remove the hash sign if it's included
  hex = hex.replace(/^#/, "");

  // Parse the hex values
  let bigint = parseInt(hex, 16);

  // Extract RGB components
  let r = (bigint >> 16) & 255;
  let g = (bigint >> 8) & 255;
  let b = bigint & 255;

  // Return the RGBA string
  return `rgba(${r}, ${g}, ${b}, ${alpha})`;
}

/**
 * Converts a Date object to ISO format string.
 * @param {Date} date - The date object to convert
 * @returns {string} The ISO formatted date string
 */
function convertDate(date) {
  return date.toISOString();
}

/**
 * Creates a popover HTML element for displaying event details.
 * @param {string} id - The unique ID for the popover element
 * @param {object} event - The event object containing popover_html
 * @param {string} horizontalAlignment - Horizontal alignment ('left' or 'right')
 * @param {string} verticalAlignment - Vertical alignment ('top' or 'bottom')
 * @returns {string} The HTML string for the popover element
 */
function newEventPopover(id, event, horizontalAlignment, verticalAlignment) {
  const alignmentClasses = [
    POPOVER_BASE_CLASSES,
    horizontalAlignment == "right" ? "end-0" : "",
    verticalAlignment == "top" ? POPOVER_TOP_CLASSES : POPOVER_BOTTOM_CLASSES,
  ]
    .filter(Boolean)
    .join(" ");

  // prettier-ignore
  const popover = `
  <div
    id="${id}"
    role="tooltip"
    data-popover="true"
    class="${alignmentClasses}"
  >
    <div class="explore-popover-card-shell">
      ${event.popover_html}
    </div>
  </div>
  `;

  return popover;
}

/**
 * Creates the popover DOM if it doesn't already exist.
 * @param {HTMLElement} parent - The parent element to attach the popover to
 * @param {object} event - The event object containing popover_html
 */
function createPopoverIfNeeded(parent, event) {
  const alignData = readPopoverAlignment(parent);
  if (!alignData) return;

  // Check if popover already exists
  if (getElementById(document, alignData.id)) return;

  // Set popovertarget and create popover
  parent.setAttribute("popovertarget", alignData.id);
  insertTrustedHtml(
    parent,
    "beforeend",
    newEventPopover(alignData.id, event, alignData.horizontal, alignData.vertical),
  );
}

/**
 * Updates the browser URL to reflect the current calendar filters.
 * @param {URLSearchParams} params - Query params to write to the URL
 */
function updateCalendarUrl(params) {
  const nextUrl = new URL(window.location.href);
  nextUrl.search = params.toString();
  window.history.replaceState({}, "", nextUrl);
}
