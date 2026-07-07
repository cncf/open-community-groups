import { handleHtmxResponse } from "/static/js/common/alerts.js";
import { convertDateTimeLocalToISO } from "/static/js/common/datetime.js";

/**
 * Converts shared event and session datetime request parameters to ISO format.
 * @param {Record<string, string>} parameters HTMX request parameters.
 * @returns {void}
 */
const convertSharedEventDateParameters = (parameters) => {
  Object.keys(parameters).forEach((key) => {
    const isEventDate = key.match(
      /^(starts_at|ends_at|registration_starts_at|registration_ends_at|cfs_starts_at|cfs_ends_at)$/,
    );
    const isSessionDate = key.match(/^sessions\[\d+\]\[(starts_at|ends_at)\]$/);
    if ((isEventDate || isSessionDate) && parameters[key]) {
      parameters[key] = convertDateTimeLocalToISO(parameters[key]);
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
