import "/static/js/common/actions-menu.js";
import { handleHtmxResponse, showErrorAlert, showInfoAlert } from "/static/js/common/alerts.js";
import { closestElement, getElementById, isElementHidden, markDatasetReady } from "/static/js/common/dom.js";
import { hasHtmxTrigger } from "/static/js/common/htmx-triggers.js";
import { isEscapeEvent } from "/static/js/common/keyboard.js";
import { toggleModalVisibility, trapModalFocus } from "/static/js/common/modals/modal-lifecycle.js";
import { collectQuestionAnswers, setQuestionAnswersInputValue } from "/static/js/common/question-answers.js";
import { isSuccessfulXHRStatus, parseJsonText } from "/static/js/common/utils.js";

// Maps recoverable server conflict codes to actionable offer-claim guidance.
const CLAIM_CONFLICT_MESSAGES = {
  "admission-offer-unavailable": "Ticket offer expired or is no longer available.",
  "payment-setup-unavailable":
    "Payment is temporarily unavailable for this ticket offer. Try again before the offer deadline.",
  "ticket-type-price-unavailable":
    "This ticket offer does not have a current price. Try again before the offer deadline.",
};
const DATA_KEY = "userEventOffersReady";
const REFRESH_BODY_TRIGGER = "refresh-body";

/**
 * Initializes delegated event-offer actions for the user dashboard.
 * @returns {void}
 */
const initializeUserEventOffers = () => {
  if (!markDatasetReady(document.documentElement, DATA_KEY)) {
    return;
  }

  // Document-level delegation continues to own controls after dashboard HTMX swaps.
  document.addEventListener("click", handleClick);
  document.addEventListener("htmx:afterRequest", handleAfterRequest);
  document.addEventListener("htmx:configRequest", handleConfigRequest);
  document.addEventListener("keydown", handleKeydown);
  document.addEventListener("submit", handleSubmit, true);
};

/**
 * Closes a visible offer modal and restores its trigger focus.
 * @param {Element|null} modal Offer modal.
 * @returns {void}
 */
const closeModal = (modal) => {
  if (modal instanceof HTMLElement && !isElementHidden(modal)) {
    toggleModalVisibility(modal.id);
  }
};

/**
 * Resolves the offer modal controlled by a trigger.
 * @param {HTMLElement} trigger Offer modal trigger.
 * @returns {Element|null} Controlled offer modal.
 */
const getModal = (trigger) => {
  const modalId = trigger?.dataset?.userEventOfferModal;
  return modalId ? getElementById(document, modalId) : null;
};

/**
 * Handles completed offer claims and checkout cancellations.
 * @param {Event} event HTMX after-request event.
 * @returns {void}
 */
const handleAfterRequest = (event) => {
  const target = event.target;
  if (target instanceof HTMLFormElement && target.matches("[data-user-event-offer-form]")) {
    // Resolve known offer conflicts before falling back to the shared response handler.
    const xhr = event.detail?.xhr;
    const response = parseJsonText(xhr?.responseText, {});
    const conflictMessage = CLAIM_CONFLICT_MESSAGES[response?.conflict];
    if (!isSuccessfulXHRStatus(xhr?.status) && conflictMessage) {
      if (response.conflict === "admission-offer-unavailable") {
        // Remove an unavailable offer immediately so it cannot be submitted again.
        closeModal(target.closest("[data-user-event-offer-dialog]"));
        refreshInvitations();
      }
      showErrorAlert(conflictMessage);
      return;
    }

    const ok = handleHtmxResponse({
      xhr,
      successMessage: "",
      errorMessage: "Something went wrong claiming this offer. Please try again later.",
    });
    if (!ok) {
      return;
    }

    if (response?.redirect_url) {
      // Paid claims hand control to the provider checkout page.
      window.location.assign(response.redirect_url);
      return;
    }

    closeModal(target.closest("[data-user-event-offer-dialog]"));
    if (responseRefreshesBody(xhr)) {
      // The server-triggered body refresh owns the replacement UI and feedback.
      return;
    }

    // Non-redirect claims finish locally and then refresh the invitation list.
    showInfoAlert(
      target.dataset.isSimpleRsvp === "true"
        ? "Your RSVP has been confirmed."
        : "Your ticket has been claimed.",
    );
    refreshInvitations();
    return;
  }

  if (closestElement(target, "[data-user-event-offer-checkout-cancel]")) {
    // The shared confirmation handler owns errors for confirmation-gated actions.
    if (!isSuccessfulXHRStatus(event.detail?.xhr?.status)) {
      return;
    }

    showInfoAlert("Your checkout has been canceled. The offer is ready to claim again.");
    refreshInvitations();
  }
};

/**
 * Opens and closes offer claim modals from delegated click controls.
 * @param {MouseEvent} event Click event.
 * @returns {void}
 */
const handleClick = (event) => {
  const trigger = closestElement(event.target, "[data-user-event-offer-open]");
  if (trigger instanceof HTMLElement) {
    const modal = getModal(trigger);
    if (modal instanceof HTMLElement && isElementHidden(modal)) {
      // Pass the opener so the shared lifecycle can restore focus on close.
      toggleModalVisibility(modal.id, trigger);
    }
    return;
  }

  const closeTrigger = closestElement(event.target, "[data-user-event-offer-close]");
  if (closeTrigger instanceof HTMLElement) {
    // Close buttons and modal overlays share the same delegated selector.
    closeModal(closeTrigger.closest("[data-user-event-offer-dialog]"));
  }
};

/**
 * Normalizes optional discount codes before an offer claim request.
 * @param {Event} event HTMX request configuration event.
 * @returns {void}
 */
const handleConfigRequest = (event) => {
  const form = event.target;
  if (!(form instanceof HTMLFormElement) || !form.matches("[data-user-event-offer-form]")) {
    return;
  }

  const discountCodeInput = form.elements.namedItem("discount_code");
  if (!(discountCodeInput instanceof HTMLInputElement)) {
    return;
  }

  const normalizedDiscountCode = discountCodeInput.value.trim();
  discountCodeInput.value = normalizedDiscountCode;
  if (normalizedDiscountCode) {
    // Keep filtered and unfiltered HTMX parameter views synchronized.
    event.detail.parameters.discount_code = normalizedDiscountCode;
    if (event.detail?.unfilteredParameters && typeof event.detail.unfilteredParameters === "object") {
      event.detail.unfilteredParameters.discount_code = normalizedDiscountCode;
    }
    return;
  }

  // Omit blank optional values instead of submitting whitespace.
  delete event.detail.parameters.discount_code;
  if (event.detail?.unfilteredParameters && typeof event.detail.unfilteredParameters === "object") {
    delete event.detail.unfilteredParameters.discount_code;
  }
};

/**
 * Contains focus and closes visible offer modals from keyboard input.
 * @param {KeyboardEvent} event Keyboard event.
 * @returns {void}
 */
const handleKeydown = (event) => {
  if (event.key === "Tab") {
    for (const modal of document.querySelectorAll("[data-user-event-offer-dialog]")) {
      if (modal instanceof HTMLElement && !isElementHidden(modal)) {
        trapModalFocus(event, modal);
        return;
      }
    }
    return;
  }

  if (!isEscapeEvent(event)) {
    return;
  }

  // Multiple offers can render together, but only visible modals are changed.
  document.querySelectorAll("[data-user-event-offer-dialog]").forEach((modal) => {
    closeModal(modal);
  });
};

/**
 * Validates and serializes registration answers before an offer claim.
 * @param {SubmitEvent} event Form submit event.
 * @returns {void}
 */
const handleSubmit = (event) => {
  const form = event.target;
  if (!(form instanceof HTMLFormElement) || !form.matches("[data-user-event-offer-form]")) {
    return;
  }

  const answersPayload = collectQuestionAnswers(form, {
    answerSelector: "[data-question-answer]",
  });
  if (!answersPayload) {
    // Stop the capture-phase submit before HTMX receives invalid answers.
    event.preventDefault();
    event.stopPropagation();
    return;
  }

  // Serialize the validated answers into the server-facing hidden input.
  setQuestionAnswersInputValue(form, "[data-user-event-offer-answers]", answersPayload);
};

/**
 * Refreshes the user dashboard invitations section.
 * @returns {void}
 */
const refreshInvitations = () => {
  window.htmx?.trigger?.("#dashboard-content", "refresh-user-dashboard-content");
};

/**
 * Checks whether the response delegates its refresh to the document body.
 * @param {XMLHttpRequest} xhr HTMX response.
 * @returns {boolean} Whether the response refreshes the body.
 */
const responseRefreshesBody = (xhr) => hasHtmxTrigger(xhr, REFRESH_BODY_TRIGGER);

initializeUserEventOffers();
