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
    // Render the DOM fixture for opening and closes the action required modal.
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

    // Call initialize submissions ui.
    initializeSubmissionsUi();

    // Keep a reference to the action required modal element.
    const modal = document.getElementById("action-required-modal");
    const message = document.getElementById("action-required-modal-message");

    // Click the next control.
    document
      .querySelector('[data-action="open-action-required-modal"]')
      ?.click();

    // Verify opens and closes the action required modal with the selected message.
    expect(message.textContent).to.equal(
      "Please update the abstract before resubmitting.",
    );
    expect(modal.classList.contains("hidden")).to.equal(false);
    expect(document.body.style.overflow).to.equal("hidden");

    // Verify opens and closes the action required.
    document.getElementById("close-action-required-modal")?.click();

    // Verify opens and closes the action required modal with the selected message.
    expect(modal.classList.contains("hidden")).to.equal(true);
    expect(document.body.style.overflow).to.equal("");
  });

  it("opens the action required modal after the dashboard body is swapped", () => {
    // Prepare replacement body for opening the action required modal.
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

    // Verify opens the action required modal after the dashboard.
    initializeSubmissionsUi();
    document
      .querySelector('[data-action="open-action-required-modal"]')
      ?.click();

    // Verify opens the action required modal after the dashboard body is swapped.
    expect(
      document.getElementById("action-required-modal-message")?.textContent,
    ).to.equal("Please update the bio before resubmitting.");
    expect(
      document
        .getElementById("action-required-modal")
        ?.classList.contains("hidden"),
    ).to.equal(false);
  });

  it("opens the action required modal when swapped triggers and modal are siblings", () => {
    // Render the sibling roots produced by user dashboard submissions swaps.
    document.body.innerHTML = `
      <div id="submissions-list">
        <button
          type="button"
          data-action="open-action-required-modal"
          data-action-required-message="Please update the outline before resubmitting."
        >
          Open
        </button>
      </div>
      <div id="action-required-modal" class="hidden"></div>
      <div id="action-required-modal-message"></div>
      <button id="close-action-required-modal" type="button">Close</button>
      <button id="cancel-action-required-modal" type="button">Cancel</button>
      <div id="overlay-action-required-modal"></div>
    `;

    // Initialize each top-level swapped child independently.
    dispatchHtmxLoad(document.getElementById("submissions-list"));
    dispatchHtmxLoad(document.getElementById("action-required-modal"));

    // Open the modal from the trigger sibling.
    document
      .querySelector('[data-action="open-action-required-modal"]')
      ?.click();

    // The document-level modal fallback keeps sibling triggers working.
    expect(
      document.getElementById("action-required-modal-message")?.textContent,
    ).to.equal("Please update the outline before resubmitting.");
    expect(
      document
        .getElementById("action-required-modal")
        ?.classList.contains("hidden"),
    ).to.equal(false);
  });

  it("opens a confirmation dialog for withdraw actions and handles request errors", async () => {
    // Render the DOM fixture for opening a confirmation dialog for withdraw actions.
    document.body.innerHTML = `
      <button
        type="button"
        data-action="withdraw-submission"
        data-submission-id="submission-42"
      >
        Withdraw
      </button>
    `;

    // Verify opens a confirmation dialog for withdraw actions.
    initializeSubmissionsUi();

    // Read the rendered DOM state for opening a confirmation dialog for withdraw actions.
    const button = document.querySelector(
      '[data-action="withdraw-submission"]',
    );
    button.click();
    await waitForMicrotask();

    // Verify withdraw request errors keep the confirmation flow visible.
    expect(button.id).to.equal("withdraw-submission-submission-42");
    expect(env.current.swal.calls).to.have.length(1);
    expect(env.current.swal.calls[0].html).to.include(
      "Are you sure you want to withdraw this submission?",
    );
    expect(env.current.swal.calls[0].confirmButtonText).to.equal("Withdraw");
    expect(env.current.htmx.triggerCalls).to.deep.equal([
      ["#withdraw-submission-submission-42", "confirmed"],
    ]);

    // Dispatch the HTMX after-request event.
    dispatchHtmxAfterRequest(button, {
      status: 500,
    });

    // Verify withdraw success clears the confirmation state.
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
    // Render the DOM fixture for opening a resubmit confirmation dialog and handles.
    document.body.innerHTML = `
      <button
        type="button"
        data-action="resubmit-submission"
        data-submission-id="submission-84"
      >
        Resubmit
      </button>
    `;

    // Verify opens a resubmit confirmation dialog and handles.
    initializeSubmissionsUi();

    // Read the rendered DOM state for opening a resubmit confirmation dialog and handles.
    const button = document.querySelector(
      '[data-action="resubmit-submission"]',
    );
    button.click();
    await waitForMicrotask();

    // Verify opens a resubmit confirmation dialog and handles successful requests.
    expect(button.id).to.equal("resubmit-submission-submission-84");
    expect(env.current.swal.calls).to.have.length(1);
    expect(env.current.swal.calls[0].html).to.include(
      "Before resubmitting, please make sure",
    );
    expect(env.current.swal.calls[0].confirmButtonText).to.equal("Resubmit");
    expect(env.current.htmx.triggerCalls).to.deep.equal([
      ["#resubmit-submission-submission-84", "confirmed"],
    ]);

    // Dispatch the HTMX after-request event.
    dispatchHtmxAfterRequest(button, {
      status: 204,
    });

    // Verify opens a resubmit confirmation dialog and handles successful requests.
    expect(env.current.swal.calls).to.have.length(1);
  });
});
