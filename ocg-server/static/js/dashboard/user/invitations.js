import { handleHtmxResponse, showErrorAlert, showInfoAlert } from "/static/js/common/alerts.js";
import { closestElement, getElementById, isElementHidden, markDatasetReady } from "/static/js/common/dom.js";
import { isEscapeEvent } from "/static/js/common/keyboard.js";
import { toggleModalVisibility } from "/static/js/common/modals/modal-lifecycle.js";
import { collectQuestionAnswers, setQuestionAnswersInputValue } from "/static/js/common/question-answers.js";
import { hasHtmxTrigger } from "/static/js/common/htmx-triggers.js";
import { isSuccessfulXHRStatus, parseJsonText } from "/static/js/common/utils.js";

const DATA_KEY = "userEventOffersReady";
const REFRESH_BODY_TRIGGER = "refresh-body";

const CLAIM_CONFLICT_MESSAGES = {
  "admission-offer-unavailable": "Ticket offer expired or is no longer available.",
  "payment-setup-unavailable":
    "Payment is temporarily unavailable for this ticket offer. Try again before the offer deadline.",
  "ticket-type-price-unavailable":
    "This ticket offer does not have a current price. Try again before the offer deadline.",
};

const getModal = (trigger) => {
  const modalId = trigger?.dataset?.userEventOfferModal;
  return modalId ? getElementById(document, modalId) : null;
};

const closeModal = (modal) => {
  if (modal instanceof HTMLElement && !isElementHidden(modal)) {
    toggleModalVisibility(modal.id);
  }
};

const refreshInvitations = () => {
  window.htmx?.trigger?.("#dashboard-content", "refresh-user-dashboard-content");
};

const responseRefreshesBody = (xhr) => hasHtmxTrigger(xhr, REFRESH_BODY_TRIGGER);

const handleClick = (event) => {
  const trigger = closestElement(event.target, "[data-user-event-offer-open]");
  if (trigger instanceof HTMLElement) {
    const modal = getModal(trigger);
    if (modal instanceof HTMLElement && isElementHidden(modal)) {
      toggleModalVisibility(modal.id);
    }
    return;
  }

  const closeTrigger = closestElement(event.target, "[data-user-event-offer-close]");
  if (closeTrigger instanceof HTMLElement) {
    closeModal(closeTrigger.closest("[data-user-event-offer-dialog]"));
  }
};

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
    event.detail.parameters.discount_code = normalizedDiscountCode;
    if (event.detail?.unfilteredParameters && typeof event.detail.unfilteredParameters === "object") {
      event.detail.unfilteredParameters.discount_code = normalizedDiscountCode;
    }
    return;
  }

  delete event.detail.parameters.discount_code;
  if (event.detail?.unfilteredParameters && typeof event.detail.unfilteredParameters === "object") {
    delete event.detail.unfilteredParameters.discount_code;
  }
};

const handleSubmit = (event) => {
  const form = event.target;
  if (!(form instanceof HTMLFormElement) || !form.matches("[data-user-event-offer-form]")) {
    return;
  }

  const answersPayload = collectQuestionAnswers(form, {
    answerSelector: "[data-question-answer]",
  });
  if (!answersPayload) {
    event.preventDefault();
    event.stopPropagation();
    return;
  }

  setQuestionAnswersInputValue(form, "[data-user-event-offer-answers]", answersPayload);
};

const handleAfterRequest = (event) => {
  const target = event.target;
  if (target instanceof HTMLFormElement && target.matches("[data-user-event-offer-form]")) {
    const xhr = event.detail?.xhr;
    const response = parseJsonText(xhr?.responseText, {});
    const conflictMessage = CLAIM_CONFLICT_MESSAGES[response?.conflict];
    if (!isSuccessfulXHRStatus(xhr?.status) && conflictMessage) {
      if (response.conflict === "admission-offer-unavailable") {
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
      window.location.assign(response.redirect_url);
      return;
    }

    closeModal(target.closest("[data-user-event-offer-dialog]"));
    if (responseRefreshesBody(xhr)) {
      return;
    }

    showInfoAlert(
      target.elements.namedItem("event_ticket_type_id")
        ? "Your ticket has been claimed."
        : "Your event invitation has been accepted.",
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

const handleKeydown = (event) => {
  if (!isEscapeEvent(event)) {
    return;
  }

  document.querySelectorAll("[data-user-event-offer-dialog]").forEach((modal) => {
    closeModal(modal);
  });
};

const initializeUserEventOffers = () => {
  if (!markDatasetReady(document.documentElement, DATA_KEY)) {
    return;
  }

  document.addEventListener("click", handleClick);
  document.addEventListener("htmx:configRequest", handleConfigRequest);
  document.addEventListener("submit", handleSubmit, true);
  document.addEventListener("htmx:afterRequest", handleAfterRequest);
  document.addEventListener("keydown", handleKeydown);
};

initializeUserEventOffers();
