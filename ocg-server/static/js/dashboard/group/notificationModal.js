import { toggleModalVisibility } from "/static/js/common/common.js";
import { showSuccessAlert, showErrorAlert, handleHtmxResponse } from "/static/js/common/alerts.js";
import { queryElementById } from "/static/js/common/dom.js";

const DEFAULT_ERROR_MESSAGE = "Something went wrong while trying to send the email. Please try again later.";

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
  root = document,
}) => {
  // Locate the modal once and mark it ready so we only bind listeners once.
  const modal = queryElementById(root, modalId);
  if (!modal || modal.dataset[dataKey] === "true") {
    return;
  }

  modal.dataset[dataKey] = "true";

  const openButton = openButtonId ? queryElementById(root, openButtonId) : null;
  const closeButton = closeButtonId ? queryElementById(root, closeButtonId) : null;
  const cancelButton = cancelButtonId ? queryElementById(root, cancelButtonId) : null;
  const overlay = overlayId ? queryElementById(root, overlayId) : null;
  const form = formId ? queryElementById(root, formId) : null;
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
        errorMessage: xhr ? xhr.responseText || DEFAULT_ERROR_MESSAGE : DEFAULT_ERROR_MESSAGE,
      });
      if (ok) {
        form.reset();
        toggleModal();
      }
    });
  }

  updateFormEndpoint();
};
