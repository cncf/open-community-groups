import "/static/js/common/actions-menu.js";
import {
  closestElementWithinRoot,
  focusElementById,
  getElementById,
  initializeMatchingRoots,
  initializeOnReadyAndHtmxLoad,
  isElementHidden,
  markDatasetReady,
} from "/static/js/common/dom.js";
import { isEscapeEvent } from "/static/js/common/keyboard.js";
import { toggleModalVisibility } from "/static/js/common/modals/modal-lifecycle.js";
import { isSuccessfulXHRStatus } from "/static/js/common/utils.js";

const RECOVERY_MODAL_ID = "refund-recovery-modal";
const REFUND_FILTER_FORM_SELECTOR = "#refund-filters";
const REFUND_FOCUS_TARGET_DATA_KEY = "refundFocusAfterSwap";
const REFUND_REVIEW_CONFIGS = [
  {
    closeSelector: "#close-refund-approve-modal, #cancel-refund-approve-modal, #overlay-refund-approve-modal",
    contextPrefix: "refund-approve",
    formId: "refund-approve-form",
    modalId: "refund-approve-modal",
    reviewNoteId: "refund-approve-review-note",
    triggerSelector: "[data-refund-approve-open]",
    urlDataKey: "refundApproveUrl",
  },
  {
    closeSelector: "#close-refund-reject-modal, #cancel-refund-reject-modal, #overlay-refund-reject-modal",
    contextPrefix: "refund-reject",
    formId: "refund-reject-form",
    modalId: "refund-reject-modal",
    reviewNoteId: "refund-review-note",
    triggerSelector: "[data-refund-reject-open]",
    urlDataKey: "refundRejectUrl",
  },
];
const REFUND_SEARCH_CLEAR_SELECTOR = "[data-refund-search-clear]";
const REFUND_SEARCH_ID = "refund-search";
const ROOT_SELECTOR = "#dashboard-content";

/**
 * Initializes refund interactions for a rendered refunds list.
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

    for (const config of REFUND_REVIEW_CONFIGS) {
      const reviewTrigger = closestElementWithinRoot(event.target, config.triggerSelector, root);
      if (reviewTrigger instanceof HTMLElement) {
        openRefundReviewModal(root, reviewTrigger, config);
        return;
      }

      if (closestElementWithinRoot(event.target, config.closeSelector, root)) {
        setRefundModalVisible(root, config.modalId, false);
        return;
      }
    }

    const closeTrigger = closestElementWithinRoot(
      event.target,
      "#close-refund-recovery-modal, #cancel-refund-recovery-modal, #overlay-refund-recovery-modal",
      root,
    );
    if (closeTrigger) {
      setRefundModalVisible(root, RECOVERY_MODAL_ID, false);
    }
  });

  root.addEventListener("keydown", (event) => {
    if (isEscapeEvent(event)) {
      setRefundModalVisible(root, RECOVERY_MODAL_ID, false);
      REFUND_REVIEW_CONFIGS.forEach((config) => {
        setRefundModalVisible(root, config.modalId, false);
      });
    }
  });

  root.addEventListener("htmx:configRequest", (event) => {
    configureRefundNavigation(root, event.target);
    normalizeRefundReviewNote(root, event);
  });

  root.addEventListener("htmx:afterSwap", (event) => {
    if (event.target === root) {
      focusRefundSwapTarget(root);
    }
  });

  root.addEventListener("htmx:afterRequest", (event) => {
    const requestSucceeded = isSuccessfulXHRStatus(event.detail?.xhr?.status);
    if (event.target === getElementById(root, "refund-recovery-form") && requestSucceeded) {
      root.dataset[REFUND_FOCUS_TARGET_DATA_KEY] = REFUND_SEARCH_ID;
      setRefundModalVisible(root, RECOVERY_MODAL_ID, false);
    }

    const refundReviewConfig = REFUND_REVIEW_CONFIGS.find(
      (config) => event.target === getElementById(root, config.formId),
    );
    if (refundReviewConfig && requestSucceeded) {
      root.dataset[REFUND_FOCUS_TARGET_DATA_KEY] = REFUND_SEARCH_ID;
      setRefundModalVisible(root, refundReviewConfig.modalId, false);
    }

    if (!requestSucceeded) {
      delete root.dataset[REFUND_FOCUS_TARGET_DATA_KEY];
    }
  });
};

/**
 * Builds the full dashboard URL represented by the refund filter form.
 * @param {HTMLFormElement} form Refund filter form.
 * @param {ReadonlySet<string>} [excludedNames] Form fields to omit.
 * @returns {string} Dashboard URL with non-empty filter values.
 */
const buildRefundDashboardUrl = (form, excludedNames = new Set()) => {
  const dashboardUrl = new URL(form.action, window.location.origin);
  new FormData(form).forEach((value, name) => {
    if (!excludedNames.has(name) && typeof value === "string" && value.length > 0) {
      dashboardUrl.searchParams.append(name, value);
    }
  });

  return `${dashboardUrl.pathname}${dashboardUrl.search}`;
};

/**
 * Configures history and fallback focus for refund HTMX navigation.
 * @param {Element} root Refunds list root.
 * @param {EventTarget|null} requestTarget HTMX request element.
 * @returns {void}
 */
const configureRefundNavigation = (root, requestTarget) => {
  if (requestTarget instanceof HTMLButtonElement && requestTarget.matches(REFUND_SEARCH_CLEAR_SELECTOR)) {
    const form = requestTarget.closest(REFUND_FILTER_FORM_SELECTOR);
    if (form instanceof HTMLFormElement) {
      requestTarget.setAttribute("hx-push-url", buildRefundDashboardUrl(form, new Set(["ts_query"])));
    }
    root.dataset[REFUND_FOCUS_TARGET_DATA_KEY] = REFUND_SEARCH_ID;
    return;
  }

  if (requestTarget instanceof HTMLAnchorElement && requestTarget.hasAttribute("hx-get")) {
    const dashboardUrl = requestTarget.getAttribute("href");
    if (dashboardUrl) {
      requestTarget.setAttribute("hx-push-url", dashboardUrl);
    }
    if (!requestTarget.id) {
      root.dataset[REFUND_FOCUS_TARGET_DATA_KEY] = REFUND_SEARCH_ID;
    }
    return;
  }

  if (requestTarget instanceof HTMLFormElement && requestTarget.matches(REFUND_FILTER_FORM_SELECTOR)) {
    const focusedFilter = document.activeElement;
    if (focusedFilter instanceof HTMLElement && requestTarget.contains(focusedFilter) && focusedFilter.id) {
      root.dataset[REFUND_FOCUS_TARGET_DATA_KEY] = focusedFilter.id;
    }
    requestTarget.setAttribute("hx-push-url", buildRefundDashboardUrl(requestTarget));
  }
};

/**
 * Restores focus after a refund control without a replacement is swapped out.
 * @param {Element} root Refunds list root.
 * @returns {void}
 */
const focusRefundSwapTarget = (root) => {
  const focusTargetId = root.dataset[REFUND_FOCUS_TARGET_DATA_KEY];
  if (!focusTargetId) {
    return;
  }

  delete root.dataset[REFUND_FOCUS_TARGET_DATA_KEY];
  focusElementById(root, focusTargetId);
};

/**
 * Normalizes the optional review note before HTMX submits the request.
 * @param {Element} root Refunds list root.
 * @param {Event} event HTMX configuration event.
 * @returns {void}
 */
const normalizeRefundReviewNote = (root, event) => {
  const config = REFUND_REVIEW_CONFIGS.find(
    (reviewConfig) => event.target === getElementById(root, reviewConfig.formId),
  );
  if (!config) {
    return;
  }

  const reviewNote = getElementById(root, config.reviewNoteId);
  const parameters = event.detail?.parameters;
  if (!(reviewNote instanceof HTMLTextAreaElement) || !parameters || typeof parameters !== "object") {
    return;
  }

  const normalizedReviewNote = reviewNote.value.trim();
  reviewNote.value = normalizedReviewNote;
  [parameters, event.detail?.unfilteredParameters].forEach((parameterSet) => {
    if (!parameterSet || typeof parameterSet !== "object") {
      return;
    }

    if (normalizedReviewNote) {
      parameterSet.review_note = normalizedReviewNote;
    } else {
      delete parameterSet.review_note;
    }
  });
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

  const actionsMenuSummary = trigger.closest("[data-actions-menu]")?.querySelector("summary");
  const focusOrigin = actionsMenuSummary instanceof HTMLElement ? actionsMenuSummary : trigger;
  setRefundModalVisible(root, RECOVERY_MODAL_ID, true, focusOrigin);
};

/**
 * Populates and opens a review modal for one refund row.
 * @param {Element} root Refunds list root.
 * @param {HTMLElement} trigger Refund review action button.
 * @param {Object} config Refund review modal contract.
 * @returns {void}
 */
const openRefundReviewModal = (root, trigger, config) => {
  const form = getElementById(root, config.formId);
  if (!(form instanceof HTMLFormElement)) {
    return;
  }

  form.reset();
  const reviewUrl = trigger.dataset[config.urlDataKey];
  if (reviewUrl) {
    form.setAttribute("hx-put", reviewUrl);
    window.htmx?.process?.(form);
  } else {
    form.removeAttribute("hx-put");
  }

  const attendee = getElementById(root, `${config.contextPrefix}-attendee`);
  const event = getElementById(root, `${config.contextPrefix}-event`);
  const reason = getElementById(root, `${config.contextPrefix}-reason`);
  if (attendee) {
    attendee.textContent = trigger.dataset.refundAttendee || "-";
  }
  if (event) {
    event.textContent = trigger.dataset.refundEvent || "-";
  }
  if (reason) {
    reason.textContent = trigger.dataset.refundReason || "No reason provided.";
  }

  const actionsMenuSummary = trigger.closest("[data-actions-menu]")?.querySelector("summary");
  const focusOrigin = actionsMenuSummary instanceof HTMLElement ? actionsMenuSummary : trigger;
  setRefundModalVisible(root, config.modalId, true, focusOrigin);
};

/**
 * Changes refund modal visibility only when needed.
 * @param {Element} root Refunds list root.
 * @param {string} modalId Modal element id.
 * @param {boolean} visible Whether the modal should be visible.
 * @param {HTMLElement|null} [focusOrigin=null] Element that opened the modal.
 * @returns {void}
 */
const setRefundModalVisible = (root, modalId, visible, focusOrigin = null) => {
  const modal = getElementById(root, modalId);
  if (!modal) {
    return;
  }

  const isHidden = isElementHidden(modal);
  if ((visible && isHidden) || (!visible && !isHidden)) {
    toggleModalVisibility(modalId, focusOrigin);
  }
};

initializeOnReadyAndHtmxLoad((root) => {
  initializeMatchingRoots(root, ROOT_SELECTOR, initializeRefundRecovery);
});
