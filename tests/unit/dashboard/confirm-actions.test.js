import { expect } from "@open-wc/testing";

import "/static/js/dashboard/confirm-actions.js";
import { waitForMicrotask } from "/tests/unit/test-utils/async.js";
import { resetDom } from "/tests/unit/test-utils/dom.js";
import { mockHtmx, mockSwal } from "/tests/unit/test-utils/globals.js";

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

    document.getElementById("delete-button")?.click();
    await waitForMicrotask();

    expect(swal.calls).to.have.length(1);
    expect(swal.calls[0].text).to.equal("Delete this event?");
    expect(swal.calls[0].confirmButtonText).to.equal("Delete");
    expect(htmx.triggerCalls).to.deep.equal([["#delete-button", "confirmed"]]);
  });

  it("ignores disabled confirm-action buttons", async () => {
    document.body.innerHTML = `
      <button id="delete-button" data-confirm-action="true" disabled>
        Delete
      </button>
    `;

    document.getElementById("delete-button")?.click();
    await waitForMicrotask();

    expect(swal.calls).to.have.length(0);
    expect(htmx.triggerCalls).to.have.length(0);
  });

  it("handles successful htmx requests for confirm-action buttons", () => {
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

    document.getElementById("publish-button")?.dispatchEvent(
      new CustomEvent("htmx:afterRequest", {
        bubbles: true,
        detail: {
          xhr: { status: 204 },
        },
      }),
    );

    expect(swal.calls).to.have.length(1);
    expect(swal.calls[0]).to.include({ text: "Published successfully.", icon: "success" });
  });

  it("handles failed htmx requests for confirm-action buttons", () => {
    document.body.innerHTML = `
      <button
        id="publish-button"
        data-confirm-action="true"
        data-error-message="Publish failed."
      >
        Publish
      </button>
    `;

    document.getElementById("publish-button")?.dispatchEvent(
      new CustomEvent("htmx:afterRequest", {
        bubbles: true,
        detail: {
          xhr: { status: 500 },
        },
      }),
    );

    expect(swal.calls).to.have.length(1);
    expect(swal.calls[0]).to.include({ text: "Publish failed.", icon: "error" });
  });
});
