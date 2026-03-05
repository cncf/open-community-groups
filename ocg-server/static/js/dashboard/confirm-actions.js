import { showConfirmAlert, handleHtmxResponse } from "/static/js/common/alerts.js";

if (!window.__ocgConfirmActionsBound) {
  window.__ocgConfirmActionsBound = true;

  document.addEventListener("click", (event) => {
    const button = event.target.closest("[data-confirm-action]");
    if (!button || button.disabled) {
      return;
    }

    showConfirmAlert(
      button.dataset.confirmMessage || "Are you sure?",
      button.id,
      button.dataset.confirmText || "Yes",
    );
  });

  document.addEventListener("htmx:afterRequest", (event) => {
    const button = event.target?.closest?.("[data-confirm-action]");
    if (!button) {
      return;
    }

    handleHtmxResponse({
      xhr: event.detail?.xhr,
      successMessage: button.dataset.successMessage || "",
      errorMessage: button.dataset.errorMessage || "Something went wrong. Please try again later.",
    });
  });
}
