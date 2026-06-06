import { closestElement } from "/static/js/common/dom.js";

const DOCSIFY_BODY_CLASSES = ["close", "ready", "sticky"];
const DOCS_ANCHOR_SCROLL_PADDING_PX = 30;

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
