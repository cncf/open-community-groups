import { expect } from "@open-wc/testing";

import { getNextLoopedIndex, isEscapeEvent } from "/static/js/common/keyboard.js";

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
});
