import { expect } from "@open-wc/testing";

import { clearTimeoutId, replaceTimeout } from "/static/js/common/timers.js";

describe("common timers", () => {
  const originalClearTimeout = window.clearTimeout;
  const originalSetTimeout = window.setTimeout;

  afterEach(() => {
    window.clearTimeout = originalClearTimeout;
    window.setTimeout = originalSetTimeout;
  });

  it("clears timeout ids", () => {
    // Track timeout ids cleared by the helper.
    const clearedTimeoutIds = [];
    window.clearTimeout = (timeoutId) => {
      clearedTimeoutIds.push(timeoutId);
    };

    // The helper clears truthy ids and returns the empty timeout value.
    expect(clearTimeoutId(42)).to.equal(0);
    expect(clearTimeoutId(0)).to.equal(0);
    expect(clearedTimeoutIds).to.deep.equal([42]);
  });

  it("replaces timeout ids", () => {
    // Track the cleared timeout and scheduled callback.
    const clearedTimeoutIds = [];
    let scheduledCallback = null;
    let scheduledDelay = null;
    window.clearTimeout = (timeoutId) => {
      clearedTimeoutIds.push(timeoutId);
    };
    window.setTimeout = (callback, delay) => {
      scheduledCallback = callback;
      scheduledDelay = delay;
      return 7;
    };

    // The helper clears the old timeout and schedules the replacement.
    let callbackRun = false;
    const timeoutId = replaceTimeout(
      3,
      () => {
        callbackRun = true;
      },
      200,
    );
    scheduledCallback();

    expect(timeoutId).to.equal(7);
    expect(scheduledDelay).to.equal(200);
    expect(clearedTimeoutIds).to.deep.equal([3]);
    expect(callbackRun).to.equal(true);
  });
});
