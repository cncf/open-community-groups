const DOCS_SIDEBAR_SELECTOR = ".sidebar-nav";

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
export const resolveAppPath = (href, inMarkdown) => {
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
export const rewriteAppLinks = (docsRoot) => {
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

    link.setAttribute("href", path);
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
 * Adds per-cell labels so CSS can render markdown tables as mobile cards.
 * @param {HTMLElement} docsRoot Docs root container.
 */
export const enhanceMobileCardTables = (docsRoot) => {
  if (!docsRoot || !docsRoot.isConnected) {
    return;
  }

  const tables = docsRoot.querySelectorAll(".markdown-section table");
  tables.forEach((table) => {
    if (table.dataset.ocgMobileCardTableEnhanced === "1") {
      return;
    }

    let headerCells = Array.from(table.querySelectorAll("thead th"));
    if (!headerCells.length) {
      const firstRow = table.querySelector("tr");
      if (firstRow) {
        headerCells = Array.from(firstRow.querySelectorAll("th, td"));
      }
    }

    if (!headerCells.length) {
      return;
    }

    const headerLabels = headerCells.map((cell) => {
      return (cell.textContent || "").trim();
    });
    const bodyRows = table.querySelectorAll("tbody tr");
    bodyRows.forEach((row) => {
      const cells = row.querySelectorAll("td");
      cells.forEach((cell, index) => {
        const label = headerLabels[index] || "";
        cell.setAttribute("data-label", label);
      });
    });

    table.classList.add("ocg-mobile-card-table");
    table.dataset.ocgMobileCardTableEnhanced = "1";
  });
};

/**
 * Normalizes docs path by removing leading/trailing slashes and .md suffix.
 * @param {string} path Route path.
 * @returns {string} Normalized path.
 */
export const normalizeDocsPath = (path) => {
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
export const parseDocsRoute = (hashValue) => {
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
export const getCurrentDocsRoute = () =>
  parseDocsRoute(window.location.hash) || {
    id: null,
    path: "",
    rawPath: "/",
  };

/**
 * Keeps the current page section list open and matches the active section to the hash.
 * @param {HTMLElement} docsRoot Docs root container.
 */
export const syncCurrentSidebarSectionState = (docsRoot) => {
  const sidebar = docsRoot.querySelector(DOCS_SIDEBAR_SELECTOR);
  if (!sidebar) {
    return;
  }

  const currentRoute = getCurrentDocsRoute();
  if (!currentRoute.path) {
    return;
  }

  const pageLink = Array.from(sidebar.querySelectorAll("a[href^='#/']")).find((link) => {
    const route = parseDocsRoute(link.getAttribute("href"));
    return route && route.path === currentRoute.path && !route.id;
  });
  if (!pageLink) {
    return;
  }

  const pageItem = pageLink.closest("li");
  const sections = pageItem ? pageItem.querySelector(":scope > .app-sub-sidebar") : null;
  if (!pageItem || !sections) {
    return;
  }

  pageItem.classList.remove("collapse");
  sections.querySelectorAll(":scope > li.active").forEach((item) => {
    item.classList.remove("active");
  });

  if (!currentRoute.id) {
    pageItem.classList.add("active");
    return;
  }

  const sectionLinks = sections.querySelectorAll(":scope > li > a[href^='#/']");
  const activeSectionLink = Array.from(sectionLinks).find((link) => {
    const route = parseDocsRoute(link.getAttribute("href"));
    return route && route.path === currentRoute.path && route.id === currentRoute.id;
  });
  if (!activeSectionLink) {
    return;
  }

  activeSectionLink.closest("li")?.classList.add("active");
};

/**
 * Parses link href for same-page anchor handling.
 * @param {string|null} href Link href.
 * @returns {{id: string, path: string, rawPath: string}|null} Anchor route.
 */
export const parseSamePageAnchor = (href) => {
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
 * Runs post-render docs enhancements for links, tables, and sidebar state.
 * @param {HTMLElement} docsRoot Docs root container.
 */
export const runDocsEnhancements = (docsRoot) => {
  rewriteAppLinks(docsRoot);
  enhanceMobileCardTables(docsRoot);
  syncCurrentSidebarSectionState(docsRoot);
};
