import {
  closestElementWithinRoot,
  getElementById,
  markDatasetReady,
  setElementHidden,
} from "/static/js/common/dom.js";
import { isSuccessfulXHRStatus } from "/static/js/common/utils.js";
import {
  bindScopedModalEscape,
  closeScopedModalFromEvent,
  setScopedModalVisibility,
} from "/static/js/dashboard/group/attendees/shared.js";

const refundModalId = "attendee-refund-modal";
const refundApproveButtonId = "attendee-refund-approve";
const refundRejectButtonId = "attendee-refund-reject";

/**
 * Resolve the current refund review modal controls from the latest DOM.
 * @param {Document|Element} [root=document] Query root.
 * @returns {Object} Refund modal controls.
 */
const getRefundReviewControls = (root = document) => ({
  modal: getElementById(root, refundModalId),
  nameField: getElementById(root, "attendee-refund-name"),
  ticketField: getElementById(root, "attendee-refund-ticket"),
  amountField: getElementById(root, "attendee-refund-amount"),
  approveButton: getElementById(root, refundApproveButtonId),
  rejectButton: getElementById(root, refundRejectButtonId),
});

/**
 * Show the refund review modal if it is currently hidden.
 * @param {Document|Element} [root=document] Query root.
 * @returns {void}
 */
const openRefundModal = (root = document) => {
  setScopedModalVisibility(root, refundModalId, true);
};

/**
 * Hide the refund review modal if it is currently visible.
 * @param {Document|Element} [root=document] Query root.
 * @returns {void}
 */
const closeRefundModal = (root = document) => {
  setScopedModalVisibility(root, refundModalId, false);
};

/**
 * Update a refund modal action button label.
 * @param {HTMLElement|null} button Action button.
 * @param {string} label Button label.
 * @returns {void}
 */
const setRefundActionLabel = (button, label) => {
  const labelNode = button?.querySelector("[data-refund-action-label]");
  if (labelNode) {
    labelNode.textContent = label;
    return;
  }

  if (button) {
    button.textContent = label;
  }
};

/**
 * Re-process a refund action button after its HTMX attributes change.
 * @param {HTMLElement|null} button Action button.
 * @returns {void}
 */
const processRefundActionButton = (button) => {
  if (button && window.htmx && typeof window.htmx.process === "function") {
    window.htmx.process(button);
  }
};

/**
 * Apply trigger data to the refund review modal.
 * @param {HTMLElement} triggerButton Refund review trigger button.
 * @param {Document|Element} [root=document] Query root.
 * @returns {void}
 */
const populateRefundReviewModal = (triggerButton, root = document) => {
  const { modal, nameField, ticketField, amountField, approveButton, rejectButton } =
    getRefundReviewControls(root);

  if (!modal) {
    return;
  }

  const status = (triggerButton.dataset.refundStatus || "pending").trim();

  if (nameField) {
    nameField.textContent = triggerButton.dataset.refundAttendeeName || "-";
  }

  if (ticketField) {
    ticketField.textContent = triggerButton.dataset.refundTicketTitle || "-";
  }

  if (amountField) {
    amountField.textContent = triggerButton.dataset.refundAmount || "-";
  }

  if (approveButton) {
    setElementHidden(approveButton, false);
    setRefundActionLabel(
      approveButton,
      status === "approving" ? "Retry refund finalization" : "Approve refund",
    );
    if (triggerButton.dataset.refundApproveUrl) {
      approveButton.setAttribute("hx-put", triggerButton.dataset.refundApproveUrl);
    } else {
      approveButton.removeAttribute("hx-put");
    }
    processRefundActionButton(approveButton);
  }

  if (!rejectButton) {
    return;
  }

  if (status === "approving") {
    setElementHidden(rejectButton, true);
    rejectButton.removeAttribute("hx-put");
    processRefundActionButton(rejectButton);
    return;
  }

  setElementHidden(rejectButton, false);
  if (triggerButton.dataset.refundRejectUrl) {
    rejectButton.setAttribute("hx-put", triggerButton.dataset.refundRejectUrl);
  } else {
    rejectButton.removeAttribute("hx-put");
  }
  processRefundActionButton(rejectButton);
};

/**
 * Initialize refund review modal controls for attendee purchases.
 * @param {Document|Element} [root=document] Query root.
 * @returns {void}
 */
export const initializeRefundReviewModal = (root = document) => {
  if (!(root instanceof Element) || !markDatasetReady(root, "attendeeRefundReviewReady")) {
    return;
  }

  root.addEventListener("click", (event) => {
    const refundTrigger = closestElementWithinRoot(event.target, "[data-refund-review-trigger]", root);
    if (refundTrigger instanceof HTMLElement) {
      event.stopPropagation();
      populateRefundReviewModal(refundTrigger, root);
      openRefundModal(root);
      return;
    }

    closeScopedModalFromEvent(
      event,
      root,
      "#close-attendee-refund-modal, #cancel-attendee-refund-modal, #overlay-attendee-refund-modal",
      closeRefundModal,
    );
  });

  bindScopedModalEscape(root, closeRefundModal);

  root.addEventListener("htmx:afterRequest", (event) => {
    const requestTarget = event.target;
    if (
      !(requestTarget instanceof HTMLElement) ||
      ![refundApproveButtonId, refundRejectButtonId].includes(requestTarget.id)
    ) {
      return;
    }

    if (isSuccessfulXHRStatus(event.detail?.xhr?.status)) {
      closeRefundModal(root);
    }
  });
};
