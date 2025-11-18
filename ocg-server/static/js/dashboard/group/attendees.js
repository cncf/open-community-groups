import { toggleModalVisibility } from "/static/js/common/common.js";
import { showSuccessAlert, showErrorAlert } from "/static/js/common/alerts.js";

const modalId = "attendee-notification-modal";
const formId = "attendee-notification-form";
const dataKey = "attendeeNotificationReady";

const bindAttendeeNotificationModal = () => {
  const modal = document.getElementById(modalId);
  if (!modal || modal.dataset[dataKey] === "true") {
    return;
  }

  modal.dataset[dataKey] = "true";

  const openButton = document.getElementById("open-attendee-notification-modal");
  const closeButton = document.getElementById("close-attendee-notification-modal");
  const cancelButton = document.getElementById("cancel-attendee-notification");
  const overlay = document.getElementById("overlay-attendee-notification-modal");
  const form = document.getElementById(formId);

  const toggleModal = () => toggleModalVisibility(modalId);

  const updateFormEndpoint = () => {
    if (!form) {
      return;
    }
    const eventId = openButton?.getAttribute("data-event-id") || "";
    if (eventId) {
      form.setAttribute("hx-post", `/dashboard/group/notifications/${eventId}`);
    } else {
      form.removeAttribute("hx-post");
    }
  };

  if (openButton) {
    openButton.addEventListener("click", () => {
      updateFormEndpoint();
      toggleModal();
    });
  }

  if (closeButton) {
    closeButton.addEventListener("click", toggleModal);
  }

  if (cancelButton) {
    cancelButton.addEventListener("click", toggleModal);
  }

  if (overlay) {
    overlay.addEventListener("click", toggleModal);
  }

  if (form) {
    form.addEventListener("htmx:afterRequest", (event) => {
      const xhr = event.detail?.xhr;
      if (!xhr) {
        showErrorAlert("Failed to send notification. Please try again.", false);
        return;
      }

      if (xhr.status >= 200 && xhr.status < 300) {
        showSuccessAlert("Notification sent successfully to all event attendees!");
        form.reset();
        toggleModal();
      } else {
        const errorMessage = xhr.responseText || "Failed to send notification. Please try again.";
        showErrorAlert(errorMessage, true);
      }
    });
  }

  updateFormEndpoint();
};

const initializeAttendeeNotification = () => {
  bindAttendeeNotificationModal();
};

initializeAttendeeNotification();

if (document.body) {
  document.body.addEventListener("htmx:load", initializeAttendeeNotification);
}
