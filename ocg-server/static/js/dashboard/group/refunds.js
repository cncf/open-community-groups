import {
  closestElementWithinRoot,
  getElementById,
  initializeMatchingRoots,
  initializeOnReadyAndHtmxLoad,
  isElementHidden,
  markDatasetReady,
} from "/static/js/common/dom.js";
import { isEscapeEvent } from "/static/js/common/keyboard.js";
import { toggleModalVisibility } from "/static/js/common/modals/modal-lifecycle.js";
import { isSuccessfulXHRStatus } from "/static/js/common/utils.js";

const MODAL_ID = "refund-recovery-modal";
const ROOT_SELECTOR = "#dashboard-content";

/**
 * Changes refund recovery modal visibility only when needed.
 * @param {Element} root Refunds list root.
 * @param {boolean} visible Whether the modal should be visible.
 * @returns {void}
 */
const setRecoveryModalVisible = (root, visible) => {
  const modal = getElementById(root, MODAL_ID);
  if (!modal) {
    return;
  }

  const isHidden = isElementHidden(modal);
  if ((visible && isHidden) || (!visible && !isHidden)) {
    toggleModalVisibility(MODAL_ID);
  }
};

/**
 * Populates and opens the recovery modal for one refund row.
 * @param {Element} root Refunds list root.
 * @param {HTMLElement} trigger Recovery action button.
 * @returns {void}
 */
const openRecoveryModal = (root, trigger) => {
  const form = getElementById(root, "refund-recovery-form");
  form?.reset();

  const purchaseId = getElementById(root, "refund-recovery-purchase-id");
  const attendee = getElementById(root, "refund-recovery-attendee");
  const event = getElementById(root, "refund-recovery-event");

  if (purchaseId instanceof HTMLInputElement) {
    purchaseId.value = trigger.dataset.eventPurchaseId || "";
  }
  if (attendee) {
    attendee.textContent = trigger.dataset.refundAttendee || "-";
  }
  if (event) {
    event.textContent = trigger.dataset.refundEvent || "-";
  }

  setRecoveryModalVisible(root, true);
};

/**
 * Initializes refund recovery interactions for a rendered refunds list.
 * @param {Element} root Refunds list root.
 * @returns {void}
 */
export const initializeRefundRecovery = (root) => {
  if (!markDatasetReady(root, "refundRecoveryReady")) {
    return;
  }

  root.addEventListener("click", (event) => {
    const openTrigger = closestElementWithinRoot(event.target, "[data-refund-recovery-open]", root);
    if (openTrigger instanceof HTMLElement) {
      openRecoveryModal(root, openTrigger);
      return;
    }

    const closeTrigger = closestElementWithinRoot(
      event.target,
      "#close-refund-recovery-modal, #cancel-refund-recovery-modal, #overlay-refund-recovery-modal",
      root,
    );
    if (closeTrigger) {
      setRecoveryModalVisible(root, false);
    }
  });

  root.addEventListener("keydown", (event) => {
    if (isEscapeEvent(event)) {
      setRecoveryModalVisible(root, false);
    }
  });

  root.addEventListener("htmx:afterRequest", (event) => {
    if (
      event.target === getElementById(root, "refund-recovery-form") &&
      isSuccessfulXHRStatus(event.detail?.xhr?.status)
    ) {
      setRecoveryModalVisible(root, false);
    }
  });
};

initializeOnReadyAndHtmxLoad((root) => {
  initializeMatchingRoots(root, ROOT_SELECTOR, initializeRefundRecovery);
});
