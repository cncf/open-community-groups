import { confirmAction, handleHtmxResponse, showInfoAlert } from "/static/js/common/alerts.js";
import { initializeMatchingRoots, initializeOnReadyAndHtmxLoad } from "/static/js/common/dom.js";

const BODY_ID = "community-contact-body";
const DEFAULT_ERROR_MESSAGE = "Something went wrong while trying to send the email. Please try again later.";
const FILTER_INPUTS_SELECTOR = 'input[type="hidden"][name^="filters["]';
const FILTERS_CHANGED_EVENT = "contact-filters-changed";
const FILTERS_ID = "community-contact-filters";
const FORM_SELECTOR = "#community-contact-form";
const PREVIEW_ERROR_MESSAGE = "Something went wrong while loading the recipients. Please try again.";
const RECIPIENTS_CHANGED_MESSAGE = "Recipients changed, please review the updated count";
const RECIPIENTS_ID = "community-contact-recipients";
const SUBJECT_ID = "community-contact-subject";
const SUBMIT_ID = "community-contact-submit";
const SUCCESS_MESSAGE = "Email sent successfully.";
const SUMMARY_ID = "community-contact-summary";
// Tracks wired forms in memory, as a dataset marker would survive in HTMX
// history snapshots and leave restored forms without listeners
const initializedForms = new WeakSet();

/**
 * Wires the community contact form so emails are only sent for the recipients
 * summary that matches the filters on screen.
 * @param {HTMLFormElement} form Community contact form.
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

  const state = { isBusy: false, isStale: false };
  const refreshSendState = () => updateSendState({ filters, form, recipients, state, submitButton });

  // Invalidate the preview as soon as the filters change, then refresh it
  filters.addEventListener("change", () => {
    state.isStale = true;
    refreshSendState();
    recipients.setAttribute("aria-busy", "true");
    htmx.trigger(recipients, FILTERS_CHANGED_EVENT);
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
    if (state.isBusy || !isPreviewCurrent({ filters, recipients, state }) || !form.reportValidity()) {
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

    htmx.trigger(form, "confirmed");
  });

  // Report the send result, clearing the message only on success
  form.addEventListener("htmx:afterRequest", (event) => {
    if (event.target !== form) {
      return;
    }
    state.isBusy = false;
    const xhr = event.detail?.xhr;
    const ok = handleHtmxResponse({
      xhr,
      successMessage: SUCCESS_MESSAGE,
      errorMessage: xhr?.responseText || DEFAULT_ERROR_MESSAGE,
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
 * @param {Element} filters Filters container.
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
 * Clears the subject and body after a successful send, keeping the filters.
 * @param {HTMLFormElement} form Community contact form.
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
 * @param {{filters: Element, recipients: Element, state: {isStale: boolean}}} context Contact form context.
 * @returns {boolean} True when the preview is current.
 */
const isPreviewCurrent = ({ filters, recipients, state }) => {
  const summary = readSummary(recipients);
  return !state.isStale && Boolean(summary) && summary.filtersKey === buildFiltersKey(filters);
};

/**
 * Reads the recipients summary rendered by the server.
 * @param {Element} recipients Summary container.
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
 * Replaces the summary with an error message.
 * @param {Element} recipients Summary container.
 * @param {string} message Error message.
 * @returns {void}
 */
const renderPreviewError = (recipients, message) => {
  const error = document.createElement("p");
  error.className = "text-sm text-red-700";
  error.setAttribute("role", "alert");
  error.textContent = message;
  recipients.replaceChildren(error);
};

/**
 * Enables sending only for a current, non-empty preview the user can send to.
 * @param {object} context Contact form context.
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
