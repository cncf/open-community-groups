import { unsafeHTML } from "/static/vendor/js/lit-all.v3.3.1.min.js";

/**
 * Renders server-sanitized trusted HTML inside Lit templates.
 * @param {string|null|undefined} html Trusted HTML string.
 * @returns {unknown} Lit unsafe HTML directive.
 */
export const renderTrustedHtml = (html) => unsafeHTML(String(html ?? ""));
