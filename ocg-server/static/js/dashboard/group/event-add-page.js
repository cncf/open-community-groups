import { initializeSessionsRemovalWarning } from "/static/js/dashboard/group/event-form-helpers.js";
import {
  attachEventSaveAfterRequest,
  attachEventSaveBeforeRequestValidation,
  attachEventSaveConfigRequest,
  bindSharedEventDateFieldListeners,
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
    hasVenueData,
    confirmVenueDataDeletion,
    clearVenueFields,
    updateSectionVisibility,
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
