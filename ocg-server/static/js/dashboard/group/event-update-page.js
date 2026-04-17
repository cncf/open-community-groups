import { handleHtmxResponse, showConfirmAlert, showErrorAlert } from "/static/js/common/alerts.js";
import { convertDateTimeLocalToISO } from "/static/js/common/common.js";
import {
  clearCfsWindowValidity,
  clearSessionDateBoundsValidity,
  parseLocalDate,
  validateCfsWindow,
  validateEventDates,
  validateSessionDateBounds,
} from "/static/js/common/form-validation.js";
import { initializeTicketingWaitlistState } from "/static/js/dashboard/event/ticketing.js";
import { initializeSessionsRemovalWarning } from "/static/js/dashboard/group/event-form-helpers.js";
import {
  clearVenueFields,
  confirmVenueDataDeletion,
  hasVenueData,
  updateSectionVisibility,
} from "/static/js/dashboard/group/meeting-validations.js";
import { initializePendingChangesAlert } from "/static/js/dashboard/group/pending-changes-alert.js";
import {
  bindBooleanToggle,
  collectExistingFormIds,
  initializeSectionTabs,
} from "/static/js/dashboard/group/page-form-state.js";

const queryElementById = (root, id) => {
  if (typeof root.getElementById === "function") {
    return root.getElementById(id);
  }

  return root.querySelector(`#${id}`);
};

const resolvePageRoot = (root) => {
  if (root instanceof Element && root.matches('[data-event-page="update"]')) {
    return root;
  }

  return root.querySelector?.('[data-event-page="update"]') || root;
};

const readBooleanDataAttribute = (element, attributeName) => element?.dataset?.[attributeName] === "true";

export const initializeEventUpdatePage = (root = document) => {
  const pageRoot = resolvePageRoot(root);
  if (pageRoot instanceof HTMLElement && pageRoot.dataset.eventPageReady === "true") {
    return;
  }

  if (pageRoot instanceof HTMLElement) {
    pageRoot.dataset.eventPageReady = "true";
  }

  const queryById = (id) => queryElementById(pageRoot, id);
  const queryOne = (selector) => pageRoot.querySelector(selector);

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

  const syncSessionsDateRange = () => {
    const sessionsSection = queryOne("sessions-section");
    if (!sessionsSection) {
      return;
    }

    sessionsSection.eventStartsAt = startsAtInput?.value || "";
    sessionsSection.eventEndsAt = endsAtInput?.value || "";
    sessionsSection.requestUpdate?.();
  };

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

  if (document.body && document.body.dataset.approvedSubmissionsSyncBound !== "true") {
    document.body.dataset.approvedSubmissionsSyncBound = "true";
    document.body.addEventListener(approvedSubmissionsEvent, (event) => {
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

  const validateEventForms = () => {
    const formSections = ["details", "date-venue", "hosts-sponsors", "sessions", "payments", "cfs"];
    clearCfsWindowValidity({
      cfsStartsInput: cfsStartsAtInput,
      cfsEndsInput: cfsEndsAtInput,
    });
    clearSessionDateBoundsValidity({
      sessionForm: queryById("sessions-form"),
    });

    for (const formName of formSections) {
      const formElement = queryById(`${formName}-form`);

      if (formElement && !formElement.checkValidity()) {
        displayActiveSection(formName);
        requestAnimationFrame(() => setTimeout(() => formElement.reportValidity(), 0));
        return false;
      }
    }

    return true;
  };

  const validateSessionOnlineDetails = () => {
    const sessionsSection = queryOne("sessions-section");
    if (!sessionsSection) {
      return true;
    }

    const sessionOnlineDetails = sessionsSection.querySelectorAll("online-event-details");
    const displaySessionsSection = () => displayActiveSection("sessions");

    for (const component of sessionOnlineDetails) {
      if (!component.validate(displaySessionsSection)) {
        displaySessionsSection();
        return false;
      }
    }

    return true;
  };

  const showSessionBoundsError = () => {
    const sessionsForm = queryById("sessions-form");
    const sessionDateInputs = sessionsForm?.querySelectorAll(
      'input[name^="sessions"][name$="[starts_at]"], input[name^="sessions"][name$="[ends_at]"]',
    );
    const invalidInput = sessionDateInputs
      ? Array.from(sessionDateInputs).find((input) => !!input.validationMessage)
      : null;

    showErrorAlert(
      invalidInput?.validationMessage || "Session dates must be within the event start and end dates.",
    );
  };

  bindBooleanToggle({
    toggle: queryById("toggle_registration_required"),
    hiddenInput: queryById("registration_required"),
  });

  initializeTicketingWaitlistState(pageRoot);

  bindBooleanToggle({
    toggle: queryById("toggle_event_reminder_enabled"),
    hiddenInput: queryById("event_reminder_enabled"),
  });

  const updateCfsFields = (enabled) => {
    const isLocked = (field) => field?.dataset?.locked === "true";

    if (cfsStartsAtInput) {
      const locked = isLocked(cfsStartsAtInput);
      cfsStartsAtInput.disabled = locked || !enabled;
      cfsStartsAtInput.required = enabled && !locked;
    }
    if (cfsEndsAtInput) {
      const locked = isLocked(cfsEndsAtInput);
      cfsEndsAtInput.disabled = locked || !enabled;
      cfsEndsAtInput.required = enabled && !locked;
    }
    if (cfsDescriptionInput) {
      const locked = isLocked(cfsDescriptionInput);
      cfsDescriptionInput.disabled = locked || !enabled;
      cfsDescriptionInput.required = enabled && !locked;
    }
    if (cfsLabelsEditor) {
      cfsLabelsEditor.disabled = !enabled;
    }
  };

  if (toggleCfsEnabled) {
    if (cfsEnabledInput) {
      cfsEnabledInput.value = String(toggleCfsEnabled.checked);
    }
    updateCfsFields(toggleCfsEnabled.checked);
  }

  if (toggleCfsEnabled && !toggleCfsEnabled.disabled) {
    bindBooleanToggle({
      toggle: toggleCfsEnabled,
      hiddenInput: cfsEnabledInput,
      onChange: (enabled) => {
        clearCfsWindowValidity({
          cfsStartsInput: cfsStartsAtInput,
          cfsEndsInput: cfsEndsAtInput,
        });
        updateCfsFields(enabled);
      },
    });
  }

  if (kindSelect) {
    let previousKindValue = kindSelect.value;
    updateSectionVisibility(kindSelect.value || "");
    if (onlineEventDetails) {
      onlineEventDetails.kind = kindSelect.value;
    }

    kindSelect.addEventListener("change", async () => {
      const newValue = kindSelect.value;

      if (newValue === "virtual" && hasVenueData()) {
        const confirmed = await confirmVenueDataDeletion();
        if (!confirmed) {
          kindSelect.value = previousKindValue;
          updateSectionVisibility(kindSelect.value || "");
          if (onlineEventDetails) {
            onlineEventDetails.kind = kindSelect.value;
          }
          return;
        }
        clearVenueFields();
      }

      if (onlineEventDetails) {
        const accepted = await onlineEventDetails.trySetKind(newValue);
        if (!accepted) {
          kindSelect.value = previousKindValue;
          updateSectionVisibility(kindSelect.value || "");
          return;
        }
      }

      previousKindValue = newValue;
      updateSectionVisibility(newValue);
    });
  } else {
    updateSectionVisibility("");
  }

  let previousStartsAt = startsAtInput?.value || "";
  let previousEndsAt = endsAtInput?.value || "";

  if (startsAtInput) {
    startsAtInput.addEventListener("change", () => {
      startsAtInput.setCustomValidity("");
      clearCfsWindowValidity({
        cfsStartsInput: cfsStartsAtInput,
        cfsEndsInput: cfsEndsAtInput,
      });
      clearSessionDateBoundsValidity({
        sessionForm: queryById("sessions-form"),
      });
      syncSessionsDateRange();
    });
  }

  if (endsAtInput) {
    endsAtInput.addEventListener("change", () => {
      endsAtInput.setCustomValidity("");
      clearCfsWindowValidity({
        cfsStartsInput: cfsStartsAtInput,
        cfsEndsInput: cfsEndsAtInput,
      });
      clearSessionDateBoundsValidity({
        sessionForm: queryById("sessions-form"),
      });
      syncSessionsDateRange();
    });
  }

  if (cfsStartsAtInput) {
    cfsStartsAtInput.addEventListener("change", () => {
      cfsStartsAtInput.setCustomValidity("");
    });
  }

  if (cfsEndsAtInput) {
    cfsEndsAtInput.addEventListener("change", () => {
      cfsEndsAtInput.setCustomValidity("");
    });
  }

  if (startsAtInput && onlineEventDetails) {
    startsAtInput.addEventListener("change", async () => {
      const accepted = await onlineEventDetails.trySetStartsAt(startsAtInput.value);
      if (!accepted) {
        startsAtInput.value = previousStartsAt;
        return;
      }
      previousStartsAt = startsAtInput.value;
    });
  }

  if (endsAtInput && onlineEventDetails) {
    endsAtInput.addEventListener("change", async () => {
      const accepted = await onlineEventDetails.trySetEndsAt(endsAtInput.value);
      if (!accepted) {
        endsAtInput.value = previousEndsAt;
        return;
      }
      previousEndsAt = endsAtInput.value;
    });
  }

  if (cancelButton) {
    cancelButton.addEventListener("htmx:afterRequest", () => {
      history.pushState({}, "Events list", "/dashboard/group?tab=events");
    });
  }

  initializePendingChangesAlert({
    alertId: "pending-changes-alert",
    formIds: collectExistingFormIds(
      [
        "details-form",
        "date-venue-form",
        "hosts-sponsors-form",
        "sessions-form",
        "payments-form",
        "cfs-form",
      ],
      pageRoot,
    ),
    cancelButtonId: "cancel-button",
    confirmMessage: "You have pending changes. If you continue, unsaved changes will be lost.",
    confirmText: "Leave",
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

  updateEventButton.addEventListener("htmx:beforeRequest", (event) => {
    if (event.detail.elt.id !== "update-event-button") {
      return;
    }

    const isValid = validateEventForms();
    const eventStartsAt = parseLocalDate(startsAtInput?.value);
    const eventEndsAt = parseLocalDate(endsAtInput?.value);
    const datesValid = validateEventDates({
      startsInput: startsAtInput,
      endsInput: endsAtInput,
      allowPastDates: true,
      latestDate: isPastEvent ? new Date() : null,
      onDateSection: () => displayActiveSection("date-venue"),
    });
    const cfsValid = validateCfsWindow({
      cfsEnabledInput,
      cfsStartsInput: cfsStartsAtInput,
      cfsEndsInput: cfsEndsAtInput,
      eventStartsInput: startsAtInput,
      onDateSection: () => displayActiveSection("date-venue"),
      onCfsSection: () => displayActiveSection("cfs"),
    });

    if (!datesValid || !cfsValid) {
      event.preventDefault();
      event.stopImmediatePropagation();
      return false;
    }

    let onlineValid = true;
    if (onlineEventDetails) {
      onlineEventDetails.startsAt = startsAtInput?.value || "";
      onlineEventDetails.endsAt = endsAtInput?.value || "";
      onlineValid = onlineEventDetails.validate(displayActiveSection);
    }

    const sessionsOnlineValid = validateSessionOnlineDetails();
    const sessionBoundsValid = datesValid
      ? validateSessionDateBounds({
          eventStartsAt,
          eventEndsAt,
          sessionForm: queryById("sessions-form"),
          onSessionsSection: () => displayActiveSection("sessions"),
        })
      : true;

    if (!sessionBoundsValid) {
      showSessionBoundsError();
    }

    if (!isValid || !datesValid || !cfsValid || !onlineValid || !sessionsOnlineValid || !sessionBoundsValid) {
      event.preventDefault();
      event.stopImmediatePropagation();
      return false;
    }
  });

  updateEventButton.addEventListener("htmx:configRequest", (event) => {
    if (event.detail.elt.id !== "update-event-button") {
      return;
    }

    if (!validateEventForms()) {
      event.preventDefault();
      event.stopPropagation();
      return;
    }

    Object.keys(event.detail.parameters).forEach((key) => {
      const isEventDate = key.match(/^(starts_at|ends_at|cfs_starts_at|cfs_ends_at)$/);
      const isSessionDate = key.match(/^sessions\[\d+\]\[(starts_at|ends_at)\]$/);
      if ((isEventDate || isSessionDate) && event.detail.parameters[key]) {
        event.detail.parameters[key] = convertDateTimeLocalToISO(event.detail.parameters[key]);
      }
    });
  });

  updateEventButton.addEventListener("htmx:afterRequest", (event) => {
    if (event.detail.elt.id !== "update-event-button") {
      return;
    }

    const ok = handleHtmxResponse({
      xhr: event.detail?.xhr,
      successMessage: "You have successfully updated the event.",
      errorMessage: "Something went wrong updating the event. Please try again later.",
    });

    if (ok) {
      document.body.dispatchEvent(new CustomEvent("refresh-event-submissions"));
    }
  });
};
