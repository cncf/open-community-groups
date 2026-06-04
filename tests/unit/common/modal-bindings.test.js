import { expect } from "@open-wc/testing";

import "/static/js/common/modal-bindings.js";
import { resetDom } from "/tests/unit/test-utils/dom.js";

describe("modal bindings", () => {
  beforeEach(() => {
    resetDom();
  });

  afterEach(() => {
    resetDom();
  });

  it("toggles the target modal from declarative controls", () => {
    // Build the DOM fixture with a modal and declarative trigger.
    document.body.innerHTML = `
      <button id="open-modal" data-modal-toggle="details-modal">Open</button>
      <div id="details-modal" class="hidden"></div>
    `;

    // Click the trigger to open the modal.
    document.getElementById("open-modal")?.click();

    // The target modal becomes visible.
    expect(document.getElementById("details-modal")?.classList.contains("hidden")).to.equal(false);

    // Click the trigger again to close the modal.
    document.getElementById("open-modal")?.click();

    // The target modal is hidden again.
    expect(document.getElementById("details-modal")?.classList.contains("hidden")).to.equal(true);
  });

  it("ignores controls without a modal id", () => {
    // Build the DOM fixture with an incomplete declarative trigger.
    document.body.innerHTML = `<button id="open-modal" data-modal-toggle>Open</button>`;

    // Click the incomplete trigger.
    document.getElementById("open-modal")?.click();

    // Missing modal ids are ignored without changing body modal state.
    expect(document.body.dataset.modalOpenCount).to.equal(undefined);
  });
});
