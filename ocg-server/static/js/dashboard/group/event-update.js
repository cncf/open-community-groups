import { bindHtmxResponseAlert, showConfirmAlert } from "/static/js/common/alerts.js";
import {
  getElementById,
  initializeMatchingRoots,
  initializeOnReadyAndHtmxLoad,
  markDatasetReady,
} from "/static/js/common/dom.js";
import { parseJsonAttribute } from "/static/js/common/utils.js";
import "/static/js/common/modals/share-modal.js";
import { initializeSessionsRemovalWarning } from "/static/js/dashboard/group/event-form-helpers.js";
import { initializeEventPreview } from "/static/js/dashboard/group/event-preview.js";
import "/static/js/dashboard/group/questions-editor.js";
import {
  attachEventSaveAfterRequest,
  attachEventSaveBeforeRequestValidation,
  attachEventSaveConfigRequest,
  createSessionsDateRangeSync,
  initializeEventPageContext,
  initializeEventPagePendingChanges,
  initializeSharedEventPageControls,
  resolveSharedEventPageControls,
} from "/static/js/dashboard/group/event-page-shared.js";
import { initializeSectionTabs } from "/static/js/dashboard/group/page-form-state.js";

/**
 * Reads a boolean data attribute from the given element.
 * @param {HTMLElement|null} element Source element
 * @param {string} attributeName Data attribute name without the `data-` prefix
 * @returns {boolean}
 */
const readBooleanDataAttribute = (element, attributeName) => element?.dataset?.[attributeName] === "true";

const canceledEventReviewSections = new Set(["submissions", "attendees", "invitation-requests", "waitlist"]);
const EVENT_UPDATE_PAGE_SELECTOR = '[data-event-page="update"]';

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
  const updateEventButton = getElementById(pageRoot, "update-event-button");
  const setEventDefaultsButton = getElementById(pageRoot, "set-event-defaults-button");
  const locationSearchField = queryOne("location-search-field");
  const inertForm = queryOne(".inert-form");
  const capacityInput = getElementById(pageRoot, "capacity");
  const approvedSubmissionsEvent = "event-approved-submissions-updated";
  const isCanceledEvent = readBooleanDataAttribute(pageRoot, "eventCanceled");
  const isPastEvent = readBooleanDataAttribute(pageRoot, "eventPast");
  const canManageEvents = readBooleanDataAttribute(pageRoot, "canManageEvents");
  const initialWaitlistCount = Number.parseInt(updateEventButton?.dataset.waitlistCount || "0", 10);

  if (onlineEventDetails) {
    onlineEventDetails.eventPast = isPastEvent;
    onlineEventDetails.toggleAttribute("event-past", isPastEvent);
  }
  queryOne("sessions-section")?.toggleAttribute("event-past", isPastEvent);

  // Sessions need the parent event date range before their own validation runs.
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

    const parsed = parseJsonAttribute(payload, []);
    return Array.isArray(parsed) ? parsed : [];
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

  if (pageRoot instanceof HTMLElement && markDatasetReady(pageRoot, "approvedSubmissionsSyncBound")) {
    // CFS review updates happen in another section but must refresh session options.
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

  const { displayActiveSection } = initializeSectionTabs({
    root: pageRoot,
    onSectionChange: (sectionName) => {
      // Maps need a visible container before Leaflet can size the preview.
      if (sectionName === "date-venue") {
        showLocationMapIfNeeded();
      }

      if (sectionName === "sessions") {
        syncSessionsDateRange();
      }

      // Canceled/read-only pages still allow specific review-only sections.
      if ((isCanceledEvent || !canManageEvents) && inertForm) {
        const canUseReadOnlyReviewSection =
          (isCanceledEvent && canManageEvents && canceledEventReviewSections.has(sectionName)) ||
          (!isCanceledEvent && !canManageEvents && sectionName === "submissions");

        if (canUseReadOnlyReviewSection) {
          inertForm.removeAttribute("inert");
        } else {
          inertForm.setAttribute("inert", "");
        }
      }
    },
  });

  const { validateEventForms, validateSessionOnlineDetails, showSessionBoundsError } =
    initializeSharedEventPageControls({
      pageRoot,
      queryOne,
      displayActiveSection,
      syncSessionsDateRange,
      controls,
      isCfsFieldLocked: (field) => field?.dataset?.locked === "true",
    });

  initializeEventPagePendingChanges({
    pageRoot,
    confirmMessage: "You have pending changes. If you continue, unsaved changes will be lost.",
  });

  initializeEventPreview({
    pageRoot,
  });

  bindHtmxResponseAlert(setEventDefaultsButton, {
    successMessage: "Group event defaults updated.",
    errorMessage: "Something went wrong updating group event defaults. Please try again later.",
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
      // Removing capacity can release the whole waitlist, so confirm first.
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

  // Save handlers run in capture order: validate, normalize payload, then alert.
  attachEventSaveBeforeRequestValidation({
    saveButton: updateEventButton,
    saveButtonId: "update-event-button",
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

/**
 * Initializes event update page roots inside a swapped fragment.
 * @param {Document|Element} [root=document] Root page container
 * @returns {void}
 */
export const initializeEventUpdatePageRoots = (root = document) => {
  initializeMatchingRoots(root, EVENT_UPDATE_PAGE_SELECTOR, initializeEventUpdatePage);
};

initializeOnReadyAndHtmxLoad(initializeEventUpdatePageRoots);
