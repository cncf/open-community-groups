import {
  cleanInputField,
  closeFiltersDrawer,
  FILTER_CHANGE_EVENT,
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
import {
  closestElement,
  getElementById,
  isDatasetReady,
  markDatasetReady,
  setElementHidden,
} from "/static/js/common/dom.js";
import { ocgFetch } from "/static/js/common/fetch.js";
import { isEscapeEvent } from "/static/js/common/keyboard.js";
import {
  bindModalDismissListeners,
  focusModal,
  lockBodyScroll,
  restoreModalFocus,
  trapModalFocus,
  unlockBodyScroll,
} from "/static/js/common/modals/modal-lifecycle.js";
import { bindSheetGestures } from "/static/js/common/modals/sheet-gestures.js";
import { isPhoneViewport, PHONE_MEDIA_QUERY } from "/static/js/common/phone-viewport.js";
import { parseJsonText } from "/static/js/common/utils.js";
import {
  createLatestRequest,
  ExploreFetchError,
  isAbortError,
  reportFetchError,
} from "/static/js/community/explore/results.js";

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
const CALENDAR_MODULE_PATH = "/static/js/community/explore/calendar.js";
const APPLIED_FILTER_SELECTOR = "[data-applied-filter]";
const APPLIED_FILTERS_CARD_SELECTOR = "[data-applied-filters]";
const APPLIED_FILTERS_ID = "applied-filters";
const APPLIED_FILTERS_TOGGLE_LABEL_SELECTOR = "[data-applied-filters-toggle-label]";
const APPLIED_FILTERS_TOGGLE_SELECTOR = "[data-applied-filters-toggle]";
const APPLY_FILTERS_SELECTOR = "[data-apply-filters]";
const CARDS_LIST_ID = "cards-list";
const CLOSE_FILTERS_ID = "close-filters";
const COMMUNITY_FILTER_SELECTOR = 'collapsible-filter[name="community"]';
const DRAWER_FILTERS_ID = "drawer-filters";
const ENTITY_SECTION_ID = "entity-section";
const ENTITY_SWITCH_PRESSED_SELECTOR = '[role="group"][aria-label="Show"] [aria-pressed="true"]';
const ENTITY_SWITCH_REQUEST_SELECTOR = '[role="group"][aria-label="Show"] button[hx-get]';
const FILTER_SECTION_SYNC = "closest #entity-section:replace";
const FILTER_STATUS_ID = "explore-filter-status";
const OPEN_FILTERS_ID = "open-filters";
const RESULTS_EMPTY_SELECTOR = "[data-results-empty]";
const RESULTS_ID = "results";
const SEARCH_KEY_HINT = "search";

// Whether the phone Active filters card shows every chip. Kept across swaps, so removing a chip
// from the expanded card leaves the rest in view.
let appliedFiltersExpanded = false;

// Calendar module, once a calendar view has loaded it.
let calendarModule = null;

// Phone filter sheet held open, or null. Teardown keys on this, never on the viewport width.
let filterSheet = null;

// Focus to place once the next section swap settles.
let settleFocus = null;

// Drawers holding choices the results do not reflect yet. A swap replaces the drawer, so
// entries clear themselves.
const pendingDrawers = new WeakSet();

// Filters a refresh took out of the sheet's form, kept for the history snapshot. A swap replaces
// the form, so entries clear themselves.
const appliedFilterNodes = new WeakMap();

// Chip removals waiting for their swap, or null. Tapped chips are tracked here and not `disabled`:
// the history snapshot taken before the swap would keep it, and Back would restore a dead chip.
let chipRemoval = null;

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
  return parseJsonText(marker.textContent || "{}", null, (error) => {
    console.error("Failed to parse explore payload", error);
  });
};

/**
 * Binds a calendar navigation button to the active calendar instance.
 * @param {Document|Element} root - Root element containing the calendar controls
 * @param {string} id - Button id
 * @param {Function} callback - Calendar action called on click
 * @param {Object} options - Binding options
 * @param {boolean} options.force - Whether to bind even when the DOM was marked ready
 */
const bindCalendarButton = (root, id, callback, { force = false } = {}) => {
  const button = getElementById(root, id);
  if (!button) {
    return;
  }

  if (!force && !markDatasetReady(button, EXPLORE_WIDGET_READY_KEY)) {
    return;
  }

  if (force) {
    markDatasetReady(button, EXPLORE_WIDGET_READY_KEY);
  }

  button.addEventListener("click", () => {
    callback();
    button.blur();
  });
};

/**
 * Binds calendar navigation controls for a calendar instance.
 * @param {Document|Element} root - Root element containing the calendar controls
 * @param {object} calendar - Calendar instance
 * @param {Object} options - Binding options
 * @param {boolean} options.force - Whether to bind even when the DOM was marked ready
 */
const bindCalendarControls = (root, calendar, options = {}) => {
  bindCalendarButton(root, CURRENT_MONTH_BUTTON_ID, () => calendar.currentMonth(), options);
  bindCalendarButton(root, PREV_MONTH_BUTTON_ID, () => calendar.previousMonth(), options);
  bindCalendarButton(root, NEXT_MONTH_BUTTON_ID, () => calendar.nextMonth(), options);
};

/**
 * Handles click interactions for explore controls.
 * @param {MouseEvent} event - Click event
 */
const handleExploreClick = (event) => {
  const openFiltersButton = closestElement(event.target, "#open-filters");
  if (openFiltersButton) {
    event.preventDefault();
    if (isPhoneViewport()) {
      openFilterSheet(openFiltersButton);
    } else {
      openFiltersDrawer();
    }
    return;
  }

  const applyFiltersButton = closestElement(event.target, APPLY_FILTERS_SELECTOR);
  if (
    applyFiltersButton ||
    closestElement(event.target, "#close-filters") ||
    closestElement(event.target, "#drawer-backdrop")
  ) {
    event.preventDefault();
    if (filterSheet) {
      closeFilterSheet({ retry: Boolean(applyFiltersButton) });
    } else {
      closeFiltersDrawer();
    }
    return;
  }

  if (closestElement(event.target, APPLIED_FILTERS_TOGGLE_SELECTOR)) {
    event.preventDefault();
    appliedFiltersExpanded = !appliedFiltersExpanded;
    fitAppliedFilters();
    return;
  }

  const entitySwitch = closestElement(event.target, ENTITY_SWITCH_REQUEST_SELECTOR);
  if (entitySwitch && isPhoneViewport()) {
    settleFocus = { switchLabel: entitySwitch.textContent.trim() };
    document.addEventListener("htmx:responseError", handleEntitySwitchRequestEnd);
    document.addEventListener("htmx:sendAbort", handleEntitySwitchRequestEnd);
    document.addEventListener("htmx:sendError", handleEntitySwitchRequestEnd);
    return;
  }

  const formId = getExploreFormId();
  if (!formId) {
    return;
  }

  if (closestElement(event.target, "#search-btn")) {
    event.preventDefault();
    triggerChangeOnForm(formId, true);
    return;
  }

  if (closestElement(event.target, "#clean-search")) {
    event.preventDefault();
    cleanInputField(SEARCH_INPUT_ID, formId);
    return;
  }

  const resetButton = closestElement(event.target, ".reset-filters");
  if (resetButton) {
    event.preventDefault();
    // Reset leaves with the card it sits in.
    if (isPhoneViewport() && closestElement(resetButton, APPLIED_FILTERS_CARD_SELECTOR)) {
      settleFocus = { reset: true };
    }
    resetFilters(formId);
    return;
  }

  const appliedFilter = closestElement(event.target, APPLIED_FILTER_SELECTOR);
  if (appliedFilter) {
    event.preventDefault();
    removeAppliedFilter(appliedFilter, formId);
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
      resetDateFiltersOnCalendarViewMode(formId);
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
 * Handles custom filter component changes.
 * @param {CustomEvent} event - Filter change event
 */
const handleFilterChange = (event) => {
  const form = closestElement(event.target, FILTER_FORM_SELECTOR);
  if (form?.id) {
    triggerChangeOnForm(form.id);
    if (filterSheet?.drawer.contains(form) && event.target.matches(COMMUNITY_FILTER_SELECTOR)) {
      refreshFilterSheetForm(form);
    }
  }
};

/**
 * Re-initializes dynamic widgets restored from HTMX history cache. No settle follows a restore,
 * and the snapshot may come from the other side of the phone query.
 */
const handleExploreHistoryRestore = async () => {
  if (isPhoneViewport()) {
    resetFilterSheet();
    releaseChipRemoval();
    releaseEntitySwitchPress();
    if (applyPhoneViewMode()) {
      return;
    }
    setPhoneAttributes();
  } else {
    removePhoneAttributes();
  }
  await initializeExploreWidgets(document, { force: true });
};

/**
 * Syncs explore controls after HTMX swaps.
 * @param {CustomEvent} event - HTMX swap event
 */
const handleExploreAfterSwap = (event) => {
  if (event.target instanceof Element) {
    destroyDetachedCalendar();
    if (applyPhoneViewMode()) {
      return;
    }
    syncNoResultsPlaceholders(event.target);
    initializeExploreWidgets(event.target);
  }
};

/**
 * Destroys the calendar once its view is no longer in the document.
 */
const destroyDetachedCalendar = () => {
  if (!calendarModule || document.querySelector(CALENDAR_DATA_SELECTOR)) {
    return;
  }
  calendarModule.Calendar._instance?.destroy();
};

/**
 * Builds the list view URL phones land on from a calendar or map URL.
 * @param {string} href - Current URL
 * @param {boolean} isCalendar - Whether the current view is the calendar
 * @returns {string} URL without the view mode, nor the month range the calendar sets
 */
export const getPhoneListUrl = (href, isCalendar) => {
  const url = new URL(href);
  url.searchParams.delete("view_mode");
  if (isCalendar) {
    url.searchParams.delete("date_from");
    url.searchParams.delete("date_to");
  }
  return url.toString();
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

  if (getElementById(root, CALENDAR_BOX_ID)) {
    return;
  }

  const formId = getExploreFormId();
  if (!formId) {
    return;
  }

  const filtered = hasActiveFilters(formId);

  defaultPlaceholders.forEach((placeholder) => {
    setElementHidden(placeholder, filtered);
  });
  filteredPlaceholders.forEach((placeholder) => {
    setElementHidden(placeholder, !filtered);
  });
};

/**
 * Initializes explore calendar and map widgets from declarative payload markers.
 * @param {Document|Element} root - Root element containing widget markers
 * @param {Object} options - Initialization options
 * @param {boolean} options.force - Whether to initialize widgets marked ready
 */
export const initializeExploreWidgets = async (root = document, { force = false } = {}) => {
  const calendarMarker = root.querySelector(CALENDAR_DATA_SELECTOR);
  if (calendarMarker && (force || !isDatasetReady(calendarMarker, EXPLORE_WIDGET_READY_KEY))) {
    const data = readExplorePayload(calendarMarker);
    if (data) {
      markDatasetReady(calendarMarker, EXPLORE_WIDGET_READY_KEY);
      calendarModule = await import(CALENDAR_MODULE_PATH);
      const calendar = new calendarModule.Calendar(data);
      bindCalendarControls(root, calendar, { force });
    }
  }

  const mapMarker = root.querySelector(MAP_DATA_SELECTOR);
  if (mapMarker && (force || !isDatasetReady(mapMarker, EXPLORE_WIDGET_READY_KEY))) {
    const data = readExplorePayload(mapMarker);
    const entity = mapMarker.dataset.entity;
    if (data && entity) {
      markDatasetReady(mapMarker, EXPLORE_WIDGET_READY_KEY);
      const module = await import("/static/js/community/explore/map.js");
      new module.Map(entity, data);
    }
  }
};

/**
 * Initializes delegated explore page controls.
 * @param {Document} root - Document root used for event binding
 */
const initializeExploreControls = (root = document) => {
  if (!markDatasetReady(root.documentElement, EXPLORE_CONTROLS_READY_KEY)) {
    return;
  }

  root.addEventListener("click", handleExploreClick);
  root.addEventListener("keydown", handleExploreKeydown);
  root.addEventListener("change", handleExploreChange);
  root.addEventListener(FILTER_CHANGE_EVENT, handleFilterChange);
  root.addEventListener("htmx:afterSwap", handleExploreAfterSwap);
  root.addEventListener("htmx:historyRestore", handleExploreHistoryRestore);
  initializePhoneControls();
  if (applyPhoneViewMode()) {
    return;
  }
  syncNoResultsPlaceholders(root);
  initializeExploreWidgets(root);
};

/**
 * Sends the pending choices of the filter sheet in one request.
 */
const applyFilterSheet = () => {
  const { drawer, refreshRequest } = filterSheet;
  const form = drawer.querySelector(FILTER_FORM_SELECTOR);

  filterSheet.applying = true;
  refreshRequest.cancel();
  setFilterSheetBusy(drawer, false);
  setApplyFiltersDisabled(drawer, true);
  document.removeEventListener("htmx:confirm", handleFilterSheetConfirm);
  triggerChangeOnForm(form.id);
};

/**
 * Leaves the calendar or map on phones, which show the list only.
 * @returns {boolean} Whether the page is being replaced
 */
const applyPhoneViewMode = () => {
  if (!isPhoneViewport()) {
    return false;
  }

  const isCalendar = Boolean(document.querySelector(CALENDAR_DATA_SELECTOR));
  if (!isCalendar && !document.querySelector(MAP_DATA_SELECTOR)) {
    return false;
  }

  window.location.replace(getPhoneListUrl(window.location.href, isCalendar));
  return true;
};

/**
 * Announces a filter change in the status region, followed by the results count.
 * @param {string} message - Change to announce
 */
const announceFilterChange = (message) => {
  const status = getElementById(document, FILTER_STATUS_ID);
  if (!status) {
    return;
  }

  const results = document.querySelector(RESULTS_EMPTY_SELECTOR) ?? getElementById(document, RESULTS_ID);
  const count = results?.textContent.trim() ?? "";
  status.textContent = `${message} ${count}`.trim();
};

/**
 * Reads the filter values of a form, to put them back if a removal fails.
 * @param {HTMLFormElement} form - Form holding the applied state
 * @returns {Function} Puts the values back
 */
const captureFilterValues = (form) => {
  const filters = [...form.querySelectorAll("collapsible-filter, multi-select-filter")].map((filter) => [
    filter,
    filter.selected,
  ]);
  const inputs = [...form.querySelectorAll("input[type=checkbox], input[type=radio]")].map((input) => [
    input,
    input.checked,
  ]);

  return () => {
    filters.forEach(([filter, selected]) => {
      filter.selected = selected;
    });
    inputs.forEach(([input, checked]) => {
      input.checked = checked;
    });
  };
};

/**
 * Closes the phone filter sheet, applying pending choices first. The sheet then stays open
 * until the swap replaces it, so a failed request keeps the choices on screen.
 * @param {object} [options] - Close options
 * @param {boolean} [options.retry=false] - Whether to apply again after a failed request
 */
const closeFilterSheet = ({ retry = false } = {}) => {
  if (!filterSheet || filterSheet.applying) {
    return;
  }

  const { drawer, failed } = filterSheet;
  if (pendingDrawers.has(drawer) && (retry || !failed)) {
    applyFilterSheet();
    return;
  }

  releaseFilterSheet();
  settleFocus = null;
  restoreModalFocus(drawer);
};

/**
 * Fits the Active filters chips on one line, followed by a toggle that shows the rest. A chip that
 * does not fit is hidden, and a shorter one after it may still take the space left.
 */
const fitAppliedFilters = () => {
  const group = getElementById(document, APPLIED_FILTERS_ID);
  const toggle = document.querySelector(APPLIED_FILTERS_TOGGLE_SELECTOR);
  const label = toggle?.querySelector(APPLIED_FILTERS_TOGGLE_LABEL_SELECTOR);
  if (!group || !label) {
    appliedFiltersExpanded = false;
    return;
  }

  const chips = [...group.querySelectorAll(APPLIED_FILTER_SELECTOR)];
  chips.forEach((chip) => {
    chip.hidden = false;
  });
  toggle.setAttribute("aria-expanded", String(appliedFiltersExpanded));

  // Measured on a wrapping row, where no chip gives up width to the toggle. The toggle keeps its
  // box meanwhile, so it keeps focus too. Widths keep their fractions, and a pixel is spared so
  // rounding never wraps a chip the sum says fits.
  const row = toggle.parentElement;
  const rowStyle = getComputedStyle(row);
  row.style.flexWrap = "wrap";
  group.style.flexWrap = "wrap";
  const width =
    row.getBoundingClientRect().width -
    parseFloat(rowStyle.paddingLeft) -
    parseFloat(rowStyle.paddingRight) -
    1;
  const chipGap = parseFloat(getComputedStyle(group).columnGap) || 0;
  const chipWidths = chips.map((chip) => chip.getBoundingClientRect().width);
  row.style.removeProperty("flex-wrap");
  group.style.removeProperty("flex-wrap");

  const chipsWidth = chipWidths.reduce((sum, chipWidth) => sum + chipWidth + chipGap, -chipGap);
  toggle.hidden = chips.length === 0 || width <= 0 || chipsWidth <= width;
  if (toggle.hidden) {
    return;
  }

  if (appliedFiltersExpanded) {
    label.textContent = "Show less";
    return;
  }

  // The widest label the toggle can show, so the chips kept never push it to a new line.
  label.textContent = `+${chips.length} more`;
  const available = width - toggle.getBoundingClientRect().width - (parseFloat(rowStyle.columnGap) || 0);
  let used = 0;
  chips.forEach((chip, index) => {
    const needed = used + (used > 0 ? chipGap : 0) + chipWidths[index];
    if (needed <= available) {
      used = needed;
    } else {
      chip.hidden = true;
    }
  });

  // A chip wider than the space left still shows, truncated.
  if (used === 0) {
    chips[0].hidden = false;
  }
  label.textContent = `+${chips.filter((chip) => chip.hidden).length} more`;
};

/**
 * Finds the real control behind an applied filter chip.
 * @param {HTMLFormElement} form - Form holding the applied state
 * @param {HTMLElement} chip - Chip button
 * @returns {HTMLElement|undefined} Control that removes the filter when clicked
 */
const getAppliedFilterControl = (form, chip) => {
  const { appliedFilter: name, appliedFilterValue: value } = chip.dataset;
  const input = [...form.querySelectorAll(`input[name="${name}[]"]`)].find((item) => item.value === value);
  if (input?.type !== "hidden") {
    return input;
  }

  // Multi-select values live in hidden inputs: their chip owns the remove button.
  const removeLabel = `Remove ${chip.textContent.trim()}`;
  return [...input.closest("multi-select-filter").querySelectorAll("button")].find(
    (button) => button.getAttribute("aria-label") === removeLabel,
  );
};

/**
 * Builds the query of the sheet's form, without empty values.
 * @param {HTMLFormElement} form - Filter form
 * @returns {string} Encoded query
 */
const getFilterFormQuery = (form) => {
  const params = new URLSearchParams();
  new FormData(form).forEach((value, name) => {
    if (value !== "") {
      params.append(name, value);
    }
  });
  return params.toString();
};

/**
 * Recovers from a failed chip removal: the form returns to the applied state, so the chip works
 * again and the next request cannot carry the removal. An open sheet reports the failure itself.
 * @param {CustomEvent} event - HTMX error event
 */
const handleChipRemovalError = (event) => {
  if (!closestElement(event.target, FILTER_FORM_SELECTOR)) {
    return;
  }

  const { restoreFilterValues } = chipRemoval;
  releaseChipRemoval();
  settleFocus = null;
  restoreFilterValues();
  if (!filterSheet) {
    reportFetchError({});
  }
};

/**
 * Ends a switch press whose request will not swap, reporting a failure. The page stays on the side
 * it shows, focus stays on the pressed button, and an open sheet reports the failure itself.
 * @param {CustomEvent} event - HTMX error or abort event
 */
const handleEntitySwitchRequestEnd = (event) => {
  if (!closestElement(event.target, ENTITY_SWITCH_REQUEST_SELECTOR)) {
    return;
  }

  releaseEntitySwitchPress();
  if (event.type !== "htmx:sendAbort" && !filterSheet) {
    reportFetchError({});
  }
};

/**
 * Holds back the requests of the open filter sheet until its choices are applied.
 * @param {CustomEvent} event - HTMX confirm event
 */
const handleFilterSheetConfirm = (event) => {
  if (!filterSheet?.drawer.contains(event.target)) {
    return;
  }

  event.preventDefault();
  pendingDrawers.add(filterSheet.drawer);
  filterSheet.failed = false;

  // A refresh in flight left this choice out, and its markup would drop it.
  if (event.target.getAttribute("aria-busy") === "true") {
    refreshFilterSheetForm(event.target);
  }
};

/**
 * Reports a failed section request. The sheet stays open and keeps its choices.
 * @param {CustomEvent} event - HTMX error event
 */
const handleFilterSheetError = (event) => {
  if (!filterSheet || !closestElement(event.target, `#${ENTITY_SECTION_ID}`)) {
    return;
  }

  reportFetchError({});
  if (!filterSheet.applying) {
    return;
  }

  const { drawer, unbindGestures } = filterSheet;
  settleFocus = null;
  filterSheet.applying = false;
  filterSheet.failed = true;
  setApplyFiltersDisabled(drawer, false);
  document.addEventListener("htmx:confirm", handleFilterSheetConfirm);

  // A close request uses up the watcher, so Back needs a new one.
  unbindGestures();
  filterSheet.unbindGestures = bindSheetGestures(drawer);
};

/**
 * Handles Escape and Tab in the open filter sheet. A nested control handles Escape first,
 * and an alert above the sheet owns the keyboard.
 * @param {KeyboardEvent} event - Keydown event
 */
const handleFilterSheetKeydown = (event) => {
  if (event.defaultPrevented || !filterSheet || globalThis.Swal?.isVisible?.()) {
    return;
  }

  if (isEscapeEvent(event)) {
    event.preventDefault();
    closeFilterSheet();
    return;
  }

  trapModalFocus(event, filterSheet.drawer);
};

/**
 * Resets the filter sheet when the browser restores the page from its back-forward cache.
 * @param {PageTransitionEvent} event - Page show event
 */
const handleFilterSheetPageShow = (event) => {
  if (event.persisted) {
    resetFilterSheet();
  }
};

/**
 * Syncs phone state after a swap: paging lands below the results bar, and the attributes and
 * focus of a replaced section come back.
 * @param {CustomEvent} event - HTMX after settle event
 */
const handlePhoneAfterSettle = (event) => {
  const target = event.target;
  if (!(target instanceof Element)) {
    return;
  }

  if (target.id === CARDS_LIST_ID) {
    // After the swap's own show:#header:top, which htmx applies once this event returns.
    requestAnimationFrame(() => target.scrollIntoView());
    return;
  }

  if (target === document.body || target.id === ENTITY_SECTION_ID) {
    if (filterSheet && !filterSheet.drawer.isConnected) {
      releaseFilterSheet();
    }
    releaseChipRemoval();
    setPhoneAttributes();
    placeSettleFocus();
    releaseEntitySwitchPress();
  }
};

/**
 * Follows the phone query. Leaving it closes the sheet and removes every phone write.
 * @param {MediaQueryListEvent} event - Query change event
 */
const handlePhoneQueryChange = (event) => {
  if (event.matches) {
    document.addEventListener("htmx:afterSettle", handlePhoneAfterSettle);
    document.addEventListener("htmx:beforeHistorySave", showAppliedFiltersToSnapshot);
    window.addEventListener("resize", fitAppliedFilters);
    setPhoneAttributes();
    applyPhoneViewMode();
    return;
  }

  document.removeEventListener("htmx:afterSettle", handlePhoneAfterSettle);
  document.removeEventListener("htmx:beforeHistorySave", showAppliedFiltersToSnapshot);
  window.removeEventListener("resize", fitAppliedFilters);
  leaveFilterSheet();
  restoreAppliedFilters();
  releaseChipRemoval();
  releaseEntitySwitchPress();
  settleFocus = null;
  appliedFiltersExpanded = false;
  removePhoneAttributes();
};

/**
 * Starts following the phone query.
 */
const initializePhoneControls = () => {
  if (typeof window.matchMedia !== "function") {
    return;
  }

  const phoneQuery = window.matchMedia(PHONE_MEDIA_QUERY);
  phoneQuery.addEventListener("change", handlePhoneQueryChange);
  if (phoneQuery.matches) {
    handlePhoneQueryChange(phoneQuery);
  }

  // Chips measured before the web font loads are narrower or wider than the ones shown.
  document.fonts?.ready.then(() => {
    if (phoneQuery.matches) {
      fitAppliedFilters();
    }
  });
};

/**
 * Closes the sheet when the phone layout goes away, keeping its pending choices.
 */
const leaveFilterSheet = () => {
  if (!filterSheet) {
    return;
  }

  const { applying, drawer } = filterSheet;
  const form = drawer.querySelector(FILTER_FORM_SELECTOR);
  releaseFilterSheet();
  restoreModalFocus(drawer);
  if (pendingDrawers.has(drawer) && !applying) {
    triggerChangeOnForm(form.id);
  }
};

/**
 * Opens the filters drawer as the phone bottom sheet, which defers its requests.
 * @param {HTMLElement} trigger - Button that opened the sheet
 */
const openFilterSheet = (trigger) => {
  const drawer = getElementById(document, DRAWER_FILTERS_ID);
  if (!drawer || filterSheet) {
    return;
  }

  openFiltersDrawer();
  lockBodyScroll();
  setFilterSheetSemantics(drawer, true);
  focusModal(drawer, trigger);
  filterSheet = {
    applying: false,
    drawer,
    failed: false,
    refreshRequest: createLatestRequest(),
    unbindGestures: bindSheetGestures(drawer),
    unbindKeyboard: bindModalDismissListeners({ onKeydown: handleFilterSheetKeydown }),
  };
  document.addEventListener("htmx:beforeHistorySave", releaseFilterSheet);
  document.addEventListener("htmx:confirm", handleFilterSheetConfirm);
  document.addEventListener("htmx:responseError", handleFilterSheetError);
  document.addEventListener("htmx:sendError", handleFilterSheetError);
  window.addEventListener("pageshow", handleFilterSheetPageShow);
};

/**
 * Replaces the filters around the Community filter, which stays in place.
 * @param {HTMLFormElement} form - Form inside the sheet
 * @param {Node[]} nodes - Children of a form, holding its own Community filter
 */
const placeFiltersAroundCommunity = (form, nodes) => {
  const community = form.querySelector(COMMUNITY_FILTER_SELECTOR);
  const communityIndex = nodes.findIndex((node) => node.matches?.(COMMUNITY_FILTER_SELECTOR));
  [...form.childNodes].filter((node) => node !== community).forEach((node) => node.remove());
  community.before(...nodes.slice(0, communityIndex));
  community.after(...nodes.slice(communityIndex + 1));
};

/**
 * Places the focus requested for the swap that just settled, and announces a removed filter.
 * A swap from another request leaves the other side pressed, so a switch entry places nothing.
 */
const placeSettleFocus = () => {
  if (!settleFocus) {
    return;
  }

  const { chipIndex, chipLabel, reset, switchLabel } = settleFocus;
  settleFocus = null;
  if (switchLabel) {
    const pressedSwitch = document.querySelector(ENTITY_SWITCH_PRESSED_SELECTOR);
    if (pressedSwitch?.textContent.trim() === switchLabel) {
      pressedSwitch.focus({ preventScroll: true });
    }
    return;
  }

  if (chipIndex === undefined) {
    getElementById(document, OPEN_FILTERS_ID)?.focus({ preventScroll: true });
    if (reset) {
      announceFilterChange("Filters reset.");
    }
    return;
  }

  const chips = [...document.querySelectorAll(APPLIED_FILTER_SELECTOR)];
  const results = getElementById(document, RESULTS_ID);
  results?.setAttribute("tabindex", "-1");
  const emptyResults = document.querySelector(RESULTS_EMPTY_SELECTOR);
  // A chip the card hides behind its toggle cannot take focus, so the toggle takes it.
  const chip = chips[chipIndex] ?? chips.at(-1);
  const target =
    (chip?.hidden ? document.querySelector(APPLIED_FILTERS_TOGGLE_SELECTOR) : chip) ??
    emptyResults ??
    results;
  target?.focus({ preventScroll: true });
  announceFilterChange(`Removed filter ${chipLabel}.`);
};

/**
 * Refreshes the sheet's form for a new community, so its dependent filters appear at once.
 * A read-only request: URL, history and results wait for the apply. The Community filter
 * itself stays in place, so the option keeps its state.
 * @param {HTMLFormElement} form - Form inside the sheet
 */
const refreshFilterSheetForm = async (form) => {
  const sheet = filterSheet;
  const { drawer, refreshRequest } = sheet;
  const { id, signal } = refreshRequest.start();

  setFilterSheetBusy(drawer, true);
  try {
    const path = form.getAttribute("hx-get");
    const response = await ocgFetch(`${path}?${getFilterFormQuery(form)}`, { signal });
    if (!response.ok) {
      throw new ExploreFetchError(`Failed to refresh filters (status ${response.status})`, {
        responseText: await response.text().catch(() => ""),
        status: response.status,
      });
    }

    const html = await response.text();
    if (filterSheet === sheet && refreshRequest.isCurrent(id)) {
      replaceDependentFilters(form, html);
    }
  } catch (error) {
    if (!isAbortError(error) && filterSheet === sheet && refreshRequest.isCurrent(id)) {
      reportFetchError(error);
    }
  } finally {
    if (filterSheet === sheet && refreshRequest.isCurrent(id)) {
      setFilterSheetBusy(drawer, false);
    }
  }
};

/**
 * Stops waiting for chip removals, once their swap settled or their request failed.
 */
const releaseChipRemoval = () => {
  chipRemoval = null;
  document.removeEventListener("htmx:responseError", handleChipRemovalError);
  document.removeEventListener("htmx:sendError", handleChipRemovalError);
};

/**
 * Stops waiting for a switch press, once its swap settled or its request ended without one.
 */
const releaseEntitySwitchPress = () => {
  document.removeEventListener("htmx:responseError", handleEntitySwitchRequestEnd);
  document.removeEventListener("htmx:sendAbort", handleEntitySwitchRequestEnd);
  document.removeEventListener("htmx:sendError", handleEntitySwitchRequestEnd);
  if (settleFocus?.switchLabel) {
    settleFocus = null;
  }
};

/**
 * Releases everything an open filter sheet holds. Safe at any width and on a removed drawer.
 */
const releaseFilterSheet = () => {
  if (!filterSheet) {
    return;
  }

  const { drawer, refreshRequest, unbindGestures, unbindKeyboard } = filterSheet;
  filterSheet = null;
  settleFocus = { opener: true };
  refreshRequest.cancel();
  unbindKeyboard();
  unbindGestures();
  document.removeEventListener("htmx:beforeHistorySave", releaseFilterSheet);
  document.removeEventListener("htmx:confirm", handleFilterSheetConfirm);
  document.removeEventListener("htmx:responseError", handleFilterSheetError);
  document.removeEventListener("htmx:sendError", handleFilterSheetError);
  window.removeEventListener("pageshow", handleFilterSheetPageShow);
  setFilterSheetBusy(drawer, false);
  setApplyFiltersDisabled(drawer, false);
  setFilterSheetSemantics(drawer, false);
  closeFiltersDrawer();
  unlockBodyScroll();
};

/**
 * Removes an applied filter through its real control. Chip taps stay live: the control's own
 * change sends the request.
 * @param {HTMLButtonElement} chip - Chip button
 * @param {string} formId - Form holding the applied state
 */
const removeAppliedFilter = (chip, formId) => {
  const form = getElementById(document, formId);
  const control = form && getAppliedFilterControl(form, chip);
  if (!control || chipRemoval?.chips.has(chip)) {
    return;
  }

  if (!chipRemoval) {
    chipRemoval = { chips: new Set(), restoreFilterValues: captureFilterValues(form) };
    document.addEventListener("htmx:responseError", handleChipRemovalError);
    document.addEventListener("htmx:sendError", handleChipRemovalError);
  }

  settleFocus = {
    chipIndex: [...document.querySelectorAll(APPLIED_FILTER_SELECTOR)].indexOf(chip),
    chipLabel: chip.textContent.trim(),
  };
  // A second tap on the same chip would turn the filter back on before the swap.
  chipRemoval.chips.add(chip);
  control.click();
};

/**
 * Removes the attributes set on shared nodes for phones.
 */
const removePhoneAttributes = () => {
  document.querySelectorAll(FILTER_FORM_SELECTOR).forEach((form) => form.removeAttribute("hx-sync"));
  getElementById(document, RESULTS_ID)?.removeAttribute("tabindex");
  getElementById(document, SEARCH_INPUT_ID)?.removeAttribute("enterkeyhint");
  showAllAppliedFilters();
};

/**
 * Replaces the filters around the Community filter with the ones of a section response.
 * @param {HTMLFormElement} form - Form inside the sheet
 * @param {string} html - Section markup
 */
const replaceDependentFilters = (form, html) => {
  const incomingForm = new DOMParser().parseFromString(html, "text/html").getElementById(form.id);
  const incomingCommunity = incomingForm?.querySelector(COMMUNITY_FILTER_SELECTOR);
  const community = form.querySelector(COMMUNITY_FILTER_SELECTOR);
  if (!incomingCommunity || !community) {
    return;
  }

  if (!appliedFilterNodes.has(form)) {
    appliedFilterNodes.set(form, [...form.childNodes]);
  }
  placeFiltersAroundCommunity(form, [...incomingForm.childNodes]);

  const option =
    community.querySelector("input:checked") ?? community.querySelector("button[aria-label^='Any']");
  option?.focus({ preventScroll: true });
};

/**
 * Clears sheet state from the DOM after a restore, which a module flag cannot describe.
 */
const resetFilterSheet = () => {
  releaseFilterSheet();
  settleFocus = null;

  const drawer = getElementById(document, DRAWER_FILTERS_ID);
  if (!drawer) {
    return;
  }

  // The shared restore hides any open dialog, but this one is shown by its translate classes.
  setElementHidden(drawer, false);
  drawer.removeAttribute("aria-hidden");
  if (drawer.getAttribute("role") === "dialog") {
    setFilterSheetSemantics(drawer, false);
    closeFiltersDrawer();
  }
};

/**
 * Puts back the filters a refresh replaced, dropping the choices that were never applied.
 */
const restoreAppliedFilters = () => {
  const form = getElementById(document, DRAWER_FILTERS_ID)?.querySelector(FILTER_FORM_SELECTOR);
  const nodes = form && appliedFilterNodes.get(form);
  if (!nodes) {
    return;
  }

  appliedFilterNodes.delete(form);
  placeFiltersAroundCommunity(form, nodes);
};

/**
 * Shows every Active filters chip and hides the toggle, as the card is served.
 */
const showAllAppliedFilters = () => {
  getElementById(document, APPLIED_FILTERS_ID)
    ?.querySelectorAll(APPLIED_FILTER_SELECTOR)
    .forEach((chip) => {
      chip.hidden = false;
    });

  const toggle = document.querySelector(APPLIED_FILTERS_TOGGLE_SELECTOR);
  if (toggle) {
    toggle.hidden = true;
    toggle.setAttribute("aria-expanded", "false");
  }
};

/**
 * Shows a history snapshot the applied filters. htmx clones the page right after this event, and
 * paging swaps only the cards, so the pending choices return once the clone is taken.
 */
const showAppliedFiltersToSnapshot = () => {
  const form = getElementById(document, DRAWER_FILTERS_ID)?.querySelector(FILTER_FORM_SELECTOR);
  const nodes = form && appliedFilterNodes.get(form);
  if (!nodes) {
    return;
  }

  const pendingNodes = [...form.childNodes];
  placeFiltersAroundCommunity(form, nodes);
  queueMicrotask(() => {
    if (form.isConnected) {
      placeFiltersAroundCommunity(form, pendingNodes);
    }
  });
};

/**
 * Disables Show results while its request is in flight.
 * @param {HTMLElement} drawer - Sheet element
 * @param {boolean} disabled - Whether the button is disabled
 */
const setApplyFiltersDisabled = (drawer, disabled) => {
  const button = drawer.querySelector(APPLY_FILTERS_SELECTOR);
  if (button) {
    button.disabled = disabled;
  }
};

/**
 * Shows the sheet's loading state while its form refreshes.
 * @param {HTMLElement} drawer - Sheet element
 * @param {boolean} busy - Whether a refresh is running
 */
const setFilterSheetBusy = (drawer, busy) => {
  const form = drawer.querySelector(FILTER_FORM_SELECTOR);
  if (busy) {
    form?.setAttribute("aria-busy", "true");
  } else {
    form?.removeAttribute("aria-busy");
  }
};

/**
 * Gives the drawer its dialog semantics while it is a sheet. The tablet drawer keeps its tree.
 * @param {HTMLElement} drawer - Sheet element
 * @param {boolean} open - Whether the sheet is open
 */
const setFilterSheetSemantics = (drawer, open) => {
  const closeButton = getElementById(drawer, CLOSE_FILTERS_ID);
  if (open) {
    drawer.removeAttribute("aria-labelledby");
    drawer.setAttribute("aria-label", "Filters");
    drawer.setAttribute("aria-modal", "true");
    drawer.setAttribute("role", "dialog");
    closeButton?.setAttribute("aria-label", "Close filters");
    return;
  }

  drawer.removeAttribute("aria-label");
  drawer.removeAttribute("aria-modal");
  drawer.removeAttribute("role");
  drawer.setAttribute("aria-labelledby", "drawer-label");
  closeButton?.removeAttribute("aria-label");
};

/**
 * Sets the attributes phones need on shared nodes, at init and after every swap. Both forms get
 * the sync, because chips act on the hidden desktop form: a second chip tap replaces the first
 * request instead of being lost. The Active filters chips are fitted on one line.
 */
const setPhoneAttributes = () => {
  document.querySelectorAll(FILTER_FORM_SELECTOR).forEach((form) => {
    form.setAttribute("hx-sync", FILTER_SECTION_SYNC);
  });
  getElementById(document, SEARCH_INPUT_ID)?.setAttribute("enterkeyhint", SEARCH_KEY_HINT);
  fitAppliedFilters();
};

initializeExploreControls();
