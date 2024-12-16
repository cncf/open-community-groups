import { fetchData } from "./explore.js";

export class Calendar {
  // Initialize calendar.
  constructor() {
    // Check if calendar is already initialized
    if (Calendar._instance) {
      Calendar._instance.setup();
      return Calendar._instance;
    }

    // Load `fullcalendar` script
    let script = document.createElement("script");
    script.type = "text/javascript";
    script.src = "https://cdn.jsdelivr.net/npm/fullcalendar@6.1.15/index.global.min.js";
    document.getElementsByTagName("head")[0].appendChild(script);

    // Setup calendar after script is loaded
    script.onload = () => {
      this.setup();
    };

    // Save calendar instance
    Calendar._instance = this;
  }

  // Setup calendar instance.
  setup() {
    const calendarEl = document.getElementById("calendar-box");

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

      // TODO - Add event click
      eventClick: (info) => {
        console.log("Event: " + info.event.name + info.view.type);
      },

      // Add popover to events when they are mounted
      eventDidMount: (info) => {
        // Calculate alignment based on the position of the event in the calendar
        const horizontalAlignment = info.el.fcSeg.firstCol > 3 ? "right" : "left";
        const verticalAlignment = info.el.fcSeg.row > 4 ? "top" : "bottom";

        // Add popover
        const id = `popover-${info.event.extendedProps.event.slug}`;
        info.el.parentNode.setAttribute("popovertarget", id);
        info.el.parentNode.insertAdjacentHTML(
          "beforeend",
          newEventPopover(id, info.event.extendedProps.event, horizontalAlignment, verticalAlignment)
        );
      },
    });

    this.refresh();
    this.fullCalendar.render();
  }

  // Refresh calendar, updating the title and events.
  async refresh() {
    // Update calendar title
    const el = document.getElementById("calendar-date");
    if (el) {
      el.textContent = this.fullCalendar.currentData.viewTitle;
    }

    // Refresh calendar events
    const events = await this.fetchEvents();
    if (events && events.length > 0) {
      this.addEvents(events);
    }
  }

  // Fetch events for the selected month from the server.
  async fetchEvents() {
    // Prepare query params
    const params = new URLSearchParams(location.search);

    // Remove view mode and date range from query params
    params.delete("view_mode");
    params.delete("date_from");
    params.delete("date_to");

    // Add limit and offset
    params.append("limit", 100);
    params.append("offset", 0);

    // Add date range for the month displayed
    let date = this.fullCalendar.getDate();
    const firstDayMonth = new Date(date.getFullYear(), date.getMonth(), 1);
    const lastDayMonth = new Date(date.getFullYear(), date.getMonth() + 1, 0);
    params.append("date_from", firstDayMonth.toISOString());
    params.append("date_to", lastDayMonth.toISOString());

    // Fetch events
    const data = await fetchData("events", params.toString());

    return data.events;
  }

  // Add events provided to calendar.
  addEvents(events) {
    // Prepare events for calendar
    let formattedEvents = events.map((event) => {
      // Background color for past events
      let color;
      if (!event.starts_at) {
        return;
      }

      // Get end date
      const endDate = event.ends_at ? new Date(event.ends_at * 1000) : new Date(event.starts_at * 1000);

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
        start: convertDate(new Date(event.starts_at * 1000)),
        end: convertDate(endDate),
        className: "cursor-pointer",
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
  }

  // Load current month data.
  currentMonth() {
    const today =  document.querySelector('.fc-day-today');
    if (today) {
      return;
    }

    this.fullCalendar.today();
    this.refresh();
  }

  // Load next month data.
  nextMonth() {
    this.fullCalendar.next();
    this.refresh();
  }

  // Load previous month data.
  previousMonth() {
    this.fullCalendar.prev();
    this.refresh();
  }
}

function updateColor (color) {
  if (!color) {
    return;
  }
  return hexToRgb(color, 0.35);
}

function hexToRgb(hex, alpha = 1) {
  // Remove the hash sign if it's included
  hex = hex.replace(/^#/, '');

  // Parse the hex values
  let bigint = parseInt(hex, 16);

  // Extract RGB components
  let r = (bigint >> 16) & 255;
  let g = (bigint >> 8) & 255;
  let b = bigint & 255;

  // Return the RGBA string
  return `rgba(${r}, ${g}, ${b}, ${alpha})`;
}

// Convert date to ISO format.
function convertDate(date) {
  return date.toISOString();
}

// Create a new popover for the event provided.
function newEventPopover(id, event, horizontalAlignment, verticalAlignment) {
  // prettier-ignore
  const popover = `
  <div
    id="${id}"
    role="tooltip"
    data-popover="true"
    class="absolute ${horizontalAlignment == "right" ? "end-0" : ""} ${verticalAlignment == "top" ? "top-0 -translate-y-full pb-1.5" : "pt-1.5"} z-10 invisible inline-block w-[380px] text-sm text-gray-500 transition-opacity duration-300 opacity-0 tooltip-with-arrow"
  >
    <div class="bg-white border border-gray-300 p-2 rounded-lg shadow-md">
      ${event.popover_html}
    </div>
  </div>
  `;

  return popover;
}
