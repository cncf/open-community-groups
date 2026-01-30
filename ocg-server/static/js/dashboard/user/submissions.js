import { handleHtmxResponse, showConfirmAlert } from "/static/js/common/alerts.js";

const initializeSubmissionActions = () => {
  document.querySelectorAll('[data-action="withdraw-submission"]').forEach((button) => {
    if (button.dataset.bound === "true") {
      return;
    }
    button.dataset.bound = "true";
    button.addEventListener("click", () => {
      if (!button.id) {
        button.id = `withdraw-submission-${button.dataset.submissionId}`;
      }
      showConfirmAlert("Withdraw this submission?", button.id, "Withdraw");
    });
    button.addEventListener("htmx:afterRequest", (event) => {
      handleHtmxResponse({
        xhr: event.detail?.xhr,
        successMessage: "",
        errorMessage: "Unable to withdraw this submission. Please try again later.",
      });
    });
  });

  document.querySelectorAll('[data-action="resubmit-submission"]').forEach((button) => {
    if (button.dataset.bound === "true") {
      return;
    }
    button.dataset.bound = "true";
    button.addEventListener("htmx:afterRequest", (event) => {
      handleHtmxResponse({
        xhr: event.detail?.xhr,
        successMessage: "",
        errorMessage: "Unable to resubmit this submission. Please try again later.",
      });
    });
  });
};

initializeSubmissionActions();

if (document.body) {
  document.body.addEventListener("htmx:load", initializeSubmissionActions);
}
