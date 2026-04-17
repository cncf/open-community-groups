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
