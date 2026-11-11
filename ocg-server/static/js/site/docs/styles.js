import { getElementById } from "/static/js/common/dom.js";
import { scopeCssRules } from "/static/js/site/docs/css-scope.js";

const DOCS_SCOPE_SELECTOR = ".ocg-docs-root";

const STYLE_URLS = {
  docsify: "/static/vendor/css/docsify-vue.v4.13.1.min.css",
  shell: "/static/css/docs/shell.css",
  theme: "/static/css/docs/theme.css",
};

const STYLE_IDS = {
  docsify: "ocg-docsify-vue-scoped-style",
  shell: "ocg-docs-shell-style",
  theme: "ocg-docs-theme-scoped-style",
};

/**
 * Fetches text content from a static asset URL.
 * Uses plain fetch because browser and shared caches keep static assets across
 * deployments, so they must not take part in deployment version checks.
 * @param {string} url URL to fetch.
 * @returns {Promise<string>} Resolved text.
 */
const fetchText = async (url) => {
  const response = await fetch(url, { credentials: "same-origin" });
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
 * Loads and scopes docs styles.
 * Fetches every stylesheet before applying any, so the docs root never paints
 * the scoped theme without the shell rules that override it. The shell styles
 * stay unscoped and are set last to win equal-specificity ties.
 */
export const setupDocsScopedStyles = async () => {
  const [docsifyCss, themeCss, shellCss] = await Promise.all([
    fetchText(STYLE_URLS.docsify),
    fetchText(STYLE_URLS.theme),
    fetchText(STYLE_URLS.shell),
  ]);

  setStyleTag(STYLE_IDS.docsify, scopeCssRules(docsifyCss, DOCS_SCOPE_SELECTOR));
  setStyleTag(STYLE_IDS.theme, scopeCssRules(themeCss, DOCS_SCOPE_SELECTOR));
  setStyleTag(STYLE_IDS.shell, shellCss);
};
