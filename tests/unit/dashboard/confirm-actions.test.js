import { expect } from "@open-wc/testing";

import "/static/js/dashboard/confirm-actions.js";
import { waitForMicrotask } from "/tests/unit/test-utils/async.js";
import { resetDom } from "/tests/unit/test-utils/dom.js";
import { mockHtmx, mockSwal } from "/tests/unit/test-utils/globals.js";
import { dispatchHtmxAfterRequest } from "/tests/unit/test-utils/htmx.js";

describe("confirm actions", () => {
  let swal;
  let htmx;

  beforeEach(() => {
    resetDom();
    swal = mockSwal();
    htmx = mockHtmx();
  });

  afterEach(() => {
    resetDom();
    swal.restore();
    htmx.restore();
  });

  it("opens a confirmation dialog for confirm-action buttons", async () => {
    // Build the DOM fixture to check it opens a confirmation dialog for confirm-action.
    document.body.innerHTML = `
      <button
        id="delete-button"
        data-confirm-action="true"
        data-confirm-message="Delete this event?"
        data-confirm-text="Delete"
      >
        Delete
      </button>
    `;

    // Trigger the user interaction to check it opens a confirmation dialog.
    document.getElementById("delete-button")?.click();
    await waitForMicrotask();

    // Confirm it opens a confirmation dialog for confirm-action buttons.
    expect(swal.calls).to.have.length(1);
    expect(swal.calls[0].text).to.equal("Delete this event?");
    expect(swal.calls[0].confirmButtonText).to.equal("Delete");
    expect(htmx.triggerCalls).to.deep.equal([["#delete-button", "confirmed"]]);
  });

  it("ignores disabled confirm-action buttons", async () => {
    // Build the DOM fixture to check it ignores disabled confirm-action buttons.
    document.body.innerHTML = `
      <button id="delete-button" data-confirm-action="true" disabled>
        Delete
      </button>
    `;

    // Trigger the user interaction to check it ignores disabled confirm-action buttons.
    document.getElementById("delete-button")?.click();
    await waitForMicrotask();

    // Confirm it ignores disabled confirm-action buttons.
    expect(swal.calls).to.have.length(0);
    expect(htmx.triggerCalls).to.have.length(0);
  });

  it("handles successful htmx requests for confirm-action buttons", () => {
    // Build the DOM fixture to check it handles successful HTMX requests.
    document.body.innerHTML = `
      <button
        id="publish-button"
        data-confirm-action="true"
        data-success-message="Published successfully."
        data-error-message="Publish failed."
      >
        Publish
      </button>
    `;

    // Dispatch the HTMX after request event to check it handles successful HTMX requests.
    dispatchHtmxAfterRequest(document.getElementById("publish-button"), {
      status: 204,
    });

    // Confirm it handles successful HTMX requests for confirm-action buttons.
    expect(swal.calls).to.have.length(1);
    expect(swal.calls[0]).to.include({
      text: "Published successfully.",
      icon: "success",
    });
  });

  it("handles failed htmx requests for confirm-action buttons", () => {
    // Build the DOM fixture to check it handles failed HTMX requests for confirm-action.
    document.body.innerHTML = `
      <button
        id="publish-button"
        data-confirm-action="true"
        data-error-message="Publish failed."
      >
        Publish
      </button>
    `;

    // Dispatch the HTMX after request event to check it handles failed HTMX requests.
    dispatchHtmxAfterRequest(document.getElementById("publish-button"), {
      status: 500,
    });

    // Confirm it handles failed HTMX requests for confirm-action buttons.
    expect(swal.calls).to.have.length(1);
    expect(swal.calls[0]).to.include({
      text: "Publish failed.",
      icon: "error",
    });
  });
});
