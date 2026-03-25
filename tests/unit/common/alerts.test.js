import { expect } from "@open-wc/testing";

import {
  confirmAction,
  handleHtmxResponse,
  showConfirmAlert,
  showErrorAlert,
  showInfoAlert,
  showServerErrorAlert,
  showSuccessAlert,
} from "/static/js/common/alerts.js";
import { waitForMicrotask } from "/tests/unit/test-utils/async.js";
import { setupDashboardTestEnv } from "/tests/unit/test-utils/env.js";

describe("alerts", () => {
  let env;

  beforeEach(() => {
    env = setupDashboardTestEnv({
      path: "/dashboard/groups",
      withHtmx: true,
      withScroll: true,
      withSwal: true,
    });
  });

  afterEach(() => {
    env.restore();
  });

  it("renders success, error, info, and server error alerts", () => {
    showSuccessAlert("Saved");
    showErrorAlert("Failed");
    showInfoAlert("Heads up");
    showServerErrorAlert("Validation failed", "Missing field");

    expect(env.swal.calls).to.have.length(4);
    expect(env.swal.calls[0]).to.include({ text: "Saved", icon: "success", timer: 5000 });
    expect(env.swal.calls[1]).to.include({ text: "Failed", icon: "error", timer: 30000 });
    expect(env.swal.calls[2]).to.include({ text: "Heads up", icon: "info", timer: 10000 });
    expect(env.swal.calls[3].html).to.include("Validation failed");
    expect(env.swal.calls[3].html).to.include("Missing field");
  });

  it("supports persistent and html error alerts", () => {
    showErrorAlert("<strong>Broken</strong>", true, true);

    expect(env.swal.calls).to.have.length(1);
    expect(env.swal.calls[0].html).to.equal("<strong>Broken</strong>");
    expect("timer" in env.swal.calls[0]).to.equal(false);
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

    expect(env.swal.calls).to.have.length(4);
    expect(env.swal.calls[0]).to.include({ text: "Updated", icon: "success" });
    expect(env.swal.calls[1].text).to.equal(
      "Delete failed. It looks like you don't have permission to perform this operation.",
    );
    expect(env.swal.calls[2].html).to.include("Save failed");
    expect(env.swal.calls[2].html).to.include("Slug already taken");
    expect(env.swal.calls[3].text).to.equal("Unexpected failure");
    expect(env.scrollToMock.calls).to.deep.equal([
      { top: 0, behavior: "auto" },
      { top: 0, behavior: "auto" },
      { top: 0, behavior: "auto" },
    ]);
  });

  it("resolves confirm actions from the swal result", async () => {
    env.swal.setNextResult({ isConfirmed: false });

    const declined = await confirmAction({
      message: "Delete entry?",
      confirmText: "Yes",
    });

    env.swal.setNextResult({ isConfirmed: true });

    const confirmed = await confirmAction({
      message: "<strong>Delete entry?</strong>",
      confirmText: "Delete",
      cancelText: "Cancel",
      withHtml: true,
    });

    expect(declined).to.equal(false);
    expect(confirmed).to.equal(true);
    expect(env.swal.calls[0]).to.include({
      text: "Delete entry?",
      icon: "warning",
      confirmButtonText: "Yes",
      cancelButtonText: "No",
    });
    expect(env.swal.calls[1].html).to.equal("<strong>Delete entry?</strong>");
    expect(env.swal.calls[1].confirmButtonText).to.equal("Delete");
    expect(env.swal.calls[1].cancelButtonText).to.equal("Cancel");
  });

  it("triggers htmx confirmed events after confirmation", async () => {
    env.swal.setNextResult({ isConfirmed: true });

    showConfirmAlert("Proceed?", "save-button", "Yes");
    await waitForMicrotask();

    expect(env.htmx.triggerCalls).to.deep.equal([["#save-button", "confirmed"]]);

    env.htmx.triggerCalls.length = 0;
    env.swal.setNextResult({ isConfirmed: false });

    showConfirmAlert("Proceed?", "save-button", "Yes");
    await waitForMicrotask();

    expect(env.htmx.triggerCalls).to.deep.equal([]);
  });
});
