import { parseJsonAttribute } from "/static/js/common/utils.js";

/**
 * Parses server-provided session list payloads.
 * @param {*} value Raw sessions attribute value.
 * @returns {Object[]} Parsed sessions.
 */
export const parseSessionsAttribute = (value) => {
  const sessions = parseJsonAttribute(value, []);
  if (Array.isArray(sessions)) {
    return sessions;
  }

  if (sessions && typeof sessions === "object") {
    return Object.values(sessions).reduce((acc, sessionGroup) => {
      if (Array.isArray(sessionGroup)) {
        acc.push(...sessionGroup);
      }
      return acc;
    }, []);
  }

  return [];
};

/**
 * Parses server-provided array payloads.
 * @param {*} value Raw attribute value.
 * @returns {Object[]} Parsed array.
 */
export const parseArrayAttribute = (value) => {
  const parsed = parseJsonAttribute(value, []);
  return Array.isArray(parsed) ? parsed : [];
};

/**
 * Parses server-provided object payloads.
 * @param {*} value Raw attribute value.
 * @returns {Object} Parsed object.
 */
export const parseObjectAttribute = (value) => {
  const parsed = parseJsonAttribute(value, {});
  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
    return {};
  }
  return parsed;
};
