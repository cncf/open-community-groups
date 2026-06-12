/**
 * Defers work until an HTMX swap settles to avoid acting on stale nodes.
 * This prevents empty-state rendering from targeting elements replaced by a swap.
 * @param {() => Promise<void> | void} task - Work to run after swap settles.
 * @returns {Promise<void>} Promise resolved when task completes.
 */
export const deferUntilHtmxSettled = (task) => {
  const body = document.body;
  const shouldDefer = Boolean(
    window.htmx &&
    body &&
    (body.classList.contains("htmx-swapping") || body.classList.contains("htmx-settling")),
  );

  if (!shouldDefer) {
    return Promise.resolve().then(() => task());
  }

  return new Promise((resolve, reject) => {
    let hasRun = false;

    const runTask = () => {
      if (hasRun) {
        return;
      }
      hasRun = true;
      Promise.resolve()
        .then(() => task())
        .then(resolve)
        .catch(reject);
    };

    body.addEventListener("htmx:afterSwap", runTask, { once: true });
    body.addEventListener("htmx:afterSettle", runTask, { once: true });
  });
};
