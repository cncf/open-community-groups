import { convertDateTimeLocalToISO } from "/static/js/common/common.js";
import { handleHtmxResponse, showErrorAlert } from "/static/js/common/alerts.js";
import { getElementById, markDatasetReady } from "/static/js/common/dom.js";
import {
  clearCfsWindowValidity,
  clearSessionDateBoundsValidity,
  parseLocalDate,
  validateCfsWindow,
  validateEventDates,
  validateSessionDateBounds,
} from "/static/js/common/form-validation.js";
import { initializeEventEnrollmentState } from "/static/js/dashboard/event/ticketing.js";
import {
  clearVenueFields,
  confirmVenueDataDeletion,
  hasVenueData,
  updateSectionVisibility,
} from "/static/js/dashboard/group/meeting-validations.js";
import { collectExistingFormIds, bindBooleanToggle } from "/static/js/dashboard/group/page-form-state.js";
import { initializePendingChangesAlert } from "/static/js/dashboard/group/pending-changes-alert.js";

export const EVENT_PAGE_FORM_IDS = [
  "details-form",
  "date-venue-form",
  "hosts-sponsors-form",
  "sessions-form",
  "payments-form",
  "questions-form",
  "cfs-form",
];

/**
 * Resolves the page root for an event page bootstrap.
 * @param {Document|Element} root Query root.
 * @param {"add"|"update"} pageName Page marker value.
 * @returns {Document|Element} Page root or the provided root.
 */
const resolveEventPageRoot = (root, pageName) => {
  if (root instanceof Element && root.matches(`[data-event-page="${pageName}"]`)) {
    return root;
  }

  return root.querySelector?.(`[data-event-page="${pageName}"]`) || root;
};

/**
 * Initializes the shared root-scoped page context for an event bootstrap.
 * @param {Document|Element} root Query root.
 * @param {"add"|"update"} pageName Page marker value.
 * @returns {{pageRoot: Document|Element, queryOne: (selector: string) => Element|null}|null}
 * Shared event page context, or null when the page is already initialized.
 */
export const initializeEventPageContext = (root, pageName) => {
  const pageRoot = resolveEventPageRoot(root, pageName);
  if (pageRoot instanceof HTMLElement && !markDatasetReady(pageRoot, "eventPageReady")) {
    return null;
  }

  return {
    pageRoot,
    queryOne: (selector) => pageRoot.querySelector(selector),
  };
};

/**
 * Resolves the controls shared by add and update event pages.
 * @param {Document|Element} pageRoot Page root.
 * @returns {Object} Shared event page controls.
 */
export const resolveSharedEventPageControls = (pageRoot) => ({
  kindSelect: getElementById(pageRoot, "kind_id"),
  onlineEventDetails: getElementById(pageRoot, "online-event-details"),
  clearLocationButton: getElementById(pageRoot, "clear-location-fields"),
  toggleCfsEnabled: getElementById(pageRoot, "toggle_cfs_enabled"),
  cfsEnabledInput: getElementById(pageRoot, "cfs_enabled"),
  cfsStartsAtInput: getElementById(pageRoot, "cfs_starts_at"),
  cfsEndsAtInput: getElementById(pageRoot, "cfs_ends_at"),
  cfsDescriptionInput: getElementById(pageRoot, "cfs_description"),
  cfsLabelsEditor: getElementById(pageRoot, "cfs-labels-editor"),
  startsAtInput: getElementById(pageRoot, "starts_at"),
  endsAtInput: getElementById(pageRoot, "ends_at"),
});

/**
 * Initializes the shared form controls used by add and update event pages.
 * @param {Object} config Control initialization configuration.
 * @param {Document|Element} config.pageRoot Page root.
 * @param {(selector: string) => Element|null} config.queryOne Root selector lookup.
 * @param {(sectionName: string) => void} config.displayActiveSection Section callback.
 * @param {() => void} config.syncSessionsDateRange Sessions sync callback.
 * @param {Object} config.controls Shared event page controls.
 * @param {boolean} [config.bindDisabledCfsToggle=false] Bind disabled CFS toggles.
 * @param {(field: HTMLElement|null) => boolean} [config.isCfsFieldLocked]
 * Field lock lookup.
 * @returns {Object} Shared validation callbacks.
 */
export const initializeSharedEventPageControls = ({
  pageRoot,
  queryOne,
  displayActiveSection,
  syncSessionsDateRange,
  controls,
  bindDisabledCfsToggle = false,
  isCfsFieldLocked = () => false,
}) => {
  const {
    kindSelect,
    onlineEventDetails,
    clearLocationButton,
    toggleCfsEnabled,
    cfsEnabledInput,
    cfsStartsAtInput,
    cfsEndsAtInput,
    cfsDescriptionInput,
    cfsLabelsEditor,
    startsAtInput,
    endsAtInput,
  } = controls;

  const validationCallbacks = createEventPageValidationCallbacks({
    pageRoot,
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
    isFieldLocked: isCfsFieldLocked,
  });

  configureScopedTicketingEditors({
    pageRoot,
    queryOne,
  });

  initializeCommonEventPageToggles({
    pageRoot,
    toggleCfsEnabled,
    cfsEnabledInput,
    cfsStartsAtInput,
    cfsEndsAtInput,
    updateCfsFields,
    bindDisabledCfsToggle,
  });

  initializeEventKindField({
    kindSelect,
    onlineEventDetails,
    hasVenueData: () => hasVenueData(pageRoot),
    confirmVenueDataDeletion,
    clearVenueFields: () => clearVenueFields(pageRoot),
    updateSectionVisibility: (kind) => updateSectionVisibility(kind, pageRoot),
  });

  if (clearLocationButton) {
    clearLocationButton.addEventListener("click", () => {
      clearVenueFields(pageRoot);
    });
  }

  bindSharedEventDateFieldListeners({
    pageRoot,
    syncSessionsDateRange,
    startsAtInput,
    endsAtInput,
    cfsStartsAtInput,
    cfsEndsAtInput,
    onlineEventDetails,
  });

  return validationCallbacks;
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
const createEventPageCfsFieldUpdater = ({
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
 * Finds the first invalid form control.
 * @param {HTMLFormElement} formElement Form to inspect.
 * @returns {HTMLElement|null} Invalid form control, or null when all controls are valid.
 */
const findFirstInvalidFormControl = (formElement) => {
  const controls = Array.from(formElement.elements || []);

  return (
    controls.find((control) => {
      if (!(control instanceof HTMLElement) || typeof control.checkValidity !== "function") {
        return false;
      }

      if ("validity" in control && control.validity) {
        return !control.validity.valid;
      }

      return !control.checkValidity();
    }) || null
  );
};

/**
 * Reports native validity on a field after its section has been made visible.
 * @param {HTMLElement|HTMLFormElement} target Element that owns the validity UI.
 * @returns {void}
 */
const reportInvalidTarget = (target) => {
  const report = () => {
    if (target instanceof HTMLElement && typeof target.scrollIntoView === "function") {
      target.scrollIntoView({ behavior: "auto", block: "center" });
    }

    if (target instanceof HTMLElement && typeof target.focus === "function") {
      target.focus({ preventScroll: true });
    }

    target.reportValidity();
  };

  if (typeof requestAnimationFrame === "function") {
    requestAnimationFrame(() => setTimeout(report, 0));
  } else {
    setTimeout(report, 0);
  }
};

/**
 * Validates the common event forms and activates the first invalid section.
 * @param {Object} config Validation configuration.
 * @param {Document|Element} config.pageRoot Page root.
 * @param {string[]} config.formSections Form ids to validate.
 * @param {(sectionName: string) => void} config.displayActiveSection Section activation callback.
 * @param {HTMLInputElement|null} config.cfsStartsAtInput CFS starts input.
 * @param {HTMLInputElement|null} config.cfsEndsAtInput CFS ends input.
 * @returns {boolean} True when every existing form is valid.
 */
const validateEventFormsAcrossSections = ({
  pageRoot,
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
    sessionForm: getElementById(pageRoot, "sessions-form"),
  });

  for (const formId of formSections) {
    const formElement = getElementById(pageRoot, formId);

    if (formElement) {
      const invalidControl = findFirstInvalidFormControl(formElement);
      const invalidTarget = invalidControl || (!formElement.checkValidity() ? formElement : null);

      if (!invalidTarget) {
        continue;
      }

      displayActiveSection(formId.replace(/-form$/, ""));
      reportInvalidTarget(invalidTarget);
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
const validateSessionOnlineDetailsWidgets = ({ queryOne, displayActiveSection }) => {
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
 * @param {Document|Element} config.pageRoot Page root.
 * @param {(selector: string) => Element|null} config.queryOne Root-scoped selector lookup.
 * @param {(sectionName: string) => void} config.displayActiveSection Section activation callback.
 * @param {HTMLInputElement|null} config.cfsStartsAtInput CFS starts input.
 * @param {HTMLInputElement|null} config.cfsEndsAtInput CFS ends input.
 * @returns {{validateEventForms: () => boolean, validateSessionOnlineDetails: () => boolean, showSessionBoundsError: () => void}}
 * Shared validation callbacks.
 */
const createEventPageValidationCallbacks = ({
  pageRoot,
  queryOne,
  displayActiveSection,
  cfsStartsAtInput,
  cfsEndsAtInput,
}) => ({
  validateEventForms: () =>
    validateEventFormsAcrossSections({
      pageRoot,
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
        pageRoot,
      }),
    );
  },
});

/**
 * Resolves the most specific session bounds validation error.
 * @param {Object} config Error lookup configuration.
 * @param {Document|Element} config.pageRoot Page root.
 * @returns {string} Validation message.
 */
const getSessionBoundsErrorMessage = ({ pageRoot }) => {
  const sessionsForm = getElementById(pageRoot, "sessions-form");
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
 * @param {Document|Element} config.pageRoot Page root.
 * @param {() => void} config.syncSessionsDateRange Sessions sync callback.
 * @param {HTMLInputElement|null} config.startsAtInput Event start input.
 * @param {HTMLInputElement|null} config.endsAtInput Event end input.
 * @param {HTMLInputElement|null} config.cfsStartsAtInput CFS start input.
 * @param {HTMLInputElement|null} config.cfsEndsAtInput CFS end input.
 * @param {HTMLElement|null} config.onlineEventDetails Online event details component.
 * @returns {void}
 */
const bindSharedEventDateFieldListeners = ({
  pageRoot,
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
        sessionForm: getElementById(pageRoot, "sessions-form"),
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
        sessionForm: getElementById(pageRoot, "sessions-form"),
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
        syncSessionsDateRange();
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
        syncSessionsDateRange();
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
const convertSharedEventDateParameters = (parameters) => {
  Object.keys(parameters).forEach((key) => {
    const isEventDate = key.match(/^(starts_at|ends_at|cfs_starts_at|cfs_ends_at)$/);
    const isSessionDate = key.match(/^sessions\[\d+\]\[(starts_at|ends_at)\]$/);
    if ((isEventDate || isSessionDate) && parameters[key]) {
      parameters[key] = convertDateTimeLocalToISO(parameters[key]);
    }
  });
};

/**
 * Initializes the shared boolean toggles and enrollment state used by event pages.
 * @param {Object} config Toggle initialization configuration.
 * @param {Document|Element} config.pageRoot Page root.
 * @param {HTMLInputElement|null} config.toggleCfsEnabled CFS toggle.
 * @param {HTMLInputElement|null} config.cfsEnabledInput Hidden CFS field.
 * @param {HTMLInputElement|null} config.cfsStartsAtInput CFS starts input.
 * @param {HTMLInputElement|null} config.cfsEndsAtInput CFS ends input.
 * @param {(enabled: boolean) => void} config.updateCfsFields CFS field updater.
 * @param {boolean} [config.bindDisabledCfsToggle=false] Whether disabled CFS toggles should bind changes.
 * @returns {void}
 */
const initializeCommonEventPageToggles = ({
  pageRoot,
  toggleCfsEnabled,
  cfsEnabledInput,
  cfsStartsAtInput,
  cfsEndsAtInput,
  updateCfsFields,
  bindDisabledCfsToggle = false,
}) => {
  bindBooleanToggle({
    toggle: getElementById(pageRoot, "toggle_registration_required"),
    hiddenInput: getElementById(pageRoot, "registration_required"),
  });

  bindBooleanToggle({
    toggle: getElementById(pageRoot, "toggle_test_event"),
    hiddenInput: getElementById(pageRoot, "test_event"),
  });

  initializeEventEnrollmentState(pageRoot);

  bindBooleanToggle({
    toggle: getElementById(pageRoot, "toggle_event_reminder_enabled"),
    hiddenInput: getElementById(pageRoot, "event_reminder_enabled"),
  });

  bindBooleanToggle({
    toggle: getElementById(pageRoot, "toggle_meeting_recording_published"),
    hiddenInput: getElementById(pageRoot, "meeting_recording_published"),
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
 * Configures ticketing editors with root-scoped dependencies.
 * @param {Object} config Ticketing editor configuration.
 * @param {Document|Element} config.pageRoot Page root.
 * @param {(selector: string) => Element|null} config.queryOne Root-scoped selector lookup.
 * @returns {void}
 */
const configureScopedTicketingEditors = ({ pageRoot, queryOne }) => {
  const currencyInput = getElementById(pageRoot, "payment_currency_code");
  const timezoneInput = queryOne('[name="timezone"]');

  getElementById(pageRoot, "ticket-types-ui")?.configure?.({
    addButton: getElementById(pageRoot, "add-ticket-type-button"),
    currencyInput,
    timezoneInput,
  });

  getElementById(pageRoot, "discount-codes-ui")?.configure?.({
    addButton: getElementById(pageRoot, "add-discount-code-button"),
    currencyInput,
    timezoneInput,
  });
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
const initializeEventKindField = ({
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
 * Attaches the shared HTMX before-request validation flow for event save buttons.
 * @param {Object} config Save validation configuration.
 * @param {HTMLElement|null} config.saveButton Save button element.
 * @param {string} config.saveButtonId Expected save button id.
 * @param {() => boolean} config.validateEventForms Cross-form validation callback.
 * @param {() => boolean} config.validateSessionOnlineDetails Session online details validation callback.
 * @param {() => void} config.showSessionBoundsError Session bounds error callback.
 * @param {(sectionName: string) => void} config.displayActiveSection Section activation callback.
 * @param {Document|Element} config.pageRoot Page root.
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
  pageRoot,
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
          sessionForm: getElementById(pageRoot, "sessions-form"),
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
