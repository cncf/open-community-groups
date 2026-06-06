import { getElementById } from "/static/js/common/dom.js";
import { ocgFetch } from "/static/js/common/fetch.js";
import { scopeCssRules } from "/static/js/site/docs-css-scope.js";

const DOCS_SCOPE_SELECTOR = ".ocg-docs-root";

const STYLE_URLS = {
  docsify: "/static/vendor/css/docsify-vue.v4.13.1.min.css",
  theme: "/static/docs/assets/theme.css",
};

const STYLE_IDS = {
  docsify: "ocg-docsify-vue-scoped-style",
  theme: "ocg-docs-theme-scoped-style",
  overrides: "ocg-docs-shell-overrides",
};

const DOCS_SHELL_OVERRIDES = `
.ocg-docs-root {
  --ocg-docs-top-offset: 0px;
  --ocg-docs-sidebar-top-margin: 0px;
  --ocg-docs-sidebar-bottom-margin: 20px;
  --ocg-docs-sidebar-inline-margin: 16px;
  --ocg-docs-desktop-sidebar-width: 264px;
  --ocg-docs-mobile-sidebar-width: 264px;
  background: transparent;
  min-height: calc(100vh - var(--ocg-docs-top-offset));
  position: relative;
  width: 100%;
}

.ocg-docs-root main {
  height: auto;
  min-height: calc(100vh - var(--ocg-docs-top-offset));
  width: 100%;
}

.ocg-docs-root .content {
  min-height: calc(100vh - var(--ocg-docs-top-offset));
}

.ocg-docs-root .sidebar .sidebar-nav {
  padding-bottom: 60px;
}

.ocg-docs-root .sidebar-toggle {
  background: #fff;
  border: 1px solid var(--theme-color, #0094ff);
  border-radius: 9999px;
  bottom: calc(env(safe-area-inset-bottom, 0px) + 12px);
  box-shadow: 0 1px 2px rgba(28, 25, 23, 0.08);
  display: block;
  height: 42px;
  left: 12px;
  padding: 0;
  position: fixed;
  top: auto;
  width: 42px;
  z-index: 45;
}

.ocg-docs-root .sidebar-toggle:hover {
  background: #f5f9ff;
}

.ocg-docs-root .sidebar-toggle-button {
  align-items: center;
  display: flex;
  flex-direction: column;
  gap: 3px;
  height: 100%;
  justify-content: center;
  opacity: 1;
}

.ocg-docs-root .sidebar-toggle span {
  background-color: var(--theme-color, #0094ff);
  margin-bottom: 0;
}

.ocg-docs-root.close .sidebar-toggle {
  background: var(--theme-color, #0094ff);
  border-color: var(--theme-color, #0094ff);
  bottom: calc(env(safe-area-inset-bottom, 0px) + 12px);
  height: 42px;
  padding: 0;
}

.ocg-docs-root.close .sidebar-toggle span {
  background-color: #fff;
}

@media screen and (min-width: 1025px) {
  .ocg-docs-root .content {
    background: #fff;
    border: 1px solid #e7e5e4;
    border-radius: 0.5rem;
    bottom: auto;
    box-shadow: 0 1px 2px rgba(28, 25, 23, 0.04);
    left: calc(
      var(--ocg-docs-desktop-sidebar-width) + (2 * var(--ocg-docs-sidebar-inline-margin))
    );
    margin-bottom: var(--ocg-docs-sidebar-bottom-margin);
    margin-right: var(--ocg-docs-sidebar-inline-margin);
    margin-top: var(--ocg-docs-sidebar-top-margin);
    min-height: calc(
      100vh - max(var(--ocg-docs-top-offset), var(--ocg-docs-sidebar-top-margin)) -
        var(--ocg-docs-sidebar-bottom-margin)
    );
    position: relative;
    right: auto;
    top: auto;
    width: calc(
      100% - var(--ocg-docs-desktop-sidebar-width) - (3 * var(--ocg-docs-sidebar-inline-margin))
    );
  }

  .ocg-docs-root .sidebar {
    border: 0;
    border-radius: 0;
    box-shadow: none;
    height: auto;
    left: var(--ocg-docs-sidebar-inline-margin);
    max-height: calc(
      100vh - max(var(--ocg-docs-top-offset), var(--ocg-docs-sidebar-top-margin)) -
        var(--ocg-docs-sidebar-bottom-margin)
    );
    top: max(var(--ocg-docs-top-offset), var(--ocg-docs-sidebar-top-margin));
    width: var(--ocg-docs-desktop-sidebar-width);
  }

  .ocg-docs-root .sidebar-toggle {
    display: none;
  }

  .ocg-docs-root.close .sidebar {
    transform: none;
  }

  .ocg-docs-root.close .content {
    left: calc(
      var(--ocg-docs-desktop-sidebar-width) + (2 * var(--ocg-docs-sidebar-inline-margin))
    );
    width: calc(
      100% - var(--ocg-docs-desktop-sidebar-width) - (3 * var(--ocg-docs-sidebar-inline-margin))
    );
  }
}

.ocg-docs-root .sidebar {
  max-height: none;
  position: fixed;
}

@media screen and (max-width: 1024px) {
  .ocg-docs-root .content {
    background: #fff;
    border: 1px solid #e7e5e4;
    border-radius: 0.5rem;
    box-shadow: 0 1px 2px rgba(28, 25, 23, 0.04);
    left: 0;
    margin: 12px;
    min-height: calc(100vh - var(--ocg-docs-top-offset) - 24px);
    position: relative;
    right: auto;
    width: auto;
    z-index: 10;
  }

  .ocg-docs-root .sidebar {
    background: #f5f5f4;
    border: 0;
    border-radius: 0;
    box-shadow: 0 8px 24px rgba(28, 25, 23, 0.18);
    height: 100vh;
    left: calc(-1 * var(--ocg-docs-mobile-sidebar-width));
    top: 0;
    width: var(--ocg-docs-mobile-sidebar-width);
    z-index: 40;
  }

  .ocg-docs-root.close .sidebar-toggle {
    width: calc(var(--ocg-docs-mobile-sidebar-width) - 24px);
  }

  .ocg-docs-root.close .sidebar {
    transform: translateX(var(--ocg-docs-mobile-sidebar-width));
  }

  .ocg-docs-root.close .content {
    transform: none;
  }
}
`;

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
 * Loads and scopes docs styles.
 */
export const setupDocsScopedStyles = async () => {
  const [docsifyCss, themeCss] = await Promise.all([
    fetchText(STYLE_URLS.docsify),
    fetchText(STYLE_URLS.theme),
  ]);

  setStyleTag(STYLE_IDS.docsify, scopeCssRules(docsifyCss, DOCS_SCOPE_SELECTOR));
  setStyleTag(STYLE_IDS.theme, scopeCssRules(themeCss, DOCS_SCOPE_SELECTOR));
  setStyleTag(STYLE_IDS.overrides, DOCS_SHELL_OVERRIDES);
};
