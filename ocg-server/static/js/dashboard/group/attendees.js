import { createNotificationModal } from "/static/js/dashboard/group/notificationModal.js";
import { initializeQrCodeModal } from "/static/js/dashboard/group/qr-code-modal.js";
import { showErrorAlert } from "/static/js/common/alerts.js";
import { isSuccessfulXHRStatus, toggleModalVisibility } from "/static/js/common/common.js";
import { queryElementById } from "/static/js/common/dom.js";

const modalId = "attendee-notification-modal";
const formId = "attendee-notification-form";
const dataKey = "attendeeNotificationReady";
const refundModalId = "attendee-refund-modal";
const refundApproveButtonId = "attendee-refund-approve";
const refundRejectButtonId = "attendee-refund-reject";

const resolveAttendeesRoot = (root = document) => {
  if (root instanceof Element && root.id === "attendees-content") {
    return root;
  }

  if (root instanceof Element) {
    return root.closest("#attendees-content") || root.querySelector("#attendees-content") || root;
  }

  return root.querySelector?.("#attendees-content") || root.body || root;
};

/**
 * Resolve the current refund review modal controls from the latest DOM.
 * @param {Document|Element} [root=document] Query root.
 * @returns {Object} Refund modal controls.
 */
const getRefundReviewControls = (root = document) => ({
  modal: queryElementById(root, refundModalId),
  nameField: queryElementById(root, "attendee-refund-name"),
  ticketField: queryElementById(root, "attendee-refund-ticket"),
  amountField: queryElementById(root, "attendee-refund-amount"),
  statusField: queryElementById(root, "attendee-refund-status"),
  approveButton: queryElementById(root, refundApproveButtonId),
  rejectButton: queryElementById(root, refundRejectButtonId),
});

/**
 * Show the refund review modal if it is currently hidden.
 * @param {Document|Element} [root=document] Query root.
 * @returns {void}
 */
const openRefundModal = (root = document) => {
  const modal = queryElementById(root, refundModalId);
  if (modal?.classList.contains("hidden")) {
    toggleModalVisibility(refundModalId);
  }
};

/**
 * Hide the refund review modal if it is currently visible.
 * @param {Document|Element} [root=document] Query root.
 * @returns {void}
 */
const closeRefundModal = (root = document) => {
  const modal = queryElementById(root, refundModalId);
  if (modal && !modal.classList.contains("hidden")) {
    toggleModalVisibility(refundModalId);
  }
};

/**
 * Update a refund modal action button label.
 * @param {HTMLElement | null} button
 * @param {string} label
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
 * @param {HTMLElement | null} button
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
  const { modal, nameField, ticketField, amountField, statusField, approveButton, rejectButton } =
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

  if (statusField) {
    const isApproving = status === "approving";
    statusField.textContent = isApproving ? "Refund processing" : "Refund requested";
    statusField.classList.toggle("border-amber-800", true);
    statusField.classList.toggle("bg-amber-100", true);
    statusField.classList.toggle("text-amber-800", true);
    statusField.classList.remove("border-amber-300", "bg-amber-50", "text-amber-700");
  }

  if (approveButton) {
    approveButton.classList.remove("hidden");
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
    rejectButton.classList.add("hidden");
    rejectButton.removeAttribute("hx-put");
    processRefundActionButton(rejectButton);
    return;
  }

  rejectButton.classList.remove("hidden");
  if (triggerButton.dataset.refundRejectUrl) {
    rejectButton.setAttribute("hx-put", triggerButton.dataset.refundRejectUrl);
  } else {
    rejectButton.removeAttribute("hx-put");
  }
  processRefundActionButton(rejectButton);
};

// Set up the attendee modal with its dynamic endpoint and success copy.
const initializeAttendeeNotification = (root) => {
  createNotificationModal({
    modalId,
    formId,
    dataKey,
    openButtonId: "open-attendee-notification-modal",
    closeButtonId: "close-attendee-notification-modal",
    cancelButtonId: "cancel-attendee-notification",
    overlayId: "overlay-attendee-notification-modal",
    successMessage: "Email sent successfully to all event attendees!",
    root,
    // Apply the event-specific endpoint before the modal opens.
    updateEndpoint: ({ form, openButton }) => {
      if (!form) {
        return;
      }

      const eventId = openButton?.getAttribute("data-event-id") || "";
      if (eventId) {
        form.setAttribute("hx-post", `/dashboard/group/notifications/${eventId}`);
      } else {
        form.removeAttribute("hx-post");
      }
    },
  });
};

/**
 * Initialize check-in toggle checkboxes with optimistic UI updates.
 * @param {Document|Element} [root=document] Query root.
 */
const initCheckInToggles = (root = document) => {
  root.querySelectorAll(".check-in-toggle").forEach((checkbox) => {
    if (checkbox.dataset.checkInReady === "true") {
      return;
    }

    checkbox.dataset.checkInReady = "true";
    checkbox.addEventListener("change", async () => {
      const url = checkbox.dataset.url;
      const label = checkbox.closest("label");

      // Optimistic update: disable and show as checked
      checkbox.disabled = true;
      if (label) {
        label.classList.remove("cursor-pointer");
        label.classList.add("cursor-not-allowed");
      }

      try {
        const response = await fetch(url, { method: "POST" });
        if (!response.ok) {
          throw new Error("Check-in failed");
        }
      } catch {
        // Revert on error
        checkbox.checked = false;
        checkbox.disabled = false;
        if (label) {
          label.classList.add("cursor-pointer");
          label.classList.remove("cursor-not-allowed");
        }
        showErrorAlert("Failed to check in attendee. Please try again.");
      }
    });
  });
};

/**
 * Initialize refund review modal controls for attendee purchases.
 * @param {Document|Element} [root=document] Query root.
 */
const initializeRefundReviewModal = (root = document) => {
  if (!(root instanceof Element) || root.dataset.attendeeRefundReviewReady === "true") {
    return;
  }

  root.dataset.attendeeRefundReviewReady = "true";

  root.addEventListener("click", (event) => {
    const target = event.target instanceof Element ? event.target : null;
    const refundTrigger = target?.closest("[data-refund-review-trigger]");
    if (refundTrigger instanceof HTMLElement && root.contains(refundTrigger)) {
      event.stopPropagation();
      populateRefundReviewModal(refundTrigger, root);
      openRefundModal(root);
      return;
    }

    if (
      target?.closest(
        "#close-attendee-refund-modal, #cancel-attendee-refund-modal, #overlay-attendee-refund-modal",
      )
    ) {
      event.stopPropagation();
      closeRefundModal(root);
    }
  });

  root.addEventListener("keydown", (event) => {
    if (event.key === "Escape") {
      closeRefundModal(root);
    }
  });

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

const initializeAttendeesFeatures = (root = document) => {
  const attendeesRoot = resolveAttendeesRoot(root);
  if (!attendeesRoot) {
    return;
  }

  initializeAttendeeNotification(attendeesRoot);
  initializeQrCodeModal(attendeesRoot);
  initializeRefundReviewModal(attendeesRoot);
  initCheckInToggles(attendeesRoot);
};

initializeAttendeesFeatures();

if (document.body) {
  document.body.addEventListener("htmx:load", (event) => {
    initializeAttendeesFeatures(event.target || document);
  });
}
