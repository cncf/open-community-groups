import { toggleModalVisibility } from "/static/js/common/common.js";
import { handleHtmxResponse } from "/static/js/common/alerts.js";
import { getElementById, markDatasetReady } from "/static/js/common/dom.js";
import { bindModalControlClicks } from "/static/js/common/modal-lifecycle.js";

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
  const modal = getElementById(root, modalId);
  if (!markDatasetReady(modal, dataKey)) {
    return;
  }

  const openButton = openButtonId ? getElementById(root, openButtonId) : null;
  const closeButton = closeButtonId ? getElementById(root, closeButtonId) : null;
  const cancelButton = cancelButtonId ? getElementById(root, cancelButtonId) : null;
  const overlay = overlayId ? getElementById(root, overlayId) : null;
  const form = formId ? getElementById(root, formId) : null;
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

  bindModalControlClicks([closeButton, cancelButton, overlay], toggleModal);

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
