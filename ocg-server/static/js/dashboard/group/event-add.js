import { initializeSessionsRemovalWarning } from "/static/js/dashboard/group/event-form-helpers.js";
import { initializeEventPreview } from "/static/js/dashboard/group/event-preview.js";
import "/static/js/dashboard/group/questions-editor.js";
import {
  getElementById,
  initializeMatchingRoots,
  initializeOnReadyAndHtmxLoad,
  markDatasetReady,
  setElementHidden,
} from "/static/js/common/dom.js";
import {
  attachEventSaveAfterRequest,
  attachEventSaveBeforeRequestValidation,
  attachEventSaveConfigRequest,
  createSessionsDateRangeSync,
  initializeEventPageContext,
  initializeEventPagePendingChanges,
  initializeRegistrationModeToggle,
  initializeSharedEventPageControls,
  resolveSharedEventPageControls,
} from "/static/js/dashboard/group/event-page-shared.js";
import { initializeSectionTabs } from "/static/js/dashboard/group/page-form-state.js";

const EVENT_ADD_PAGE_SELECTOR = '[data-event-page="add"]';
const DRAFT_EVENT_DATE_FALLBACK = "Date not set yet";
const DRAFT_EVENT_TITLE_FALLBACK = "Untitled event";
const DRAFT_EVENT_DATE_OPTIONS = {
  day: "numeric",
  hour: "numeric",
  minute: "2-digit",
  month: "long",
  year: "numeric",
};
const DRAFT_EVENT_TIME_OPTIONS = {
  hour: "numeric",
  minute: "2-digit",
};

/**
 * Initializes recurrence labels and conditional additional-occurrence validation.
 * @param {Object} config Recurrence control configuration
 * @param {HTMLElement|null} config.recurrenceAdditionalOccurrencesContainer Wrapper element
 * @param {HTMLInputElement|null} config.recurrenceAdditionalOccurrencesInput Additional count input
 * @param {HTMLSelectElement|null} config.recurrencePatternSelect Recurrence select
 * @param {HTMLInputElement|null} config.startsAtInput Event start input
 * @returns {void}
 */
const initializeRecurrenceFields = ({
  recurrenceAdditionalOccurrencesContainer,
  recurrenceAdditionalOccurrencesInput,
  recurrencePatternSelect,
  startsAtInput,
}) => {
  if (!recurrencePatternSelect) {
    return;
  }

  const update = () => {
    updateRecurrenceLabels(recurrencePatternSelect, startsAtInput);
    updateRecurrenceAdditionalOccurrencesState({
      recurrenceAdditionalOccurrencesContainer,
      recurrenceAdditionalOccurrencesInput,
      recurrencePatternSelect,
    });
  };

  recurrencePatternSelect.addEventListener("change", update);
  startsAtInput?.addEventListener("change", update);
  update();
};

/**
 * Returns a local Date from a datetime-local input value.
 * @param {string} value Input value
 * @returns {Date|null} Parsed date
 */
const parseDateTimeLocal = (value) => {
  if (!value) {
    return null;
  }

  const parsed = new Date(value);
  return Number.isNaN(parsed.getTime()) ? null : parsed;
};

/**
 * Formats a draft event date input for the header reminder.
 * @param {HTMLInputElement|null} input Date input
 * @param {Intl.DateTimeFormatOptions} options Format options
 * @returns {string} Formatted date or an empty string
 */
const formatDraftEventDate = (input, options) => {
  const parsedDate = parseDateTimeLocal(input?.value || "");
  if (!parsedDate) {
    return "";
  }

  return new Intl.DateTimeFormat(undefined, options).format(parsedDate);
};

/**
 * Returns the draft event date range label.
 * @param {HTMLInputElement|null} startsAtInput Start date input
 * @param {HTMLInputElement|null} endsAtInput End date input
 * @returns {string} Draft event date label
 */
const getDraftEventDateLabel = (startsAtInput, endsAtInput) => {
  const startLabel = formatDraftEventDate(startsAtInput, DRAFT_EVENT_DATE_OPTIONS);
  const endLabel = formatDraftEventDate(endsAtInput, DRAFT_EVENT_TIME_OPTIONS);

  if (startLabel && endLabel) {
    return `${startLabel} - ${endLabel}`;
  }

  if (startLabel) {
    return startLabel;
  }

  return endLabel ? `Ends ${endLabel}` : DRAFT_EVENT_DATE_FALLBACK;
};

/**
 * Updates the add-event reminder title and date from draft fields.
 * @param {Object} config Reminder configuration
 * @param {HTMLElement} config.dateElement Date text element
 * @param {HTMLInputElement|null} config.endsAtInput End date input
 * @param {HTMLInputElement|null} config.nameInput Event name input
 * @param {HTMLInputElement|null} config.startsAtInput Start date input
 * @param {HTMLElement} config.titleElement Title text element
 * @returns {void}
 */
const updateDraftEventReminder = ({ dateElement, endsAtInput, nameInput, startsAtInput, titleElement }) => {
  titleElement.textContent = nameInput?.value.trim() || DRAFT_EVENT_TITLE_FALLBACK;
  dateElement.textContent = getDraftEventDateLabel(startsAtInput, endsAtInput);
};

/**
 * Initializes the add-event draft title reminder.
 * @param {Object} config Reminder configuration
 * @param {HTMLInputElement|null} config.endsAtInput End date input
 * @param {HTMLElement} config.pageRoot Event page root
 * @param {HTMLInputElement|null} config.startsAtInput Start date input
 * @returns {void}
 */
const initializeDraftEventReminder = ({ endsAtInput, pageRoot, startsAtInput }) => {
  const titleElement = getElementById(pageRoot, "draft-event-title");
  const dateElement = getElementById(pageRoot, "draft-event-date");
  if (!titleElement || !dateElement || !markDatasetReady(titleElement, "draftEventReminderReady")) {
    return;
  }

  const nameInput = getElementById(pageRoot, "name");
  const update = () =>
    updateDraftEventReminder({
      dateElement,
      endsAtInput,
      nameInput,
      startsAtInput,
      titleElement,
    });

  nameInput?.addEventListener("input", update);
  startsAtInput?.addEventListener("input", update);
  startsAtInput?.addEventListener("change", update);
  endsAtInput?.addEventListener("input", update);
  endsAtInput?.addEventListener("change", update);
  update();
};

/**
 * Updates the visible recurrence labels based on the selected start date.
 * @param {HTMLSelectElement} recurrencePatternSelect Recurrence select
 * @param {HTMLInputElement|null} startsAtInput Event start input
 * @returns {void}
 */
const updateRecurrenceLabels = (recurrencePatternSelect, startsAtInput) => {
  const startsAt = parseDateTimeLocal(startsAtInput?.value || "");
  const weekday = startsAt?.toLocaleDateString(undefined, { weekday: "long" });
  const ordinal = startsAt ? ordinalWeekdayInMonth(startsAt) : null;

  for (const option of recurrencePatternSelect.options) {
    switch (option.dataset.recurrenceLabel) {
      case "weekly":
        option.textContent = weekday ? `Weekly on ${weekday}` : "Weekly";
        break;
      case "biweekly":
        option.textContent = weekday ? `Every two weeks on ${weekday}` : "Every two weeks";
        break;
      case "monthly":
        option.textContent = weekday && ordinal ? `Monthly on the ${ordinal} ${weekday}` : "Monthly";
        break;
      default:
        break;
    }
  }
};

/**
 * Returns the ordinal word for the weekday occurrence within the month.
 * @param {Date} date Local date
 * @returns {string} Ordinal word
 */
const ordinalWeekdayInMonth = (date) => {
  const ordinal = Math.floor((date.getDate() - 1) / 7);
  return ["first", "second", "third", "fourth", "fifth"][ordinal] || "last";
};

/**
 * Toggles the additional-occurrences input when recurring creation is selected.
 * @param {Object} config Additional-occurrences configuration
 * @param {HTMLElement|null} config.recurrenceAdditionalOccurrencesContainer Wrapper element
 * @param {HTMLInputElement|null} config.recurrenceAdditionalOccurrencesInput Additional count input
 * @param {HTMLSelectElement} config.recurrencePatternSelect Recurrence select
 * @returns {void}
 */
const updateRecurrenceAdditionalOccurrencesState = ({
  recurrenceAdditionalOccurrencesContainer,
  recurrenceAdditionalOccurrencesInput,
  recurrencePatternSelect,
}) => {
  const recurring = recurrencePatternSelect.value !== "just-once";
  setElementHidden(recurrenceAdditionalOccurrencesContainer, !recurring);

  if (!recurrenceAdditionalOccurrencesInput) {
    return;
  }

  recurrenceAdditionalOccurrencesInput.disabled = !recurring;
  recurrenceAdditionalOccurrencesInput.required = recurring;
  if (!recurring) {
    recurrenceAdditionalOccurrencesInput.value = "";
  }
};

/**
 * Initializes the event add page behavior for the active form fragment.
 * @param {Document|Element} [root=document] Root page container
 * @returns {void}
 */
export const initializeEventAddPage = (root = document) => {
  const pageContext = initializeEventPageContext(root, "add");
  if (!pageContext) {
    return;
  }

  const { pageRoot, queryOne } = pageContext;

  const controls = resolveSharedEventPageControls(pageRoot);
  const {
    startsAtInput,
    endsAtInput,
    registrationStartsAtInput,
    registrationEndsAtInput,
    cfsEnabledInput,
    cfsStartsAtInput,
    cfsEndsAtInput,
    onlineEventDetails,
  } = controls;
  const addEventButton = getElementById(pageRoot, "add-event-button");
  const recurrenceAdditionalOccurrencesContainer = getElementById(
    pageRoot,
    "recurrence-additional-occurrences-container",
  );
  const recurrenceAdditionalOccurrencesInput = getElementById(pageRoot, "recurrence_additional_occurrences");
  const recurrencePatternSelect = getElementById(pageRoot, "recurrence_pattern");

  // Sessions need the parent event date range before their own validation runs.
  const syncSessionsDateRange = createSessionsDateRangeSync({
    queryOne,
    startsAtInput,
    endsAtInput,
  });

  const { displayActiveSection } = initializeSectionTabs({
    root: pageRoot,
    onSectionChange: (sectionName) => {
      if (sectionName === "sessions") {
        syncSessionsDateRange();
      }
    },
  });

  // Shared setup binds CFS, online details, and cross-section validation rules.
  const { validateEventForms, validateSessionOnlineDetails, showSessionBoundsError } =
    initializeSharedEventPageControls({
      pageRoot,
      queryOne,
      displayActiveSection,
      syncSessionsDateRange,
      controls,
      bindDisabledCfsToggle: true,
    });

  initializeRecurrenceFields({
    recurrenceAdditionalOccurrencesContainer,
    recurrenceAdditionalOccurrencesInput,
    recurrencePatternSelect,
    startsAtInput,
  });
  initializeDraftEventReminder({
    endsAtInput,
    pageRoot,
    startsAtInput,
  });

  initializeEventPagePendingChanges({
    pageRoot,
    confirmMessage:
      "You have pending changes for this new event. If you continue, this event will not be created.",
  });

  initializeEventPreview({
    pageRoot,
  });

  initializeRegistrationModeToggle(pageRoot);

  if (!addEventButton) {
    return;
  }

  initializeSessionsRemovalWarning({
    saveButton: addEventButton,
  });

  // Save handlers run in capture order: validate, normalize payload, then alert.
  attachEventSaveBeforeRequestValidation({
    saveButton: addEventButton,
    saveButtonId: "add-event-button",
    validateEventForms,
    validateSessionOnlineDetails,
    showSessionBoundsError,
    displayActiveSection,
    pageRoot,
    startsAtInput,
    endsAtInput,
    registrationStartsAtInput,
    registrationEndsAtInput,
    cfsEnabledInput,
    cfsStartsAtInput,
    cfsEndsAtInput,
    onlineEventDetails,
    allowPastDates: false,
  });

  attachEventSaveConfigRequest({
    saveButton: addEventButton,
    saveButtonId: "add-event-button",
    validateEventForms,
  });

  attachEventSaveAfterRequest({
    saveButton: addEventButton,
    saveButtonId: "add-event-button",
    successMessage: "You have successfully created the event.",
    errorMessage: "Something went wrong creating the event. Please try again later.",
  });
};

/**
 * Initializes event add page roots inside a swapped fragment.
 * @param {Document|Element} [root=document] Root page container
 * @returns {void}
 */
export const initializeEventAddPageRoots = (root = document) => {
  initializeMatchingRoots(root, EVENT_ADD_PAGE_SELECTOR, initializeEventAddPage);
};

initializeOnReadyAndHtmxLoad(initializeEventAddPageRoots);
