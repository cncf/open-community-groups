import { handleHtmxResponse } from "/static/js/common/alerts.js";
import { localizeCurrencyLabel } from "/static/js/common/currency.js";
import { closestElementWithinRoot, getElementById, markDatasetReady } from "/static/js/common/dom.js";
import { trapModalFocus } from "/static/js/common/modals/modal-lifecycle.js";
import { isSuccessfulXHRStatus } from "/static/js/common/utils.js";
import {
  bindScopedModalEscape,
  closeScopedModalFromEvent,
  setScopedModalVisibility,
} from "/static/js/dashboard/group/attendees/shared.js";

const CLOSE_SELECTOR =
  "#close-attendee-external-payment-modal, #cancel-attendee-external-payment-modal, #overlay-attendee-external-payment-modal";
const AMOUNT_ID = "attendee-external-payment-amount";
const ATTENDEE_ID = "attendee-external-payment-attendee";
const DETAILS_ID = "attendee-external-payment-details";
const FORM_ID = "attendee-external-payment-form";
const MODAL_ID = "attendee-external-payment-modal";
const REFERENCE_ID = "attendee-external-payment-reference";
const SUBMIT_ID = "submit-attendee-external-payment";
const TICKET_ID = "attendee-external-payment-ticket";
const TRIGGER_SELECTOR = "[data-external-payment-open]";
const requestUrls = new WeakMap();

/**
 * Initialize the mark-paid confirmation modal for external purchases.
 * @param {Document|Element} [root=document] Query root.
 * @returns {void}
 */
export const initializeExternalPaymentModal = (root = document) => {
  if (!(root instanceof Element) || !markDatasetReady(root, "attendeeExternalPaymentReady")) {
    return;
  }

  root.addEventListener("click", (event) => {
    const trigger = closestElementWithinRoot(event.target, TRIGGER_SELECTOR, root);
    if (trigger instanceof HTMLElement) {
      openExternalPaymentModal(trigger, root);
      return;
    }

    closeScopedModalFromEvent(event, root, CLOSE_SELECTOR, (modalRoot) =>
      closeExternalPaymentModal(modalRoot),
    );
  });

  bindScopedModalEscape(root, (modalRoot) => {
    closeExternalPaymentModal(modalRoot);
  });

  root.addEventListener("keydown", (event) => {
    if (event.key !== "Tab") {
      return;
    }

    const modal = getElementById(root, MODAL_ID);
    if (modal instanceof HTMLElement) {
      trapModalFocus(event, modal);
    }
  });

  root.addEventListener("htmx:beforeRequest", (event) => {
    const form = getElementById(root, FORM_ID);
    const xhr = event.detail?.xhr;
    if (event.target === form && xhr && typeof xhr === "object") {
      requestUrls.set(xhr, form.getAttribute("hx-post") || "");
    }
  });

  root.addEventListener("htmx:afterRequest", (event) => {
    const form = getElementById(root, FORM_ID);
    if (event.target !== form || !(form instanceof HTMLFormElement)) {
      return;
    }

    const xhr = event.detail?.xhr;
    const requestUrl =
      (xhr && typeof xhr === "object" ? requestUrls.get(xhr) : "") ||
      event.detail?.requestConfig?.path ||
      form.getAttribute("hx-post") ||
      "";
    if (requestUrl !== form.getAttribute("hx-post")) {
      return;
    }

    if (isSuccessfulXHRStatus(xhr?.status)) {
      closeExternalPaymentModal(root);
      return;
    }

    const submit = getElementById(root, SUBMIT_ID);
    if (submit instanceof HTMLButtonElement) {
      submit.disabled = false;
    }
    handleHtmxResponse({
      xhr,
      successMessage: "",
      errorMessage: "Payment could not be marked as received. Check its status and try again.",
    });
  });
};

/**
 * Hide the mark-paid modal and restore submit state.
 * @param {Document|Element} root Query root.
 * @returns {void}
 */
const closeExternalPaymentModal = (root) => {
  const form = getElementById(root, FORM_ID);
  const details = getElementById(root, DETAILS_ID);
  const submit = getElementById(root, SUBMIT_ID);

  setScopedModalVisibility(root, MODAL_ID, false);
  if (form instanceof HTMLFormElement) {
    form.removeAttribute("hx-post");
  }
  if (details instanceof HTMLTextAreaElement) {
    details.value = "";
  }
  if (submit instanceof HTMLButtonElement) {
    submit.disabled = false;
  }
};

/**
 * Open the mark-paid modal for a selected attendee purchase.
 * @param {HTMLElement} trigger Trigger button.
 * @param {Document|Element} root Query root.
 * @returns {void}
 */
const openExternalPaymentModal = (trigger, root) => {
  const modal = getElementById(root, MODAL_ID);
  const form = getElementById(root, FORM_ID);
  const details = getElementById(root, DETAILS_ID);
  const url = trigger.dataset.externalPaymentUrl;
  if (!(modal instanceof HTMLElement) || !(form instanceof HTMLFormElement) || !url) {
    return;
  }

  const attendee = trigger.dataset.externalPaymentAttendee || "this attendee";
  const ticket = trigger.dataset.externalPaymentTicket || "ticket";
  const amount = localizeCurrencyLabel(trigger.dataset.externalPaymentAmount);
  const reference = trigger.dataset.externalPaymentReference || "";
  const paymentSummary = new Map([
    [ATTENDEE_ID, attendee],
    [TICKET_ID, ticket],
    [AMOUNT_ID, amount],
    [REFERENCE_ID, reference],
  ]);
  paymentSummary.forEach((value, fieldId) => {
    const field = getElementById(root, fieldId);
    if (field instanceof HTMLElement) {
      field.textContent = value;
    }
  });
  if (details instanceof HTMLTextAreaElement) {
    details.value = "";
  }

  form.setAttribute("hx-post", url);
  if (window.htmx) {
    window.htmx.process(form);
  }

  const actionsMenuSummary = trigger.closest("[data-actions-menu]")?.querySelector("summary");
  const focusOrigin = actionsMenuSummary instanceof HTMLElement ? actionsMenuSummary : trigger;
  setScopedModalVisibility(root, MODAL_ID, true, focusOrigin);
  details?.focus();
};
