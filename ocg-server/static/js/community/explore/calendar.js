import { getElementById, loadScriptOnce, setElementHidden } from "/static/js/common/dom.js";
import { navigateWithHtmx } from "/static/js/common/htmx-navigation.js";
import { hideLoadingSpinner, showLoadingSpinner } from "/static/js/common/loading-spinner.js";
import { setTrustedHtml } from "/static/js/common/trusted-html.js";
import {
  getFirstAndLastDayOfMonth,
  hasActiveCalendarFilters,
  updateDateInput,
} from "/static/js/community/explore/filters.js";
import {
  createLatestRequest,
  fetchWidgetData,
  isAbortError,
  reportFetchError,
} from "/static/js/community/explore/results.js";
import {
  bindExploreCardTooltip,
  bindExploreCardTrigger,
  createCardController,
  createExploreCardLoader,
  getExploreItemUrl,
  isPlainLeftClick,
  loadWidgetScripts,
  renderExploreCard,
  syncExploreCardTooltip,
  updateTruncationNotice,
} from "/static/js/community/explore/widgets.js";

const CALENDAR_DATE_ID = "calendar-date";
const CALENDAR_ELEMENT_ID = "calendar-box";
const CALENDAR_STATUS = Object.freeze({
  empty: "empty",
  error: "error",
  idle: "idle",
  loading: "loading",
  ready: "ready",
});
const DATE_TO_INPUT_SELECTOR = 'input[name="date_to"]';
const DEFAULT_NO_RESULTS_SELECTOR = ".no-results-default";
const EVENTS_FORM_ID = "events-form";
const FILTERED_NO_RESULTS_SELECTOR = ".no-results-filtered";
const FULLCALENDAR_SCRIPT_SRC = "/static/vendor/js/fullcalendar.v6.1.21.min.js";
const LOADING_CALENDAR_ID = "loading-calendar";
const MAIN_LOADING_CALENDAR_ID = "main-loading-calendar";
const NO_RESULTS_SELECTOR = ".no-results-default, .no-results-filtered";
const POPOVER_BASE_CLASSES =
  "absolute z-10 invisible inline-block text-sm text-stone-500 transition-opacity duration-300 opacity-0 tooltip-with-arrow";
const POPOVER_BOTTOM_CLASSES = "pt-1.5";
const POPOVER_TOP_CLASSES = "top-0 -translate-y-full pb-1.5";
const RIGHT_ALIGNED_COLUMN_THRESHOLD = 3;
const TOP_ALIGNED_ROW_THRESHOLD = 3;
const TRUNCATION_NOTICE_SELECTOR = "[data-explore-truncation-notice]";
const UPCOMING_COLOR_VARIABLES = {
  background: "--color-primary-50",
  border: "--color-primary-200",
};

/**
 * FullCalendar-backed community explore calendar controller.
 */
export class Calendar {
  /**
   * Initializes the calendar with FullCalendar library.
   * Uses singleton pattern to ensure only one calendar instance exists.
   * @param {object} data - Initial minimal events envelope
   */
  constructor(data) {
    // Reuse the existing controller for a new calendar view
    if (Calendar._instance) {
      Calendar._instance.initialize(data);
      return Calendar._instance;
    }

    this.calendarElement = null;
    this.cardLoader = createExploreCardLoader("events", "calendar");
    this.cards = new globalThis.Map();
    this.fullCalendar = null;
    this.generation = 0;
    this.mountSequence = 0;
    this.releaseCleanupListener = null;
    this.request = createLatestRequest();
    this.state = { status: CALENDAR_STATUS.idle };

    // Save calendar instance
    Calendar._instance = this;
    this.initialize(data);
  }

  /**
   * Adds events to the calendar after formatting them for FullCalendar.
   * @param {Array} events - Array of event objects to add to the calendar
   */
  addEvents(events) {
    const colors = getCalendarColors();
    const formattedEvents = events.map((event) => formatCalendarEvent(event, colors)).filter(Boolean);

    // Replace the previous events
    this.fullCalendar.removeAllEvents();
    this.fullCalendar.addEventSource(formattedEvents);
  }

  /**
   * Navigates to and loads data for the current month.
   */
  currentMonth() {
    if (!this.fullCalendar || document.querySelector(".fc-day-today")) {
      return;
    }

    this.fullCalendar.today();
    this.refresh();
  }

  /**
   * Destroys the calendar and ignores any pending work started before.
   */
  destroy() {
    this.generation += 1;
    this.teardown();
  }

  /**
   * Fetches events for the currently displayed month from the server.
   * @param {AbortSignal} signal - Signal aborting the request
   * @returns {Promise<object>} Minimal events envelope for the current month
   */
  async fetchEvents(signal) {
    // Prepare query params for the displayed month
    const params = new URLSearchParams(location.search);
    params.set("view_mode", "calendar");
    params.delete("date_from");
    params.delete("date_to");
    const date = this.fullCalendar.getDate();
    const { first, last } = getFirstAndLastDayOfMonth(date);
    params.set("date_from", first);
    params.set("date_to", last);

    // Sync the filters and URL with the displayed month
    updateDateInput(date);
    updateCalendarUrl(params);

    return fetchWidgetData("events", params.toString(), { signal });
  }

  /**
   * Loads FullCalendar and sets up the calendar for the current view.
   * @param {object} data - Initial minimal events envelope
   */
  initialize(data) {
    const generation = ++this.generation;
    loadWidgetScripts({
      mainLoadingId: MAIN_LOADING_CALENDAR_ID,
      loadScripts: loadFullCalendarScript,
      onReady: () => {
        if (generation === this.generation) this.setup(data);
      },
    });
  }

  /**
   * Checks whether a request still belongs to the live, mounted calendar.
   * @param {number} requestId - Request id
   * @param {number} generation - Calendar generation when the request started
   * @returns {boolean} Whether the request result can be applied
   */
  isCurrentRequest(requestId, generation) {
    return (
      this.request.isCurrent(requestId) &&
      generation === this.generation &&
      Boolean(this.fullCalendar) &&
      Boolean(this.calendarElement?.isConnected)
    );
  }

  /**
   * Creates the card controller of a mounted event segment.
   * @param {object} info - FullCalendar event mount info
   */
  mountEventCard(info) {
    const trigger = info.el;
    const parent = trigger.parentNode;
    const event = info.event.extendedProps.event;
    if (!parent || !event) return;

    // Give every mounted segment its own tooltip id
    this.mountSequence += 1;
    const alignment = getPopoverAlignment(info);
    const tooltipId = `explore-calendar-card-${event.event_id}-${this.mountSequence}`;
    let releaseTooltip = null;
    let tooltip = null;

    // Render the card in a non-interactive tooltip described by the event
    const controller = createCardController({
      item: event,
      loader: this.cardLoader,
      close: () => {
        releaseTooltip?.();
        releaseTooltip = null;
        tooltip?.remove();
        tooltip = null;
        trigger.removeAttribute("aria-describedby");
      },
      render: (result) => {
        if (!tooltip) {
          tooltip = createTooltipElement(tooltipId, alignment);
          parent.append(tooltip);
          releaseTooltip = bindExploreCardTooltip(tooltip, trigger, controller);
        }
        setTrustedHtml(tooltip, renderExploreCard(result, event.name));
        syncExploreCardTooltip({ result, tooltip, tooltipId, trigger });
        tooltip.setAttribute("data-open", "");
      },
    });
    const releaseTrigger = bindExploreCardTrigger(trigger, controller);
    this.cards.set(trigger, { controller, releaseTrigger });
  }

  /**
   * Navigates to and loads data for the next month.
   */
  nextMonth() {
    if (!this.fullCalendar) return;
    this.fullCalendar.next();
    this.refresh();
  }

  /**
   * Navigates to and loads data for the previous month.
   */
  previousMonth() {
    if (!this.fullCalendar) return;
    this.fullCalendar.prev();
    this.refresh();
  }

  /**
   * Refreshes the calendar title and events, ignoring replaced requests.
   * @param {object} [data] - Optional minimal events envelope instead of a request
   */
  async refresh(data) {
    if (!this.fullCalendar) return;

    // Replace any pending request with this one
    const generation = this.generation;
    const { id: requestId, signal } = this.request.start();

    // Update calendar title
    const titleElement = getElementById(document, CALENDAR_DATE_ID);
    if (titleElement) {
      titleElement.textContent = this.fullCalendar.currentData.viewTitle;
    }

    // Fetch the displayed month unless the data was provided
    let envelope = data;
    if (!envelope) {
      this.setStatus(CALENDAR_STATUS.loading);
      try {
        envelope = await this.fetchEvents(signal);
      } catch (error) {
        if (this.isCurrentRequest(requestId, generation) && !isAbortError(error)) {
          this.setStatus(CALENDAR_STATUS.error);
          reportFetchError(error);
        }
        return;
      }
      if (!this.isCurrentRequest(requestId, generation)) return;
    }

    // Update the truncation notice for the current results
    const events = envelope?.events || [];
    updateTruncationNotice(document.querySelector(TRUNCATION_NOTICE_SELECTOR), {
      shown: events.length,
      total: envelope?.total ?? events.length,
      truncated: Boolean(envelope?.truncated),
    });

    // Toggle placeholder visibility and calendar opacity
    const calendarEl = getElementById(document, CALENDAR_ELEMENT_ID);
    const wrapper = calendarEl ? calendarEl.parentElement : null;
    hideNoResultsPlaceholders(wrapper);
    if (events.length > 0) {
      calendarEl?.classList.remove("opacity-30");
      this.addEvents(events);
      this.setStatus(CALENDAR_STATUS.ready);
    } else {
      calendarEl?.classList.add("opacity-30");
      this.addEvents([]);
      showNoResultsPlaceholder(wrapper, this.fullCalendar);
      this.setStatus(CALENDAR_STATUS.empty);
    }
  }

  /**
   * Stores the current calendar status and syncs the blocking loading affordance.
   * @param {string} status - Calendar status
   */
  setStatus(status) {
    this.state = { status };
    if (status === CALENDAR_STATUS.loading) {
      showLoadingSpinner(LOADING_CALENDAR_ID);
    } else {
      hideLoadingSpinner(LOADING_CALENDAR_ID);
    }
  }

  /**
   * Sets up the FullCalendar instance with configuration and event handlers.
   * @param {object} data - Initial minimal events envelope
   */
  setup(data) {
    // Replace any previous calendar instance
    this.teardown();
    const calendarEl = getElementById(document, CALENDAR_ELEMENT_ID);
    if (!calendarEl) return;
    this.calendarElement = calendarEl;

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
      initialDate: getInitialCalendarDate(),

      // Navigate with HTMX on plain clicks and leave other clicks to the browser
      eventClick: (info) => {
        const url = info.event.url;
        if (!url || !isPlainLeftClick(info.jsEvent)) return;
        info.jsEvent.preventDefault();
        navigateWithHtmx(url);
      },

      // Attach a card to every mounted event segment
      eventDidMount: (info) => this.mountEventCard(info),

      // Release the card of an unmounted event segment
      eventWillUnmount: (info) => this.unmountEventCard(info),
    });

    // Destroy the calendar when HTMX removes its container
    const handleCleanup = (event) => {
      if (event.target === calendarEl) this.destroy();
    };
    calendarEl.addEventListener("htmx:beforeCleanupElement", handleCleanup);
    this.releaseCleanupListener = () =>
      calendarEl.removeEventListener("htmx:beforeCleanupElement", handleCleanup);

    // Refresh calendar with initial data and render it
    this.refresh(data);
    this.fullCalendar.render();
  }

  /**
   * Releases the calendar instance, pending requests, cards, and listeners.
   */
  teardown() {
    this.request.cancel();
    this.cards.forEach((card) => {
      card.controller.destroy();
      card.releaseTrigger();
    });
    this.cards.clear();
    this.releaseCleanupListener?.();
    this.releaseCleanupListener = null;
    this.fullCalendar?.destroy();
    this.fullCalendar = null;
    this.calendarElement = null;
    hideLoadingSpinner(LOADING_CALENDAR_ID);
  }

  /**
   * Releases the card controller of an unmounted event segment.
   * @param {object} info - FullCalendar event unmount info
   */
  unmountEventCard(info) {
    const card = this.cards.get(info.el);
    if (!card) return;
    card.controller.destroy();
    card.releaseTrigger();
    this.cards.delete(info.el);
  }
}

/**
 * Creates the tooltip element holding an event card.
 * @param {string} id - Tooltip element id
 * @param {object} alignment - Tooltip alignment
 * @param {string} alignment.horizontal - Horizontal alignment ('left' or 'right')
 * @param {string} alignment.vertical - Vertical alignment ('top' or 'bottom')
 * @returns {HTMLDivElement} Tooltip element
 */
const createTooltipElement = (id, { horizontal, vertical }) => {
  const tooltip = document.createElement("div");
  tooltip.id = id;
  tooltip.setAttribute("role", "tooltip");
  tooltip.setAttribute("data-popover", "true");
  tooltip.className = [
    POPOVER_BASE_CLASSES,
    horizontal === "right" ? "end-0" : "",
    vertical === "top" ? POPOVER_TOP_CLASSES : POPOVER_BOTTOM_CLASSES,
  ]
    .filter(Boolean)
    .join(" ");
  return tooltip;
};

/**
 * Formats one event for FullCalendar.
 * @param {object} event - Minimal explore event
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

  return {
    title: event.name,
    start: startDate.toISOString(),
    end: endDate.toISOString(),
    url: getExploreItemUrl("events", event),
    className: `cursor-pointer ${isPast ? "opacity-40" : ""}`,
    // Past events keep the default colors, dimmed by their opacity
    ...(isPast ? {} : { backgroundColor: colors.upcomingBg, borderColor: colors.upcomingBorder }),
    extendedProps: {
      event,
    },
  };
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
 * Reads the initially selected calendar date from the hidden date input.
 * @returns {Date} Initial calendar date
 */
const getInitialCalendarDate = () => {
  const dateToInput = document.querySelector(DATE_TO_INPUT_SELECTOR);
  return dateToInput ? new Date(dateToInput.value) : new Date();
};

/**
 * Builds tooltip alignment data from the FullCalendar segment.
 * @param {object} info - FullCalendar event mount info
 * @returns {object} Tooltip alignment data
 */
const getPopoverAlignment = (info) => ({
  horizontal: (info.el.fcSeg?.firstCol ?? 0) > RIGHT_ALIGNED_COLUMN_THRESHOLD ? "right" : "left",
  vertical: (info.el.fcSeg?.row ?? 0) >= TOP_ALIGNED_ROW_THRESHOLD ? "top" : "bottom",
});

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
 * Loads the FullCalendar script when needed.
 * @returns {Promise<void>} Promise resolved when FullCalendar is available
 */
const loadFullCalendarScript = () =>
  loadScriptOnce(FULLCALENDAR_SCRIPT_SRC, {
    isLoaded: () => typeof window.FullCalendar !== "undefined",
  });

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
 * Updates the browser URL to reflect the current calendar filters.
 * @param {URLSearchParams} params - Query params to write to the URL
 */
const updateCalendarUrl = (params) => {
  const nextUrl = new URL(window.location.href);
  nextUrl.search = params.toString();
  window.history.replaceState({}, "", nextUrl);
};
