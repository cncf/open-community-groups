const DOCS_ROOT_SELECTOR = ".ocg-docs-root";
const DOCS_APP_SELECTOR = "#ocg-docs-app";
const DOCS_SCOPE_SELECTOR = ".ocg-docs-root";
const DOCSIFY_BODY_CLASSES = ["close", "ready", "sticky"];

const STYLE_URLS = {
  docsify: "/static/vendor/css/docsify-vue.v4.13.1.min.css",
  theme: "/static/docs/assets/theme.css",
};

const SCRIPT_URLS = {
  copyCode: "/static/vendor/js/docsify-copy-code.v3.0.2.min.js",
  docsify: "/static/vendor/js/docsify.v4.13.1.min.js",
};

const STYLE_IDS = {
  docsify: "ocg-docsify-vue-scoped-style",
  theme: "ocg-docs-theme-scoped-style",
  overrides: "ocg-docs-shell-overrides",
};

const DOCS_SHELL_OVERRIDES = `
.ocg-docs-root {
  --ocg-docs-top-offset: 0px;
  background: #fff;
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

@media screen and (min-width: 769px) {
  .ocg-docs-root .content {
    bottom: auto;
    position: relative;
    right: auto;
    top: auto;
    width: calc(100% - 336px);
  }
}

.ocg-docs-root .sidebar {
  height: calc(100vh - var(--ocg-docs-top-offset));
  max-height: none;
  position: fixed;
  top: var(--ocg-docs-top-offset);
}

.ocg-docs-root .sidebar-toggle {
  bottom: auto;
  height: auto;
  position: fixed;
  top: var(--ocg-docs-top-offset);
}

@media screen and (max-width: 768px) {
  .ocg-docs-root .content {
    min-height: calc(100vh - var(--ocg-docs-top-offset));
  }

  .ocg-docs-root .sidebar {
    height: 100vh;
    top: 0;
  }

  .ocg-docs-root .sidebar-toggle {
    top: 0;
  }

  .ocg-docs-root.close .sidebar-toggle {
    width: 284px;
  }
}
`;

let activeDocsRoot = null;
let cleanupCurrentMount = null;
let mountRunId = 0;
let lifecycleListenersBound = false;
const rewriteTimeoutIds = new Set();

/**
 * Fetches text content from a URL.
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
 * Splits selectors by comma while keeping function contents intact.
 * @param {string} selectorText Raw selector list.
 * @returns {string[]} Selector list.
 */
const splitSelectors = (selectorText) => {
  const selectors = [];
  let current = "";
  let bracketDepth = 0;
  let parenDepth = 0;
  let quoteChar = "";

  for (let index = 0; index < selectorText.length; index += 1) {
    const char = selectorText[index];

    if (quoteChar) {
      current += char;
      if (char === quoteChar && selectorText[index - 1] !== "\\") {
        quoteChar = "";
      }
      continue;
    }

    if (char === "'" || char === '"') {
      quoteChar = char;
      current += char;
      continue;
    }

    if (char === "(") {
      parenDepth += 1;
      current += char;
      continue;
    }

    if (char === ")") {
      parenDepth = Math.max(0, parenDepth - 1);
      current += char;
      continue;
    }

    if (char === "[") {
      bracketDepth += 1;
      current += char;
      continue;
    }

    if (char === "]") {
      bracketDepth = Math.max(0, bracketDepth - 1);
      current += char;
      continue;
    }

    if (char === "," && parenDepth === 0 && bracketDepth === 0) {
      selectors.push(current.trim());
      current = "";
      continue;
    }

    current += char;
  }

  if (current.trim()) {
    selectors.push(current.trim());
  }

  return selectors;
};

/**
 * Adds scope selector to a single CSS selector.
 * @param {string} selector CSS selector.
 * @param {string} scope Scope selector.
 * @returns {string} Scoped selector.
 */
const scopeSelector = (selector, scope) => {
  if (!selector) {
    return selector;
  }

  if (selector.includes(scope)) {
    return selector;
  }

  const withRootReplaced = selector.replace(
    /(^|[\s>+~])(:root|html|body)(?=($|[\s>+~.#[:]))/g,
    (match, prefix) => `${prefix}${scope}`,
  );

  if (withRootReplaced.includes(scope)) {
    return withRootReplaced;
  }

  return `${scope} ${withRootReplaced}`;
};

/**
 * Returns the matching closing brace index.
 * @param {string} cssText CSS text.
 * @param {number} openBraceIndex Opening brace index.
 * @returns {number} Closing brace index.
 */
const findMatchingBrace = (cssText, openBraceIndex) => {
  let depth = 0;
  let quoteChar = "";

  for (let index = openBraceIndex; index < cssText.length; index += 1) {
    const char = cssText[index];
    const nextChar = cssText[index + 1];

    if (quoteChar) {
      if (char === quoteChar && cssText[index - 1] !== "\\") {
        quoteChar = "";
      }
      continue;
    }

    if (char === "'" || char === '"') {
      quoteChar = char;
      continue;
    }

    if (char === "/" && nextChar === "*") {
      const commentEnd = cssText.indexOf("*/", index + 2);
      if (commentEnd === -1) {
        return cssText.length - 1;
      }
      index = commentEnd + 1;
      continue;
    }

    if (char === "{") {
      depth += 1;
      continue;
    }

    if (char === "}") {
      depth -= 1;
      if (depth === 0) {
        return index;
      }
    }
  }

  return cssText.length - 1;
};

/**
 * Finds next top-level rule delimiter.
 * @param {string} cssText CSS text.
 * @param {number} startIndex Search start.
 * @returns {{char: string, index: number}|null} Next delimiter.
 */
const findTopLevelDelimiter = (cssText, startIndex) => {
  let bracketDepth = 0;
  let parenDepth = 0;
  let quoteChar = "";

  for (let index = startIndex; index < cssText.length; index += 1) {
    const char = cssText[index];
    const nextChar = cssText[index + 1];

    if (quoteChar) {
      if (char === quoteChar && cssText[index - 1] !== "\\") {
        quoteChar = "";
      }
      continue;
    }

    if (char === "'" || char === '"') {
      quoteChar = char;
      continue;
    }

    if (char === "/" && nextChar === "*") {
      const commentEnd = cssText.indexOf("*/", index + 2);
      if (commentEnd === -1) {
        return null;
      }
      index = commentEnd + 1;
      continue;
    }

    if (char === "(") {
      parenDepth += 1;
      continue;
    }

    if (char === ")") {
      parenDepth = Math.max(0, parenDepth - 1);
      continue;
    }

    if (char === "[") {
      bracketDepth += 1;
      continue;
    }

    if (char === "]") {
      bracketDepth = Math.max(0, bracketDepth - 1);
      continue;
    }

    if (parenDepth === 0 && bracketDepth === 0 && (char === "{" || char === ";")) {
      return { char, index };
    }
  }

  return null;
};

/**
 * Scopes a CSS rule list to a selector.
 * @param {string} cssText CSS text.
 * @param {string} scope Scope selector.
 * @returns {string} Scoped CSS text.
 */
const scopeCssRules = (cssText, scope) => {
  const noScopeAtRules = [
    "@font-face",
    "@keyframes",
    "@-webkit-keyframes",
    "@property",
    "@counter-style",
    "@page",
  ];
  const recursiveAtRules = ["@media", "@supports", "@document", "@container", "@layer"];

  let scopedCss = "";
  let cursor = 0;

  while (cursor < cssText.length) {
    const delimiter = findTopLevelDelimiter(cssText, cursor);
    if (!delimiter) {
      scopedCss += cssText.slice(cursor);
      break;
    }

    if (delimiter.char === ";") {
      scopedCss += cssText.slice(cursor, delimiter.index + 1);
      cursor = delimiter.index + 1;
      continue;
    }

    const prelude = cssText.slice(cursor, delimiter.index).trim();
    const blockEnd = findMatchingBrace(cssText, delimiter.index);
    const blockBody = cssText.slice(delimiter.index + 1, blockEnd);

    if (!prelude.startsWith("@")) {
      const scopedPrelude = splitSelectors(prelude)
        .map((selector) => scopeSelector(selector, scope))
        .join(", ");
      scopedCss += `${scopedPrelude}{${blockBody}}`;
      cursor = blockEnd + 1;
      continue;
    }

    const lowerPrelude = prelude.toLowerCase();
    if (noScopeAtRules.some((rule) => lowerPrelude.startsWith(rule))) {
      scopedCss += `${prelude}{${blockBody}}`;
      cursor = blockEnd + 1;
      continue;
    }

    if (recursiveAtRules.some((rule) => lowerPrelude.startsWith(rule))) {
      scopedCss += `${prelude}{${scopeCssRules(blockBody, scope)}}`;
      cursor = blockEnd + 1;
      continue;
    }

    scopedCss += `${prelude}{${blockBody}}`;
    cursor = blockEnd + 1;
  }

  return scopedCss;
};

/**
 * Injects or updates a style tag by ID.
 * @param {string} styleId Style element ID.
 * @param {string} cssText CSS content.
 */
const setStyleTag = (styleId, cssText) => {
  let styleTag = document.getElementById(styleId);
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
const setupScopedStyles = async () => {
  const [docsifyCss, themeCss] = await Promise.all([
    fetchText(STYLE_URLS.docsify),
    fetchText(STYLE_URLS.theme),
  ]);

  setStyleTag(STYLE_IDS.docsify, scopeCssRules(docsifyCss, DOCS_SCOPE_SELECTOR));
  setStyleTag(STYLE_IDS.theme, scopeCssRules(themeCss, DOCS_SCOPE_SELECTOR));
  setStyleTag(STYLE_IDS.overrides, DOCS_SHELL_OVERRIDES);
};

/**
 * Loads a script once by URL.
 * @param {string} src Script source URL.
 * @returns {Promise<void>} Resolved once loaded.
 */
const loadScript = (src) =>
  new Promise((resolve, reject) => {
    const existingScript = document.querySelector(`script[src="${src}"]`);
    if (existingScript) {
      if (existingScript.dataset.loaded === "1") {
        resolve();
        return;
      }
      existingScript.addEventListener("load", () => resolve(), { once: true });
      existingScript.addEventListener("error", () => reject(new Error(src)), {
        once: true,
      });
      return;
    }

    const script = document.createElement("script");
    script.src = src;
    script.addEventListener(
      "load",
      () => {
        script.dataset.loaded = "1";
        resolve();
      },
      { once: true },
    );
    script.addEventListener("error", () => reject(new Error(src)), { once: true });
    document.head.appendChild(script);
  });

/**
 * Mirrors docsify body classes to the docs container root.
 * @param {HTMLElement} docsRoot Docs root container.
 * @returns {() => void} Cleanup callback.
 */
const mirrorDocsifyBodyClasses = (docsRoot) => {
  const syncClasses = () => {
    DOCSIFY_BODY_CLASSES.forEach((className) => {
      docsRoot.classList.toggle(className, document.body.classList.contains(className));
    });
  };

  syncClasses();
  const observer = new MutationObserver(syncClasses);
  observer.observe(document.body, {
    attributeFilter: ["class"],
    attributes: true,
  });

  return () => {
    observer.disconnect();
  };
};

/**
 * Keeps the docs fixed layout offset in sync with the docs root viewport position.
 * @param {HTMLElement} docsRoot Docs root container.
 * @returns {() => void} Cleanup callback.
 */
const setupDocsTopOffsetSync = (docsRoot) => {
  let rafId = 0;

  const syncOffset = () => {
    rafId = 0;
    const topOffset = Math.max(0, Math.round(docsRoot.getBoundingClientRect().top));
    docsRoot.style.setProperty("--ocg-docs-top-offset", `${topOffset}px`);
  };

  const scheduleSync = () => {
    if (rafId !== 0) {
      return;
    }
    rafId = window.requestAnimationFrame(syncOffset);
  };

  syncOffset();
  window.addEventListener("scroll", scheduleSync, { passive: true });
  window.addEventListener("resize", scheduleSync, { passive: true });
  window.addEventListener("hashchange", scheduleSync, { passive: true });

  return () => {
    window.removeEventListener("scroll", scheduleSync);
    window.removeEventListener("resize", scheduleSync);
    window.removeEventListener("hashchange", scheduleSync);
    if (rafId !== 0) {
      window.cancelAnimationFrame(rafId);
      rafId = 0;
    }
  };
};

/**
 * Checks whether value starts with any given prefix.
 * @param {string} value Input value.
 * @param {string[]} prefixes Candidate prefixes.
 * @returns {boolean} True when prefix matches.
 */
const startsWithAnyPrefix = (value, prefixes) =>
  prefixes.some(
    (prefix) => value === prefix || value.startsWith(`${prefix}/`) || value.startsWith(`${prefix}?`),
  );

/**
 * Resolves app route links inside docs to top-level app paths.
 * @param {string} href Link href.
 * @param {boolean} inMarkdown True when inside markdown section.
 * @returns {string|null} Resolved app path.
 */
const resolveAppPath = (href, inMarkdown) => {
  const hashAppPrefixes = ["#/dashboard", "#/explore", "#/log-in", "#/log-out", "#/sign-up", "#/stats"];
  const absoluteAppPrefixes = ["/dashboard", "/explore", "/log-in", "/log-out", "/sign-up", "/stats"];

  if (!href) {
    return null;
  }

  if (inMarkdown && href === "#/") {
    return "/";
  }

  if (startsWithAnyPrefix(href, hashAppPrefixes)) {
    return href.slice(1);
  }

  if (startsWithAnyPrefix(href, absoluteAppPrefixes)) {
    return href;
  }

  return null;
};

/**
 * Rewrites app links so they navigate the top-level site.
 * @param {HTMLElement} docsRoot Docs root container.
 */
const rewriteAppLinks = (docsRoot) => {
  if (!docsRoot || !docsRoot.isConnected) {
    return;
  }

  const links = docsRoot.querySelectorAll("a[href]");
  links.forEach((link) => {
    const href = link.getAttribute("href");
    if (!href) {
      return;
    }

    if (link.dataset.ocgAppLinkRewritten === "1" && !href.startsWith("#/")) {
      return;
    }

    const path = resolveAppPath(href, Boolean(link.closest(".markdown-section")));
    if (!path) {
      return;
    }

    link.setAttribute("href", path || "/");
    link.setAttribute("hx-boost", "true");
    link.setAttribute("hx-target", "body");
    link.removeAttribute("rel");
    link.removeAttribute("target");
    link.dataset.ocgAppLinkRewritten = "1";

    if (window.htmx && typeof window.htmx.process === "function") {
      window.htmx.process(link);
    }
  });
};

/**
 * Normalizes docs path by removing leading/trailing slashes and .md suffix.
 * @param {string} path Route path.
 * @returns {string} Normalized path.
 */
const normalizeDocsPath = (path) => {
  if (!path || path === "/") {
    return "";
  }

  const trimmed = path.replace(/^\/+|\/+$/g, "");
  if (!trimmed || trimmed === "index" || trimmed === "index.md") {
    return "";
  }

  return trimmed.endsWith(".md") ? trimmed.slice(0, -3) : trimmed;
};

/**
 * Parses a docs route hash value.
 * @param {string} hashValue Current hash value.
 * @returns {{id: string|null, path: string, rawPath: string}|null} Route info.
 */
const parseDocsRoute = (hashValue) => {
  if (!hashValue || !hashValue.startsWith("#/")) {
    return null;
  }

  const routeValue = hashValue.slice(1);
  const queryIndex = routeValue.indexOf("?");
  const rawPath = queryIndex === -1 ? routeValue : routeValue.slice(0, queryIndex);
  const query = queryIndex === -1 ? "" : routeValue.slice(queryIndex + 1);
  const params = new URLSearchParams(query);

  return {
    id: params.get("id"),
    path: normalizeDocsPath(rawPath || "/"),
    rawPath: rawPath || "/",
  };
};

/**
 * Returns current docs route details.
 * @returns {{id: string|null, path: string, rawPath: string}} Route info.
 */
const getCurrentDocsRoute = () =>
  parseDocsRoute(window.location.hash) || {
    id: null,
    path: "",
    rawPath: "/",
  };

/**
 * Parses link href for same-page anchor handling.
 * @param {string|null} href Link href.
 * @returns {{id: string, path: string, rawPath: string}|null} Anchor route.
 */
const parseSamePageAnchor = (href) => {
  if (!href || !href.startsWith("#")) {
    return null;
  }

  if (href.startsWith("#/")) {
    const route = parseDocsRoute(href);
    if (!route || !route.id) {
      return null;
    }
    return route;
  }

  if (href.length <= 1) {
    return null;
  }

  const currentRoute = getCurrentDocsRoute();
  return {
    id: decodeURIComponent(href.slice(1)),
    path: currentRoute.path,
    rawPath: currentRoute.rawPath,
  };
};

/**
 * Updates docs hash to include current path and section ID.
 * @param {string} rawPath Route path.
 * @param {string} id Target section ID.
 */
const updateDocsAnchorHash = (rawPath, id) => {
  const nextHash = `#${rawPath || "/"}?id=${encodeURIComponent(id)}`;
  if (window.location.hash === nextHash) {
    window.history.replaceState(null, "", nextHash);
    return;
  }

  window.history.pushState(null, "", nextHash);
};

/**
 * Performs an instant jump to an element.
 * @param {HTMLElement} element Target element.
 */
const jumpToElement = (element) => {
  const top = element.getBoundingClientRect().top + window.pageYOffset;
  window.scrollTo({
    behavior: "auto",
    top,
  });
};

/**
 * Handles same-page anchor clicks without smooth scroll animation.
 * @param {MouseEvent} event Click event.
 */
const handleSamePageAnchorClick = (event) => {
  const link = event.target.closest("a[href]");
  if (!link) {
    return;
  }

  if (!link.closest(".markdown-section, .app-sub-sidebar")) {
    return;
  }

  const targetRoute = parseSamePageAnchor(link.getAttribute("href"));
  if (!targetRoute || !targetRoute.id) {
    return;
  }

  const currentRoute = getCurrentDocsRoute();
  if (targetRoute.path !== currentRoute.path) {
    return;
  }

  const targetElement = document.getElementById(targetRoute.id);
  if (!targetElement) {
    return;
  }

  event.preventDefault();
  updateDocsAnchorHash(currentRoute.rawPath, targetRoute.id);
  jumpToElement(targetElement);
};

/**
 * Rewrites app links after docs render.
 * @param {HTMLElement} docsRoot Docs root container.
 */
const rewriteAfterRender = (docsRoot) => {
  if (!docsRoot || !docsRoot.isConnected) {
    return;
  }

  [0, 80].forEach((delay) => {
    const timeoutId = window.setTimeout(() => {
      rewriteTimeoutIds.delete(timeoutId);
      rewriteAppLinks(docsRoot);
    }, delay);
    rewriteTimeoutIds.add(timeoutId);
  });
};

/**
 * Initializes docs routing hash when visiting /docs without one.
 */
const ensureInitialDocsHash = () => {
  if (!window.location.hash) {
    window.history.replaceState(null, "", `${window.location.pathname}#/`);
  }
};

/**
 * Clears scheduled link-rewrite timers.
 */
const clearRewriteTimeouts = () => {
  rewriteTimeoutIds.forEach((timeoutId) => window.clearTimeout(timeoutId));
  rewriteTimeoutIds.clear();
};

/**
 * Checks whether a mount run is still current.
 * @param {number} runId Mount run ID.
 * @param {HTMLElement} docsRoot Docs root container.
 * @returns {boolean} True when mount is still current.
 */
const isCurrentMount = (runId, docsRoot) =>
  runId === mountRunId && activeDocsRoot === docsRoot && docsRoot.isConnected;

/**
 * Unmounts docs lifecycle and listeners.
 */
const unmountDocs = () => {
  mountRunId += 1;
  clearRewriteTimeouts();
  if (cleanupCurrentMount) {
    cleanupCurrentMount();
    cleanupCurrentMount = null;
  }
  activeDocsRoot = null;
};

/**
 * Bootstraps docsify in the site shell for the active docs root.
 * @param {HTMLElement} docsRoot Docs root container.
 * @param {HTMLElement} docsApp Docs app container.
 */
const mountDocs = async (docsRoot, docsApp) => {
  if (!docsRoot || !docsApp) {
    return;
  }

  unmountDocs();
  mountRunId += 1;
  const runId = mountRunId;
  activeDocsRoot = docsRoot;

  const cleanups = [];
  cleanupCurrentMount = () => {
    while (cleanups.length > 0) {
      const cleanup = cleanups.pop();
      cleanup();
    }
  };

  ensureInitialDocsHash();
  await setupScopedStyles();

  if (!isCurrentMount(runId, docsRoot)) {
    return;
  }

  cleanups.push(setupDocsTopOffsetSync(docsRoot));

  window.$docsify = {
    alias: {
      "/.*/_sidebar.md": "/static/docs/_sidebar.md",
    },
    auto2top: true,
    basePath: "/static/docs/",
    el: DOCS_APP_SELECTOR,
    homepage: "index.md",
    loadSidebar: "_sidebar.md",
    maxLevel: 3,
    name: "Documentation",
    relativePath: true,
    subMaxLevel: 2,
  };

  cleanups.push(mirrorDocsifyBodyClasses(docsRoot));
  document.addEventListener("click", handleSamePageAnchorClick);
  cleanups.push(() => {
    document.removeEventListener("click", handleSamePageAnchorClick);
  });

  const handleRewriteOnHashChange = () => {
    rewriteAfterRender(docsRoot);
  };
  window.addEventListener("hashchange", handleRewriteOnHashChange);
  cleanups.push(() => {
    window.removeEventListener("hashchange", handleRewriteOnHashChange);
  });

  await loadScript(SCRIPT_URLS.docsify);
  if (!isCurrentMount(runId, docsRoot)) {
    return;
  }

  await loadScript(SCRIPT_URLS.copyCode);
  if (!isCurrentMount(runId, docsRoot)) {
    return;
  }

  rewriteAfterRender(docsRoot);
};

/**
 * Synchronizes docs lifecycle with current DOM.
 */
const syncDocsLifecycle = () => {
  const docsRoot = document.querySelector(DOCS_ROOT_SELECTOR);
  const docsApp = docsRoot ? docsRoot.querySelector(DOCS_APP_SELECTOR) : null;

  if (!docsRoot || !docsApp) {
    unmountDocs();
    return;
  }

  if (docsRoot === activeDocsRoot && cleanupCurrentMount) {
    return;
  }

  void mountDocs(docsRoot, docsApp);
};

/**
 * Binds HTMX/document lifecycle listeners once.
 */
const bindLifecycleListeners = () => {
  if (lifecycleListenersBound) {
    return;
  }

  document.addEventListener("htmx:afterSwap", syncDocsLifecycle);
  document.addEventListener("htmx:historyRestore", syncDocsLifecycle);
  window.addEventListener("pageshow", syncDocsLifecycle);

  lifecycleListenersBound = true;
};

bindLifecycleListeners();
syncDocsLifecycle();
