/** Wait message of a plain-text rate limit rejection, as the server words it. */
export const RATE_LIMIT_MESSAGE = "Too many requests from your network. Please wait 2 minutes and try again.";

/**
 * Creates an XHR fixture whose header lookup ignores case, as XMLHttpRequest does.
 * @param {object} [options] - XHR fixture options.
 * @param {number} [options.status] - Response status.
 * @param {string} [options.responseText] - Response body.
 * @param {Record<string, string>} [options.headers] - Response headers.
 * @returns {{getResponseHeader: (name: string) => string|null, responseText: string, status: number}} XHR fixture.
 */
export const createXhr = ({ status = 200, responseText = "", headers = {} } = {}) => {
  const headerValues = new Map(Object.entries(headers).map(([name, value]) => [name.toLowerCase(), value]));
  return {
    getResponseHeader: (name) => headerValues.get(String(name).toLowerCase()) ?? null,
    responseText,
    status,
  };
};

/**
 * Creates the XHR fixture of a plain-text rate limit rejection sent by the server.
 * @param {string} [message] - Wait message in the response body.
 * @returns {ReturnType<typeof createXhr>} XHR fixture.
 */
export const createRateLimitedXhr = (message = RATE_LIMIT_MESSAGE) =>
  createXhr({
    status: 429,
    responseText: message,
    headers: {
      "Cache-Control": "no-store",
      "Content-Type": "text/plain; charset=utf-8",
      "Retry-After": "120",
      "X-OCG-Rate-Limited": "true",
    },
  });

/**
 * Dispatches a failed HTMX request event shaped like the ones htmx sends.
 * @param {Element} element - Request element that emits the event.
 * @param {string} [type] - Event type: htmx:responseError, htmx:sendError or htmx:timeout.
 * @param {object} [detail] - Event detail options.
 * @param {boolean} [detail.boosted] - Whether hx-boost issued the request.
 * @param {Element} [detail.target] - Resolved swap target.
 * @param {object} [detail.xhr] - Failed request.
 * @returns {CustomEvent} The dispatched event.
 */
export const dispatchHtmxRequestError = (
  element,
  type = "htmx:responseError",
  { boosted, target, xhr } = {},
) => {
  const event = new CustomEvent(type, {
    bubbles: true,
    detail: {
      boosted,
      elt: element,
      requestConfig: { boosted, elt: element },
      target,
      xhr,
    },
  });

  element.dispatchEvent(event);
  return event;
};

/**
 * Dispatches an HTMX before-request event from the provided target.
 * @param {EventTarget} target - Target that emits the event.
 * @param {object} detail - Event detail payload.
 * @param {object} options - Event options.
 * @param {boolean} options.cancelable - Whether the event can be canceled.
 * @returns {CustomEvent} The dispatched event.
 */
export const dispatchHtmxBeforeRequest = (target, detail = {}, { cancelable = false } = {}) => {
  const event = new CustomEvent("htmx:beforeRequest", {
    bubbles: true,
    cancelable,
    detail,
  });

  target.dispatchEvent(event);
  return event;
};

/**
 * Dispatches an HTMX before-on-load event with a configurable xhr payload.
 * @param {Element} target - Request element that emits the event.
 * @param {object} options - Event detail and XHR fixture options.
 * @param {number} options.status - Mock XHR status.
 * @param {string} options.responseText - Mock XHR response text.
 */
export const dispatchHtmxBeforeOnLoad = (target, { status = 200, responseText = "", ...detail } = {}) => {
  target.dispatchEvent(
    new CustomEvent("htmx:beforeOnLoad", {
      bubbles: true,
      detail: {
        elt: target,
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
