import { createNotificationModal } from "/static/js/dashboard/group/notificationModal.js";
import { initializeQrCodeModal } from "/static/js/dashboard/group/qr-code-modal.js";
import { showErrorAlert } from "/static/js/common/alerts.js";

const modalId = "attendee-notification-modal";
const formId = "attendee-notification-form";
const dataKey = "attendeeNotificationReady";

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

const initializeAttendeesFeatures = () => {
  initializeAttendeeNotification();
  initializeQrCodeModal();
  initCheckInToggles();
};

initializeAttendeesFeatures();

if (document.body) {
  document.body.addEventListener("htmx:load", initializeAttendeesFeatures);
}
