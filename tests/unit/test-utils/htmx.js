/**
 * Dispatches an HTMX before-request event from the provided target.
 * @param {EventTarget} target - Target that emits the event.
 * @param {object} detail - Event detail payload.
 */
export const dispatchHtmxBeforeRequest = (target, detail = {}) => {
  target.dispatchEvent(
    new CustomEvent("htmx:beforeRequest", {
      bubbles: true,
      detail,
    }),
  );
};

/**
 * Dispatches an HTMX after-request event with a configurable xhr payload.
 * @param {EventTarget} target - Target that emits the event.
 * @param {object} options - Event detail and XHR fixture options.
 * @param {number} options.status - Mock XHR status.
 * @param {string} options.responseText - Mock XHR response text.
 */
export const dispatchHtmxAfterRequest = (target, { status = 200, responseText = "", ...detail } = {}) => {
  target.dispatchEvent(
    new CustomEvent("htmx:afterRequest", {
      bubbles: true,
      detail: {
        ...detail,
        xhr: {
          status,
          responseText,
        },
      },
    }),
  );
};

/**
 * Dispatches an HTMX load event from the provided target.
 * @param {EventTarget} target - Target that emits the event.
 */
export const dispatchHtmxLoad = (target = document.body) => {
  target.dispatchEvent(
    new CustomEvent("htmx:load", {
      bubbles: true,
    }),
  );
};

/**
 * Dispatches an HTMX after-swap event from the provided target.
 * @param {EventTarget|null} target - Target that emits the event.
 * @param {object} detail - Event detail payload.
 */
export const dispatchHtmxAfterSwap = (target = document, detail = {}) => {
  (target ?? document).dispatchEvent(
    new CustomEvent("htmx:afterSwap", {
      bubbles: true,
      detail,
    }),
  );
};
