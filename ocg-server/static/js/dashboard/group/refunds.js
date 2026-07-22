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

const MODAL_ID = "refund-recovery-modal";
const REFUND_FILTER_FORM_SELECTOR = "#refund-filters";
const REFUND_FOCUS_TARGET_DATA_KEY = "refundFocusAfterSwap";
const REFUND_SEARCH_CLEAR_SELECTOR = "[data-refund-search-clear]";
const REFUND_SEARCH_ID = "refund-search";
const ROOT_SELECTOR = "#dashboard-content";

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

  root.addEventListener("htmx:configRequest", (event) => {
    configureRefundNavigation(root, event.target);
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
      setRecoveryModalVisible(root, false);
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
  setRecoveryModalVisible(root, true, focusOrigin);
};

/**
 * Changes refund recovery modal visibility only when needed.
 * @param {Element} root Refunds list root.
 * @param {boolean} visible Whether the modal should be visible.
 * @param {HTMLElement|null} [focusOrigin=null] Element that opened the modal.
 * @returns {void}
 */
const setRecoveryModalVisible = (root, visible, focusOrigin = null) => {
  const modal = getElementById(root, MODAL_ID);
  if (!modal) {
    return;
  }

  const isHidden = isElementHidden(modal);
  if ((visible && isHidden) || (!visible && !isHidden)) {
    toggleModalVisibility(MODAL_ID, focusOrigin);
  }
};

initializeOnReadyAndHtmxLoad((root) => {
  initializeMatchingRoots(root, ROOT_SELECTOR, initializeRefundRecovery);
});
