import { expect } from "@open-wc/testing";

import {
  bindModalControlClicks,
  bindModalDismissListeners,
  closeModalBodyScroll,
  isModalOverlayTarget,
  openModalBodyScroll,
  resetRestoredModalState,
  trapModalFocus,
} from "/static/js/common/modals/modal-lifecycle.js";
import { resetDom } from "/tests/unit/test-utils/dom.js";

describe("modal lifecycle", () => {
  beforeEach(() => {
    resetDom();
  });

  afterEach(() => {
    resetDom();
  });

  it("recognizes modal overlay targets", () => {
    // Build a modal overlay fixture.
    const overlay = document.createElement("div");
    overlay.className = "modal-overlay";

    // The helper identifies overlay targets.
    expect(isModalOverlayTarget(overlay)).to.equal(true);
    expect(isModalOverlayTarget(document.createElement("div"))).to.equal(false);
    expect(isModalOverlayTarget(null)).to.equal(false);
  });

  it("binds and removes document dismissal listeners", () => {
    // Track listener calls.
    let keydownCount = 0;
    let outsideClickCount = 0;

    // Bind the document-level modal dismissal listeners.
    const cleanup = bindModalDismissListeners({
      onKeydown: () => {
        keydownCount += 1;
      },
      onOutsideClick: () => {
        outsideClickCount += 1;
      },
    });

    // Dispatch events while listeners are active.
    document.dispatchEvent(new KeyboardEvent("keydown", { key: "Escape" }));
    document.dispatchEvent(new MouseEvent("mousedown"));

    // Remove listeners and verify later events are ignored.
    cleanup();
    document.dispatchEvent(new KeyboardEvent("keydown", { key: "Escape" }));
    document.dispatchEvent(new MouseEvent("mousedown"));

    expect(keydownCount).to.equal(1);
    expect(outsideClickCount).to.equal(1);
  });

  it("binds dismissal listeners to custom targets", () => {
    // Build a custom event target for owner-document scoped components.
    const target = document.createElement("section");
    let keydownCount = 0;

    // Bind the keydown listener to the custom target.
    const cleanup = bindModalDismissListeners({
      onKeydown: () => {
        keydownCount += 1;
      },
      target,
    });

    // Dispatch while bound, then verify cleanup removes the listener.
    target.dispatchEvent(new KeyboardEvent("keydown", { key: "Escape" }));
    cleanup();
    target.dispatchEvent(new KeyboardEvent("keydown", { key: "Escape" }));

    expect(keydownCount).to.equal(1);
  });

  it("binds modal control clicks and skips missing controls", () => {
    // Build two controls and include an absent one.
    const closeButton = document.createElement("button");
    const overlay = document.createElement("div");
    let clickCount = 0;

    // Bind the shared click handler to available controls only.
    bindModalControlClicks([closeButton, null, overlay], () => {
      clickCount += 1;
    });

    // Click each available control.
    closeButton.click();
    overlay.click();

    expect(clickCount).to.equal(2);
  });

  it("wraps forward and reverse keyboard focus within an open modal", () => {
    // Build an open modal with two keyboard focus targets.
    const modal = document.createElement("div");
    modal.innerHTML = `
      <button type="button" tabindex="-1">Backdrop</button>
      <button type="button">First</button>
      <input type="hidden" />
      <button type="button">Last</button>
    `;
    document.body.append(modal);
    const [, firstButton, lastButton] = modal.querySelectorAll("button");

    // Tab from the final target wraps to the first target.
    lastButton.focus();
    const forwardEvent = new KeyboardEvent("keydown", {
      cancelable: true,
      key: "Tab",
    });
    expect(trapModalFocus(forwardEvent, modal)).to.equal(true);
    expect(forwardEvent.defaultPrevented).to.equal(true);
    expect(document.activeElement).to.equal(firstButton);

    // Shift+Tab from the first target wraps to the final target.
    const backwardEvent = new KeyboardEvent("keydown", {
      cancelable: true,
      key: "Tab",
      shiftKey: true,
    });
    expect(trapModalFocus(backwardEvent, modal)).to.equal(true);
    expect(backwardEvent.defaultPrevented).to.equal(true);
    expect(document.activeElement).to.equal(lastButton);
  });

  it("locks body scroll only across modal open transitions", () => {
    // Open the modal twice and close it twice.
    let isOpen = false;
    isOpen = openModalBodyScroll(isOpen);
    isOpen = openModalBodyScroll(isOpen);
    isOpen = closeModalBodyScroll(isOpen);
    isOpen = closeModalBodyScroll(isOpen);

    // The helpers only lock and unlock on real state transitions.
    expect(isOpen).to.equal(false);
    expect(document.body.dataset.modalOpenCount).to.equal("0");
    expect(document.body.style.overflow).to.equal("");
  });

  it("hides declarative modals and clears scroll locks after history restore", () => {
    // Build a restored server-rendered modal fixture.
    const root = document.createElement("section");
    root.innerHTML = `
      <button data-modal-toggle="details-modal">Close</button>
      <div id="details-modal" aria-hidden="false"></div>
      <div id="custom-modal" data-restorable-modal aria-hidden="false"></div>
    `;
    root.dataset.modalToggle = "root-modal";
    document.body.append(root);
    const rootModal = document.createElement("div");
    rootModal.id = "root-modal";
    document.body.append(rootModal);
    document.body.dataset.modalOpenCount = "1";
    document.body.style.overflow = "hidden";

    // Reset modal state after a cached history snapshot is restored.
    resetRestoredModalState(root);

    // The restored modal is closed and body scrolling is available again.
    expect(document.getElementById("details-modal").classList.contains("hidden")).to.equal(true);
    expect(document.getElementById("details-modal").getAttribute("aria-hidden")).to.equal("true");
    expect(rootModal.classList.contains("hidden")).to.equal(true);
    expect(document.getElementById("custom-modal").classList.contains("hidden")).to.equal(true);
    expect(document.getElementById("custom-modal").getAttribute("aria-hidden")).to.equal("true");
    expect(document.body.style.overflow).to.equal("");
    expect(document.body.dataset.modalOpenCount).to.equal(undefined);
  });

  it("hides custom modals from a restored full page", () => {
    // Build a custom modal captured while open in the browser history cache.
    document.body.innerHTML = `
      <div id="custom-modal" data-restorable-modal aria-hidden="false"></div>
    `;
    document.body.dataset.modalOpenCount = "1";
    document.body.style.overflow = "hidden";

    // Reset the full document as the persisted pageshow handler does.
    resetRestoredModalState(document);

    // The custom modal and page scroll state are both reset.
    expect(document.getElementById("custom-modal").classList.contains("hidden")).to.equal(true);
    expect(document.getElementById("custom-modal").getAttribute("aria-hidden")).to.equal("true");
    expect(document.body.style.overflow).to.equal("");
    expect(document.body.dataset.modalOpenCount).to.equal(undefined);
  });
});
