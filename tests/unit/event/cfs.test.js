import { expect } from "@open-wc/testing";

import { waitForMicrotask } from "/tests/unit/test-utils/async.js";
import { resetDom } from "/tests/unit/test-utils/dom.js";
import { mockSwal } from "/tests/unit/test-utils/globals.js";
import { dispatchHtmxAfterSwap } from "/tests/unit/test-utils/htmx.js";

describe("event cfs modal", () => {
  afterEach(() => {
    resetDom();
  });

  it("opens after the modal root is swapped and enables or disables submit as the selection changes", async () => {
    // Build the modal fixture after the root is swapped.
    document.body.innerHTML = `
      <div id="cfs-modal-root"></div>
      <div id="cfs-modal" class="hidden">
        <button id="close-cfs-modal" type="button">Close</button>
        <div id="overlay-cfs-modal"></div>
        <button id="cancel-cfs-modal" type="button">Cancel</button>
        <select id="session_proposal_id">
          <option value="">Pick one</option>
          <option value="12">Proposal</option>
        </select>
        <button id="cfs-submit-button" type="button">Submit</button>
      </div>
    `;

    // Load the CFS module after setup.
    await import(`/static/js/event/cfs.js?test=${Date.now()}`);

    // Dispatch the HTMX after-swap event.
    dispatchHtmxAfterSwap(document.getElementById("cfs-modal-root"));
    await waitForMicrotask();

    // Read the CFS modal after the swapped root is initialized.
    const modal = document.getElementById("cfs-modal");
    const select = document.getElementById("session_proposal_id");
    const submit = document.getElementById("cfs-submit-button");

    // Assert the expected visibility state.
    expect(modal.classList.contains("hidden")).to.equal(false);
    expect(submit.disabled).to.equal(true);

    // Enter the maximum title length.
    select.value = "12";
    select.dispatchEvent(new Event("change", { bubbles: true }));

    // Assert the submit button state.
    expect(submit.disabled).to.equal(false);

    // Assert the behavior after the update.
    select.value = "";
    select.dispatchEvent(new Event("change", { bubbles: true }));

    // Assert the updated submit button state.
    expect(submit.disabled).to.equal(true);
  });

  it("closes from the close button, overlay, and cancel button without duplicating listeners", async () => {
    // Render the DOM fixture for closing from the close button, overlay.
    document.body.innerHTML = `
      <div id="cfs-modal-root"></div>
      <div id="cfs-modal" class="hidden">
        <button id="close-cfs-modal" type="button">Close</button>
        <div id="overlay-cfs-modal"></div>
        <button id="cancel-cfs-modal" type="button">Cancel</button>
        <select id="session_proposal_id">
          <option value="">Pick one</option>
          <option value="12">Proposal</option>
        </select>
        <button id="cfs-submit-button" type="button">Submit</button>
      </div>
    `;

    // Load the CFS module after setup.
    await import(`/static/js/event/cfs.js?test=${Date.now()}-close`);

    // Keep a reference to the CFS modal root element.
    const root = document.getElementById("cfs-modal-root");
    const modal = document.getElementById("cfs-modal");
    dispatchHtmxAfterSwap(root);
    dispatchHtmxAfterSwap(root);
    await waitForMicrotask();

    // Verify closes from the close button, overlay.
    document.getElementById("close-cfs-modal")?.click();
    expect(modal.classList.contains("hidden")).to.equal(true);

    // Dispatch the HTMX after-swap event.
    dispatchHtmxAfterSwap(root);
    await waitForMicrotask();
    document.getElementById("overlay-cfs-modal")?.click();
    expect(modal.classList.contains("hidden")).to.equal(true);

    // Dispatch the HTMX after-swap event again.
    dispatchHtmxAfterSwap(root);
    await waitForMicrotask();
    document.getElementById("cancel-cfs-modal")?.click();
    expect(modal.classList.contains("hidden")).to.equal(true);
  });

  it("opens after the page body is swapped", async () => {
    // Load the CFS module after setup.
    await import(`/static/js/event/cfs.js?test=${Date.now()}-body-swap`);

    // Prepare a replacement body for the HTMX swap.
    const replacementBody = document.createElement("body");
    replacementBody.innerHTML = `
      <div id="cfs-modal-root"></div>
      <div id="cfs-modal" class="hidden">
        <button id="close-cfs-modal" type="button">Close</button>
        <div id="overlay-cfs-modal"></div>
        <button id="cancel-cfs-modal" type="button">Cancel</button>
        <select id="session_proposal_id">
          <option value="">Pick one</option>
          <option value="12">Proposal</option>
        </select>
        <button id="cfs-submit-button" type="button">Submit</button>
      </div>
    `;
    document.documentElement.replaceChild(replacementBody, document.body);

    // Dispatch the HTMX after-swap event.
    dispatchHtmxAfterSwap(document.getElementById("cfs-modal-root"));
    await waitForMicrotask();

    // Verify opens after the page body is swapped.
    expect(document.getElementById("cfs-modal")?.classList.contains("hidden")).to.equal(false);
  });

  it("prompts incomplete profiles after loading the proposal modal", async () => {
    const swal = mockSwal();
    try {
      swal.setNextResult({ isConfirmed: false });
      document.body.innerHTML = `
        <button
          id="open-cfs-modal"
          type="button"
          data-profile-complete="false"
        >
          Submit session proposal
        </button>
        <div id="cfs-modal-root"></div>
        <div id="cfs-modal" class="hidden">
          <button id="close-cfs-modal" type="button">Close</button>
          <div id="overlay-cfs-modal"></div>
          <button id="cancel-cfs-modal" type="button">Cancel</button>
          <select id="session_proposal_id">
            <option value="">Pick one</option>
            <option value="12">Proposal</option>
          </select>
          <button id="cfs-submit-button" type="button">Submit</button>
        </div>
      `;

      // Load the CFS module after setup.
      await import(`/static/js/event/cfs.js?test=${Date.now()}-profile`);
      const button = document.getElementById("open-cfs-modal");
      const event = new CustomEvent("htmx:beforeRequest", {
        bubbles: true,
        cancelable: true,
      });

      // Dispatch the HTMX request event.
      button.dispatchEvent(event);
      await waitForMicrotask();

      // Verify the request continues before the modal swap.
      expect(event.defaultPrevented).to.equal(false);
      expect(swal.calls).to.have.length(0);

      // Dispatch the HTMX after-swap event.
      dispatchHtmxAfterSwap(document.getElementById("cfs-modal-root"));
      await waitForMicrotask();

      // Verify the prompt appears after the modal opens.
      expect(document.getElementById("cfs-modal")?.classList.contains("hidden")).to.equal(false);
      expect(swal.calls.at(-1)).to.include({
        title: "Make your profile yours",
        confirmButtonText: "Complete profile",
        cancelButtonText: "Continue anyway",
      });
    } finally {
      swal.restore();
    }
  });

  it("keeps successful proposal submissions on the inline confirmation", async () => {
    const swal = mockSwal();
    try {
      swal.setNextResult({ isConfirmed: false });
      document.body.innerHTML = `
        <div id="cfs-modal-root"></div>
        <div id="cfs-modal">
          <form
            id="cfs-submission-form"
            data-profile-complete="false"
          ></form>
        </div>
      `;

      // Load the CFS module after setup.
      await import(`/static/js/event/cfs.js?test=${Date.now()}-submit-profile`);
      const form = document.getElementById("cfs-submission-form");
      const event = new CustomEvent("htmx:beforeRequest", {
        bubbles: true,
        cancelable: true,
      });

      // Dispatch the HTMX request event.
      form.dispatchEvent(event);
      await waitForMicrotask();

      // Verify the request continues without opening a profile prompt.
      expect(event.defaultPrevented).to.equal(false);
      expect(swal.calls).to.have.length(0);

      // Swap a successful submission notice into the modal root.
      document.getElementById("cfs-modal-root").innerHTML = `
        <div data-cfs-submission-notice>Submitted</div>
      `;
      dispatchHtmxAfterSwap(document.getElementById("cfs-modal-root"));
      await waitForMicrotask();

      // Verify the successful response stays visible without a second dialog.
      expect(document.querySelector("[data-cfs-submission-notice]")?.textContent).to.include("Submitted");
      expect(swal.calls).to.have.length(0);
    } finally {
      swal.restore();
    }
  });
});
