import { expect } from "@open-wc/testing";

import {
  getNextLoopedIndex,
  handleEnterActivationKeydown,
  isEscapeEvent,
  registerEnterActivationHandler,
} from "/static/js/common/keyboard.js";

describe("common keyboard", () => {
  it("recognizes Escape keyboard events", () => {
    // Build the keyboard events used by dropdown and modal handlers.
    const escapeEvent = new KeyboardEvent("keydown", { key: "Escape" });
    const enterEvent = new KeyboardEvent("keydown", { key: "Enter" });

    // The helper only matches Escape.
    expect(isEscapeEvent(escapeEvent)).to.equal(true);
    expect(isEscapeEvent(enterEvent)).to.equal(false);
    expect(isEscapeEvent(new Event("click"))).to.equal(false);
    expect(isEscapeEvent(null)).to.equal(false);
  });

  it("moves active indexes through looped lists", () => {
    // Move through the list from empty, first, and last active positions.
    expect(getNextLoopedIndex(null, 3, 1)).to.equal(0);
    expect(getNextLoopedIndex(0, 3, 1)).to.equal(1);
    expect(getNextLoopedIndex(2, 3, 1)).to.equal(0);
    expect(getNextLoopedIndex(0, 3, -1)).to.equal(2);

    // Empty lists do not resolve an active index.
    expect(getNextLoopedIndex(null, 0, 1)).to.equal(null);
  });

  it("clicks a focused data-enter-activates element on unmodified Enter only", () => {
    // Create a container with a focusable row and a nested child element.
    const root = document.createElement("div");
    const row = document.createElement("div");
    row.setAttribute("tabindex", "0");
    row.setAttribute("data-enter-activates", "");
    const child = document.createElement("button");
    row.appendChild(child);
    root.appendChild(row);
    document.body.appendChild(root);

    let clicks = 0;
    row.addEventListener("click", () => {
      clicks += 1;
    });

    try {
      // Register twice to confirm listener binding is idempotent.
      registerEnterActivationHandler(root);
      registerEnterActivationHandler(root);

      // Non-Enter keys and modified/repeated/composing Enter events must not fire.
      for (const init of [
        { key: "Space" },
        { key: "ArrowDown" },
        { key: "Escape" },
        { key: "Enter", shiftKey: true },
        { key: "Enter", ctrlKey: true },
        { key: "Enter", altKey: true },
        { key: "Enter", metaKey: true },
        { key: "Enter", repeat: true },
        { key: "Enter", isComposing: true },
      ]) {
        row.dispatchEvent(new KeyboardEvent("keydown", { bubbles: true, cancelable: true, ...init }));
      }
      expect(clicks).to.equal(0);

      // Pressing Enter on a nested element must not trigger the outer row.
      child.dispatchEvent(new KeyboardEvent("keydown", { bubbles: true, cancelable: true, key: "Enter" }));
      expect(clicks).to.equal(0);

      // Pressing unmodified Enter on the row itself clicks it once and prevents default.
      const enterEvent = new KeyboardEvent("keydown", { bubbles: true, cancelable: true, key: "Enter" });
      row.dispatchEvent(enterEvent);
      expect(clicks).to.equal(1);
      expect(enterEvent.defaultPrevented).to.equal(true);

      // Already-prevented Enter events are ignored.
      const preventedEvent = new KeyboardEvent("keydown", {
        bubbles: true,
        cancelable: true,
        key: "Enter",
      });
      preventedEvent.preventDefault();
      handleEnterActivationKeydown(preventedEvent);
      expect(clicks).to.equal(1);
    } finally {
      root.remove();
    }
  });
});
