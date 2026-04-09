import { expect } from "@open-wc/testing";

import "/static/js/dashboard/user/submissions.js";
import { waitForMicrotask } from "/tests/unit/test-utils/async.js";
import { setupDashboardTestEnv } from "/tests/unit/test-utils/env.js";

describe("dashboard user submissions", () => {
  let env;

  beforeEach(() => {
    env = setupDashboardTestEnv({
      path: "/dashboard/user/submissions",
      withHtmx: true,
      withScroll: true,
      withSwal: true,
    });
  });

  afterEach(() => {
    env.restore();
  });

  const initializeSubmissionsUi = () => {
    document.body.dispatchEvent(new CustomEvent("htmx:load", { bubbles: true }));
  };

  it("opens and closes the action required modal with the selected message", () => {
    document.body.innerHTML = `
      <div id="action-required-modal" class="hidden"></div>
      <div id="action-required-modal-message"></div>
      <button id="close-action-required-modal" type="button">Close</button>
      <button id="cancel-action-required-modal" type="button">Cancel</button>
      <div id="overlay-action-required-modal"></div>
      <button
        type="button"
        data-action="open-action-required-modal"
        data-action-required-message="Please update the abstract before resubmitting."
      >
        Open
      </button>
    `;

    initializeSubmissionsUi();

    const modal = document.getElementById("action-required-modal");
    const message = document.getElementById("action-required-modal-message");

    document.querySelector('[data-action="open-action-required-modal"]')?.click();

    expect(message.textContent).to.equal("Please update the abstract before resubmitting.");
    expect(modal.classList.contains("hidden")).to.equal(false);
    expect(document.body.style.overflow).to.equal("hidden");

    document.getElementById("close-action-required-modal")?.click();

    expect(modal.classList.contains("hidden")).to.equal(true);
    expect(document.body.style.overflow).to.equal("");
  });

  it("opens a confirmation dialog for withdraw actions and handles request errors", async () => {
    document.body.innerHTML = `
      <button
        type="button"
        data-action="withdraw-submission"
        data-submission-id="submission-42"
      >
        Withdraw
      </button>
    `;

    initializeSubmissionsUi();

    const button = document.querySelector('[data-action="withdraw-submission"]');
    button.click();
    await waitForMicrotask();

    expect(button.id).to.equal("withdraw-submission-submission-42");
    expect(env.swal.calls).to.have.length(1);
    expect(env.swal.calls[0].html).to.include("Are you sure you want to withdraw this submission?");
    expect(env.swal.calls[0].confirmButtonText).to.equal("Withdraw");
    expect(env.htmx.triggerCalls).to.deep.equal([["#withdraw-submission-submission-42", "confirmed"]]);

    button.dispatchEvent(
      new CustomEvent("htmx:afterRequest", {
        bubbles: true,
        detail: {
          xhr: {
            status: 500,
          },
        },
      }),
    );

    expect(env.swal.calls).to.have.length(2);
    expect(env.swal.calls[1]).to.include({
      text: "Unable to withdraw this submission. Please try again later.",
      icon: "error",
    });
    expect(env.scrollToMock.calls).to.deep.equal([{ top: 0, behavior: "auto" }]);
  });

  it("opens a resubmit confirmation dialog and handles successful requests", async () => {
    document.body.innerHTML = `
      <button
        type="button"
        data-action="resubmit-submission"
        data-submission-id="submission-84"
      >
        Resubmit
      </button>
    `;

    initializeSubmissionsUi();

    const button = document.querySelector('[data-action="resubmit-submission"]');
    button.click();
    await waitForMicrotask();

    expect(button.id).to.equal("resubmit-submission-submission-84");
    expect(env.swal.calls).to.have.length(1);
    expect(env.swal.calls[0].html).to.include("Before resubmitting, please make sure");
    expect(env.swal.calls[0].confirmButtonText).to.equal("Resubmit");
    expect(env.htmx.triggerCalls).to.deep.equal([["#resubmit-submission-submission-84", "confirmed"]]);

    button.dispatchEvent(
      new CustomEvent("htmx:afterRequest", {
        bubbles: true,
        detail: {
          xhr: {
            status: 204,
          },
        },
      }),
    );

    expect(env.swal.calls).to.have.length(1);
  });
});
