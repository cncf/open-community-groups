import {
  cleanInputField,
  closeFiltersDrawer,
  hasActiveCalendarFilters,
  hasActiveFilters,
  openFiltersDrawer,
  resetDateFiltersOnCalendarViewMode,
  resetFilters,
  searchOnEnter,
  triggerChangeOnForm,
  unckeckAllKinds,
  updateDateInput,
  updateSortInputsFromSelector,
} from "/static/js/community/explore/filters.js";
import { getElementById } from "/static/js/common/dom.js";

const EXPLORE_CONTROLS_READY_KEY = "exploreControlsReady";
const DESKTOP_FILTER_FORM_SELECTOR = "#explore-filters .filters-form";
const FILTER_FORM_SELECTOR = ".filters-form";
const SEARCH_INPUT_ID = "ts_query";
const SORT_SELECTOR_ID = "sort_selector";
const SORT_BY_INPUT_ID = "sort_by";
const SORT_DIRECTION_INPUT_ID = "sort_direction";
const CALENDAR_BOX_ID = "calendar-box";
const NO_RESULTS_DEFAULT_SELECTOR = ".no-results-default";
const NO_RESULTS_FILTERED_SELECTOR = ".no-results-filtered";
const CALENDAR_DATA_SELECTOR = "[data-explore-calendar-data]";
const MAP_DATA_SELECTOR = "[data-explore-map-data]";
const EXPLORE_WIDGET_READY_KEY = "exploreWidgetReady";
const CURRENT_MONTH_BUTTON_ID = "current-month-btn";
const PREV_MONTH_BUTTON_ID = "prev-month-btn";
const NEXT_MONTH_BUTTON_ID = "next-month-btn";

/**
 * Gets the active desktop explore form id.
 * @returns {string|undefined} Explore form id when present
 */
const getExploreFormId = () => {
  const desktopForm = document.querySelector(DESKTOP_FILTER_FORM_SELECTOR);
  const fallbackForm = document.querySelector(FILTER_FORM_SELECTOR);
  return (desktopForm || fallbackForm)?.id;
};

/**
 * Parses JSON data from an inert explore payload marker.
 * @param {HTMLScriptElement} marker - Script marker containing JSON data
 * @returns {object|null} Parsed payload when valid
 */
const readExplorePayload = (marker) => {
  try {
    return JSON.parse(marker.textContent || "{}");
  } catch (error) {
    console.error("Failed to parse explore payload", error);
    return null;
  }
};

/**
 * Binds a calendar navigation button to the active calendar instance.
 * @param {Document|Element} root - Root element containing the calendar controls
 * @param {string} id - Button id
 * @param {Function} callback - Calendar action called on click
 */
const bindCalendarButton = (root, id, callback) => {
  const button = getElementById(root, id);
  if (!button || button.dataset[EXPLORE_WIDGET_READY_KEY] === "true") {
    return;
  }

  button.dataset[EXPLORE_WIDGET_READY_KEY] = "true";
  button.addEventListener("click", () => {
    callback();
    button.blur();
  });
};

/**
 * Binds calendar navigation controls for a calendar instance.
 * @param {Document|Element} root - Root element containing the calendar controls
 * @param {object} calendar - Calendar instance
 */
const bindCalendarControls = (root, calendar) => {
  bindCalendarButton(root, CURRENT_MONTH_BUTTON_ID, () => calendar.currentMonth());
  bindCalendarButton(root, PREV_MONTH_BUTTON_ID, () => calendar.previousMonth());
  bindCalendarButton(root, NEXT_MONTH_BUTTON_ID, () => calendar.nextMonth());
};

/**
 * Syncs the no-results placeholders with the current filter state.
 * @param {Document|Element} root - Root element containing the swapped results
 */
export const syncNoResultsPlaceholders = (root = document) => {
  const defaultPlaceholders = root.querySelectorAll(NO_RESULTS_DEFAULT_SELECTOR);
  const filteredPlaceholders = root.querySelectorAll(NO_RESULTS_FILTERED_SELECTOR);
  if (defaultPlaceholders.length === 0 && filteredPlaceholders.length === 0) {
    return;
  }

  const formId = getExploreFormId();
  if (!formId) {
    return;
  }

  const hasCalendar = Boolean(getElementById(document, CALENDAR_BOX_ID));
  const filtered = hasCalendar ? hasActiveCalendarFilters(formId) : hasActiveFilters(formId);

  defaultPlaceholders.forEach((placeholder) => {
    placeholder.classList.toggle("hidden", filtered);
  });
  filteredPlaceholders.forEach((placeholder) => {
    placeholder.classList.toggle("hidden", !filtered);
  });
};

/**
 * Initializes explore calendar and map widgets from declarative payload markers.
 * @param {Document|Element} root - Root element containing widget markers
 */
export const initializeExploreWidgets = async (root = document) => {
  const calendarMarker = root.querySelector(CALENDAR_DATA_SELECTOR);
  if (calendarMarker && calendarMarker.dataset[EXPLORE_WIDGET_READY_KEY] !== "true") {
    const data = readExplorePayload(calendarMarker);
    if (data) {
      calendarMarker.dataset[EXPLORE_WIDGET_READY_KEY] = "true";
      const module = await import("/static/js/community/explore/calendar.js");
      const calendar = new module.Calendar(data);
      bindCalendarControls(root, calendar);
    }
  }

  const mapMarker = root.querySelector(MAP_DATA_SELECTOR);
  if (mapMarker && mapMarker.dataset[EXPLORE_WIDGET_READY_KEY] !== "true") {
    const data = readExplorePayload(mapMarker);
    const entity = mapMarker.dataset.entity;
    if (data && entity) {
      mapMarker.dataset[EXPLORE_WIDGET_READY_KEY] = "true";
      const module = await import("/static/js/community/explore/map.js");
      new module.Map(entity, data);
    }
  }
};

/**
 * Handles click interactions for explore controls.
 * @param {MouseEvent} event - Click event
 */
const handleExploreClick = (event) => {
  const target = event.target;
  if (!(target instanceof Element)) {
    return;
  }

  if (target.closest("#open-filters")) {
    event.preventDefault();
    openFiltersDrawer();
    return;
  }

  if (target.closest("#close-filters") || target.closest("#drawer-backdrop")) {
    event.preventDefault();
    closeFiltersDrawer();
    return;
  }

  const formId = getExploreFormId();
  if (!formId) {
    return;
  }

  if (target.closest("#search-btn")) {
    event.preventDefault();
    triggerChangeOnForm(formId, true);
    return;
  }

  if (target.closest("#clean-search")) {
    event.preventDefault();
    cleanInputField(SEARCH_INPUT_ID, formId);
    return;
  }

  if (target.closest(".reset-filters")) {
    event.preventDefault();
    resetFilters(formId);
  }
};

/**
 * Handles keyboard interactions for explore controls.
 * @param {KeyboardEvent} event - Keydown event
 */
const handleExploreKeydown = (event) => {
  if (!(event.target instanceof Element) || event.target.id !== SEARCH_INPUT_ID) {
    return;
  }

  const formId = getExploreFormId();
  if (formId) {
    searchOnEnter(event, formId);
  }
};

/**
 * Handles changed explore form controls.
 * @param {Event} event - Change event
 */
const handleExploreChange = (event) => {
  const target = event.target;
  if (!(target instanceof HTMLInputElement || target instanceof HTMLSelectElement)) {
    return;
  }

  const formId = getExploreFormId();
  if (!formId) {
    return;
  }

  if (target.matches('input[name="view_mode"]')) {
    if (target.value === "calendar") {
      updateDateInput();
    } else {
      resetDateFiltersOnCalendarViewMode();
    }
    unckeckAllKinds();
    triggerChangeOnForm(formId);
    return;
  }

  if (target.id === SORT_SELECTOR_ID) {
    updateSortInputsFromSelector(target, SORT_BY_INPUT_ID, SORT_DIRECTION_INPUT_ID);
    triggerChangeOnForm(formId);
  }
};

/**
 * Re-initializes dynamic widgets restored from HTMX history cache.
 */
const handleExploreHistoryRestore = async () => {
  await initializeExploreWidgets();
};

/**
 * Syncs explore controls after HTMX swaps.
 * @param {CustomEvent} event - HTMX swap event
 */
const handleExploreAfterSwap = (event) => {
  if (event.target instanceof Element) {
    syncNoResultsPlaceholders(event.target);
    initializeExploreWidgets(event.target);
  }
};

/**
 * Initializes delegated explore page controls.
 * @param {Document} root - Document root used for event binding
 */
export const initializeExploreControls = (root = document) => {
  if (root.documentElement.dataset[EXPLORE_CONTROLS_READY_KEY] === "true") {
    return;
  }

  root.documentElement.dataset[EXPLORE_CONTROLS_READY_KEY] = "true";
  root.addEventListener("click", handleExploreClick);
  root.addEventListener("keydown", handleExploreKeydown);
  root.addEventListener("change", handleExploreChange);
  root.addEventListener("htmx:afterSwap", handleExploreAfterSwap);
  root.addEventListener("htmx:historyRestore", handleExploreHistoryRestore);
  syncNoResultsPlaceholders(root);
  initializeExploreWidgets(root);
};

initializeExploreControls();
