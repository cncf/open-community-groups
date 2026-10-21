import { confirmAction, handleHtmxResponse } from "/static/js/common/alerts.js";
import { convertDateTimeLocalToISO, toDateTimeLocalInTimezone } from "/static/js/common/datetime.js";
import { isForcedDeploymentRefresh } from "/static/js/common/deployment-version.js";
import { closestElementWithinRoot, getElementById, isElementHidden } from "/static/js/common/dom.js";
import { isEscapeEvent } from "/static/js/common/keyboard.js";
import { toggleModalVisibility, trapModalFocus } from "/static/js/common/modals/modal-lifecycle.js";
import { bindBooleanToggle } from "/static/js/dashboard/group/page-form-state.js";
import { trackFormChanges } from "/static/js/dashboard/group/pending-changes-alert.js";
import { bindQuestionOptionsToggles } from "/static/js/dashboard/group/question-breakdown.js";

/** Id of the dashboard region replaced by dashboard navigation. */
const DASHBOARD_CONTENT_ID = "dashboard-content";

/** Selector of an element only the surveys list renders. */
const EVENT_SURVEYS_LIST_SELECTOR = "[data-event-surveys-count]";

/** Selector of the loading state shown until the surveys list first loads. */
const EVENT_SURVEYS_LOADING_SELECTOR = "#surveys-loading";

/** Body event that reloads the surveys list into the tab. */
const EVENT_SURVEYS_REFRESH_EVENT = "refresh-event-surveys";

/** Selector of the surveys tab content root. */
const EVENT_SURVEYS_ROOT_SELECTOR = "[data-event-surveys-root]";

/** Selector of the surveys section tab. */
const EVENT_SURVEYS_TAB_SELECTOR = "[data-section='surveys']";

/** Names of the survey date fields sent in the database date format. */
const EVENT_SURVEY_DATE_FIELDS = ["closes_at", "opens_at"];

/** Selector of the survey editor form. */
const EVENT_SURVEY_FORM_SELECTOR = "form[data-event-survey-form]";

/**
 * Modals of the survey results views, each loaded by HTMX into its content
 * container: the respondent responses of the Individual view and the
 * free-text answers of the Summary view.
 * @type {ReadonlyArray<{closeSelector: string, contentId: string, initialFocusSelector?: string, modalId: string, navAttribute: string}>}
 */
const EVENT_SURVEY_MODALS = [
  {
    closeSelector: "[data-event-survey-response-close]",
    contentId: "event-survey-response-modal-content",
    modalId: "event-survey-response-modal",
    navAttribute: "data-event-survey-response-nav",
  },
  {
    closeSelector: "[data-event-survey-text-answers-close]",
    contentId: "event-survey-text-answers-modal-content",
    initialFocusSelector: "#event-survey-text-answers-search",
    modalId: "event-survey-text-answers-modal",
    navAttribute: "data-event-survey-text-answers-nav",
  },
];

/** Selector of survey toggles bound to the hidden input their data attribute names. */
const EVENT_SURVEY_TOGGLE_SELECTOR = "input[type='checkbox'][data-event-survey-toggle]";

/** Confirmation shown before a request discards unsaved survey edits. */
export const UNSAVED_SURVEY_CHANGES_MESSAGE =
  "You have unsaved survey changes. If you continue, they will be lost.";

/** Whether the `beforeunload` listener is currently registered. */
let beforeUnloadBound = false;

/** Surveys tab roots whose delegated listeners are bound. */
const boundRoots = new WeakSet();

/** Whether the document-level guard closing removed survey modals is installed. */
let modalRemovalGuardInstalled = false;

/**
 * Survey form tracked for unsaved changes; only one editor is open at a time.
 * Its tracker checks value changes once per animation frame, and the pending
 * check is flushed before any decision reads the dirty state.
 * `submittedSnapshot` holds the values of the save in flight, so edits made
 * while it runs are not taken as saved.
 * @type {{form: HTMLFormElement, submittedSnapshot: string|null, tracker: import("/static/js/dashboard/group/pending-changes-alert.js").FormChangesTracker}|null}
 */
let trackedSurveyForm = null;

/** Whether the document-level `htmx:confirm` guard is installed. */
let unsavedChangesGuardInstalled = false;

/**
 * Initializes the surveys tab of the event update page: survey forms loaded
 * into the tab are tracked for unsaved changes, their toggles and dates are
 * prepared for submission, results get their breakdown toggles, respondent
 * responses and free-text answers open in modals that close before a swap
 * removes them, and form responses are reported through alerts. The survey form is never part of the event
 * payload or its pending-changes tracking.
 * @param {Document|Element} pageRoot - Event update page root.
 * @returns {void}
 */
export const initializeEventSurveys = (pageRoot) => {
  const root = pageRoot?.querySelector?.(EVENT_SURVEYS_ROOT_SELECTOR);
  if (!(root instanceof HTMLElement) || boundRoots.has(root)) {
    return;
  }
  boundRoots.add(root);

  // Guard requests that would discard unsaved survey edits or open modals
  installUnsavedSurveyChangesGuard();
  installEventSurveyModalRemovalGuard();
  bindQuestionOptionsToggles(root);
  EVENT_SURVEY_MODALS.forEach((config) => bindEventSurveyModal(root, config));

  // Go back to the list when the active surveys tab is clicked again. It
  // runs before the section tabs mark the clicked tab active
  pageRoot.addEventListener(
    "click",
    (event) => {
      const tab = event.target instanceof Element ? event.target.closest(EVENT_SURVEYS_TAB_SELECTOR) : null;
      if (tab?.getAttribute("data-active") === "true" && isSurveyViewShown(root)) {
        document.body.dispatchEvent(new CustomEvent(EVENT_SURVEYS_REFRESH_EVENT));
      }
    },
    true,
  );

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

  // Flag survey dates the server would reject, so Save reports them inline
  ["change", "input"].forEach((type) => {
    root.addEventListener(type, (event) => {
      const input = event.target;
      if (
        input instanceof HTMLInputElement &&
        EVENT_SURVEY_DATE_FIELDS.includes(input.name) &&
        input.form?.matches(EVENT_SURVEY_FORM_SELECTOR)
      ) {
        validateEventSurveyDates(input.form);
      }
    });
  });

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

  // Keep the saved values once accepted, before the response refreshes the tab.
  // A new-version intercept never ran the save, so the edits stay unsaved
  root.addEventListener("htmx:beforeOnLoad", (event) => {
    if (!isEventSurveyFormRequest(event)) {
      return;
    }
    const xhr = event.detail?.xhr;
    const status = xhr?.status ?? 0;
    acceptSubmittedSurveyValues(status >= 200 && status < 300 && !isForcedDeploymentRefresh(xhr));
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
  trackedSurveyForm.tracker.flush();
  return trackedSurveyForm?.tracker.isDirty() ?? false;
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
 * later field edits mark it dirty while its values differ from that baseline.
 * Checks are batched per animation frame.
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

  // Watch the form fields once custom editors render their hidden fields
  const editorUpdates = Array.from(form.querySelectorAll("questions-editor")).map(
    (editor) => editor.updateComplete || Promise.resolve(),
  );
  const state = { form, submittedSnapshot: null, tracker: null };
  state.tracker = trackFormChanges({
    forms: [form],
    onCheck: (dirty) => updateUnsavedSurveyChanges(state, dirty),
    onCheckScheduled: () => setBeforeUnloadBound(true),
    ready: Promise.all(editorUpdates),
  });
  trackedSurveyForm = state;
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
  state.tracker.setBaseline(submittedSnapshot);
};

/**
 * Opens a survey results modal once its content loads, keeps focus on the
 * navigation control after moving between pages of content, brings focus
 * back into it when the swap removed the focused control, keeps Tab
 * navigation inside the open modal, and closes it from its close controls,
 * its overlay and Escape. Closing restores focus to the control that opened
 * it, and content requested from inside the modal is dropped once the modal
 * was closed while the request ran, so it never opens again unasked.
 * @param {HTMLElement} root - Surveys tab content root.
 * @param {(typeof EVENT_SURVEY_MODALS)[number]} config - Modal contract.
 * @returns {void}
 */
const bindEventSurveyModal = (root, config) => {
  // Drop content requested from inside a modal closed while it loaded
  root.addEventListener("htmx:beforeSwap", (event) => {
    if (event.detail?.target?.id !== config.contentId) {
      return;
    }
    const modal = getElementById(document, config.modalId);
    const trigger = event.detail?.requestConfig?.elt;
    if (
      modal instanceof HTMLElement &&
      isElementHidden(modal) &&
      trigger instanceof Node &&
      modal.contains(trigger)
    ) {
      event.detail.shouldSwap = false;
    }
  });

  // Open the modal, or keep focus in it, once its content is loaded
  root.addEventListener("htmx:afterSwap", (event) => {
    if (event.detail?.target?.id !== config.contentId) {
      return;
    }
    const modal = getElementById(document, config.modalId);
    if (!(modal instanceof HTMLElement)) {
      return;
    }
    const trigger = event.detail?.requestConfig?.elt;
    if (isElementHidden(modal)) {
      toggleModalVisibility(modal, trigger instanceof HTMLElement ? trigger : null);
      focusEventSurveyModalEntry(modal, config);
      return;
    }
    focusEventSurveyModalNavigation(modal, trigger, config);
    recoverEventSurveyModalFocus(modal, config);
  });

  // Close the modal from its close controls and overlay
  root.addEventListener("click", (event) => {
    if (closestElementWithinRoot(event.target, config.closeSelector, root)) {
      closeEventSurveyModal(config.modalId);
    }
  });

  // Trap Tab inside the open modal and close it on Escape
  root.addEventListener("keydown", (event) => {
    const modal = getElementById(document, config.modalId);
    if (!(modal instanceof HTMLElement) || isElementHidden(modal)) {
      return;
    }
    if (event.key === "Tab") {
      trapModalFocus(event, modal);
    } else if (isEscapeEvent(event)) {
      closeEventSurveyModal(config.modalId);
    }
  });
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
 * Closes a survey results modal when it is open.
 * @param {string} modalId - Id of the modal.
 * @returns {void}
 */
const closeEventSurveyModal = (modalId) => {
  const modal = getElementById(document, modalId);
  if (modal instanceof HTMLElement && !isElementHidden(modal)) {
    toggleModalVisibility(modal);
  }
};

/**
 * Closes the open survey results modals a swap is about to remove, such as
 * when a respondents search lands after a respondent's responses opened, so
 * the body scroll lock and the focus origin are released with them.
 * @param {CustomEvent} event - HTMX `htmx:beforeSwap` event.
 * @returns {void}
 */
const closeEventSurveyModalsRemovedBySwap = (event) => {
  const target = event.detail?.target;
  if (!(target instanceof Element) || event.detail?.shouldSwap === false) {
    return;
  }
  EVENT_SURVEY_MODALS.forEach(({ modalId }) => {
    const modal = getElementById(document, modalId);
    if (modal instanceof HTMLElement && target.contains(modal)) {
      closeEventSurveyModal(modalId);
    }
  });
};

/**
 * Moves focus to the entry point of a survey results modal just opened, when
 * its contract names one, such as the search box of the free-text answers.
 * @param {HTMLElement} modal - Open survey results modal.
 * @param {(typeof EVENT_SURVEY_MODALS)[number]} config - Modal contract.
 * @returns {void}
 */
const focusEventSurveyModalEntry = (modal, config) => {
  if (!config.initialFocusSelector) {
    return;
  }
  const entry = modal.querySelector(config.initialFocusSelector);
  if (entry instanceof HTMLElement) {
    entry.focus();
  }
};

/**
 * Moves focus to the navigation button of the content just loaded, in the
 * direction the user navigated, or to the footer close button when nothing
 * remains in that direction.
 * @param {HTMLElement} modal - Open survey results modal.
 * @param {unknown} trigger - Element that requested the content.
 * @param {(typeof EVENT_SURVEY_MODALS)[number]} config - Modal contract.
 * @returns {void}
 */
const focusEventSurveyModalNavigation = (modal, trigger, config) => {
  const direction = trigger instanceof Element ? trigger.getAttribute(config.navAttribute) : null;
  if (!direction) {
    return;
  }
  const button = modal.querySelector(`[${config.navAttribute}="${direction}"]`);
  const target =
    button instanceof HTMLButtonElement && !button.disabled
      ? button
      : Array.from(modal.querySelectorAll(`button${config.closeSelector}`)).at(-1);
  if (target instanceof HTMLElement) {
    target.focus();
  }
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
 * Installs the document-level guard closing survey results modals removed by
 * a swap once. It covers swaps requested from anywhere on the page and does
 * nothing while no survey modal is open.
 * @returns {void}
 */
const installEventSurveyModalRemovalGuard = () => {
  if (modalRemovalGuardInstalled) {
    return;
  }
  modalRemovalGuardInstalled = true;
  document.addEventListener("htmx:beforeSwap", closeEventSurveyModalsRemovedBySwap);
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
 * Returns whether the tab shows a survey form, results or responses instead
 * of the list or its first load.
 * @param {HTMLElement} root - Surveys tab content root.
 * @returns {boolean}
 */
const isSurveyViewShown = (root) =>
  !root.querySelector(EVENT_SURVEYS_LIST_SELECTOR) && !root.querySelector(EVENT_SURVEYS_LOADING_SELECTOR);

/**
 * Records the values of the tracked form sent by the save starting now.
 * @returns {void}
 */
const recordSubmittedSurveyValues = () => {
  if (!trackedSurveyForm) {
    return;
  }
  trackedSurveyForm.submittedSnapshot = trackedSurveyForm.tracker.snapshot();
};

/**
 * Moves focus back into an open survey results modal when the swap removed
 * the focused control, such as the clear button of the answers search, so Tab
 * stays trapped and Escape keeps closing it. Focus goes to the modal entry
 * point when its contract names one, or to the footer close button.
 * @param {HTMLElement} modal - Open survey results modal.
 * @param {(typeof EVENT_SURVEY_MODALS)[number]} config - Modal contract.
 * @returns {void}
 */
const recoverEventSurveyModalFocus = (modal, config) => {
  if (modal.contains(document.activeElement)) {
    return;
  }
  const entry = config.initialFocusSelector ? modal.querySelector(config.initialFocusSelector) : null;
  const target =
    entry instanceof HTMLElement
      ? entry
      : Array.from(modal.querySelectorAll(`button${config.closeSelector}`)).at(-1);
  if (target instanceof HTMLElement) {
    target.focus();
  }
};

/**
 * Stops tracking the current survey form and removes the unload warning.
 * @returns {void}
 */
const releaseTrackedSurveyForm = () => {
  trackedSurveyForm?.tracker.destroy();
  trackedSurveyForm = null;
  setBeforeUnloadBound(false);
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

/**
 * Applies the result of a dirty check of a tracked form, warning on browser
 * navigation only while it is dirty. A form removed from the page is released.
 * @param {object} state - Tracked form state.
 * @param {boolean} dirty - Whether the form has unsaved changes.
 * @returns {void}
 */
const updateUnsavedSurveyChanges = (state, dirty) => {
  if (trackedSurveyForm !== state) {
    return;
  }
  if (!state.form.isConnected) {
    releaseTrackedSurveyForm();
    return;
  }
  setBeforeUnloadBound(dirty);
};

/**
 * Validates the survey closing date against the current time in the event
 * timezone and the opening date. A stored closing date that was not changed
 * is accepted, so closed surveys stay editable.
 * @param {HTMLFormElement} form - Survey editor form.
 * @returns {void}
 */
const validateEventSurveyDates = (form) => {
  const opensInput = form.elements.namedItem("opens_at");
  const closesInput = form.elements.namedItem("closes_at");
  if (!(opensInput instanceof HTMLInputElement) || !(closesInput instanceof HTMLInputElement)) {
    return;
  }

  // Compare local event times at minute precision
  const closesAt = closesInput.value.slice(0, 16);
  const opensAt = opensInput.value.slice(0, 16);
  const now = toDateTimeLocalInTimezone(new Date().toISOString(), form.dataset.eventTimezone || "");
  let message = "";
  if (closesAt && closesInput.value !== closesInput.defaultValue && closesAt <= now) {
    message = "Closing date must be in the future.";
  } else if (closesAt && opensAt && closesAt <= opensAt) {
    message = "Closing date must be after the opening date.";
  }
  closesInput.setCustomValidity(message);
};
