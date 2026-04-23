import { initializeSessionsRemovalWarning } from "/static/js/dashboard/group/event-form-helpers.js";
import {
  attachEventSaveAfterRequest,
  attachEventSaveBeforeRequestValidation,
  attachEventSaveConfigRequest,
  bindSharedEventDateFieldListeners,
  configureScopedTicketingEditors,
  createEventPageCfsFieldUpdater,
  createEventPageValidationCallbacks,
  createSessionsDateRangeSync,
  initializeEventPageContext,
  initializeCommonEventPageToggles,
  initializeEventKindField,
  initializeEventPageCancelNavigation,
  initializeEventPagePendingChanges,
} from "/static/js/dashboard/group/event-page-shared.js";
import {
  clearVenueFields,
  confirmVenueDataDeletion,
  hasVenueData,
  updateSectionVisibility,
} from "/static/js/dashboard/group/meeting-validations.js";
import { initializeSectionTabs } from "/static/js/dashboard/group/page-form-state.js";

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

  const { pageRoot, queryById, queryOne } = pageContext;

  const addEventButton = queryById("add-event-button");
  const cancelButton = queryById("cancel-button");
  const kindSelect = queryById("kind_id");
  const onlineEventDetails = queryById("online-event-details");
  const toggleCfsEnabled = queryById("toggle_cfs_enabled");
  const cfsEnabledInput = queryById("cfs_enabled");
  const cfsStartsAtInput = queryById("cfs_starts_at");
  const cfsEndsAtInput = queryById("cfs_ends_at");
  const cfsDescriptionInput = queryById("cfs_description");
  const cfsLabelsEditor = queryById("cfs-labels-editor");
  const startsAtInput = queryById("starts_at");
  const endsAtInput = queryById("ends_at");
  const recurrenceAdditionalOccurrencesContainer = queryById("recurrence-additional-occurrences-container");
  const recurrenceAdditionalOccurrencesInput = queryById("recurrence_additional_occurrences");
  const recurrencePatternSelect = queryById("recurrence_pattern");

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

  const { validateEventForms, validateSessionOnlineDetails, showSessionBoundsError } =
    createEventPageValidationCallbacks({
      queryById,
      queryOne,
      displayActiveSection,
      cfsStartsAtInput,
      cfsEndsAtInput,
    });

  const updateCfsFields = createEventPageCfsFieldUpdater({
    cfsStartsAtInput,
    cfsEndsAtInput,
    cfsDescriptionInput,
    cfsLabelsEditor,
  });

  configureScopedTicketingEditors({
    queryById,
    queryOne,
  });

  initializeCommonEventPageToggles({
    pageRoot,
    queryById,
    toggleCfsEnabled,
    cfsEnabledInput,
    cfsStartsAtInput,
    cfsEndsAtInput,
    updateCfsFields,
    bindDisabledCfsToggle: true,
  });

  initializeEventKindField({
    kindSelect,
    onlineEventDetails,
    hasVenueData: () => hasVenueData(pageRoot),
    confirmVenueDataDeletion,
    clearVenueFields: () => clearVenueFields(pageRoot),
    updateSectionVisibility: (kind) => updateSectionVisibility(kind, pageRoot),
  });

  bindSharedEventDateFieldListeners({
    queryById,
    syncSessionsDateRange,
    startsAtInput,
    endsAtInput,
    cfsStartsAtInput,
    cfsEndsAtInput,
    onlineEventDetails,
  });

  initializeRecurrenceFields({
    recurrenceAdditionalOccurrencesContainer,
    recurrenceAdditionalOccurrencesInput,
    recurrencePatternSelect,
    startsAtInput,
  });

  initializeEventPageCancelNavigation(cancelButton);

  initializeEventPagePendingChanges({
    pageRoot,
    confirmMessage:
      "You have pending changes for this new event. If you continue, this event will not be created.",
  });

  if (!addEventButton) {
    return;
  }

  initializeSessionsRemovalWarning({
    saveButton: addEventButton,
  });

  attachEventSaveBeforeRequestValidation({
    saveButton: addEventButton,
    saveButtonId: "add-event-button",
    validateEventForms,
    validateSessionOnlineDetails,
    showSessionBoundsError,
    displayActiveSection,
    queryById,
    startsAtInput,
    endsAtInput,
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
  recurrenceAdditionalOccurrencesContainer?.classList.toggle("hidden", !recurring);

  if (!recurrenceAdditionalOccurrencesInput) {
    return;
  }

  recurrenceAdditionalOccurrencesInput.disabled = !recurring;
  recurrenceAdditionalOccurrencesInput.required = recurring;
  if (!recurring) {
    recurrenceAdditionalOccurrencesInput.value = "";
  }
};
