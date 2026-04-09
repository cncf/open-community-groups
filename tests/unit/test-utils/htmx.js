/** Dispatches an HTMX before-request event from the provided target. */
export const dispatchHtmxBeforeRequest = (target) => {
  target.dispatchEvent(
    new CustomEvent("htmx:beforeRequest", {
      bubbles: true,
    }),
  );
};

/** Dispatches an HTMX after-request event with a configurable xhr payload. */
export const dispatchHtmxAfterRequest = (target, { status = 200, responseText = "" } = {}) => {
  target.dispatchEvent(
    new CustomEvent("htmx:afterRequest", {
      bubbles: true,
      detail: {
        xhr: {
          status,
          responseText,
        },
      },
    }),
  );
};

/** Dispatches an HTMX load event from the provided target. */
export const dispatchHtmxLoad = (target = document.body) => {
  target.dispatchEvent(
    new CustomEvent("htmx:load", {
      bubbles: true,
    }),
  );
};

/** Dispatches an HTMX after-swap event from the provided target. */
export const dispatchHtmxAfterSwap = (target = document) => {
  (target ?? document).dispatchEvent(
    new CustomEvent("htmx:afterSwap", {
      bubbles: true,
    }),
  );
};
