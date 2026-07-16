import { getElementById } from "/static/js/common/dom.js";
import {
  clearCfsWindowValidity,
  clearRegistrationWindowValidity,
  clearSessionDateBoundsValidity,
} from "/static/js/common/form-validation.js";
import { initializeEventEnrollmentState } from "/static/js/dashboard/event/ticketing.js";
import {
  clearVenueFields,
  confirmVenueDataDeletion,
  hasVenueData,
  updateSectionVisibility,
} from "/static/js/dashboard/group/meeting-validations.js";
import { bindBooleanToggle } from "/static/js/dashboard/group/page-form-state.js";
import { createEventPageValidationCallbacks } from "/static/js/dashboard/group/event-page/validation.js";

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
    registrationStartsAtInput,
    registrationEndsAtInput,
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
    registrationStartsAtInput,
    registrationEndsAtInput,
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
 * @param {(field: HTMLElement|null) => boolean} [config.isFieldLocked]
 * Locked-field lookup.
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
 * Binds the shared date and CFS field listeners used by add and update pages.
 * @param {Object} config Listener configuration.
 * @param {Document|Element} config.pageRoot Page root.
 * @param {() => void} config.syncSessionsDateRange Sessions sync callback.
 * @param {HTMLInputElement|null} config.startsAtInput Event start input.
 * @param {HTMLInputElement|null} config.endsAtInput Event end input.
 * @param {HTMLInputElement|null} config.registrationStartsAtInput
 * Registration start input.
 * @param {HTMLInputElement|null} config.registrationEndsAtInput Registration end input.
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
  registrationStartsAtInput,
  registrationEndsAtInput,
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
      clearRegistrationWindowValidity({
        registrationStartsInput: registrationStartsAtInput,
        registrationEndsInput: registrationEndsAtInput,
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
      clearRegistrationWindowValidity({
        registrationStartsInput: registrationStartsAtInput,
        registrationEndsInput: registrationEndsAtInput,
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

  if (registrationStartsAtInput) {
    registrationStartsAtInput.addEventListener("change", () => {
      clearRegistrationWindowValidity({
        registrationStartsInput: registrationStartsAtInput,
        registrationEndsInput: registrationEndsAtInput,
      });
    });
  }

  if (registrationEndsAtInput) {
    registrationEndsAtInput.addEventListener("change", () => {
      clearRegistrationWindowValidity({
        registrationStartsInput: registrationStartsAtInput,
        registrationEndsInput: registrationEndsAtInput,
      });
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
 * Initializes the shared boolean toggles and enrollment state used by event pages.
 * @param {Object} config Toggle initialization configuration.
 * @param {Document|Element} config.pageRoot Page root.
 * @param {HTMLInputElement|null} config.toggleCfsEnabled CFS toggle.
 * @param {HTMLInputElement|null} config.cfsEnabledInput Hidden CFS field.
 * @param {HTMLInputElement|null} config.cfsStartsAtInput CFS starts input.
 * @param {HTMLInputElement|null} config.cfsEndsAtInput CFS ends input.
 * @param {(enabled: boolean) => void} config.updateCfsFields CFS field updater.
 * @param {boolean} [config.bindDisabledCfsToggle=false]
 * Whether disabled CFS toggles should bind changes.
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
 * @param {(selector: string) => Element|null} config.queryOne
 * Root-scoped selector lookup.
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
 * @param {(kind: string) => void} config.updateSectionVisibility
 * Section visibility callback.
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
