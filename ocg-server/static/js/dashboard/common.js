/**
 * Dashboard common utilities
 */
import { getElementById } from "/static/js/common/dom.js";

/**
 * Triggers a change event on the specified form using htmx.
 * @param {string} formId - The ID of the form to trigger change on
 */
export const triggerChangeOnForm = (formId) => {
  const form = getElementById(document, formId);
  if (form) {
    // Trigger change event using htmx
    htmx.trigger(form, "change");
  }
};

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
