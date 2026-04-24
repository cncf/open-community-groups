import { expect } from "@open-wc/testing";

import {
  confirmAction,
  confirmSeriesAction,
  getCommonAlertOptions,
  handleHtmxResponse,
  showConfirmAlert,
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
    showSuccessAlert("Saved");
    showErrorAlert("Failed");
    showInfoAlert("Heads up");
    showServerErrorAlert("Validation failed", "Missing field");

    expect(env.current.swal.calls).to.have.length(4);
    expect(env.current.swal.calls[0]).to.include({ text: "Saved", icon: "success", timer: 5000 });
    expect(env.current.swal.calls[1]).to.include({ text: "Failed", icon: "error", timer: 30000 });
    expect(env.current.swal.calls[2]).to.include({ text: "Heads up", icon: "info", timer: 10000 });
    expect(env.current.swal.calls[3].html).to.include("Validation failed");
    expect(env.current.swal.calls[3].html).to.include("Missing field");
  });

  it("supports persistent and html error alerts", () => {
    showErrorAlert("<strong>Broken</strong>", true, true);

    expect(env.current.swal.calls).to.have.length(1);
    expect(env.current.swal.calls[0].html).to.equal("<strong>Broken</strong>");
    expect("timer" in env.current.swal.calls[0]).to.equal(false);
  });

  it("handles successful, forbidden, validation, and missing xhr responses", () => {
    expect(
      handleHtmxResponse({
        xhr: { status: 204 },
        successMessage: "Updated",
        errorMessage: "Failed",
      }),
    ).to.equal(true);

    expect(
      handleHtmxResponse({
        xhr: { status: 403, responseText: "Forbidden" },
        successMessage: "",
        errorMessage: "Delete failed. Please try again later.",
      }),
    ).to.equal(false);

    expect(
      handleHtmxResponse({
        xhr: { status: 422, responseText: "Slug already taken" },
        successMessage: "",
        errorMessage: "Save failed. Please try again later.",
      }),
    ).to.equal(false);

    expect(
      handleHtmxResponse({
        xhr: null,
        successMessage: "",
        errorMessage: "Unexpected failure",
      }),
    ).to.equal(false);

    expect(env.current.swal.calls).to.have.length(4);
    expect(env.current.swal.calls[0]).to.include({ text: "Updated", icon: "success" });
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

  it("resolves confirm actions from the swal result", async () => {
    env.current.swal.setNextResult({ isConfirmed: false });

    const declined = await confirmAction({
      message: "Delete entry?",
      confirmText: "Yes",
    });

    env.current.swal.setNextResult({ isConfirmed: true });

    const confirmed = await confirmAction({
      message: "<strong>Delete entry?</strong>",
      confirmText: "Delete",
      cancelText: "Cancel",
      withHtml: true,
    });

    expect(declined).to.equal(false);
    expect(confirmed).to.equal(true);
    expect(env.current.swal.calls[0]).to.include({
      text: "Delete entry?",
      icon: "warning",
      confirmButtonText: "Yes",
      cancelButtonText: "No",
    });
    expect(env.current.swal.calls[1].html).to.equal("<strong>Delete entry?</strong>");
    expect(env.current.swal.calls[1].confirmButtonText).to.equal("Delete");
    expect(env.current.swal.calls[1].cancelButtonText).to.equal("Cancel");
  });

  it("uses shared stylesheet classes for alert layout", () => {
    const options = getCommonAlertOptions();

    expect(options.customClass.popup).to.equal("ocg-swal-popup");
    expect(options.customClass.actions).to.equal("ocg-swal-actions");
    expect(options.customClass.confirmButton).to.equal("btn-primary ocg-swal-button");
    expect(options.customClass.denyButton).to.equal("btn-primary-outline ocg-swal-button");
    expect(options.customClass.cancelButton).to.equal("btn-primary-outline ocg-swal-button");
  });

  it("uses shared alert layout for recurring series confirmations", async () => {
    env.current.swal.setNextResult({ isConfirmed: false, isDenied: true });

    const result = await confirmSeriesAction({
      message: "Publish this series?",
      confirmText: "Only this event",
      denyText: "All in series",
    });

    expect(result).to.equal("series");
    expect(env.current.swal.calls[0].customClass.popup).to.equal("ocg-swal-popup");
    expect(env.current.swal.calls[0].customClass.actions).to.equal("ocg-swal-actions");
  });

  it("triggers htmx confirmed events after confirmation", async () => {
    env.current.swal.setNextResult({ isConfirmed: true });

    showConfirmAlert("Proceed?", "save-button", "Yes");
    await waitForMicrotask();

    expect(env.current.htmx.triggerCalls).to.deep.equal([["#save-button", "confirmed"]]);

    env.current.htmx.triggerCalls.length = 0;
    env.current.swal.setNextResult({ isConfirmed: false });

    showConfirmAlert("Proceed?", "save-button", "Yes");
    await waitForMicrotask();

    expect(env.current.htmx.triggerCalls).to.deep.equal([]);
  });
});
