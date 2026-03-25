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
import { resetDom, setLocationPath, mockScrollTo } from "/tests/unit/test-utils/dom.js";
import { mockHtmx, mockSwal } from "/tests/unit/test-utils/globals.js";

describe("alerts", () => {
  const originalPath = window.location.pathname;

  let swal;
  let htmx;
  let scrollToMock;

  beforeEach(() => {
    resetDom();
    swal = mockSwal();
    htmx = mockHtmx();
    scrollToMock = mockScrollTo();
    setLocationPath("/dashboard/groups");
  });

  afterEach(() => {
    resetDom();
    swal.restore();
    htmx.restore();
    scrollToMock.restore();
    setLocationPath(originalPath);
  });

  it("renders success, error, info, and server error alerts", () => {
    showSuccessAlert("Saved");
    showErrorAlert("Failed");
    showInfoAlert("Heads up");
    showServerErrorAlert("Validation failed", "Missing field");

    expect(swal.calls).to.have.length(4);
    expect(swal.calls[0]).to.include({ text: "Saved", icon: "success", timer: 5000 });
    expect(swal.calls[1]).to.include({ text: "Failed", icon: "error", timer: 30000 });
    expect(swal.calls[2]).to.include({ text: "Heads up", icon: "info", timer: 10000 });
    expect(swal.calls[3].html).to.include("Validation failed");
    expect(swal.calls[3].html).to.include("Missing field");
  });

  it("supports persistent and html error alerts", () => {
    showErrorAlert("<strong>Broken</strong>", true, true);

    expect(swal.calls).to.have.length(1);
    expect(swal.calls[0].html).to.equal("<strong>Broken</strong>");
    expect("timer" in swal.calls[0]).to.equal(false);
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

    expect(swal.calls).to.have.length(4);
    expect(swal.calls[0]).to.include({ text: "Updated", icon: "success" });
    expect(swal.calls[1].text).to.equal(
      "Delete failed. It looks like you don't have permission to perform this operation.",
    );
    expect(swal.calls[2].html).to.include("Save failed");
    expect(swal.calls[2].html).to.include("Slug already taken");
    expect(swal.calls[3].text).to.equal("Unexpected failure");
    expect(scrollToMock.calls).to.deep.equal([
      { top: 0, behavior: "auto" },
      { top: 0, behavior: "auto" },
      { top: 0, behavior: "auto" },
    ]);
  });

  it("resolves confirm actions from the swal result", async () => {
    swal.setNextResult({ isConfirmed: false });

    const declined = await confirmAction({
      message: "Delete entry?",
      confirmText: "Yes",
    });

    swal.setNextResult({ isConfirmed: true });

    const confirmed = await confirmAction({
      message: "<strong>Delete entry?</strong>",
      confirmText: "Delete",
      cancelText: "Cancel",
      withHtml: true,
    });

    expect(declined).to.equal(false);
    expect(confirmed).to.equal(true);
    expect(swal.calls[0]).to.include({
      text: "Delete entry?",
      icon: "warning",
      confirmButtonText: "Yes",
      cancelButtonText: "No",
    });
    expect(swal.calls[1].html).to.equal("<strong>Delete entry?</strong>");
    expect(swal.calls[1].confirmButtonText).to.equal("Delete");
    expect(swal.calls[1].cancelButtonText).to.equal("Cancel");
  });

  it("triggers htmx confirmed events after confirmation", async () => {
    swal.setNextResult({ isConfirmed: true });

    showConfirmAlert("Proceed?", "save-button", "Yes");
    await waitForMicrotask();

    expect(htmx.triggerCalls).to.deep.equal([["#save-button", "confirmed"]]);

    htmx.triggerCalls.length = 0;
    swal.setNextResult({ isConfirmed: false });

    showConfirmAlert("Proceed?", "save-button", "Yes");
    await waitForMicrotask();

    expect(htmx.triggerCalls).to.deep.equal([]);
  });
});
