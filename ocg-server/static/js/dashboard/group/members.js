import { toggleModalVisibility } from "/static/js/common/common.js";
import { showSuccessAlert, showErrorAlert } from "/static/js/common/alerts.js";

const modalId = "notification-modal";
const formId = "notification-form";
const dataKey = "membersNotificationReady";

const bindNotificationModal = () => {
  const modal = document.getElementById(modalId);
  if (!modal || modal.dataset[dataKey] === "true") {
    return;
  }

  modal.dataset[dataKey] = "true";

  const openButton = document.getElementById("open-notification-modal");
  const closeButton = document.getElementById("close-notification-modal");
  const cancelButton = document.getElementById("cancel-notification");
  const overlay = document.getElementById("overlay-notification-modal");
  const form = document.getElementById(formId);

  const toggleModal = () => toggleModalVisibility(modalId);

  if (openButton) {
    openButton.addEventListener("click", toggleModal);
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
        showSuccessAlert("Notification sent successfully to all group members.");
        form.reset();
        toggleModal();
      } else {
        const errorMessage = xhr.responseText || "Failed to send notification. Please try again.";
        showErrorAlert(errorMessage, true);
      }
    });
  }
};

const initializeMembersNotification = () => {
  bindNotificationModal();
};

initializeMembersNotification();

if (document.body) {
  document.body.addEventListener("htmx:load", initializeMembersNotification);
}
