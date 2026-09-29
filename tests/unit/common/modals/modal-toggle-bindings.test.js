import { expect } from "@open-wc/testing";

import "/static/js/common/modals/modal-toggle-bindings.js";
import { resetRestoredModalState } from "/static/js/common/modals/modal-lifecycle.js";
import { resetDom } from "/tests/unit/test-utils/dom.js";
import { dispatchHtmxAfterSwap } from "/tests/unit/test-utils/htmx.js";

describe("modal toggle bindings", () => {
  beforeEach(() => {
    resetDom();
  });

  afterEach(() => {
    // Close open modals so their keyboard listeners do not leak into other tests
    resetRestoredModalState(document);
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

  it("opens the named modal after content is swapped into its root", () => {
    // Render the swap fixture
    const { modal, opener, root } = renderSwapFixture();

    // Swap content into the root as a response to the opener
    dispatchHtmxAfterSwap(root, { requestConfig: { elt: opener } });

    // The modal opens and focuses its autofocus field
    expect(modal.classList.contains("hidden")).to.equal(false);
    expect(modal.getAttribute("aria-hidden")).to.equal("false");
    expect(document.body.dataset.modalOpenCount).to.equal("1");
    expect(document.activeElement?.id).to.equal("swap-body");
  });

  it("keeps an open modal unchanged when its root is swapped again", () => {
    // Render the swap fixture and open the modal
    const { modal, opener, root } = renderSwapFixture();
    dispatchHtmxAfterSwap(root, { requestConfig: { elt: opener } });

    // Swap new content into the already open modal
    dispatchHtmxAfterSwap(root, { requestConfig: { elt: opener } });

    // The modal stays open without a second scroll lock
    expect(modal.classList.contains("hidden")).to.equal(false);
    expect(document.body.dataset.modalOpenCount).to.equal("1");
  });

  it("ignores swaps into elements without an open-on-swap modal", () => {
    // Render the swap fixture next to an unrelated swap target
    const { modal } = renderSwapFixture();
    const unrelated = document.createElement("div");
    document.body.append(unrelated);

    // Swap content into the unrelated element
    dispatchHtmxAfterSwap(unrelated);

    // The modal stays hidden
    expect(modal.classList.contains("hidden")).to.equal(true);
    expect(document.body.dataset.modalOpenCount).to.equal(undefined);
  });

  it("closes a swap-opened modal with Escape and returns focus to the opener", () => {
    // Render the swap fixture and open the modal from its opener
    const { modal, opener, root } = renderSwapFixture();
    opener.focus();
    dispatchHtmxAfterSwap(root, { requestConfig: { elt: opener } });

    // Press Escape while the modal is open
    const escape = pressKey("Escape");

    // The modal closes and focus returns to the opener
    expect(escape.defaultPrevented).to.equal(true);
    expect(modal.classList.contains("hidden")).to.equal(true);
    expect(modal.getAttribute("aria-hidden")).to.equal("true");
    expect(document.body.dataset.modalOpenCount).to.equal("0");
    expect(document.activeElement).to.equal(opener);
  });

  it("returns focus to the request element even when focus moved elsewhere", () => {
    // Render the swap fixture and move focus away from the opener
    const { opener, root } = renderSwapFixture();
    document.getElementById("other-control")?.focus();
    dispatchHtmxAfterSwap(root, { requestConfig: { elt: opener } });

    // Close the modal from its declarative close control
    document.getElementById("close-swap-modal")?.click();

    // Focus returns to the element that issued the request
    expect(document.activeElement).to.equal(opener);
  });

  it("traps Tab navigation inside a swap-opened modal", () => {
    // Render the swap fixture and open the modal
    const { opener, root } = renderSwapFixture();
    dispatchHtmxAfterSwap(root, { requestConfig: { elt: opener } });
    document.getElementById("swap-submit")?.focus();

    // Press Tab on the last focusable control
    const tab = pressKey("Tab");

    // Focus wraps to the first focusable control
    expect(tab.defaultPrevented).to.equal(true);
    expect(document.activeElement?.id).to.equal("close-swap-modal");
  });

  it("keeps the modal open when a nested control handles Escape", () => {
    // Render the swap fixture with a nested control that consumes Escape
    const { modal, opener, root } = renderSwapFixture();
    dispatchHtmxAfterSwap(root, { requestConfig: { elt: opener } });
    const body = document.getElementById("swap-body");
    body?.addEventListener("keydown", (event) => {
      if (event.key === "Escape") {
        event.preventDefault();
      }
    });

    // Press Escape inside the nested control
    body?.dispatchEvent(new KeyboardEvent("keydown", { bubbles: true, cancelable: true, key: "Escape" }));

    // The modal stays open
    expect(modal.classList.contains("hidden")).to.equal(false);

    // Press Escape again outside the nested control
    pressKey("Escape");

    // The modal closes
    expect(modal.classList.contains("hidden")).to.equal(true);
  });

  it("removes keyboard listeners when the modal closes from a toggle control", () => {
    // Render the swap fixture and open the modal
    const { modal, opener, root } = renderSwapFixture();
    dispatchHtmxAfterSwap(root, { requestConfig: { elt: opener } });

    // Close from the toggle control and reopen without a swap
    document.getElementById("close-swap-modal")?.click();
    opener.click();
    pressKey("Escape");

    // Escape no longer closes the modal opened by the toggle control
    expect(modal.classList.contains("hidden")).to.equal(false);
  });

  it("removes keyboard listeners when the modal closes with Escape", () => {
    // Render the swap fixture and open the modal
    const { modal, opener, root } = renderSwapFixture();
    dispatchHtmxAfterSwap(root, { requestConfig: { elt: opener } });

    // Close with Escape and reopen without a swap
    pressKey("Escape");
    opener.click();
    pressKey("Escape");

    // Escape no longer closes the modal opened by the toggle control
    expect(modal.classList.contains("hidden")).to.equal(false);
  });

  it("removes keyboard listeners when navigation resets modal state", () => {
    // Render the swap fixture and open the modal
    const { modal, opener, root } = renderSwapFixture();
    dispatchHtmxAfterSwap(root, { requestConfig: { elt: opener } });

    // Reset modal state as navigation does and reopen without a swap
    resetRestoredModalState(document);
    expect(modal.classList.contains("hidden")).to.equal(true);
    opener.click();
    pressKey("Escape");

    // Escape no longer closes the modal opened by the toggle control
    expect(modal.classList.contains("hidden")).to.equal(false);
  });
});

// Helpers.

/**
 * Dispatches a keydown event on the document.
 * @param {string} key Keyboard key.
 * @returns {KeyboardEvent} Dispatched event.
 */
const pressKey = (key) => {
  const event = new KeyboardEvent("keydown", { bubbles: true, cancelable: true, key });
  document.dispatchEvent(event);
  return event;
};

/**
 * Renders a modal whose content root opens it after an HTMX swap.
 * @returns {{modal: HTMLElement, opener: HTMLElement, root: HTMLElement}} Fixture elements.
 */
const renderSwapFixture = () => {
  document.body.innerHTML = `
    <button id="swap-opener" type="button" data-modal-toggle="swap-modal">Open</button>
    <button id="other-control" type="button">Other</button>
    <div id="swap-modal" class="hidden" role="dialog" aria-modal="true">
      <button id="close-swap-modal" type="button" data-modal-toggle="swap-modal">Close</button>
      <div id="swap-root" data-modal-open-on-swap="swap-modal">
        <textarea id="swap-body" autofocus></textarea>
        <button id="swap-submit" type="submit">Send</button>
      </div>
    </div>
  `;

  return {
    modal: document.getElementById("swap-modal"),
    opener: document.getElementById("swap-opener"),
    root: document.getElementById("swap-root"),
  };
};
