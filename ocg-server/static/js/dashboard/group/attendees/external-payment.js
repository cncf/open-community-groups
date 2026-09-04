import { closestElementWithinRoot, getElementById, markDatasetReady } from "/static/js/common/dom.js";
import { isSuccessfulXHRStatus } from "/static/js/common/utils.js";
import {
  bindScopedModalEscape,
  closeScopedModalFromEvent,
  setScopedModalVisibility,
} from "/static/js/dashboard/group/attendees/shared.js";

const CLOSE_SELECTOR =
  "#close-attendee-external-payment-modal, #cancel-attendee-external-payment-modal, #overlay-attendee-external-payment-modal";
const DETAILS_ID = "attendee-external-payment-details";
const FORM_ID = "attendee-external-payment-form";
const MODAL_ID = "attendee-external-payment-modal";
const SUBMIT_ID = "submit-attendee-external-payment";
const SUMMARY_ID = "attendee-external-payment-summary";
const TRIGGER_SELECTOR = "[data-external-payment-open]";

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

  root.addEventListener("htmx:afterRequest", (event) => {
    if (event.target === getElementById(root, FORM_ID) && isSuccessfulXHRStatus(event.detail?.xhr?.status)) {
      closeExternalPaymentModal(root);
    }
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
  const summary = getElementById(root, SUMMARY_ID);
  const details = getElementById(root, DETAILS_ID);
  const url = trigger.dataset.externalPaymentUrl;
  if (!(modal instanceof HTMLElement) || !(form instanceof HTMLFormElement) || !url) {
    return;
  }

  const attendee = trigger.dataset.externalPaymentAttendee || "this attendee";
  const ticket = trigger.dataset.externalPaymentTicket || "ticket";
  const amount = trigger.dataset.externalPaymentAmount || "";
  const reference = trigger.dataset.externalPaymentReference || "";
  if (summary instanceof HTMLElement) {
    const amountText = amount ? ` (${amount})` : "";
    summary.textContent = `Mark ${ticket} for ${attendee} as paid${amountText}. Reference: ${reference}.`;
  }
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
