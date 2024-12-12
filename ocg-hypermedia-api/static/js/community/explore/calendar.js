import { isScriptLoaded } from "../../common/common.js";
import { fetchData } from "./explore.js";

class Calendar {
  constructor() {
    this.fullCalendarInstance = null;
  }

  // Initialize calendar
  initiate() {
    // If fullcalendar script is not loaded, load it
    if (!isScriptLoaded("fullcalendar")) {
      let script = document.createElement("script");
      script.type = "text/javascript";
      script.src =
        "https://cdn.jsdelivr.net/npm/fullcalendar@6.1.15/index.global.min.js";
      document.getElementsByTagName("head")[0].appendChild(script);
      // Wait for script to load and render calendar
      script.onload = () => {
        this.load();
      };
    } else {
      // If script is already loaded, load events
      this.fetchEvents();
    }
  }

  // Create tooltip for event popover on calendar
  createTooltip(id, event, horizontalAlignment, verticalAlignment) {
    const tooltip = `<div id="${id}" role="tooltip" data-popover="true" class="absolute ${
      horizontalAlignment == "right" ? "end-0" : ""
    } ${
      verticalAlignment == "top" ? "top-0 -translate-y-full pb-1.5" : "pt-1.5"
    } z-10 invisible inline-block w-[380px] text-sm text-gray-500 transition-opacity duration-300 opacity-0 tooltip-with-arrow">
      <div class="bg-white border border-gray-300 p-2 rounded-lg shadow-md">
        ${event.popover_html}
      </div>
    </div>`;

    return tooltip;
  }

  // Cleanup calendar
  cleanupCalendar() {
    if (this.fullCalendarInstance) {
      this.fullCalendarInstance.destroy();
    }
  }

  // Load calendar
  load() {
    this.cleanupCalendar();

    // Get calendar element
    const calendarEl = document.getElementById("calendar-box");

    // Initialize calendar
    this.fullCalendarInstance = new FullCalendar.Calendar(calendarEl, {
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

      // TODO - Add event click
      eventClick: (info) => {
        console.log("Event: " + info.event.name + info.view.type);
      },

      // Add tooltip to events when they are mounted
      eventDidMount: (info) => {
        // Calculate alignment based on the position of the event in the calendar
        const horizontalAlignment =
          info.el.fcSeg.firstCol > 3 ? "right" : "left";
        const verticalAlignment = info.el.fcSeg.row > 4 ? "top" : "bottom";

        // Add tooltip
        const id = `popover-${info.event.extendedProps.event.slug}`;
        info.el.parentNode.setAttribute("popovertarget", id);
        info.el.parentNode.insertAdjacentHTML(
          "beforeend",
          this.createTooltip(
            id,
            info.event.extendedProps.event,
            horizontalAlignment,
            verticalAlignment
          )
        );
      },
    });

    this.updateTitle();

    this.fetchEvents();

    // Fullcalendar render
    this.fullCalendarInstance.render();
  }

  // Convert date to ISO format
  convertDate(date) {
    return date.toISOString();
  }

  // Load events to calendar
  async fetchEvents() {
    // Prepare query params
    let date = new Date();
    if (this.fullCalendarInstance) {
      date = this.fullCalendarInstance.getDate();
    }
    // Get first and last day of the month
    const firstDayMonth = new Date(date.getFullYear(), date.getMonth(), 1);
    const lastDayMonth = new Date(date.getFullYear(), date.getMonth() + 1, 0);

    // Prepare query params
    const params = new URLSearchParams(location.search);

    // Remove view mode and date range from query params
    params.delete("view_mode");
    params.delete("date_from");
    params.delete("data_to");

    // Update date range with current month
    params.append("date_from", firstDayMonth.toISOString());
    params.append("date_to", lastDayMonth.toISOString());

    // Add limit and offset
    params.append("limit", 100);
    params.append("offset", 0);

    // Fetch events data
    const data = await fetchData("events", params.toString());

    // If events are available, add them to calendar
    if (data.events && data.events.length > 0) {
      this.renderEvents(data.events);
    }
  }

  // Add events to calendar
  renderEvents(events) {
    // Prepare events for calendar
    let formattedEvents = events.map((event) => {
      // Backgorund color for past events
      let color = "rgb(190, 190, 190)";
      if (!event.starts_at) {
        return;
      }

      // Get end date
      const endDate = event.ends_at
        ? new Date(event.ends_at * 1000)
        : new Date(event.starts_at * 1000);

      // Set end date to the end of the day to get badge color
      const endDateNoTime = endDate;
      endDateNoTime.setHours(23);
      endDateNoTime.setMinutes(59);
      endDateNoTime.setSeconds(59);

      // Get background color badge for future events
      const diff = new Date().getTime() - endDateNoTime.getTime();
      if (diff < 0) {
        color = event.group_color;
      }

      // Add event to calendar
      return {
        title: event.name,
        // allDay: true,
        start: this.convertDate(new Date(event.starts_at * 1000)),
        end: this.convertDate(endDate),
        className: "cursor-pointer",
        backgroundColor: color,
        borderColor: color,
        extendedProps: {
          event: event,
        },
      };
    });

    // Remove all previous events from calendar
    this.fullCalendarInstance.removeAllEvents();

    // Add new events to calendar
    this.fullCalendarInstance.addEventSource(formattedEvents);
  }

  // Update calendar title with month and year
  updateTitle() {
    if (this.fullCalendarInstance) {
      const el = document.getElementById("calendar-date");
      if (el) {
        el.textContent = this.fullCalendarInstance.currentData.viewTitle;
      }
    }
  }

  // Load current month data
  showCurrentMonthEvents() {
    if (this.fullCalendarInstance) {
      this.fullCalendarInstance.today();
      this.updateTitle();
      this.fetchEvents();
    }
  }

  // Load next month data
  navigateToNextMonth() {
    if (this.fullCalendarInstance) {
      this.fullCalendarInstance.next();
      this.updateTitle();
      this.fetchEvents();
    }
  }

  // Load previous month data
  navigateToPreviousMonth() {
    if (this.fullCalendarInstance) {
      this.fullCalendarInstance.prev();
      this.updateTitle();
      this.fetchEvents();
    }
  }
}

// Create calendar instance
export const calendar = new Calendar();
