/**
 * Creates timer functions whose callbacks only run when the test advances the clock.
 * @returns {object} Timer functions, the clock advancer, and the pending timer count.
 */
export const createManualTimers = () => {
  const pending = new Map();
  let currentTime = 0;
  let nextId = 1;

  return {
    advance(milliseconds) {
      const targetTime = currentTime + milliseconds;

      // Run due timers in order, including timers scheduled by earlier callbacks
      for (;;) {
        const [id, timer] =
          [...pending.entries()].sort(([, first], [, second]) => first.dueAt - second.dueAt)[0] || [];
        if (!timer || timer.dueAt > targetTime) break;
        pending.delete(id);
        currentTime = timer.dueAt;
        timer.callback(...timer.args);
      }
      currentTime = targetTime;
    },
    clearTimeout(id) {
      pending.delete(id);
    },
    get pendingCount() {
      return pending.size;
    },
    setTimeout(callback, delay = 0, ...args) {
      const id = nextId;
      nextId += 1;
      pending.set(id, { args, callback, dueAt: currentTime + delay });
      return id;
    },
  };
};

/**
 * Routes delayed window timers through manual timers while zero-delay timers keep
 * using the real clock, so async flush helpers continue to work.
 * @returns {object} Manual timers plus a restore helper.
 */
export const mockWindowTimers = () => {
  const originalClearTimeout = window.clearTimeout;
  const originalSetTimeout = window.setTimeout;
  const manualTimers = createManualTimers();
  const manualIds = new Set();

  window.setTimeout = (callback, delay = 0, ...args) => {
    if (!delay) return originalSetTimeout(callback, delay, ...args);
    const id = `manual-${manualTimers.setTimeout(callback, delay, ...args)}`;
    manualIds.add(id);
    return id;
  };
  window.clearTimeout = (id) => {
    if (manualIds.delete(id)) {
      manualTimers.clearTimeout(Number(String(id).replace("manual-", "")));
      return;
    }
    originalClearTimeout(id);
  };

  return {
    advance: (milliseconds) => manualTimers.advance(milliseconds),
    get pendingCount() {
      return manualTimers.pendingCount;
    },
    restore() {
      window.clearTimeout = originalClearTimeout;
      window.setTimeout = originalSetTimeout;
    },
  };
};
