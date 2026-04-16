import { createNotificationModal } from "/static/js/dashboard/group/notificationModal.js";
import { initializeQrCodeModal } from "/static/js/dashboard/group/qr-code-modal.js";
import { showErrorAlert } from "/static/js/common/alerts.js";
import { toggleModalVisibility } from "/static/js/common/common.js";

const modalId = "attendee-notification-modal";
const formId = "attendee-notification-form";
const dataKey = "attendeeNotificationReady";
const refundModalId = "attendee-refund-modal";

/**
 * Show the refund review modal if it is currently hidden.
 * @returns {void}
 */
const openRefundModal = () => {
  const modal = document.getElementById(refundModalId);
  if (modal?.classList.contains("hidden")) {
    toggleModalVisibility(refundModalId);
  }
};

/**
 * Hide the refund review modal if it is currently visible.
 * @returns {void}
 */
const closeRefundModal = () => {
  const modal = document.getElementById(refundModalId);
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

// Set up the attendee modal with its dynamic endpoint and success copy.
const initializeAttendeeNotification = () => {
  createNotificationModal({
    modalId,
    formId,
    dataKey,
    openButtonId: "open-attendee-notification-modal",
    closeButtonId: "close-attendee-notification-modal",
    cancelButtonId: "cancel-attendee-notification",
    overlayId: "overlay-attendee-notification-modal",
    successMessage: "Email sent successfully to all event attendees!",
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
 */
const initCheckInToggles = () => {
  document.querySelectorAll(".check-in-toggle").forEach((checkbox) => {
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
 */
const initializeRefundReviewModal = () => {
  const modal = document.getElementById(refundModalId);
  if (!modal || modal.dataset.refundReviewReady === "true") {
    return;
  }

  modal.dataset.refundReviewReady = "true";

  const nameField = document.getElementById("attendee-refund-name");
  const ticketField = document.getElementById("attendee-refund-ticket");
  const amountField = document.getElementById("attendee-refund-amount");
  const statusField = document.getElementById("attendee-refund-status");
  const approveButton = document.getElementById("attendee-refund-approve");
  const rejectButton = document.getElementById("attendee-refund-reject");
  const closeButton = document.getElementById("close-attendee-refund-modal");
  const cancelButton = document.getElementById("cancel-attendee-refund-modal");
  const overlay = document.getElementById("overlay-attendee-refund-modal");

  document.querySelectorAll("[data-refund-review-trigger]").forEach((button) => {
    if (button.dataset.refundReviewBound === "true") {
      return;
    }

    button.dataset.refundReviewBound = "true";
    button.addEventListener("click", () => {
      const status = button.dataset.refundStatus || "pending";

      if (nameField) {
        nameField.textContent = button.dataset.refundAttendeeName || "-";
      }

      if (ticketField) {
        ticketField.textContent = button.dataset.refundTicketTitle || "-";
      }

      if (amountField) {
        amountField.textContent = button.dataset.refundAmount || "-";
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
        if (button.dataset.refundApproveUrl) {
          approveButton.setAttribute("hx-put", button.dataset.refundApproveUrl);
        } else {
          approveButton.removeAttribute("hx-put");
        }
        processRefundActionButton(approveButton);
      }

      if (rejectButton) {
        if (status === "approving") {
          rejectButton.classList.add("hidden");
          rejectButton.removeAttribute("hx-put");
          processRefundActionButton(rejectButton);
        } else {
          rejectButton.classList.remove("hidden");
          if (button.dataset.refundRejectUrl) {
            rejectButton.setAttribute("hx-put", button.dataset.refundRejectUrl);
          } else {
            rejectButton.removeAttribute("hx-put");
          }
          processRefundActionButton(rejectButton);
        }
      }

      openRefundModal();
    });
  });

  if (closeButton) {
    closeButton.addEventListener("click", closeRefundModal);
  }

  if (cancelButton) {
    cancelButton.addEventListener("click", closeRefundModal);
  }

  if (overlay) {
    overlay.addEventListener("click", closeRefundModal);
  }

  if (document.body?.dataset.attendeeRefundEscapeReady !== "true") {
    document.body.dataset.attendeeRefundEscapeReady = "true";
    document.addEventListener("keydown", (event) => {
      if (event.key === "Escape") {
        closeRefundModal();
      }
    });
  }

  [approveButton, rejectButton].forEach((button) => {
    button?.addEventListener("htmx:afterRequest", (event) => {
      if (event.detail?.xhr?.ok) {
        closeRefundModal();
      }
    });
  });
};

const initializeAttendeesFeatures = () => {
  initializeAttendeeNotification();
  initializeQrCodeModal();
  initializeRefundReviewModal();
  initCheckInToggles();
};

initializeAttendeesFeatures();

if (document.body) {
  document.body.addEventListener("htmx:load", initializeAttendeesFeatures);
}
