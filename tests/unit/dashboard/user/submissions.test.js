import { expect } from "@open-wc/testing";

import "/static/js/dashboard/user/submissions.js";
import { waitForMicrotask } from "/tests/unit/test-utils/async.js";
import { useDashboardTestEnv } from "/tests/unit/test-utils/env.js";
import {
  dispatchHtmxAfterRequest,
  dispatchHtmxLoad,
} from "/tests/unit/test-utils/htmx.js";

describe("dashboard user submissions", () => {
  const env = useDashboardTestEnv({
    path: "/dashboard/user/submissions",
    withHtmx: true,
    withScroll: true,
    withSwal: true,
  });

  // Initialize submissions ui for the test.
  const initializeSubmissionsUi = () => {
    dispatchHtmxLoad();
  };

  it("opens and closes the action required modal with the selected message", () => {
    // Build the DOM fixture to check it opens and closes the action required modal.
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

    // Exercise the flow to check it opens and closes the action required modal.
    initializeSubmissionsUi();

    // Read the action required modal element to check it opens and closes the action.
    const modal = document.getElementById("action-required-modal");
    const message = document.getElementById("action-required-modal-message");

    // Exercise the flow to check it opens and closes the action required modal.
    document
      .querySelector('[data-action="open-action-required-modal"]')
      ?.click();

    // Confirm it opens and closes the action required modal with the selected message.
    expect(message.textContent).to.equal(
      "Please update the abstract before resubmitting.",
    );
    expect(modal.classList.contains("hidden")).to.equal(false);
    expect(document.body.style.overflow).to.equal("hidden");

    // Trigger the user interaction to check it opens and closes the action required.
    document.getElementById("close-action-required-modal")?.click();

    // Confirm it opens and closes the action required modal with the selected message.
    expect(modal.classList.contains("hidden")).to.equal(true);
    expect(document.body.style.overflow).to.equal("");
  });

  it("opens the action required modal after the dashboard body is swapped", () => {
    // Prepare replacement body to check it opens the action required modal.
    const replacementBody = document.createElement("body");
    replacementBody.innerHTML = `
      <div id="action-required-modal" class="hidden"></div>
      <div id="action-required-modal-message"></div>
      <button id="close-action-required-modal" type="button">Close</button>
      <button id="cancel-action-required-modal" type="button">Cancel</button>
      <div id="overlay-action-required-modal"></div>
      <button
        type="button"
        data-action="open-action-required-modal"
        data-action-required-message="Please update the bio before resubmitting."
      >
        Open
      </button>
    `;
    document.documentElement.replaceChild(replacementBody, document.body);

    // Exercise the flow to check it opens the action required modal after the dashboard.
    initializeSubmissionsUi();
    document
      .querySelector('[data-action="open-action-required-modal"]')
      ?.click();

    // Confirm it opens the action required modal after the dashboard body is swapped.
    expect(
      document.getElementById("action-required-modal-message")?.textContent,
    ).to.equal("Please update the bio before resubmitting.");
    expect(
      document
        .getElementById("action-required-modal")
        ?.classList.contains("hidden"),
    ).to.equal(false);
  });

  it("opens a confirmation dialog for withdraw actions and handles request errors", async () => {
    // Build the DOM fixture to check it opens a confirmation dialog for withdraw actions.
    document.body.innerHTML = `
      <button
        type="button"
        data-action="withdraw-submission"
        data-submission-id="submission-42"
      >
        Withdraw
      </button>
    `;

    // Exercise the flow to check it opens a confirmation dialog for withdraw actions.
    initializeSubmissionsUi();

    // Read the DOM to check it opens a confirmation dialog for withdraw actions.
    const button = document.querySelector(
      '[data-action="withdraw-submission"]',
    );
    button.click();
    await waitForMicrotask();

    // Confirm it opens a confirmation dialog for withdraw actions and handles request.
    expect(button.id).to.equal("withdraw-submission-submission-42");
    expect(env.current.swal.calls).to.have.length(1);
    expect(env.current.swal.calls[0].html).to.include(
      "Are you sure you want to withdraw this submission?",
    );
    expect(env.current.swal.calls[0].confirmButtonText).to.equal("Withdraw");
    expect(env.current.htmx.triggerCalls).to.deep.equal([
      ["#withdraw-submission-submission-42", "confirmed"],
    ]);

    // Dispatch the HTMX after request event to check it opens a confirmation dialog.
    dispatchHtmxAfterRequest(button, {
      status: 500,
    });

    // Confirm it opens a confirmation dialog for withdraw actions and handles request.
    expect(env.current.swal.calls).to.have.length(2);
    expect(env.current.swal.calls[1]).to.include({
      text: "Unable to withdraw this submission. Please try again later.",
      icon: "error",
    });
    expect(env.current.scrollToMock.calls).to.deep.equal([
      { top: 0, behavior: "auto" },
    ]);
  });

  it("opens a resubmit confirmation dialog and handles successful requests", async () => {
    // Build the DOM fixture to check it opens a resubmit confirmation dialog and handles.
    document.body.innerHTML = `
      <button
        type="button"
        data-action="resubmit-submission"
        data-submission-id="submission-84"
      >
        Resubmit
      </button>
    `;

    // Exercise the flow to check it opens a resubmit confirmation dialog and handles.
    initializeSubmissionsUi();

    // Read the DOM to check it opens a resubmit confirmation dialog and handles.
    const button = document.querySelector(
      '[data-action="resubmit-submission"]',
    );
    button.click();
    await waitForMicrotask();

    // Confirm it opens a resubmit confirmation dialog and handles successful requests.
    expect(button.id).to.equal("resubmit-submission-submission-84");
    expect(env.current.swal.calls).to.have.length(1);
    expect(env.current.swal.calls[0].html).to.include(
      "Before resubmitting, please make sure",
    );
    expect(env.current.swal.calls[0].confirmButtonText).to.equal("Resubmit");
    expect(env.current.htmx.triggerCalls).to.deep.equal([
      ["#resubmit-submission-submission-84", "confirmed"],
    ]);

    // Dispatch the HTMX after request event to check it opens a resubmit confirmation.
    dispatchHtmxAfterRequest(button, {
      status: 204,
    });

    // Confirm it opens a resubmit confirmation dialog and handles successful requests.
    expect(env.current.swal.calls).to.have.length(1);
  });
});
