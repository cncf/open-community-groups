import { expect } from "@open-wc/testing";

import {
  bindHtmxResponseAlert,
  confirmAction,
  confirmSeriesAction,
  getCommonAlertOptions,
  handleHtmxResponse,
  initializePageAlerts,
  showConfirmAlert,
  showDeploymentRefreshRetryAlert,
  showErrorAlert,
  showInfoAlert,
  showServerErrorAlert,
  showSuccessAlert,
} from "/static/js/common/alerts.js";
import { waitForMicrotask } from "/tests/unit/test-utils/async.js";
import { useDashboardTestEnv } from "/tests/unit/test-utils/env.js";

describe("alerts", () => {
  const env = useDashboardTestEnv({
    path: "/dashboard/groups",
    withHtmx: true,
    withScroll: true,
    withSwal: true,
  });

  it("renders success, error, info, and server error alerts", () => {
    // Assert each alert helper covered by this scenario.
    showSuccessAlert("Saved");
    showErrorAlert("Failed");
    showInfoAlert("Heads up");
    showServerErrorAlert("Validation failed", "Missing field");

    // Assert each helper passes the expected SweetAlert options.
    expect(env.current.swal.calls).to.have.length(4);
    expect(env.current.swal.calls[0]).to.include({
      text: "Saved",
      icon: "success",
      timer: 5000,
    });
    expect(env.current.swal.calls[1]).to.include({
      text: "Failed",
      icon: "error",
      timer: 30000,
    });
    expect(env.current.swal.calls[2]).to.include({
      text: "Heads up",
      icon: "info",
      timer: 10000,
    });
    expect(env.current.swal.calls[3].html).to.include("Validation failed");
    expect(env.current.swal.calls[3].html).to.include("Missing field");
  });

  it("renders declarative page alerts once", () => {
    // Build the DOM fixture with server-rendered alert markers.
    document.body.innerHTML = `
      <span data-page-alert data-alert-level="success" data-alert-message="Saved" hidden></span>
      <span data-page-alert data-alert-level="error" data-alert-message="Failed" hidden></span>
    `;

    // Initialize alerts twice to verify markers are consumed only once.
    initializePageAlerts();
    initializePageAlerts();

    // Assert the markers produce one success alert and one error alert.
    expect(env.current.swal.calls).to.have.length(2);
    expect(env.current.swal.calls[0]).to.include({
      text: "Saved",
      icon: "success",
    });
    expect(env.current.swal.calls[1]).to.include({
      text: "Failed",
      icon: "error",
    });
  });

  it("supports persistent and html error alerts", () => {
    // Show a persistent HTML error alert.
    showErrorAlert("<strong>Broken</strong>", true, true);

    // Assert the HTML error stays persistent without a timer.
    expect(env.current.swal.calls).to.have.length(1);
    expect(env.current.swal.calls[0].html).to.equal("<strong>Broken</strong>");
    expect("timer" in env.current.swal.calls[0]).to.equal(false);
  });

  it("renders the deployment refresh retry alert without auto-dismissal", () => {
    // Show the deployment refresh retry alert.
    showDeploymentRefreshRetryAlert();

    // Assert the retry alert stays modal and persistent.
    expect(env.current.swal.calls).to.have.length(1);
    expect(env.current.swal.calls[0]).to.include({
      showConfirmButton: false,
      allowOutsideClick: false,
      allowEscapeKey: false,
      position: "center",
      backdrop: true,
    });
    expect(env.current.swal.calls[0].iconHtml).to.include("icon-network");
    expect(env.current.swal.calls[0].html).to.include("We're deploying an update right now.");
    expect(env.current.swal.calls[0].html).to.include("This page will reload automatically");
    expect("timer" in env.current.swal.calls[0]).to.equal(false);
  });

  it("handles successful, forbidden, validation, and missing xhr responses", () => {
    // Successful responses show the success alert.
    expect(
      handleHtmxResponse({
        xhr: { status: 204 },
        successMessage: "Updated",
        errorMessage: "Failed",
      }),
    ).to.equal(true);

    // Forbidden responses use the permission alert copy.
    expect(
      handleHtmxResponse({
        xhr: { status: 403, responseText: "Forbidden" },
        successMessage: "",
        errorMessage: "Delete failed. Please try again later.",
      }),
    ).to.equal(false);

    // Validation responses include the server message.
    expect(
      handleHtmxResponse({
        xhr: { status: 422, responseText: "Slug already taken" },
        successMessage: "",
        errorMessage: "Save failed. Please try again later.",
      }),
    ).to.equal(false);

    // Missing xhr responses fall back to the provided error message.
    expect(
      handleHtmxResponse({
        xhr: null,
        successMessage: "",
        errorMessage: "Unexpected failure",
      }),
    ).to.equal(false);

    // Assert each response triggers the expected alert and scroll behavior.
    expect(env.current.swal.calls).to.have.length(4);
    expect(env.current.swal.calls[0]).to.include({
      text: "Updated",
      icon: "success",
    });
    expect(env.current.swal.calls[1].text).to.equal(
      "Delete failed. It looks like you don't have permission to perform this operation.",
    );
    expect(env.current.swal.calls[2].html).to.include("Save failed");
    expect(env.current.swal.calls[2].html).to.include("Slug already taken");
    expect(env.current.swal.calls[3].text).to.equal("Unexpected failure");
    expect(env.current.scrollToMock.calls).to.deep.equal([
      { top: 0, behavior: "auto" },
      { top: 0, behavior: "auto" },
      { top: 0, behavior: "auto" },
    ]);
  });

  it("binds standard htmx response alerts", () => {
    // Build the element that receives an HTMX after-request event.
    const button = document.createElement("button");
    bindHtmxResponseAlert(button, {
      successMessage: "Saved",
      errorMessage: "Save failed",
    });

    // Dispatch a successful HTMX response.
    button.dispatchEvent(
      new CustomEvent("htmx:afterRequest", {
        detail: {
          xhr: { status: 204 },
        },
      }),
    );

    // Assert the bound handler delegates to the shared response handling.
    expect(env.current.swal.calls).to.have.length(1);
    expect(env.current.swal.calls[0]).to.include({
      text: "Saved",
      icon: "success",
    });
    expect(() =>
      bindHtmxResponseAlert(null, {
        successMessage: "",
        errorMessage: "Missing",
      }),
    ).not.to.throw();
  });

  it("resolves confirm actions from the swal result", async () => {
    // Mock a declined SweetAlert confirmation.
    env.current.swal.setNextResult({ isConfirmed: false });

    // Capture the declined confirmation result.
    const declined = await confirmAction({
      message: "Delete entry?",
      confirmText: "Yes",
    });

    // Mock an accepted SweetAlert confirmation.
    env.current.swal.setNextResult({ isConfirmed: true });

    // Capture the accepted HTML confirmation result.
    const confirmed = await confirmAction({
      message: "<strong>Delete entry?</strong>",
      confirmText: "Delete",
      cancelText: "Cancel",
      withHtml: true,
    });

    // Assert both confirmation results and their SweetAlert options.
    expect(declined).to.equal(false);
    expect(confirmed).to.equal(true);
    expect(env.current.swal.calls[0]).to.include({
      text: "Delete entry?",
      icon: "warning",
      confirmButtonText: "Yes",
      cancelButtonText: "No",
    });
    expect(env.current.swal.calls[1].html).to.equal(
      "<strong>Delete entry?</strong>",
    );
    expect(env.current.swal.calls[1].confirmButtonText).to.equal("Delete");
    expect(env.current.swal.calls[1].cancelButtonText).to.equal("Cancel");
  });

  it("uses shared stylesheet classes for alert layout", () => {
    // Collect the shared options.
    const options = getCommonAlertOptions();

    // Assert all alert buttons use the shared stylesheet classes.
    expect(options.customClass.popup).to.equal("ocg-swal-popup");
    expect(options.customClass.actions).to.equal("ocg-swal-actions");
    expect(options.customClass.confirmButton).to.equal(
      "btn-primary ocg-swal-button",
    );
    expect(options.customClass.denyButton).to.equal(
      "btn-primary-outline ocg-swal-button",
    );
    expect(options.customClass.cancelButton).to.equal(
      "btn-primary-outline ocg-swal-button",
    );
  });

  it("uses shared alert layout for recurring series confirmations", async () => {
    // Mock the recurring-series choice in SweetAlert.
    env.current.swal.setNextResult({ isConfirmed: false, isDenied: true });

    // Capture the recurring-series confirmation result.
    const result = await confirmSeriesAction({
      message: "Publish this series?",
      confirmText: "Only this event",
      denyText: "All in series",
    });

    // Assert the recurring choice keeps the shared alert layout.
    expect(result).to.equal("series");
    expect(env.current.swal.calls[0].customClass.popup).to.equal(
      "ocg-swal-popup",
    );
    expect(env.current.swal.calls[0].customClass.actions).to.equal(
      "ocg-swal-actions",
    );
  });

  it("triggers htmx confirmed events after confirmation", async () => {
    // Mock an accepted confirmation before showing the alert.
    env.current.swal.setNextResult({ isConfirmed: true });

    // Wait for queued UI work.
    showConfirmAlert("Proceed?", "save-button", "Yes");
    await waitForMicrotask();

    // Accepted confirmation triggers the HTMX confirmed event.
    expect(env.current.htmx.triggerCalls).to.deep.equal([
      ["#save-button", "confirmed"],
    ]);

    // Reset HTMX calls and mock a declined confirmation.
    env.current.htmx.triggerCalls.length = 0;
    env.current.swal.setNextResult({ isConfirmed: false });

    // Wait for queued UI work.
    showConfirmAlert("Proceed?", "save-button", "Yes");
    await waitForMicrotask();

    // Declined confirmation does not trigger HTMX.
    expect(env.current.htmx.triggerCalls).to.deep.equal([]);
  });
});
