import { handleHtmxResponse, showErrorAlert } from "/static/js/common/alerts.js";
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
  if (root instanceof Element && root.matches('[data-event-page="add"]')) {
    return root;
  }

  return root.querySelector?.('[data-event-page="add"]') || root;
};

export const initializeEventAddPage = (root = document) => {
  const pageRoot = resolvePageRoot(root);
  if (pageRoot instanceof HTMLElement && pageRoot.dataset.eventPageReady === "true") {
    return;
  }

  if (pageRoot instanceof HTMLElement) {
    pageRoot.dataset.eventPageReady = "true";
  }

  const queryById = (id) => queryElementById(pageRoot, id);
  const queryOne = (selector) => pageRoot.querySelector(selector);

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

  const syncSessionsDateRange = () => {
    const sessionsSection = queryOne("sessions-section");
    if (!sessionsSection) {
      return;
    }

    sessionsSection.eventStartsAt = startsAtInput?.value || "";
    sessionsSection.eventEndsAt = endsAtInput?.value || "";
    sessionsSection.requestUpdate?.();
  };

  const { displayActiveSection } = initializeSectionTabs({
    root: pageRoot,
    onSectionChange: (sectionName) => {
      if (sectionName === "sessions") {
        syncSessionsDateRange();
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
    if (cfsStartsAtInput) {
      cfsStartsAtInput.disabled = !enabled;
      cfsStartsAtInput.required = enabled;
    }
    if (cfsEndsAtInput) {
      cfsEndsAtInput.disabled = !enabled;
      cfsEndsAtInput.required = enabled;
    }
    if (cfsDescriptionInput) {
      cfsDescriptionInput.disabled = !enabled;
      cfsDescriptionInput.required = enabled;
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
    confirmMessage:
      "You have pending changes for this new event. If you continue, this event will not be created.",
    confirmText: "Leave",
  });

  if (!addEventButton) {
    return;
  }

  initializeSessionsRemovalWarning({
    saveButton: addEventButton,
  });

  addEventButton.addEventListener("htmx:beforeRequest", (event) => {
    if (event.detail.elt.id !== "add-event-button") {
      return;
    }

    const isValid = validateEventForms();
    const eventStartsAt = parseLocalDate(startsAtInput?.value);
    const eventEndsAt = parseLocalDate(endsAtInput?.value);
    const datesValid = validateEventDates({
      startsInput: startsAtInput,
      endsInput: endsAtInput,
      allowPastDates: false,
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

  addEventButton.addEventListener("htmx:configRequest", (event) => {
    if (event.detail.elt.id !== "add-event-button") {
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

  addEventButton.addEventListener("htmx:afterRequest", (event) => {
    if (event.detail.elt.id !== "add-event-button") {
      return;
    }

    handleHtmxResponse({
      xhr: event.detail?.xhr,
      successMessage: "You have successfully created the event.",
      errorMessage: "Something went wrong creating the event. Please try again later.",
    });
  });
};
