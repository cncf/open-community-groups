import { expect } from "@open-wc/testing";

import {
  bindModalControlClicks,
  bindModalDismissListeners,
  closeModalBodyScroll,
  isModalOverlayTarget,
  openModalBodyScroll,
} from "/static/js/common/modal-lifecycle.js";
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
});
