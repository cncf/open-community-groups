import { closestElementWithinRoot, getElementById, markDatasetReady } from "/static/js/common/dom.js";
import { isSuccessfulXHRStatus } from "/static/js/common/utils.js";
import {
  bindScopedModalEscape,
  closeScopedModalFromEvent,
  setScopedModalVisibility,
} from "/static/js/dashboard/group/attendees/shared.js";

const refundReviewConfigs = [
  {
    attendeeId: "attendee-refund-approve-name",
    closeSelector:
      "#close-attendee-refund-approve-modal, #cancel-attendee-refund-approve-modal, #overlay-attendee-refund-approve-modal",
    eventId: "attendee-refund-approve-event",
    formId: "attendee-refund-approve-form",
    modalId: "attendee-refund-approve-modal",
    reviewNoteId: "attendee-refund-approve-review-note",
    triggerSelector: "[data-attendee-refund-approve-open]",
    urlDataKey: "refundApproveUrl",
  },
  {
    attendeeId: "attendee-refund-reject-name",
    closeSelector:
      "#close-attendee-refund-reject-modal, #cancel-attendee-refund-reject-modal, #overlay-attendee-refund-reject-modal",
    eventId: "attendee-refund-reject-event",
    formId: "attendee-refund-reject-form",
    modalId: "attendee-refund-reject-modal",
    reviewNoteId: "attendee-refund-review-note",
    triggerSelector: "[data-attendee-refund-reject-open]",
    urlDataKey: "refundRejectUrl",
  },
];

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
    for (const config of refundReviewConfigs) {
      const trigger = closestElementWithinRoot(event.target, config.triggerSelector, root);
      if (trigger instanceof HTMLElement) {
        openRefundReviewModal(trigger, config, root);
        return;
      }

      const closedModal = closeScopedModalFromEvent(event, root, config.closeSelector, (modalRoot) =>
        closeRefundReviewModal(config, modalRoot),
      );
      if (closedModal) {
        return;
      }
    }
  });

  bindScopedModalEscape(root, (modalRoot) => {
    refundReviewConfigs.forEach((config) => closeRefundReviewModal(config, modalRoot));
  });

  root.addEventListener("htmx:configRequest", (event) => {
    normalizeRefundReviewNote(root, event);
  });

  root.addEventListener("htmx:afterRequest", (event) => {
    const config = refundReviewConfigs.find(
      (reviewConfig) => event.target === getElementById(root, reviewConfig.formId),
    );
    if (config && isSuccessfulXHRStatus(event.detail?.xhr?.status)) {
      closeRefundReviewModal(config, root);
    }
  });
};

/**
 * Hide a refund review modal if it is currently visible.
 * @param {Object} config Refund review modal contract.
 * @param {Document|Element} [root=document] Query root.
 * @returns {void}
 */
const closeRefundReviewModal = (config, root = document) => {
  setScopedModalVisibility(root, config.modalId, false);
};

/**
 * Resolve refund review modal controls from the latest DOM.
 * @param {Object} config Refund review modal contract.
 * @param {Document|Element} [root=document] Query root.
 * @returns {Object} Refund review modal controls.
 */
const getRefundReviewControls = (config, root = document) => ({
  attendee: getElementById(root, config.attendeeId),
  event: getElementById(root, config.eventId),
  form: getElementById(root, config.formId),
  reviewNote: getElementById(root, config.reviewNoteId),
});

/**
 * Normalize an optional refund review note before HTMX submits the form.
 * @param {Document|Element} root Query root.
 * @param {Event} event HTMX configuration event.
 * @returns {void}
 */
const normalizeRefundReviewNote = (root, event) => {
  const config = refundReviewConfigs.find(
    (reviewConfig) => event.target === getElementById(root, reviewConfig.formId),
  );
  if (!config) {
    return;
  }

  const { reviewNote } = getRefundReviewControls(config, root);
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
 * Populate and open a refund review modal for one attendee.
 * @param {HTMLElement} trigger Refund review trigger button.
 * @param {Object} config Refund review modal contract.
 * @param {Document|Element} [root=document] Query root.
 * @returns {void}
 */
const openRefundReviewModal = (trigger, config, root = document) => {
  const { attendee, event, form, reviewNote } = getRefundReviewControls(config, root);
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

  if (attendee) {
    attendee.textContent = trigger.dataset.refundAttendeeName || "-";
  }
  if (event) {
    event.textContent = trigger.dataset.refundEventName || "-";
  }

  const actionsMenuSummary = trigger.closest("[data-actions-menu]")?.querySelector("summary");
  const focusOrigin = actionsMenuSummary instanceof HTMLElement ? actionsMenuSummary : trigger;
  setScopedModalVisibility(root, config.modalId, true, focusOrigin);
  reviewNote?.focus();
};
