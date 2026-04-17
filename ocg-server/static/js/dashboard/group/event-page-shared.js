import { convertDateTimeLocalToISO } from "/static/js/common/common.js";
import { handleHtmxResponse, showErrorAlert } from "/static/js/common/alerts.js";
import { queryElementById } from "/static/js/common/dom.js";
import {
  clearCfsWindowValidity,
  clearSessionDateBoundsValidity,
  parseLocalDate,
  validateCfsWindow,
  validateEventDates,
  validateSessionDateBounds,
} from "/static/js/common/form-validation.js";
import { initializeTicketingWaitlistState } from "/static/js/dashboard/event/ticketing.js";
import { collectExistingFormIds, bindBooleanToggle } from "/static/js/dashboard/group/page-form-state.js";
import { initializePendingChangesAlert } from "/static/js/dashboard/group/pending-changes-alert.js";

export const EVENT_PAGE_FORM_IDS = [
  "details-form",
  "date-venue-form",
  "hosts-sponsors-form",
  "sessions-form",
  "payments-form",
  "cfs-form",
];

/**
 * Resolves the page root for an event page bootstrap.
 * @param {Document|Element} root Query root.
 * @param {"add"|"update"} pageName Page marker value.
 * @returns {Document|Element} Page root or the provided root.
 */
export const resolveEventPageRoot = (root, pageName) => {
  if (root instanceof Element && root.matches(`[data-event-page="${pageName}"]`)) {
    return root;
  }

  return root.querySelector?.(`[data-event-page="${pageName}"]`) || root;
};

/**
 * Initializes the shared root-scoped page context for an event bootstrap.
 * @param {Document|Element} root Query root.
 * @param {"add"|"update"} pageName Page marker value.
 * @returns {{pageRoot: Document|Element, queryById: (id: string) => HTMLElement|null, queryOne: (selector: string) => Element|null}|null}
 * Shared event page context, or null when the page is already initialized.
 */
export const initializeEventPageContext = (root, pageName) => {
  const pageRoot = resolveEventPageRoot(root, pageName);
  if (pageRoot instanceof HTMLElement && pageRoot.dataset.eventPageReady === "true") {
    return null;
  }

  if (pageRoot instanceof HTMLElement) {
    pageRoot.dataset.eventPageReady = "true";
  }

  return {
    pageRoot,
    queryById: (id) => queryElementById(pageRoot, id),
    queryOne: (selector) => pageRoot.querySelector(selector),
  };
};

/**
 * Builds the shared CFS field enabled-state updater for event pages.
 * @param {Object} config CFS updater configuration.
 * @param {HTMLInputElement|null} config.cfsStartsAtInput CFS starts input.
 * @param {HTMLInputElement|null} config.cfsEndsAtInput CFS ends input.
 * @param {HTMLTextAreaElement|null} config.cfsDescriptionInput CFS description input.
 * @param {HTMLElement|null} config.cfsLabelsEditor CFS labels editor element.
 * @param {(field: HTMLElement|null) => boolean} [config.isFieldLocked] Locked-field lookup.
 * @returns {(enabled: boolean) => void} Shared CFS field updater.
 */
export const createEventPageCfsFieldUpdater = ({
  cfsStartsAtInput,
  cfsEndsAtInput,
  cfsDescriptionInput,
  cfsLabelsEditor,
  isFieldLocked = () => false,
}) => {
  const updateField = (field, enabled) => {
    if (!field) {
      return;
    }

    const locked = isFieldLocked(field);
    field.disabled = locked || !enabled;
    field.required = enabled && !locked;
  };

  return (enabled) => {
    updateField(cfsStartsAtInput, enabled);
    updateField(cfsEndsAtInput, enabled);
    updateField(cfsDescriptionInput, enabled);

    if (cfsLabelsEditor) {
      cfsLabelsEditor.disabled = !enabled;
    }
  };
};

/**
 * Builds a session date range sync function for sessions-section.
 * @param {Object} config Sync configuration.
 * @param {(selector: string) => Element|null} config.queryOne Root-scoped query helper.
 * @param {HTMLInputElement|null} config.startsAtInput Event start input.
 * @param {HTMLInputElement|null} config.endsAtInput Event end input.
 * @returns {() => void} Sync function.
 */
export const createSessionsDateRangeSync =
  ({ queryOne, startsAtInput, endsAtInput }) =>
  () => {
    const sessionsSection = queryOne("sessions-section");
    if (!sessionsSection) {
      return;
    }

    sessionsSection.eventStartsAt = startsAtInput?.value || "";
    sessionsSection.eventEndsAt = endsAtInput?.value || "";
    sessionsSection.requestUpdate?.();
  };

/**
 * Validates the common event forms and activates the first invalid section.
 * @param {Object} config Validation configuration.
 * @param {(id: string) => HTMLElement|null} config.queryById Root-scoped id lookup.
 * @param {string[]} config.formSections Form section names to validate.
 * @param {(sectionName: string) => void} config.displayActiveSection Section activation callback.
 * @param {HTMLInputElement|null} config.cfsStartsAtInput CFS starts input.
 * @param {HTMLInputElement|null} config.cfsEndsAtInput CFS ends input.
 * @returns {boolean} True when every existing form is valid.
 */
export const validateEventFormsAcrossSections = ({
  queryById,
  formSections,
  displayActiveSection,
  cfsStartsAtInput,
  cfsEndsAtInput,
}) => {
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

/**
 * Validates session online-event-details widgets inside sessions-section.
 * @param {Object} config Validation configuration.
 * @param {(selector: string) => Element|null} config.queryOne Root-scoped query helper.
 * @param {(sectionName: string) => void} config.displayActiveSection Section activation callback.
 * @returns {boolean} True when every session online details widget is valid.
 */
export const validateSessionOnlineDetailsWidgets = ({ queryOne, displayActiveSection }) => {
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

/**
 * Builds the shared validation callbacks used by event page bootstraps.
 * @param {Object} config Validation helper configuration.
 * @param {(id: string) => HTMLElement|null} config.queryById Root-scoped id lookup.
 * @param {(selector: string) => Element|null} config.queryOne Root-scoped selector lookup.
 * @param {(sectionName: string) => void} config.displayActiveSection Section activation callback.
 * @param {HTMLInputElement|null} config.cfsStartsAtInput CFS starts input.
 * @param {HTMLInputElement|null} config.cfsEndsAtInput CFS ends input.
 * @returns {{validateEventForms: () => boolean, validateSessionOnlineDetails: () => boolean, showSessionBoundsError: () => void}}
 * Shared validation callbacks.
 */
export const createEventPageValidationCallbacks = ({
  queryById,
  queryOne,
  displayActiveSection,
  cfsStartsAtInput,
  cfsEndsAtInput,
}) => ({
  validateEventForms: () =>
    validateEventFormsAcrossSections({
      queryById,
      formSections: EVENT_PAGE_FORM_IDS,
      displayActiveSection,
      cfsStartsAtInput,
      cfsEndsAtInput,
    }),
  validateSessionOnlineDetails: () =>
    validateSessionOnlineDetailsWidgets({
      queryOne,
      displayActiveSection,
    }),
  showSessionBoundsError: () => {
    showErrorAlert(
      getSessionBoundsErrorMessage({
        queryById,
      }),
    );
  },
});

/**
 * Resolves the most specific session bounds validation error.
 * @param {Object} config Error lookup configuration.
 * @param {(id: string) => HTMLElement|null} config.queryById Root-scoped id lookup.
 * @returns {string} Validation message.
 */
export const getSessionBoundsErrorMessage = ({ queryById }) => {
  const sessionsForm = queryById("sessions-form");
  const sessionDateInputs = sessionsForm?.querySelectorAll(
    'input[name^="sessions"][name$="[starts_at]"], input[name^="sessions"][name$="[ends_at]"]',
  );
  const invalidInput = sessionDateInputs
    ? Array.from(sessionDateInputs).find((input) => !!input.validationMessage)
    : null;

  return invalidInput?.validationMessage || "Session dates must be within the event start and end dates.";
};

/**
 * Binds the shared date and CFS field listeners used by add and update pages.
 * @param {Object} config Listener configuration.
 * @param {(id: string) => HTMLElement|null} config.queryById Root-scoped id lookup.
 * @param {() => void} config.syncSessionsDateRange Sessions sync callback.
 * @param {HTMLInputElement|null} config.startsAtInput Event start input.
 * @param {HTMLInputElement|null} config.endsAtInput Event end input.
 * @param {HTMLInputElement|null} config.cfsStartsAtInput CFS start input.
 * @param {HTMLInputElement|null} config.cfsEndsAtInput CFS end input.
 * @param {HTMLElement|null} config.onlineEventDetails Online event details component.
 * @returns {void}
 */
export const bindSharedEventDateFieldListeners = ({
  queryById,
  syncSessionsDateRange,
  startsAtInput,
  endsAtInput,
  cfsStartsAtInput,
  cfsEndsAtInput,
  onlineEventDetails,
}) => {
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
};

/**
 * Converts shared event and session datetime request parameters to ISO format.
 * @param {Record<string, string>} parameters HTMX request parameters.
 * @returns {void}
 */
export const convertSharedEventDateParameters = (parameters) => {
  Object.keys(parameters).forEach((key) => {
    const isEventDate = key.match(/^(starts_at|ends_at|cfs_starts_at|cfs_ends_at)$/);
    const isSessionDate = key.match(/^sessions\[\d+\]\[(starts_at|ends_at)\]$/);
    if ((isEventDate || isSessionDate) && parameters[key]) {
      parameters[key] = convertDateTimeLocalToISO(parameters[key]);
    }
  });
};

/**
 * Initializes the shared boolean toggles and ticketing state used by event pages.
 * @param {Object} config Toggle initialization configuration.
 * @param {Document|Element} config.pageRoot Page root.
 * @param {(id: string) => HTMLElement|null} config.queryById Root-scoped id lookup.
 * @param {HTMLInputElement|null} config.toggleCfsEnabled CFS toggle.
 * @param {HTMLInputElement|null} config.cfsEnabledInput Hidden CFS field.
 * @param {HTMLInputElement|null} config.cfsStartsAtInput CFS starts input.
 * @param {HTMLInputElement|null} config.cfsEndsAtInput CFS ends input.
 * @param {(enabled: boolean) => void} config.updateCfsFields CFS field updater.
 * @param {boolean} [config.bindDisabledCfsToggle=false] Whether disabled CFS toggles should bind changes.
 * @returns {void}
 */
export const initializeCommonEventPageToggles = ({
  pageRoot,
  queryById,
  toggleCfsEnabled,
  cfsEnabledInput,
  cfsStartsAtInput,
  cfsEndsAtInput,
  updateCfsFields,
  bindDisabledCfsToggle = false,
}) => {
  bindBooleanToggle({
    toggle: queryById("toggle_registration_required"),
    hiddenInput: queryById("registration_required"),
  });

  initializeTicketingWaitlistState(pageRoot);

  bindBooleanToggle({
    toggle: queryById("toggle_event_reminder_enabled"),
    hiddenInput: queryById("event_reminder_enabled"),
  });

  if (toggleCfsEnabled) {
    if (cfsEnabledInput) {
      cfsEnabledInput.value = String(toggleCfsEnabled.checked);
    }
    updateCfsFields(toggleCfsEnabled.checked);
  }

  if (toggleCfsEnabled && (!toggleCfsEnabled.disabled || bindDisabledCfsToggle)) {
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
};

/**
 * Initializes the shared event kind change workflow.
 * @param {Object} config Kind change configuration.
 * @param {HTMLSelectElement|null} config.kindSelect Event kind select.
 * @param {HTMLElement|null} config.onlineEventDetails Online event details component.
 * @param {() => boolean} config.hasVenueData Whether venue data exists.
 * @param {() => Promise<boolean>} config.confirmVenueDataDeletion Confirmation callback.
 * @param {() => void} config.clearVenueFields Venue clearing callback.
 * @param {(kind: string) => void} config.updateSectionVisibility Section visibility callback.
 * @returns {void}
 */
export const initializeEventKindField = ({
  kindSelect,
  onlineEventDetails,
  hasVenueData,
  confirmVenueDataDeletion,
  clearVenueFields,
  updateSectionVisibility,
}) => {
  if (!kindSelect) {
    updateSectionVisibility("");
    return;
  }

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
};

/**
 * Initializes the shared pending-changes alert for event pages.
 * @param {Object} config Pending-changes configuration.
 * @param {Document|Element} config.pageRoot Page root.
 * @param {string} config.confirmMessage Confirmation text shown on cancel.
 * @returns {void}
 */
export const initializeEventPagePendingChanges = ({ pageRoot, confirmMessage }) => {
  initializePendingChangesAlert({
    alertId: "pending-changes-alert",
    formIds: collectExistingFormIds(EVENT_PAGE_FORM_IDS, pageRoot),
    cancelButtonId: "cancel-button",
    confirmMessage,
    confirmText: "Leave",
  });
};

/**
 * Initializes the shared cancel navigation behavior for event pages.
 * @param {HTMLElement|null} cancelButton Cancel button element.
 * @returns {void}
 */
export const initializeEventPageCancelNavigation = (cancelButton) => {
  if (!cancelButton) {
    return;
  }

  cancelButton.addEventListener("htmx:afterRequest", () => {
    history.pushState({}, "Events list", "/dashboard/group?tab=events");
  });
};

/**
 * Attaches the shared HTMX before-request validation flow for event save buttons.
 * @param {Object} config Save validation configuration.
 * @param {HTMLElement|null} config.saveButton Save button element.
 * @param {string} config.saveButtonId Expected save button id.
 * @param {() => boolean} config.validateEventForms Cross-form validation callback.
 * @param {() => boolean} config.validateSessionOnlineDetails Session online details validation callback.
 * @param {() => void} config.showSessionBoundsError Session bounds error callback.
 * @param {(sectionName: string) => void} config.displayActiveSection Section activation callback.
 * @param {(id: string) => HTMLElement|null} config.queryById Root-scoped id lookup.
 * @param {HTMLInputElement|null} config.startsAtInput Event start input.
 * @param {HTMLInputElement|null} config.endsAtInput Event end input.
 * @param {HTMLInputElement|null} config.cfsEnabledInput Hidden CFS enabled input.
 * @param {HTMLInputElement|null} config.cfsStartsAtInput CFS starts input.
 * @param {HTMLInputElement|null} config.cfsEndsAtInput CFS ends input.
 * @param {HTMLElement|null} config.onlineEventDetails Online details component.
 * @param {boolean} config.allowPastDates Whether past dates are allowed.
 * @param {Date|null} [config.latestDate=null] Latest allowed date override.
 * @returns {void}
 */
export const attachEventSaveBeforeRequestValidation = ({
  saveButton,
  saveButtonId,
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
  allowPastDates,
  latestDate = null,
}) => {
  if (!saveButton) {
    return;
  }

  saveButton.addEventListener("htmx:beforeRequest", (event) => {
    if (event.detail.elt.id !== saveButtonId) {
      return;
    }

    const isValid = validateEventForms();
    const eventStartsAt = parseLocalDate(startsAtInput?.value);
    const eventEndsAt = parseLocalDate(endsAtInput?.value);
    const datesValid = validateEventDates({
      startsInput: startsAtInput,
      endsInput: endsAtInput,
      allowPastDates,
      latestDate,
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
};

/**
 * Attaches the shared HTMX config-request datetime normalization flow.
 * @param {Object} config Config-request configuration.
 * @param {HTMLElement|null} config.saveButton Save button element.
 * @param {string} config.saveButtonId Expected save button id.
 * @param {() => boolean} config.validateEventForms Cross-form validation callback.
 * @returns {void}
 */
export const attachEventSaveConfigRequest = ({ saveButton, saveButtonId, validateEventForms }) => {
  if (!saveButton) {
    return;
  }

  saveButton.addEventListener("htmx:configRequest", (event) => {
    if (event.detail.elt.id !== saveButtonId) {
      return;
    }

    if (!validateEventForms()) {
      event.preventDefault();
      event.stopPropagation();
      return;
    }

    convertSharedEventDateParameters(event.detail.parameters);
  });
};

/**
 * Attaches the shared HTMX after-request save response handling.
 * @param {Object} config After-request configuration.
 * @param {HTMLElement|null} config.saveButton Save button element.
 * @param {string} config.saveButtonId Expected save button id.
 * @param {string} config.successMessage Success alert copy.
 * @param {string} config.errorMessage Error alert copy.
 * @param {() => void} [config.onSuccess] Extra success side effects.
 * @returns {void}
 */
export const attachEventSaveAfterRequest = ({
  saveButton,
  saveButtonId,
  successMessage,
  errorMessage,
  onSuccess = () => {},
}) => {
  if (!saveButton) {
    return;
  }

  saveButton.addEventListener("htmx:afterRequest", (event) => {
    if (event.detail.elt.id !== saveButtonId) {
      return;
    }

    const ok = handleHtmxResponse({
      xhr: event.detail?.xhr,
      successMessage,
      errorMessage,
    });

    if (ok) {
      onSuccess();
    }
  });
};
