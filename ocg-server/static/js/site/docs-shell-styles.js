import { getElementById } from "/static/js/common/dom.js";
import { ocgFetch } from "/static/js/common/fetch.js";
import { scopeCssRules } from "/static/js/site/docs-css-scope.js";

const DOCS_SCOPE_SELECTOR = ".ocg-docs-root";

const STYLE_URLS = {
  docsify: "/static/vendor/css/docsify-vue.v4.13.1.min.css",
  shell: "/static/docs/assets/shell.css",
  theme: "/static/docs/assets/theme.css",
};

const STYLE_IDS = {
  docsify: "ocg-docsify-vue-scoped-style",
  overrides: "ocg-docs-shell-overrides",
  theme: "ocg-docs-theme-scoped-style",
};

/**
 * Fetches text content from a URL.
 * @param {string} url URL to fetch.
 * @returns {Promise<string>} Resolved text.
 */
const fetchText = async (url) => {
  const response = await ocgFetch(url, { credentials: "same-origin" });
  if (!response.ok) {
    throw new Error(`Failed to fetch style asset: ${url}`);
  }
  return response.text();
};

/**
 * Injects or updates a style tag by ID.
 * @param {string} styleId Style element ID.
 * @param {string} cssText CSS content.
 */
const setStyleTag = (styleId, cssText) => {
  let styleTag = getElementById(document, styleId);
  if (!styleTag) {
    styleTag = document.createElement("style");
    styleTag.id = styleId;
    document.head.appendChild(styleTag);
  }
  styleTag.textContent = cssText;
};

/**
 * Ensures a stylesheet link exists in the document head.
 * @param {string} styleId Link element ID.
 * @param {string} href Stylesheet URL.
 */
const ensureStylesheetLink = (styleId, href) => {
  if (getElementById(document, styleId)) {
    return;
  }

  const link = document.createElement("link");
  link.id = styleId;
  link.rel = "stylesheet";
  link.href = href;
  document.head.appendChild(link);
};

/**
 * Loads and scopes docs styles.
 */
export const setupDocsScopedStyles = async () => {
  const [docsifyCss, themeCss] = await Promise.all([
    fetchText(STYLE_URLS.docsify),
    fetchText(STYLE_URLS.theme),
  ]);

  setStyleTag(STYLE_IDS.docsify, scopeCssRules(docsifyCss, DOCS_SCOPE_SELECTOR));
  setStyleTag(STYLE_IDS.theme, scopeCssRules(themeCss, DOCS_SCOPE_SELECTOR));
  ensureStylesheetLink(STYLE_IDS.overrides, STYLE_URLS.shell);
};
