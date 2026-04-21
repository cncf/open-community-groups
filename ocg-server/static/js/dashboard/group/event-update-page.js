import { showConfirmAlert } from "/static/js/common/alerts.js";
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

/**
 * Reads a boolean data attribute from the given element.
 * @param {HTMLElement|null} element Source element
 * @param {string} attributeName Data attribute name without the `data-` prefix
 * @returns {boolean}
 */
const readBooleanDataAttribute = (element, attributeName) => element?.dataset?.[attributeName] === "true";

/**
 * Initializes the event update page behavior for the active form fragment.
 * @param {Document|Element} [root=document] Root page container
 * @returns {void}
 */
export const initializeEventUpdatePage = (root = document) => {
  const pageContext = initializeEventPageContext(root, "update");
  if (!pageContext) {
    return;
  }

  const { pageRoot, queryById, queryOne } = pageContext;

  const updateEventButton = queryById("update-event-button");
  const cancelButton = queryById("cancel-button");
  const kindSelect = queryById("kind_id");
  const onlineEventDetails = queryById("online-event-details");
  const clearLocationButton = queryById("clear-location-fields");
  const locationSearchField = queryOne("location-search-field");
  const inertForm = queryOne(".inert-form");
  const toggleCfsEnabled = queryById("toggle_cfs_enabled");
  const cfsEnabledInput = queryById("cfs_enabled");
  const cfsStartsAtInput = queryById("cfs_starts_at");
  const cfsEndsAtInput = queryById("cfs_ends_at");
  const cfsDescriptionInput = queryById("cfs_description");
  const cfsLabelsEditor = queryById("cfs-labels-editor");
  const startsAtInput = queryById("starts_at");
  const endsAtInput = queryById("ends_at");
  const capacityInput = queryById("capacity");
  const approvedSubmissionsEvent = "event-approved-submissions-updated";
  const isPastEvent = readBooleanDataAttribute(pageRoot, "eventPast");
  const canManageEvents = readBooleanDataAttribute(pageRoot, "canManageEvents");
  const initialWaitlistCount = Number.parseInt(updateEventButton?.dataset.waitlistCount || "0", 10);

  const syncSessionsDateRange = createSessionsDateRangeSync({
    queryOne,
    startsAtInput,
    endsAtInput,
  });

  const showLocationMapIfNeeded = () => {
    if (locationSearchField && typeof locationSearchField.showMapPreview === "function") {
      locationSearchField.showMapPreview();
    }
  };

  const getApprovedSubmissions = (sessionsSection) => {
    if (Array.isArray(sessionsSection.approvedSubmissions)) {
      return [...sessionsSection.approvedSubmissions];
    }

    const payload = sessionsSection.getAttribute("approved-submissions");
    if (!payload) {
      return [];
    }

    try {
      const parsed = JSON.parse(payload);
      return Array.isArray(parsed) ? parsed : [];
    } catch (_) {
      return [];
    }
  };

  const sortApprovedSubmissions = (submissions) =>
    submissions.sort((left, right) => {
      const leftTitle = String(left?.title || "").toLowerCase();
      const rightTitle = String(right?.title || "").toLowerCase();
      if (leftTitle !== rightTitle) {
        return leftTitle.localeCompare(rightTitle);
      }

      const leftId = String(left?.cfs_submission_id || "");
      const rightId = String(right?.cfs_submission_id || "");
      return leftId.localeCompare(rightId);
    });

  if (pageRoot instanceof HTMLElement && pageRoot.dataset.approvedSubmissionsSyncBound !== "true") {
    pageRoot.dataset.approvedSubmissionsSyncBound = "true";
    pageRoot.addEventListener(approvedSubmissionsEvent, (event) => {
      const sessionsSection = queryOne("sessions-section");
      if (!sessionsSection) {
        return;
      }

      const detail = event?.detail || {};
      const submissionId = String(detail.cfsSubmissionId || detail.submission?.cfs_submission_id || "");
      if (!submissionId) {
        return;
      }

      const currentSubmissions = getApprovedSubmissions(sessionsSection);
      const nextSubmissions = currentSubmissions.filter(
        (submission) => String(submission?.cfs_submission_id || "") !== submissionId,
      );

      if (detail.approved && detail.submission) {
        nextSubmissions.push(detail.submission);
      }

      const sortedSubmissions = sortApprovedSubmissions(nextSubmissions);
      sessionsSection.approvedSubmissions = sortedSubmissions;
      sessionsSection.setAttribute("approved-submissions", JSON.stringify(sortedSubmissions));
      sessionsSection.requestUpdate?.();
    });
  }

  if (clearLocationButton) {
    clearLocationButton.addEventListener("click", () => {
      clearVenueFields();
    });
  }

  const { displayActiveSection } = initializeSectionTabs({
    root: pageRoot,
    onSectionChange: (sectionName) => {
      if (sectionName === "date-venue") {
        showLocationMapIfNeeded();
      }

      if (sectionName === "sessions") {
        syncSessionsDateRange();
      }

      if (!canManageEvents && inertForm) {
        if (sectionName === "submissions") {
          inertForm.removeAttribute("inert");
        } else {
          inertForm.setAttribute("inert", "");
        }
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
    isFieldLocked: (field) => field?.dataset?.locked === "true",
  });

  initializeCommonEventPageToggles({
    pageRoot,
    queryById,
    toggleCfsEnabled,
    cfsEnabledInput,
    cfsStartsAtInput,
    cfsEndsAtInput,
    updateCfsFields,
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
    confirmMessage: "You have pending changes. If you continue, unsaved changes will be lost.",
  });

  if (!updateEventButton) {
    return;
  }

  initializeSessionsRemovalWarning({
    saveButton: updateEventButton,
  });

  updateEventButton.addEventListener(
    "click",
    (event) => {
      if (!capacityInput || initialWaitlistCount <= 0) {
        return;
      }

      if (capacityInput.value.trim() !== "") {
        return;
      }

      event.preventDefault();
      event.stopImmediatePropagation();

      const queuedPeopleLabel = initialWaitlistCount === 1 ? "person is" : "people are";
      showConfirmAlert(
        `${initialWaitlistCount} ${queuedPeopleLabel} currently on the waitlist. Removing capacity will make this event unlimited and add them as attendees. Do you want to continue?`,
        "update-event-button",
        "Continue",
      );
    },
    true,
  );

  attachEventSaveBeforeRequestValidation({
    saveButton: updateEventButton,
    saveButtonId: "update-event-button",
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
    allowPastDates: true,
    latestDate: isPastEvent ? new Date() : null,
  });

  attachEventSaveConfigRequest({
    saveButton: updateEventButton,
    saveButtonId: "update-event-button",
    validateEventForms,
  });

  attachEventSaveAfterRequest({
    saveButton: updateEventButton,
    saveButtonId: "update-event-button",
    successMessage: "You have successfully updated the event.",
    errorMessage: "Something went wrong updating the event. Please try again later.",
    onSuccess: () => {
      pageRoot.dispatchEvent(new CustomEvent("refresh-event-submissions"));
    },
  });
};
