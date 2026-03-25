import { expect } from "@open-wc/testing";

import "/static/js/dashboard/confirm-actions.js";

const waitForMicrotask = () => new Promise((resolve) => setTimeout(resolve, 0));

describe("confirm actions", () => {
  const originalSwal = globalThis.Swal;
  const originalHtmx = globalThis.htmx;

  let fireCalls;
  let triggerCalls;
  let nextConfirmResult;

  beforeEach(() => {
    fireCalls = [];
    triggerCalls = [];
    nextConfirmResult = { isConfirmed: true };
    document.body.innerHTML = "";

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
  });

  afterEach(() => {
    document.body.innerHTML = "";
    globalThis.Swal = originalSwal;
    globalThis.htmx = originalHtmx;
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

    expect(fireCalls).to.have.length(1);
    expect(fireCalls[0].text).to.equal("Delete this event?");
    expect(fireCalls[0].confirmButtonText).to.equal("Delete");
    expect(triggerCalls).to.deep.equal([["#delete-button", "confirmed"]]);
  });

  it("ignores disabled confirm-action buttons", async () => {
    document.body.innerHTML = `
      <button id="delete-button" data-confirm-action="true" disabled>
        Delete
      </button>
    `;

    document.getElementById("delete-button")?.click();
    await waitForMicrotask();

    expect(fireCalls).to.have.length(0);
    expect(triggerCalls).to.have.length(0);
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

    expect(fireCalls).to.have.length(1);
    expect(fireCalls[0]).to.include({ text: "Published successfully.", icon: "success" });
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

    expect(fireCalls).to.have.length(1);
    expect(fireCalls[0]).to.include({ text: "Publish failed.", icon: "error" });
  });
});
