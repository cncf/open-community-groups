import { expect } from "@open-wc/testing";

import { waitForMicrotask } from "/tests/unit/test-utils/async.js";
import { resetDom } from "/tests/unit/test-utils/dom.js";

describe("event cfs modal", () => {
  afterEach(() => {
    resetDom();
  });

  it("opens after the modal root is swapped and enables submit after selection", async () => {
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

    document.getElementById("cfs-modal-root")?.dispatchEvent(
      new CustomEvent("htmx:afterSwap", { bubbles: true }),
    );
    await waitForMicrotask();

    const modal = document.getElementById("cfs-modal");
    const select = document.getElementById("session_proposal_id");
    const submit = document.getElementById("cfs-submit-button");

    expect(modal.classList.contains("hidden")).to.equal(false);
    expect(submit.disabled).to.equal(true);

    select.value = "12";
    select.dispatchEvent(new Event("change", { bubbles: true }));

    expect(submit.disabled).to.equal(false);
  });
});
