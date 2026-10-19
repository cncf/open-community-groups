import { confirmAction, handleHtmxResponse } from "/static/js/common/alerts.js";
import { convertDateTimeLocalToISO } from "/static/js/common/datetime.js";
import { bindBooleanToggle } from "/static/js/dashboard/group/page-form-state.js";
import { buildFormsSnapshot } from "/static/js/dashboard/group/pending-changes-alert.js";
import { bindQuestionOptionsToggles } from "/static/js/dashboard/group/question-breakdown.js";

/** Id of the dashboard region replaced by dashboard navigation. */
const DASHBOARD_CONTENT_ID = "dashboard-content";

/** Selector of the surveys tab content root. */
const EVENT_SURVEYS_ROOT_SELECTOR = "[data-event-surveys-root]";

/** Names of the survey date fields sent in the database date format. */
const EVENT_SURVEY_DATE_FIELDS = ["closes_at", "opens_at"];

/** Selector of the survey editor form. */
const EVENT_SURVEY_FORM_SELECTOR = "form[data-event-survey-form]";

/** Selector of survey toggles bound to the hidden input their data attribute names. */
const EVENT_SURVEY_TOGGLE_SELECTOR = "input[type='checkbox'][data-event-survey-toggle]";

/** Confirmation shown before a request discards unsaved survey edits. */
export const UNSAVED_SURVEY_CHANGES_MESSAGE =
  "You have unsaved survey changes. If you continue, they will be lost.";

/** Whether the `beforeunload` listener is currently registered. */
let beforeUnloadBound = false;

/** Surveys tab roots whose delegated listeners are bound. */
const boundRoots = new WeakSet();

/**
 * Survey form tracked for unsaved changes; only one editor is open at a time.
 * Value changes are checked once per animation frame; `frame` holds the
 * pending check, which is flushed before any decision reads `dirty`.
 * `submittedSnapshot` holds the values of the save in flight, so edits made
 * while it runs are not taken as saved.
 * @type {{cleanup: () => void, dirty: boolean, form: HTMLFormElement, frame: number|null, ready: boolean, snapshot: string, submittedSnapshot: string|null}|null}
 */
let trackedSurveyForm = null;

/** Whether the document-level `htmx:confirm` guard is installed. */
let unsavedChangesGuardInstalled = false;

/**
 * Initializes the surveys tab of the event update page: survey forms loaded
 * into the tab are tracked for unsaved changes, their toggles and dates are
 * prepared for submission, results get their breakdown toggles, and form
 * responses are reported through alerts. The survey form is never part of
 * the event payload or its pending-changes tracking.
 * @param {Document|Element} pageRoot - Event update page root.
 * @returns {void}
 */
export const initializeEventSurveys = (pageRoot) => {
  const root = pageRoot?.querySelector?.(EVENT_SURVEYS_ROOT_SELECTOR);
  if (!(root instanceof HTMLElement) || boundRoots.has(root)) {
    return;
  }
  boundRoots.add(root);

  // Guard requests that would discard unsaved survey edits
  installUnsavedSurveyChangesGuard();
  bindQuestionOptionsToggles(root);

  // Track survey forms swapped into the tab
  root.addEventListener("htmx:load", (event) => {
    const target = event.target instanceof Element ? event.target : null;
    const form = target?.matches(EVENT_SURVEY_FORM_SELECTOR)
      ? target
      : target?.querySelector(EVENT_SURVEY_FORM_SELECTOR);
    if (form instanceof HTMLFormElement) {
      trackEventSurveyForm(form);
    }
  });
  const initialForm = root.querySelector(EVENT_SURVEY_FORM_SELECTOR);
  if (initialForm instanceof HTMLFormElement) {
    trackEventSurveyForm(initialForm);
  }

  // Send survey dates in the format the server expects
  root.addEventListener("htmx:configRequest", (event) => {
    if (isEventSurveyFormRequest(event)) {
      normalizeEventSurveyDateParameters(event.detail.parameters);
    }
  });

  // Record the values being saved, as edits may follow while the save runs
  root.addEventListener("htmx:beforeRequest", (event) => {
    if (isEventSurveyFormRequest(event)) {
      recordSubmittedSurveyValues();
    }
  });

  // Keep the saved values once accepted, before the response refreshes the tab
  root.addEventListener("htmx:beforeOnLoad", (event) => {
    if (!isEventSurveyFormRequest(event)) {
      return;
    }
    const status = event.detail?.xhr?.status ?? 0;
    acceptSubmittedSurveyValues(status >= 200 && status < 300);
  });

  // Report the outcome of survey form submissions
  root.addEventListener("htmx:afterRequest", (event) => {
    if (!isEventSurveyFormRequest(event)) {
      return;
    }
    const form = event.detail.elt;
    handleHtmxResponse({
      xhr: event.detail?.xhr,
      successMessage: form.dataset.successMessage || "",
      errorMessage:
        form.dataset.errorMessage || "Something went wrong saving the survey. Please try again later.",
    });
  });
};

/**
 * Returns whether a connected survey form has unsaved changes. A tracked form
 * removed from the page is released, so no stale reference survives it.
 * @returns {boolean}
 */
export const hasUnsavedSurveyChanges = () => {
  if (!trackedSurveyForm) {
    return false;
  }
  if (!trackedSurveyForm.form.isConnected) {
    releaseTrackedSurveyForm();
    return false;
  }
  flushUnsavedSurveyChanges(trackedSurveyForm);
  return trackedSurveyForm.dirty;
};

/**
 * Converts the survey datetime-local parameters to the server date format,
 * leaving blank values blank so they clear the dates.
 * @param {Record<string, unknown>} parameters - HTMX request parameters.
 * @returns {void}
 */
export const normalizeEventSurveyDateParameters = (parameters) => {
  if (!parameters) {
    return;
  }

  EVENT_SURVEY_DATE_FIELDS.forEach((field) => {
    const value = parameters[field];
    if (typeof value === "string" && value) {
      parameters[field] = convertDateTimeLocalToISO(value);
    }
  });
};

/**
 * Registers a survey form as the single form tracked for unsaved changes.
 * The baseline is taken once its custom editors have rendered their fields;
 * later input, change and field mutations mark it dirty while its values
 * differ from that baseline. Checks are batched per animation frame.
 * @param {HTMLFormElement} form - Survey editor form.
 * @returns {void}
 */
export const trackEventSurveyForm = (form) => {
  if (!(form instanceof HTMLFormElement) || trackedSurveyForm?.form === form) {
    return;
  }

  // Replace any previously tracked form
  releaseTrackedSurveyForm();
  bindEventSurveyToggles(form);

  // Watch the form fields for changes
  const state = {
    cleanup: () => {},
    dirty: false,
    form,
    frame: null,
    ready: false,
    snapshot: buildFormsSnapshot([form]),
    submittedSnapshot: null,
  };
  const refresh = () => scheduleUnsavedSurveyChangesRefresh(state);
  const observer = new MutationObserver(refresh);
  observer.observe(form, { attributes: true, childList: true, subtree: true });
  form.addEventListener("input", refresh);
  form.addEventListener("change", refresh);
  state.cleanup = () => {
    observer.disconnect();
    form.removeEventListener("input", refresh);
    form.removeEventListener("change", refresh);
    cancelUnsavedSurveyChangesRefresh(state);
  };
  trackedSurveyForm = state;

  // Take the baseline once custom editors render their hidden fields
  const editorUpdates = Array.from(form.querySelectorAll("questions-editor")).map(
    (editor) => editor.updateComplete || Promise.resolve(),
  );
  Promise.all(editorUpdates).then(() => {
    if (trackedSurveyForm !== state) {
      return;
    }
    cancelUnsavedSurveyChangesRefresh(state);
    state.snapshot = buildFormsSnapshot([form]);
    state.ready = true;
    refreshUnsavedSurveyChanges(state);
  });
};

/**
 * Settles the save in flight of the tracked form. Once accepted, the values
 * it sent become the baseline, so edits made while it ran stay unsaved.
 * @param {boolean} accepted - Whether the server accepted the save.
 * @returns {void}
 */
const acceptSubmittedSurveyValues = (accepted) => {
  const state = trackedSurveyForm;
  if (!state || state.submittedSnapshot === null) {
    return;
  }
  const { submittedSnapshot } = state;
  state.submittedSnapshot = null;
  if (!accepted) {
    return;
  }
  cancelUnsavedSurveyChangesRefresh(state);
  state.snapshot = submittedSnapshot;
  setUnsavedSurveyChanges(state, buildFormsSnapshot([state.form]) !== state.snapshot);
};

/**
 * Binds the survey toggles of a form to their hidden boolean inputs.
 * @param {HTMLFormElement} form - Survey editor form.
 * @returns {void}
 */
const bindEventSurveyToggles = (form) => {
  form.querySelectorAll(EVENT_SURVEY_TOGGLE_SELECTOR).forEach((toggle) => {
    const hiddenInput = form.querySelector(`#${CSS.escape(toggle.dataset.eventSurveyToggle || "")}`);
    bindBooleanToggle({ toggle, hiddenInput });
  });
};

/**
 * Drops the pending dirty check of a tracked form.
 * @param {object} state - Tracked form state.
 * @returns {void}
 */
const cancelUnsavedSurveyChangesRefresh = (state) => {
  if (state.frame === null) {
    return;
  }
  cancelAnimationFrame(state.frame);
  state.frame = null;
};

/**
 * Runs the pending dirty check of a tracked form right away, so decisions
 * include edits made in the current frame.
 * @param {object} state - Tracked form state.
 * @returns {void}
 */
const flushUnsavedSurveyChanges = (state) => {
  if (state.frame === null) {
    return;
  }
  cancelUnsavedSurveyChangesRefresh(state);
  refreshUnsavedSurveyChanges(state);
};

/**
 * Warns before browser navigation while a connected survey form is dirty.
 * @param {BeforeUnloadEvent} event - Browser unload event.
 * @returns {void}
 */
const handleBeforeUnload = (event) => {
  if (!hasUnsavedSurveyChanges()) {
    setBeforeUnloadBound(false);
    return;
  }
  event.preventDefault();
  event.returnValue = "";
};

/**
 * Asks before running a request that would remove a dirty survey form, and
 * runs it only once the user discards the edits.
 * @param {CustomEvent} event - HTMX `htmx:confirm` event.
 * @returns {void}
 */
const handleHtmxConfirm = (event) => {
  if (!hasUnsavedSurveyChanges()) {
    return;
  }

  // Let the form submit itself and requests that keep it on the page
  const { form } = trackedSurveyForm;
  const detail = event.detail || {};
  if (detail.elt === form || !swapRemovesForm(detail.target, form)) {
    return;
  }

  // Hold the request until the user decides; the edits stay guarded until
  // the swap actually removes the form, so a request cancelled before it is
  // sent (for example by form validation) keeps them protected
  event.preventDefault();
  confirmAction({
    message: UNSAVED_SURVEY_CHANGES_MESSAGE,
    confirmText: "Discard changes",
    cancelText: "Keep editing",
  }).then((confirmed) => {
    if (!confirmed) {
      return;
    }
    detail.issueRequest?.(true);
  });
};

/**
 * Installs the document-level guard once. It stays installed and does nothing
 * unless a connected dirty survey form exists.
 * @returns {void}
 */
const installUnsavedSurveyChangesGuard = () => {
  if (unsavedChangesGuardInstalled) {
    return;
  }
  unsavedChangesGuardInstalled = true;
  document.addEventListener("htmx:confirm", handleHtmxConfirm);
};

/**
 * Returns whether an HTMX lifecycle event belongs to a survey form request.
 * @param {CustomEvent} event - HTMX lifecycle event.
 * @returns {boolean}
 */
const isEventSurveyFormRequest = (event) => {
  const elt = event.detail?.elt;
  return elt instanceof HTMLFormElement && elt.matches(EVENT_SURVEY_FORM_SELECTOR);
};

/**
 * Records the values of the tracked form sent by the save starting now.
 * @returns {void}
 */
const recordSubmittedSurveyValues = () => {
  if (!trackedSurveyForm) {
    return;
  }
  trackedSurveyForm.submittedSnapshot = buildFormsSnapshot([trackedSurveyForm.form]);
};

/**
 * Updates the dirty state of a tracked form from its current values.
 * @param {object} state - Tracked form state.
 * @returns {void}
 */
const refreshUnsavedSurveyChanges = (state) => {
  if (trackedSurveyForm !== state || !state.ready) {
    return;
  }
  if (!state.form.isConnected) {
    releaseTrackedSurveyForm();
    return;
  }
  setUnsavedSurveyChanges(state, buildFormsSnapshot([state.form]) !== state.snapshot);
};

/**
 * Stops tracking the current survey form and removes the unload warning.
 * @returns {void}
 */
const releaseTrackedSurveyForm = () => {
  trackedSurveyForm?.cleanup();
  trackedSurveyForm = null;
  setBeforeUnloadBound(false);
};

/**
 * Schedules one dirty check of a tracked form for the next animation frame.
 * The unload guard is registered meanwhile so navigation in the same frame
 * still checks the pending edits.
 * @param {object} state - Tracked form state.
 * @returns {void}
 */
const scheduleUnsavedSurveyChangesRefresh = (state) => {
  if (trackedSurveyForm !== state || !state.ready || state.frame !== null) {
    return;
  }
  setBeforeUnloadBound(true);
  state.frame = requestAnimationFrame(() => {
    state.frame = null;
    refreshUnsavedSurveyChanges(state);
  });
};

/**
 * Registers or removes the `beforeunload` listener.
 * @param {boolean} bound - Whether the listener should be registered.
 * @returns {void}
 */
const setBeforeUnloadBound = (bound) => {
  if (bound === beforeUnloadBound) {
    return;
  }
  beforeUnloadBound = bound;
  if (bound) {
    window.addEventListener("beforeunload", handleBeforeUnload);
  } else {
    window.removeEventListener("beforeunload", handleBeforeUnload);
  }
};

/**
 * Sets the dirty state of a tracked form, warning on browser navigation only
 * while it is dirty.
 * @param {object} state - Tracked form state.
 * @param {boolean} dirty - Whether the form has unsaved changes.
 * @returns {void}
 */
const setUnsavedSurveyChanges = (state, dirty) => {
  state.dirty = dirty;
  setBeforeUnloadBound(dirty);
};

/**
 * Returns whether swapping a request target would remove the survey form.
 * @param {unknown} target - Resolved HTMX swap target.
 * @param {HTMLFormElement} form - Tracked survey form.
 * @returns {boolean}
 */
const swapRemovesForm = (target, form) => {
  if (!(target instanceof Element)) {
    return false;
  }
  return target === form.ownerDocument.body || target.id === DASHBOARD_CONTENT_ID || target.contains(form);
};
