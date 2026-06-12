import { createNotificationModal } from "/static/js/dashboard/group/notification-modal.js";
import { initializeOnReadyAndHtmxLoad } from "/static/js/common/dom.js";

const modalId = "notification-modal";
const formId = "notification-form";
const dataKey = "membersNotificationReady";

// Reuse the shared helper for the members notification modal.
const initializeMembersNotification = (root = document) => {
  createNotificationModal({
    modalId,
    formId,
    dataKey,
    openButtonId: "open-notification-modal",
    closeButtonId: "close-notification-modal",
    cancelButtonId: "cancel-notification",
    overlayId: "overlay-notification-modal",
    successMessage: "Email sent successfully to all group members.",
    root,
  });
};

initializeOnReadyAndHtmxLoad(initializeMembersNotification);
