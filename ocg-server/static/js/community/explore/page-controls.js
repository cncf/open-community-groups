import {
  cleanInputField,
  closeFiltersDrawer,
  openFiltersDrawer,
  resetDateFiltersOnCalendarViewMode,
  resetFilters,
  searchOnEnter,
  triggerChangeOnForm,
  unckeckAllKinds,
  updateDateInput,
  updateSortInputsFromSelector,
} from "/static/js/community/explore/filters.js";

const EXPLORE_CONTROLS_READY_KEY = "exploreControlsReady";
const DESKTOP_FILTER_FORM_SELECTOR = "#explore-filters .filters-form";
const FILTER_FORM_SELECTOR = ".filters-form";
const SEARCH_INPUT_ID = "ts_query";
const SORT_SELECTOR_ID = "sort_selector";
const SORT_BY_INPUT_ID = "sort_by";
const SORT_DIRECTION_INPUT_ID = "sort_direction";

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
  if (!document.getElementById("calendar-box")) {
    return;
  }

  const module = await import("/static/js/community/explore/calendar.js");
  new module.Calendar();
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
  root.addEventListener("htmx:historyRestore", handleExploreHistoryRestore);
};

initializeExploreControls();
