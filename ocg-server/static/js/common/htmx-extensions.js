import { handleHtmxResponse, showSuccessAlert } from "/static/js/common/alerts.js";
import {
  addLoadedCommitShaHeader,
  isDeploymentReloadRequested,
  reloadIfDeploymentChanged,
} from "/static/js/common/deployment-version.js";

// Tracks event roots already wired so repeated initialization stays idempotent.
const responseHandlerRoots = new WeakSet();
const handledDeclarativeResponseXhrs = new WeakSet();
const htmxResponseSelector = "[data-htmx-response]";
const REFRESH_BODY_TRIGGER = "refresh-body";

/**
 * Finds the element that owns declarative HTMX response configuration.
 * @param {CustomEvent} event HTMX lifecycle event.
 * @returns {Element|null} Declarative response element when present.
 */
export const getDeclarativeHtmxResponseElement = (event) => {
  const candidates = [
    event.detail?.elt,
    event.detail?.requestConfig?.elt,
    event.detail?.requestConfig?.triggeringEvent?.target,
  ];

  for (const candidate of candidates) {
    if (!(candidate instanceof Element)) {
      continue;
    }

    const responseElement = candidate.closest(htmxResponseSelector);
    if (responseElement) {
      return responseElement;
    }
  }

  return null;
};

/**
 * Filters HTMX parameters by trimming strings and dropping selected empty values.
 * @param {FormData|URLSearchParams} source Source entries collection.
 * @param {boolean} dropZero Whether the string "0" should be treated as empty.
 * @returns {Array<[string, FormDataEntryValue|string]>} Filtered entries.
 */
export const filterHtmxEntries = (source, dropZero) => {
  const filteredEntries = [];

  for (const [key, rawValue] of source.entries()) {
    const normalizedValue = typeof rawValue === "string" ? rawValue.trim() : String(rawValue);

    if (normalizedValue === "" || (dropZero && normalizedValue === "0")) {
      continue;
    }

    filteredEntries.push([key, typeof rawValue === "string" ? normalizedValue : rawValue]);
  }

  return filteredEntries;
};

/**
 * Replaces the contents of a mutable HTMX parameters collection.
 * @param {FormData|URLSearchParams} parameters Mutable parameters collection.
 * @param {Array<[string, FormDataEntryValue|string]>} entries Filtered entries.
 * @returns {void}
 */
export const replaceHtmxEntries = (parameters, entries) => {
  for (const key of [...parameters.keys()]) {
    parameters.delete(key);
  }

  for (const [key, value] of entries) {
    parameters.append(key, value);
  }
};

/**
 * Builds an HTMX extension that removes empty values before request encoding.
 * @param {boolean} dropZero Whether the string "0" should be treated as empty.
 * @returns {object} HTMX extension definition.
 */
export const createNoEmptyValuesExtension = (dropZero) => ({
  onEvent: (name, event) => {
    if (name !== "htmx:configRequest") {
      return true;
    }

    const request = event.detail;
    if (request.verb !== "get" || !request.useUrlParams) {
      return true;
    }

    const filteredParameters = new FormData();
    for (const [key, value] of filterHtmxEntries(request.formData, dropZero)) {
      filteredParameters.append(key, value);
    }

    request.formData = filteredParameters;
    request.parameters = filteredParameters;

    return true;
  },
  encodeParameters: (_xhr, parameters) => {
    replaceHtmxEntries(parameters, filterHtmxEntries(parameters, dropZero));
    return null;
  },
});

/**
 * Allows the shared HTML not found page to replace the current body on boosted requests.
 * @param {CustomEvent} event HTMX beforeSwap event.
 * @returns {void}
 */
export const handleNotFoundBeforeSwap = (event) => {
  if (isDeploymentReloadRequested()) {
    return;
  }

  const xhr = event.detail?.xhr;
  if (!xhr || xhr.status !== 404 || typeof xhr.getResponseHeader !== "function") {
    return;
  }

  if (xhr.getResponseHeader("X-OCG-Not-Found") !== "true") {
    return;
  }

  event.detail.shouldSwap = true;
  event.detail.isError = false;
};

/**
 * Adds the loaded page commit SHA to HTMX requests.
 * @param {CustomEvent} event HTMX configRequest event.
 * @param {Document} root Document used to read the loaded commit SHA.
 * @returns {void}
 */
export const handleCommitShaConfigRequest = (event, root = document) => {
  if (!event.detail) {
    return;
  }

  event.detail.headers = event.detail.headers || {};
  addLoadedCommitShaHeader(event.detail.headers, root);
};

/**
 * Records deployment refreshes before HTMX consumes native refresh headers.
 * This keeps the one-shot post-refresh alert in deployment state.
 * @param {CustomEvent} event HTMX beforeOnLoad event.
 * @param {Document} root Document used to read the loaded commit SHA.
 * @returns {void}
 */
export const handleCommitShaBeforeOnLoad = (event, root = document) => {
  if (!event.detail) {
    return;
  }

  if (reloadIfDeploymentChanged(event.detail.xhr, root)) {
    event.preventDefault();
  }
};

/**
 * Prevents stale deployment fragments from being swapped into the loaded page.
 * @param {CustomEvent} event HTMX beforeSwap event.
 * @param {Document} root Document used to read the loaded commit SHA.
 * @returns {void}
 */
export const handleCommitShaBeforeSwap = (event, root = document) => {
  if (!event.detail) {
    return;
  }

  if (isDeploymentReloadRequested() || reloadIfDeploymentChanged(event.detail.xhr, root)) {
    event.detail.shouldSwap = false;
  }
};

/**
 * Shows configured success or error alerts for declarative HTMX response elements.
 * @param {CustomEvent} event HTMX afterRequest event.
 * @returns {void}
 */
export const handleDeclarativeHtmxResponse = (event) => {
  const responseElement = getDeclarativeHtmxResponseElement(event);
  if (!responseElement) {
    return;
  }

  const xhr = event.detail?.xhr;
  if (xhr && handledDeclarativeResponseXhrs.has(xhr)) {
    return;
  }

  const successMessage = responseElement.dataset.successMessage || "";
  if (isSuccessfulRefreshBodyResponse(xhr) && successMessage) {
    if (xhr) {
      handledDeclarativeResponseXhrs.add(xhr);
    }
    showSuccessAfterBodyRefresh(successMessage);
    return;
  }

  if (xhr) {
    handledDeclarativeResponseXhrs.add(xhr);
  }
  handleHtmxResponse({
    xhr,
    successMessage,
    errorMessage: responseElement.dataset.errorMessage || "Something went wrong. Please try again later.",
  });
};

/**
 * Checks whether a successful HTMX response triggers a body refresh.
 * @param {XMLHttpRequest|undefined|null} xhr HTMX response XHR.
 * @returns {boolean} True when the response will refresh the body.
 */
export const isSuccessfulRefreshBodyResponse = (xhr) => {
  if (!xhr || xhr.status < 200 || xhr.status >= 300 || typeof xhr.getResponseHeader !== "function") {
    return false;
  }

  return (xhr.getResponseHeader("HX-Trigger") || "")
    .split(",")
    .map((trigger) => trigger.trim())
    .includes(REFRESH_BODY_TRIGGER);
};

/**
 * Shows success feedback after the triggered body refresh has settled.
 * @param {string} successMessage Success alert message.
 * @returns {void}
 */
export const showSuccessAfterBodyRefresh = (successMessage) => {
  window.setTimeout(() => {
    document.addEventListener(
      "htmx:afterSettle",
      () => {
        showSuccessAlert(successMessage);
      },
      { once: true },
    );
  }, 0);
};

/**
 * Registers the shared HTMX parameter filtering extensions.
 * @param {{defineExtension?: Function}|undefined|null} htmxInstance Global HTMX instance.
 * @returns {void}
 */
export const registerHtmxNoEmptyValuesExtensions = (htmxInstance) => {
  if (!htmxInstance || typeof htmxInstance.defineExtension !== "function") {
    return;
  }

  htmxInstance.defineExtension("no-empty-vals", createNoEmptyValuesExtension(true));
  htmxInstance.defineExtension("no-empty-vals-keep-zero", createNoEmptyValuesExtension(false));
};

/**
 * Registers shared HTMX request and response handling hooks.
 * @param {Document|undefined|null} root Event listener root.
 * @returns {void}
 */
export const registerHtmxResponseHandlers = (root = document) => {
  const eventRoot = root;
  if (!eventRoot || typeof eventRoot.addEventListener !== "function" || responseHandlerRoots.has(eventRoot)) {
    return;
  }

  eventRoot.addEventListener("htmx:configRequest", handleCommitShaConfigRequest);
  eventRoot.addEventListener("htmx:beforeOnLoad", handleCommitShaBeforeOnLoad);
  eventRoot.addEventListener("htmx:beforeOnLoad", handleDeclarativeHtmxResponse);
  eventRoot.addEventListener("htmx:beforeSwap", handleCommitShaBeforeSwap);
  eventRoot.addEventListener("htmx:beforeSwap", handleNotFoundBeforeSwap);
  eventRoot.addEventListener("htmx:beforeSwap", handleDeclarativeHtmxResponse);
  eventRoot.addEventListener("htmx:afterRequest", handleDeclarativeHtmxResponse);
  responseHandlerRoots.add(eventRoot);
};
