import { expect } from "@open-wc/testing";

import { waitForMicrotask } from "/tests/unit/test-utils/async.js";
import { resetDom } from "/tests/unit/test-utils/dom.js";
import { dispatchHtmxAfterSwap } from "/tests/unit/test-utils/htmx.js";

describe("event cfs modal", () => {
  afterEach(() => {
    resetDom();
  });

  it("opens after the modal root is swapped and enables or disables submit as the selection changes", async () => {
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

    await import(`/static/js/event/cfs.js?test=${Date.now()}`);

    dispatchHtmxAfterSwap(document.getElementById("cfs-modal-root"));
    await waitForMicrotask();

    const modal = document.getElementById("cfs-modal");
    const select = document.getElementById("session_proposal_id");
    const submit = document.getElementById("cfs-submit-button");

    expect(modal.classList.contains("hidden")).to.equal(false);
    expect(submit.disabled).to.equal(true);

    select.value = "12";
    select.dispatchEvent(new Event("change", { bubbles: true }));

    expect(submit.disabled).to.equal(false);

    select.value = "";
    select.dispatchEvent(new Event("change", { bubbles: true }));

    expect(submit.disabled).to.equal(true);
  });

  it("closes from the close button, overlay, and cancel button without duplicating listeners", async () => {
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

    await import(`/static/js/event/cfs.js?test=${Date.now()}-close`);

    const root = document.getElementById("cfs-modal-root");
    const modal = document.getElementById("cfs-modal");
    dispatchHtmxAfterSwap(root);
    dispatchHtmxAfterSwap(root);
    await waitForMicrotask();

    document.getElementById("close-cfs-modal")?.click();
    expect(modal.classList.contains("hidden")).to.equal(true);

    dispatchHtmxAfterSwap(root);
    await waitForMicrotask();
    document.getElementById("overlay-cfs-modal")?.click();
    expect(modal.classList.contains("hidden")).to.equal(true);

    dispatchHtmxAfterSwap(root);
    await waitForMicrotask();
    document.getElementById("cancel-cfs-modal")?.click();
    expect(modal.classList.contains("hidden")).to.equal(true);
  });

  it("opens after the page body is swapped", async () => {
    await import(`/static/js/event/cfs.js?test=${Date.now()}-body-swap`);

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

    dispatchHtmxAfterSwap(document.getElementById("cfs-modal-root"));
    await waitForMicrotask();

    expect(document.getElementById("cfs-modal")?.classList.contains("hidden")).to.equal(false);
  });
});
