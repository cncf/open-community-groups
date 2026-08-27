import { handleHtmxResponse, showErrorAlert } from "/static/js/common/alerts.js";
import { convertDateTimeLocalToISO } from "/static/js/common/datetime.js";
import { stashActiveEventSection } from "/static/js/dashboard/group/event-page/context.js";

export const EVENT_EDITOR_CREATED_FOLLOW_UP_MESSAGE =
  "The event was created. Open it from the Events list to continue editing.";
export const EVENT_EDITOR_SAVED_FOLLOW_UP_MESSAGE =
  "The event was saved. Open it from the Events list to continue editing.";

const EVENT_EDITOR_UPDATE_PATH = /\/dashboard\/group\/events\/[0-9a-fA-F-]{36}\/update(?:\?|$)/;

let followUpAfterRequestListener = null;
let followUpAfterSwapListener = null;

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
 * Disables a control so a completed mutation cannot be replayed from a stale form.
 * @param {HTMLElement|null|undefined} element Control to disable.
 * @returns {void}
 */
const disableEventMutationControl = (element) => {
  if (!(element instanceof HTMLElement)) {
    return;
  }

  element.disabled = true;
  element.setAttribute("disabled", "");
};

/**
 * Returns whether an HTMX event is the follow-up GET for the event editor.
 * @param {CustomEvent} event HTMX lifecycle event.
 * @returns {boolean}
 */
const isEventEditorFollowUpGet = (event) => {
  const requestConfig = event.detail?.requestConfig || {};
  const verb = String(requestConfig.verb || requestConfig.method || "").toLowerCase();
  const path = String(requestConfig.path || "");
  return verb === "get" && EVENT_EDITOR_UPDATE_PATH.test(path);
};

/**
 * Returns whether an HTMX request completed successfully.
 * @param {CustomEvent} event HTMX after-request event.
 * @returns {boolean}
 */
const isSuccessfulHtmxRequest = (event) => {
  if (typeof event.detail?.successful === "boolean") {
    return event.detail.successful;
  }

  const status = event.detail?.xhr?.status;
  return typeof status === "number" && status >= 200 && status < 300;
};

/**
 * Removes the one-shot follow-up GET listeners.
 * @returns {void}
 */
export const disarmEventEditorLocationFollowUp = () => {
  if (followUpAfterRequestListener) {
    document.body.removeEventListener("htmx:afterRequest", followUpAfterRequestListener);
    followUpAfterRequestListener = null;
  }

  if (followUpAfterSwapListener) {
    document.body.removeEventListener("htmx:afterSwap", followUpAfterSwapListener);
    followUpAfterSwapListener = null;
  }
};

/**
 * Arms a one-shot listener for the HTMX location GET that reloads the event editor.
 * @param {Object} config Follow-up configuration.
 * @param {boolean} [config.created=false] Whether the mutation created the event.
 * @param {Array<HTMLElement|null|undefined>} [config.controls=[]] Controls to disable on failure.
 * @returns {void}
 */
export const armEventEditorLocationFollowUp = ({ created = false, controls = [] } = {}) => {
  disarmEventEditorLocationFollowUp();

  const onFailure = () => {
    disarmEventEditorLocationFollowUp();
    controls.forEach(disableEventMutationControl);
    showErrorAlert(created ? EVENT_EDITOR_CREATED_FOLLOW_UP_MESSAGE : EVENT_EDITOR_SAVED_FOLLOW_UP_MESSAGE);
  };

  followUpAfterRequestListener = (event) => {
    if (!isEventEditorFollowUpGet(event)) {
      return;
    }

    if (!isSuccessfulHtmxRequest(event)) {
      onFailure();
    }
  };

  followUpAfterSwapListener = (event) => {
    const target = event.detail?.target || event.target;
    if (target?.id === "dashboard-content") {
      disarmEventEditorLocationFollowUp();
    }
  };

  document.body.addEventListener("htmx:afterRequest", followUpAfterRequestListener);
  document.body.addEventListener("htmx:afterSwap", followUpAfterSwapListener);
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
 * @param {boolean} [config.created=false] Whether a successful save creates the event.
 * @param {Array<HTMLElement|null|undefined>} [config.followUpControls] Controls to disable if the editor GET fails.
 * @param {() => void} [config.onSuccess] Extra success side effects.
 * @returns {void}
 */
export const attachEventSaveAfterRequest = ({
  saveButton,
  saveButtonId,
  successMessage,
  errorMessage,
  created = false,
  followUpControls,
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

    if (!ok) {
      return;
    }

    stashActiveEventSection(saveButton.closest("[data-event-page]") || document);
    if (created) {
      disableEventMutationControl(saveButton);
      queueMicrotask(() => disableEventMutationControl(saveButton));
    }

    armEventEditorLocationFollowUp({
      created,
      controls: followUpControls || [saveButton],
    });
    onSuccess();
  });
};
