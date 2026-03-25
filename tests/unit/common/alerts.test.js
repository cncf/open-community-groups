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

const waitForMicrotask = () => new Promise((resolve) => setTimeout(resolve, 0));

describe("alerts", () => {
  const originalSwal = globalThis.Swal;
  const originalHtmx = globalThis.htmx;
  const originalScrollTo = window.scrollTo;
  const originalPath = window.location.pathname;

  let fireCalls;
  let triggerCalls;
  let nextConfirmResult;
  let scrollCalls;

  beforeEach(() => {
    fireCalls = [];
    triggerCalls = [];
    scrollCalls = [];
    nextConfirmResult = { isConfirmed: true };

    globalThis.Swal = {
      fire: async (options) => {
        fireCalls.push(options);
        return nextConfirmResult;
      },
    };

    globalThis.htmx = {
      trigger: (...args) => {
        triggerCalls.push(args);
      },
    };

    window.scrollTo = (options) => {
      scrollCalls.push(options);
    };

    history.replaceState({}, "", "/dashboard/groups");
  });

  afterEach(() => {
    globalThis.Swal = originalSwal;
    globalThis.htmx = originalHtmx;
    window.scrollTo = originalScrollTo;
    history.replaceState({}, "", originalPath);
  });

  it("renders success, error, info, and server error alerts", () => {
    showSuccessAlert("Saved");
    showErrorAlert("Failed");
    showInfoAlert("Heads up");
    showServerErrorAlert("Validation failed", "Missing field");

    expect(fireCalls).to.have.length(4);
    expect(fireCalls[0]).to.include({ text: "Saved", icon: "success", timer: 5000 });
    expect(fireCalls[1]).to.include({ text: "Failed", icon: "error", timer: 30000 });
    expect(fireCalls[2]).to.include({ text: "Heads up", icon: "info", timer: 10000 });
    expect(fireCalls[3].html).to.include("Validation failed");
    expect(fireCalls[3].html).to.include("Missing field");
  });

  it("supports persistent and html error alerts", () => {
    showErrorAlert("<strong>Broken</strong>", true, true);

    expect(fireCalls).to.have.length(1);
    expect(fireCalls[0].html).to.equal("<strong>Broken</strong>");
    expect("timer" in fireCalls[0]).to.equal(false);
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

    expect(fireCalls).to.have.length(4);
    expect(fireCalls[0]).to.include({ text: "Updated", icon: "success" });
    expect(fireCalls[1].text).to.equal(
      "Delete failed. It looks like you don't have permission to perform this operation.",
    );
    expect(fireCalls[2].html).to.include("Save failed");
    expect(fireCalls[2].html).to.include("Slug already taken");
    expect(fireCalls[3].text).to.equal("Unexpected failure");
    expect(scrollCalls).to.deep.equal([
      { top: 0, behavior: "auto" },
      { top: 0, behavior: "auto" },
      { top: 0, behavior: "auto" },
    ]);
  });

  it("resolves confirm actions from the swal result", async () => {
    nextConfirmResult = { isConfirmed: false };

    const declined = await confirmAction({
      message: "Delete entry?",
      confirmText: "Yes",
    });

    nextConfirmResult = { isConfirmed: true };

    const confirmed = await confirmAction({
      message: "<strong>Delete entry?</strong>",
      confirmText: "Delete",
      cancelText: "Cancel",
      withHtml: true,
    });

    expect(declined).to.equal(false);
    expect(confirmed).to.equal(true);
    expect(fireCalls[0]).to.include({
      text: "Delete entry?",
      icon: "warning",
      confirmButtonText: "Yes",
      cancelButtonText: "No",
    });
    expect(fireCalls[1].html).to.equal("<strong>Delete entry?</strong>");
    expect(fireCalls[1].confirmButtonText).to.equal("Delete");
    expect(fireCalls[1].cancelButtonText).to.equal("Cancel");
  });

  it("triggers htmx confirmed events after confirmation", async () => {
    nextConfirmResult = { isConfirmed: true };

    showConfirmAlert("Proceed?", "save-button", "Yes");
    await waitForMicrotask();

    expect(triggerCalls).to.deep.equal([["#save-button", "confirmed"]]);

    triggerCalls = [];
    nextConfirmResult = { isConfirmed: false };

    showConfirmAlert("Proceed?", "save-button", "Yes");
    await waitForMicrotask();

    expect(triggerCalls).to.deep.equal([]);
  });
});
