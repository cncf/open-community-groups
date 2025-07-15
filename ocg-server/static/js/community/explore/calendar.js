import { hideLoadingSpinner, showLoadingSpinner } from "/static/js/common/common.js";
import { fetchData } from "/static/js/community/explore/explore.js";
import { getFirstAndLastDayOfMonth, updateDateInput } from "/static/js/community/explore/filters.js";

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

    // Display main loading spinner
    // This is used to show a loading spinner while the calendar is being set up
    // and the FullCalendar script is being loaded.
    const mainLoading = document.getElementById("main-loading-calendar");
    if (mainLoading) {
      mainLoading.classList.remove("hidden");
    }

    // Load `fullcalendar` script
    let script = document.createElement("script");
    script.type = "text/javascript";
    script.src = "/static/vendor/js/fullcalendar.v6.1.15.min.js";
    document.getElementsByTagName("head")[0].appendChild(script);

    // Setup calendar after script is loaded
    script.onload = () => {
      this.setup(data);
    };

    // Save calendar instance
    Calendar._instance = this;
  }

  /**
   * Sets up the FullCalendar instance with configuration and event handlers.
   * @param {object} data - Calendar data containing events to display
   */
  setup(data) {
    const calendarEl = document.getElementById("calendar-box");
    const date_to = document.querySelector('input[name="date_to"]');
    const initialDate = date_to ? new Date(date_to.value) : new Date();

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

      // Add popover to events when they are mounted
      eventDidMount: (info) => {
        if (info.event.extendedProps.event.popover_html) {
          // Calculate alignment based on the position of the event in the calendar
          const horizontalAlignment = info.el.fcSeg.firstCol > 3 ? "right" : "left";
          const verticalAlignment = info.el.fcSeg.row > 4 ? "top" : "bottom";

          // Add popover with unique ID to the event element
          const id = `popover-${info.event.extendedProps.event.slug}`;
          info.el.parentNode.setAttribute("popovertarget", id);
          info.el.parentNode.insertAdjacentHTML(
            "beforeend",
            newEventPopover(id, info.event.extendedProps.event, horizontalAlignment, verticalAlignment),
          );
        }
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
    const el = document.getElementById("calendar-date");
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
      showLoadingSpinner("loading-calendar");

      // Fetch events
      events = await this.fetchEvents();
    }

    if (events && events.length > 0) {
      this.addEvents(events);
    } else {
      // Hide loading spinner
      hideLoadingSpinner("loading-calendar");
    }
  }

  /**
   * Fetches events for the currently displayed month from the server.
   * @returns {Promise<Array>} Array of event objects for the current month
   */
  async fetchEvents() {
    // Prepare query params
    const params = new URLSearchParams(location.search);

    // Remove view mode and date range from query params
    params.delete("view_mode");
    params.delete("date_from");
    params.delete("date_to");

    // Add date range for the month displayed
    const date = this.fullCalendar.getDate();
    const { first, last } = getFirstAndLastDayOfMonth(date);

    params.append("date_from", first);
    params.append("date_to", last);

    // Update inputs
    updateDateInput(date);

    // Fetch events
    const data = await fetchData("events", params.toString());

    return data.events;
  }

  /**
   * Adds events to the calendar after formatting them for FullCalendar.
   * @param {Array} events - Array of event objects to add to the calendar
   */
  addEvents(events) {
    // Prepare events for calendar
    let formattedEvents = events.map((event) => {
      // Skip events without start date
      if (!event.starts_at) {
        return;
      }

      const color = event.group_color;
      let isPast = false;

      // Get end date
      const endDate = event.ends_at ? new Date(event.ends_at * 1000) : new Date(event.starts_at * 1000);

      // Get background color badge for future events
      const diff = new Date().getTime() - endDate.getTime();
      if (diff > 0) {
        isPast = true;
      }

      // Add event to calendar
      return {
        title: event.name,
        start: convertDate(new Date(event.starts_at * 1000)),
        end: convertDate(endDate),
        className: `cursor-pointer ${isPast ? "opacity-50" : ""}`,
        backgroundColor: updateColor(color),
        borderColor: color,
        extendedProps: {
          event: event,
        },
      };
    });

    // Remove all previous events from calendar
    this.fullCalendar.removeAllEvents();

    // Add new events to calendar
    this.fullCalendar.addEventSource(formattedEvents);

    // Hide loading spinner
    hideLoadingSpinner("loading-calendar");
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
  return hexToRgb(color, 0.35);
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
  // prettier-ignore
  const popover = `
  <div
    id="${id}"
    role="tooltip"
    data-popover="true"
    class="absolute ${horizontalAlignment == "right" ? "end-0" : ""} ${verticalAlignment == "top" ? "top-0 -translate-y-full pb-1.5" : "pt-1.5"} z-10 invisible inline-block w-[380px] text-sm text-stone-500 transition-opacity duration-300 opacity-0 tooltip-with-arrow"
  >
    <div class="bg-white border border-stone-200 p-2 rounded-lg shadow-lg">
      ${event.popover_html}
    </div>
  </div>
  `;

  return popover;
}
