import { showErrorAlert } from "/static/js/common/alerts.js";
import { getElementById } from "/static/js/common/dom.js";
import {
  clearCfsWindowValidity,
  clearSessionDateBoundsValidity,
  parseLocalDate,
  validateCfsWindow,
  validateEventDates,
  validateRegistrationWindow,
  validateSessionDateBounds,
} from "/static/js/common/form-validation.js";
import { EVENT_PAGE_FORM_IDS } from "/static/js/dashboard/group/event-page/context.js";

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
export const createEventPageValidationCallbacks = ({
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
 * @param {HTMLInputElement|null} config.registrationStartsAtInput Registration start input.
 * @param {HTMLInputElement|null} config.registrationEndsAtInput Registration end input.
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
  registrationStartsAtInput,
  registrationEndsAtInput,
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
    const registrationWindowValid = validateRegistrationWindow({
      registrationStartsInput: registrationStartsAtInput,
      registrationEndsInput: registrationEndsAtInput,
      eventStartsInput: startsAtInput,
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

    if (!datesValid || !registrationWindowValid || !cfsValid) {
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

    if (
      !isValid ||
      !datesValid ||
      !registrationWindowValid ||
      !cfsValid ||
      !onlineValid ||
      !sessionsOnlineValid ||
      !sessionBoundsValid
    ) {
      event.preventDefault();
      event.stopImmediatePropagation();
      return false;
    }
  });
};
