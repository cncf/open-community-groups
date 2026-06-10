/**
 * Reads comma-separated HTMX trigger names from a response header.
 * @param {XMLHttpRequest|undefined|null} xhr HTMX response XHR.
 * @returns {Array<string>} Trigger names sent by the server.
 */
export const getHtmxTriggerNames = (xhr) => {
  if (!xhr || typeof xhr.getResponseHeader !== "function") {
    return [];
  }

  return (xhr.getResponseHeader("HX-Trigger") || "")
    .split(",")
    .map((trigger) => trigger.trim())
    .filter(Boolean);
};

/**
 * Checks whether an HTMX response includes a named trigger.
 * @param {XMLHttpRequest|undefined|null} xhr HTMX response XHR.
 * @param {string} triggerName Trigger name to find.
 * @returns {boolean} True when the trigger is present.
 */
export const hasHtmxTrigger = (xhr, triggerName) => {
  return getHtmxTriggerNames(xhr).includes(triggerName);
};
