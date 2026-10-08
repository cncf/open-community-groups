import { confirmAction, handleHtmxResponse, showInfoAlert } from "/static/js/common/alerts.js";
import { initializeMatchingRoots, initializeOnReadyAndHtmxLoad } from "/static/js/common/dom.js";

const BODY_ID = "community-contact-body";
const DEFAULT_ERROR_MESSAGE = "Something went wrong while trying to send the email. Please try again later.";
const FILTER_INPUTS_SELECTOR = 'input[type="hidden"][name^="filters["]';
const FILTERS_CHANGED_EVENT = "contact-filters-changed";
const FILTERS_ID = "community-contact-filters";
const FORM_SELECTOR = "#community-contact-form";
const PREVIEW_ERROR_MESSAGE = "Something went wrong while loading the recipients. Please try again.";
const PREVIEW_RETRY_SELECTOR = "[data-contact-recipients-retry]";
const RECIPIENTS_CHANGED_MESSAGE = "Recipients changed, please review the updated count.";
const RECIPIENTS_ID = "community-contact-recipients";
const SUBJECT_ID = "community-contact-subject";
const SUBMIT_ID = "community-contact-submit";
const SUCCESS_MESSAGE = "Email sent successfully.";
const SUMMARY_ID = "community-contact-summary";
// Tracks wired forms in memory, as a dataset marker would survive in HTMX
// history snapshots and leave restored forms without listeners
const initializedForms = new WeakSet();

/**
 * Elements and state shared by the contact form handlers.
 * @typedef {object} ContactFormContext
 * @property {Element} filters - Filters container.
 * @property {HTMLFormElement} form - Community contact form.
 * @property {Element} recipients - Recipients summary container.
 * @property {{isBusy: boolean, isSending: boolean, isStale: boolean}} state - Send and preview state.
 * @property {HTMLButtonElement} submitButton - Send button.
 */

/**
 * Wires the community contact form so emails are only sent for the recipients
 * summary that matches the filters on screen.
 * @param {HTMLFormElement} form - Community contact form.
 * @returns {void}
 */
export const initializeCommunityContactForm = (form) => {
  if (initializedForms.has(form)) {
    return;
  }
  initializedForms.add(form);

  const filters = form.querySelector(`#${FILTERS_ID}`);
  const recipients = form.querySelector(`#${RECIPIENTS_ID}`);
  const submitButton = form.querySelector(`#${SUBMIT_ID}`);
  if (!filters || !recipients || !submitButton) {
    return;
  }

  const state = { isBusy: false, isSending: false, isStale: false };
  const refreshSendState = () => updateSendState({ filters, form, recipients, state, submitButton });

  // Invalidate the preview as soon as the filters change, then refresh it
  filters.addEventListener("change", () => {
    state.isStale = true;
    refreshSendState();
    requestPreview(recipients);
  });

  // Reload a failed preview, keeping focus in the summary while it is replaced
  recipients.addEventListener("click", (event) => {
    if (!event.target.closest?.(PREVIEW_RETRY_SELECTOR)) {
      return;
    }
    recipients.tabIndex = -1;
    recipients.focus();
    requestPreview(recipients);
  });

  // Accept a new preview only when it matches the filters on screen
  recipients.addEventListener("htmx:afterSwap", (event) => {
    if (event.target !== recipients) {
      return;
    }
    const summary = readSummary(recipients);
    state.isStale = !summary || summary.filtersKey !== buildFiltersKey(filters);
    if (!state.isStale) {
      recipients.removeAttribute("aria-busy");
    }
    refreshSendState();
  });

  // Keep sending disabled when the preview cannot be loaded
  const handlePreviewError = (event) => {
    if (event.target !== recipients) {
      return;
    }
    state.isStale = true;
    recipients.removeAttribute("aria-busy");
    renderPreviewError(recipients, event.detail?.xhr?.responseText?.trim() || PREVIEW_ERROR_MESSAGE);
    refreshSendState();
  };
  recipients.addEventListener("htmx:responseError", handlePreviewError);
  recipients.addEventListener("htmx:sendError", handlePreviewError);

  // Confirm the previewed audience before sending
  form.addEventListener("submit", async (event) => {
    event.preventDefault();
    if (state.isBusy || !isPreviewCurrent({ filters, recipients, state })) {
      return;
    }
    clearBlankMessageFields(form);
    if (!form.reportValidity()) {
      return;
    }

    const summary = readSummary(recipients);
    state.isBusy = true;
    refreshSendState();

    let confirmed = false;
    try {
      confirmed = await confirmAction({
        message: `Send this email to ${summary.peopleCount} group team ${summary.peopleCount === 1 ? "member" : "members"}?`,
        confirmText: "Send",
      });
    } catch {
      confirmed = false;
    }

    // Abort when the audience changed while the dialog was open
    if (
      !confirmed ||
      !isPreviewCurrent({ filters, recipients, state }) ||
      readSummary(recipients)?.filtersKey !== summary.filtersKey
    ) {
      state.isBusy = false;
      refreshSendState();
      if (confirmed) {
        showInfoAlert(RECIPIENTS_CHANGED_MESSAGE);
      }
      return;
    }

    // HTMX starts the request synchronously, so release the form when a
    // request listener cancelled it before it was sent
    htmx.trigger(form, "confirmed");
    if (!state.isSending) {
      state.isBusy = false;
      refreshSendState();
    }
  });

  // Track whether the send request actually started
  form.addEventListener("htmx:beforeRequest", (event) => {
    if (event.target === form) {
      state.isSending = true;
    }
  });

  // Report the send result, clearing the message only on success
  form.addEventListener("htmx:afterRequest", (event) => {
    if (event.target !== form) {
      return;
    }
    state.isBusy = false;
    state.isSending = false;
    const ok = handleHtmxResponse({
      xhr: event.detail?.xhr,
      successMessage: SUCCESS_MESSAGE,
      errorMessage: DEFAULT_ERROR_MESSAGE,
    });
    if (ok) {
      clearMessage(form);
    }
    refreshSendState();
  });

  refreshSendState();
};

/**
 * Builds the canonical query of the selected filters, matching the key the
 * server renders for the recipients summary.
 * @param {Element} filters - Filters container.
 * @returns {string} Form-encoded filters in document order.
 */
export const buildFiltersKey = (filters) => {
  const params = new URLSearchParams();
  filters.querySelectorAll(FILTER_INPUTS_SELECTOR).forEach((input) => {
    params.append(input.name, input.value);
  });
  return params.toString();
};

/**
 * Empties whitespace-only subject and body fields so native validation
 * reports them before the confirmation dialog opens.
 * @param {HTMLFormElement} form - Community contact form.
 * @returns {void}
 */
const clearBlankMessageFields = (form) => {
  [SUBJECT_ID, BODY_ID].forEach((id) => {
    const field = form.querySelector(`#${id}`);
    if (field && !field.value.trim()) {
      field.value = "";
    }
  });
};

/**
 * Clears the subject and body after a successful send, keeping the filters.
 * @param {HTMLFormElement} form - Community contact form.
 * @returns {void}
 */
const clearMessage = (form) => {
  [SUBJECT_ID, BODY_ID].forEach((id) => {
    const field = form.querySelector(`#${id}`);
    if (field) {
      field.value = "";
    }
  });
};

/**
 * Returns whether the summary on screen was computed for the current filters.
 * @param {Pick<ContactFormContext, "filters" | "recipients" | "state">} context - Contact form context.
 * @returns {boolean} True when the preview is current.
 */
const isPreviewCurrent = ({ filters, recipients, state }) => {
  const summary = readSummary(recipients);
  return !state.isStale && Boolean(summary) && summary.filtersKey === buildFiltersKey(filters);
};

/**
 * Reads the recipients summary rendered by the server.
 * @param {Element} recipients - Summary container.
 * @returns {{filtersKey: string, peopleCount: number}|null} Summary data.
 */
const readSummary = (recipients) => {
  const summary = recipients.querySelector(`#${SUMMARY_ID}`);
  if (!summary) {
    return null;
  }
  return {
    filtersKey: summary.dataset.filtersKey ?? "",
    peopleCount: Number.parseInt(summary.dataset.peopleCount ?? "0", 10) || 0,
  };
};

/**
 * Replaces the summary with an error message and a retry action.
 * @param {Element} recipients - Summary container.
 * @param {string} message - Error message.
 * @returns {void}
 */
const renderPreviewError = (recipients, message) => {
  const error = document.createElement("div");
  error.className = "rounded-lg border border-amber-200 bg-amber-50 px-4 py-3 text-sm/6 text-amber-900";
  const text = document.createElement("p");
  text.setAttribute("role", "alert");
  text.textContent = message;
  const retry = document.createElement("button");
  retry.type = "button";
  retry.className = "btn-primary-outline btn-mini mt-3";
  retry.dataset.contactRecipientsRetry = "";
  retry.textContent = "Retry";
  error.append(text, retry);
  recipients.replaceChildren(error);
};

/**
 * Marks the summary as loading and requests a fresh preview.
 * @param {Element} recipients - Summary container.
 * @returns {void}
 */
const requestPreview = (recipients) => {
  recipients.setAttribute("aria-busy", "true");
  htmx.trigger(recipients, FILTERS_CHANGED_EVENT);
};

/**
 * Enables sending only for a current, non-empty preview the user can send to.
 * @param {ContactFormContext} context - Contact form context.
 * @returns {void}
 */
const updateSendState = ({ filters, form, recipients, state, submitButton }) => {
  const summary = readSummary(recipients);
  const canSend =
    form.dataset.canSend === "true" &&
    !state.isBusy &&
    isPreviewCurrent({ filters, recipients, state }) &&
    summary.peopleCount > 0;
  submitButton.disabled = !canSend;
};

initializeOnReadyAndHtmxLoad((root) => {
  initializeMatchingRoots(root, FORM_SELECTOR, initializeCommunityContactForm);
});
