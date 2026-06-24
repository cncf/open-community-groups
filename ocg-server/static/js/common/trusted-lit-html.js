import { unsafeHTML } from "/static/vendor/js/lit-all.v3.3.3.min.js";

/**
 * Renders server-sanitized trusted HTML inside Lit templates.
 *
 * Keeps unsafeHTML centralized for rich text already sanitized by the server.
 * @param {string|null|undefined} html Trusted HTML string.
 * @returns {unknown} Lit unsafe HTML directive.
 */
export const renderTrustedHtml = (html) => unsafeHTML(String(html ?? ""));
