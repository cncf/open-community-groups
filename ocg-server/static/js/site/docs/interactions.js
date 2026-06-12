import { closestElement, getElementById } from "/static/js/common/dom.js";

const DOCSIFY_BODY_CLASSES = ["close", "ready", "sticky"];
const DOCS_ANCHOR_SCROLL_PADDING_PX = 30;
const DOCS_SIDEBAR_SELECTOR = ".sidebar-nav";

/**
 * Mirrors docsify body classes to the docs container root.
 * @param {HTMLElement} docsRoot Docs root container.
 * @returns {() => void} Cleanup callback.
 */
export const mirrorDocsifyBodyClasses = (docsRoot) => {
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
export const setupDocsTopOffsetSync = (docsRoot) => {
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
 * Closes mobile docs sidebar when clicking outside sidebar and toggle.
 * @returns {() => void} Cleanup callback.
 */
export const setupMobileSidebarOutsideDismiss = () => {
  const handleOutsideClick = (event) => {
    if (!document.body.classList.contains("close")) {
      return;
    }

    if (!window.matchMedia("(max-width: 1024px)").matches) {
      return;
    }

    if (closestElement(event.target, ".ocg-docs-root .sidebar, .ocg-docs-root .sidebar-toggle")) {
      return;
    }

    document.body.classList.remove("close");
  };

  document.addEventListener("click", handleOutsideClick);
  return () => {
    document.removeEventListener("click", handleOutsideClick);
  };
};

/**
 * Updates docs hash to include current path and section ID.
 * @param {string} rawPath Route path.
 * @param {string} id Target section ID.
 */
export const updateDocsAnchorHash = (rawPath, id) => {
  const previousUrl = window.location.href;
  const nextHash = `#${rawPath || "/"}?id=${encodeURIComponent(id)}`;
  if (window.location.hash === nextHash) {
    window.history.replaceState(null, "", nextHash);
    return;
  }

  window.history.pushState(null, "", nextHash);
  // pushState does not emit hashchange, but Docsify and our sidebar sync rely on it.
  window.dispatchEvent(
    new HashChangeEvent("hashchange", {
      oldURL: previousUrl,
      newURL: window.location.href,
    }),
  );
};

/**
 * Performs an instant jump to an element.
 * @param {HTMLElement} element Target element.
 */
export const jumpToElement = (element) => {
  const top = element.getBoundingClientRect().top + window.pageYOffset;
  window.scrollTo({
    behavior: "auto",
    top: Math.max(0, top - DOCS_ANCHOR_SCROLL_PADDING_PX),
  });
};

/**
 * Builds the handler that keeps current sidebar page sections expanded.
 * @param {Object} options Handler dependencies.
 * @param {Function} options.getCurrentDocsRoute Current route reader.
 * @param {Function} options.parseDocsRoute Docs route parser.
 * @param {Function} options.scheduleCurrentSidebarSectionStateSync Sync scheduler.
 * @returns {(event: MouseEvent) => void} Click handler.
 */
export const createCurrentSidebarPageClickHandler =
  ({ getCurrentDocsRoute, parseDocsRoute, scheduleCurrentSidebarSectionStateSync }) =>
  (event) => {
    const link = closestElement(event.target, "a[href]");
    if (!link || !link.closest(DOCS_SIDEBAR_SELECTOR) || link.closest(".app-sub-sidebar")) {
      return;
    }

    const targetRoute = parseDocsRoute(link.getAttribute("href"));
    if (!targetRoute || targetRoute.id) {
      return;
    }

    const currentRoute = getCurrentDocsRoute();
    if (targetRoute.path !== currentRoute.path || currentRoute.id) {
      return;
    }

    event.preventDefault();
    event.stopImmediatePropagation();
    scheduleCurrentSidebarSectionStateSync();
  };

/**
 * Builds the handler that performs instant jumps for same-page docs anchors.
 * @param {Object} options Handler dependencies.
 * @param {Function} options.getCurrentDocsRoute Current route reader.
 * @param {Function} options.parseSamePageAnchor Same-page anchor parser.
 * @param {Function} options.scheduleCurrentSidebarSectionStateSync Sync scheduler.
 * @returns {(event: MouseEvent) => void} Click handler.
 */
export const createSamePageAnchorClickHandler =
  ({ getCurrentDocsRoute, parseSamePageAnchor, scheduleCurrentSidebarSectionStateSync }) =>
  (event) => {
    const link = closestElement(event.target, "a[href]");
    if (!link || !link.closest(".markdown-section, .app-sub-sidebar")) {
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

    const targetElement = getElementById(document, targetRoute.id);
    if (!targetElement) {
      return;
    }

    event.preventDefault();
    updateDocsAnchorHash(currentRoute.rawPath, targetRoute.id);
    jumpToElement(targetElement);
    scheduleCurrentSidebarSectionStateSync();
  };
