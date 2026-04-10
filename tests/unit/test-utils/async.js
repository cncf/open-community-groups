/** Waits for pending microtasks and timer-queued assertions to flush. */
export const waitForMicrotask = () => new Promise((resolve) => setTimeout(resolve, 0));

/** Waits for one or more animation frames used by DOM-driven test updates. */
export const waitForAnimationFrames = async (count = 2) => {
  for (let index = 0; index < count; index += 1) {
    await new Promise((resolve) => requestAnimationFrame(() => resolve()));
  }
};
