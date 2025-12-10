import { toggleModalVisibility } from "/static/js/common/common.js";
import { showSuccessAlert, showErrorAlert, handleHtmxResponse } from "/static/js/common/alerts.js";

const DEFAULT_ERROR_MESSAGE = "Failed to send email. Please try again.";

// Central helper for attaching modal controls and HTMX success handling.
export const createNotificationModal = ({
  modalId,
  formId,
  dataKey,
  openButtonId,
  closeButtonId,
  cancelButtonId,
  overlayId,
  successMessage,
  updateEndpoint,
}) => {
  // Locate the modal once and mark it ready so we only bind listeners once.
  const modal = document.getElementById(modalId);
  if (!modal || modal.dataset[dataKey] === "true") {
    return;
  }

  modal.dataset[dataKey] = "true";

  const openButton = openButtonId ? document.getElementById(openButtonId) : null;
  const closeButton = closeButtonId ? document.getElementById(closeButtonId) : null;
  const cancelButton = cancelButtonId ? document.getElementById(cancelButtonId) : null;
  const overlay = overlayId ? document.getElementById(overlayId) : null;
  const form = formId ? document.getElementById(formId) : null;
  const toggleModal = () => toggleModalVisibility(modalId);

  // Allow callers to adjust the form action before the modal opens.
  const updateFormEndpoint = () => {
    if (!form || typeof updateEndpoint !== "function") {
      return;
    }

    updateEndpoint({
      form,
      openButton,
      closeButton,
      cancelButton,
      overlay,
    });
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
      const ok = handleHtmxResponse({
        xhr,
        successMessage: successMessage || "Email sent successfully.",
        errorMessage: xhr ? xhr.statusText || DEFAULT_ERROR_MESSAGE : DEFAULT_ERROR_MESSAGE,
      });
      if (ok) {
        form.reset();
        toggleModal();
      }
    });
  }

  updateFormEndpoint();
};
