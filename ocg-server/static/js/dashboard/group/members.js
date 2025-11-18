import { createNotificationModal } from "/static/js/dashboard/group/notificationModal.js";

const modalId = "notification-modal";
const formId = "notification-form";
const dataKey = "membersNotificationReady";

// Reuse the shared helper for the members notification modal.
const initializeMembersNotification = () => {
  createNotificationModal({
    modalId,
    formId,
    dataKey,
    openButtonId: "open-notification-modal",
    closeButtonId: "close-notification-modal",
    cancelButtonId: "cancel-notification",
    overlayId: "overlay-notification-modal",
    successMessage: "Email sent successfully to all group members.",
  });
};

initializeMembersNotification();

if (document.body) {
  document.body.addEventListener("htmx:load", initializeMembersNotification);
}
