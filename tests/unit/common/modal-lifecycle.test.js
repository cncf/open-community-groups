import { expect } from "@open-wc/testing";

import {
  bindModalDismissListeners,
  isModalEscapeEvent,
  isModalOverlayTarget,
} from "/static/js/common/modal-lifecycle.js";
import { resetDom } from "/tests/unit/test-utils/dom.js";

describe("modal lifecycle", () => {
  beforeEach(() => {
    resetDom();
  });

  afterEach(() => {
    resetDom();
  });

  it("recognizes modal dismissal events", () => {
    // Build a modal overlay fixture.
    const overlay = document.createElement("div");
    overlay.className = "modal-overlay";

    // The helpers identify Escape and overlay targets.
    expect(isModalEscapeEvent(new KeyboardEvent("keydown", { key: "Escape" }))).to.equal(true);
    expect(isModalEscapeEvent(new KeyboardEvent("keydown", { key: "Enter" }))).to.equal(false);
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
});
