import { createNotificationModal } from "/static/js/dashboard/group/notificationModal.js";

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

initializeAttendeeNotification();

if (document.body) {
  document.body.addEventListener("htmx:load", initializeAttendeeNotification);
}
