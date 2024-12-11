import { checkIfScriptIsLoaded } from '../../common/common.js';
import { fetchData } from './explore.js';

// Calendar

let calendar = null;

// Update calendar title with current month and year
export const updateCalendarDate = () => {
  if (calendar) {
    const el = document.getElementById('calendar-date');
    if (el) {
      el.textContent = calendar.currentData.viewTitle;
    }
  }
}

// Load calendar on `calendar-box` element
export const loadCalendar = () => {
  // Prepare tooltip for calendar events
  const createTooltip = (id, event, horizontalAlignment, verticalAlignment) => {
    const tooltip = `<div id="${id}" role="tooltip" data-popover="true" class="absolute ${horizontalAlignment == 'right' ? 'end-0' : ''} ${verticalAlignment == 'top' ? 'top-0 -translate-y-full pb-1.5' : 'pt-1.5'} z-10 invisible inline-block w-[380px] text-sm text-gray-500 transition-opacity duration-300 opacity-0 tooltip-with-arrow">
      <div class="bg-white border border-gray-300 p-2 rounded-lg shadow-md">
        ${event.popover_html}
      </div>
    </div>`;

    return tooltip;
  }

  // Render calendar on screen
  const renderCalendar = () => {
    const calendarEl = document.getElementById('calendar-box');

    if (calendar) {
      calendar.destroy();
    }

    // Initialize calendar
    calendar = new FullCalendar.Calendar(calendarEl, {
      timeZone: 'local',
      initialView: 'dayGridMonth',
      displayEventTime: false,
      eventDisplay: 'block',
      events: [],
      selectable: false,
      showNonCurrentDates: false,
      headerToolbar: false,
      dayMaxEventRows: 4,
      moreLinkClick: 'popover',

      // TODO - Add event click
      eventClick: (info) => {
        console.log('Event: ' + info.event.name + info.view.type);
      },

      // Add tooltip to events when they are mounted
      eventDidMount: (info) => {
        // Calculate alignment based on the position of the event in the calendar
        const horizontalAlignment = info.el.fcSeg.firstCol > 3 ? 'right' : 'left';
        const verticalAlignment = info.el.fcSeg.row > 4 ? 'top' : 'bottom';

        // Add tooltip
        const id = `popover-${info.event.extendedProps.event.slug}`;
        info.el.parentNode.setAttribute('popovertarget', id);
        info.el.parentNode.insertAdjacentHTML('beforeend', createTooltip(id, info.event.extendedProps.event, horizontalAlignment, verticalAlignment));
      },
    });

    // Update calendar title
    updateCalendarDate();

    // Load new events
    loadNewEvents();

    // Call to render calendar
    calendar.render();
  };

  // If fullcalendar script is not loaded, load it
  if (!checkIfScriptIsLoaded('fullcalendar')) {
    let script = document.createElement('script');
    script.type = 'text/javascript';
    // Load only required libraries
    script.src = 'https://cdn.jsdelivr.net/npm/fullcalendar@6.1.15/index.global.min.js';
    document.getElementsByTagName('head')[0].appendChild(script);
    // Wait for script to load and render calendar
    script.onload = () => {
      renderCalendar();
    };
  } else {
    // If script is already loaded, render calendar
    loadNewEvents();
  }
};

// Load new events on calendar
const loadNewEvents = async () => {
  // Convert date to ISO format
  const convertDate = (date) => {
    return date.toISOString();
  }

  // Prepare data for calendar
  let date = new Date();
  if (calendar) {
    date = calendar.getDate();
  }
  // Get first and last day of the month
  const firstDayMonth = new Date(date.getFullYear(), date.getMonth(), 1);
  const lastDayMonth = new Date(date.getFullYear(), date.getMonth() + 1, 0);

  // Prepare query params
  const params = new URLSearchParams(location.search);

  // Remove view mode and date range from query params
  params.delete('view_mode');
  params.delete('date_from');
  params.delete('data_to');

  // Update date range with current month
  params.append('date_from', firstDayMonth.toISOString());
  params.append('date_to', lastDayMonth.toISOString());

  // Add limit and offset
  params.append('limit', 100);
  params.append('offset', 0);

  // Fetch events data
  const data = await fetchData("events", params.toString());

  // If events are available, add them to calendar
  if (data.events && data.events.length > 0) {
    // Prepare events for calendar
    let formattedEvents = data.events.map(event => {
      // Backgorund color for past events
      let color = 'rgb(190, 190, 190)';
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
        // allDay: true,
        start: convertDate(new Date(event.starts_at * 1000)),
        end: convertDate(endDate),
        className: "cursor-pointer",
        backgroundColor: color,
        borderColor: color,
        extendedProps: {
          event: event,
        },
      };
    });

    // Remove all previous events from calendar
    calendar.removeAllEvents();

    // Add new events to calendar
    calendar.addEventSource(formattedEvents);
  }
}

// Load current month data
export const loadCurrentMonth = () => {
  if (calendar) {
    calendar.today();
    updateCalendarDate();
    loadNewEvents();
  }
}

// Load next month data
export const loadNextMonth = () => {
  if (calendar) {
    calendar.next();
    updateCalendarDate();
    loadNewEvents();
  }
}

// Load previous month data
export const loadPrevMonth = () => {
  if (calendar) {
    calendar.prev();
    updateCalendarDate();
    loadNewEvents();
  }
}
