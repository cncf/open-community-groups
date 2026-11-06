import { closestElement, getElementById } from "/static/js/common/dom.js";
import { isPhoneViewport, PHONE_MEDIA_QUERY } from "/static/js/common/phone-viewport.js";

const DOCSIFY_BODY_CLASSES = ["close", "ready", "sticky"];
const DOCSIFY_TOGGLE_NAME = "Menu";
const DOCS_ANCHOR_SCROLL_PADDING_PX = 30;
// Header 64, strip 44 and a gap of 8.
const DOCS_PHONE_ANCHOR_OFFSET_PX = 116;
const DOCS_PHONE_TOGGLE_NAME = "Contents";
const DOCS_SHEET_HEAD_CLOSE_SELECTOR = ".docs-sheet-head-close";
const DOCS_SHEET_HEAD_SELECTOR = ".docs-sheet-head";
const DOCS_SIDEBAR_SELECTOR = ".sidebar-nav";
const DOCS_TOGGLE_SELECTOR = ".sidebar-toggle";

let docsReloadHandler = () => window.location.reload();

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
 * Applies the phone anchor offset and binds the Contents sheet while the phone query matches.
 * @param {HTMLElement} docsRoot Docs root container.
 * @returns {() => void} Cleanup callback.
 */
export const setupDocsPhoneShell = (docsRoot) => {
  const query = window.matchMedia(PHONE_MEDIA_QUERY);
  let releaseContentsSheet = null;

  const release = () => {
    releaseContentsSheet?.();
    releaseContentsSheet = null;
  };

  const sync = () => {
    // Docsify reassigns this object and reads it per scroll, so hold no reference to it.
    window.$docsify.topMargin = query.matches ? DOCS_PHONE_ANCHOR_OFFSET_PX : 0;

    if (query.matches) {
      releaseContentsSheet ??= bindContentsSheet(docsRoot);
    } else {
      release();
    }
  };

  query.addEventListener("change", sync);
  sync();

  return () => {
    query.removeEventListener("change", sync);
    release();
  };
};

/**
 * Restores the page title on phones: Docsify builds it from innerText, which is empty while the
 * Contents sheet is hidden.
 * @param {HTMLElement} docsRoot Docs root container.
 */
export const syncPhoneDocsTitle = (docsRoot) => {
  if (!isPhoneViewport()) {
    return;
  }

  // Docsify moves active from the page to the section a deep link names.
  const active = docsRoot.querySelector(`${DOCS_SIDEBAR_SELECTOR} .active`);
  const pageItem = active?.closest(".app-sub-sidebar")?.parentElement ?? active;
  const title = pageItem?.querySelector(":scope > a")?.textContent.trim();
  if (title) {
    document.title = title;
  }
};

/**
 * Reloads the docs page.
 */
export const reloadDocsPage = () => {
  docsReloadHandler();
};

/**
 * Replaces the docs reload handler.
 * @param {() => void} handler Reload handler.
 */
export const setDocsReloadHandler = (handler) => {
  docsReloadHandler = handler;
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
  const padding = isPhoneViewport() ? DOCS_PHONE_ANCHOR_OFFSET_PX : DOCS_ANCHOR_SCROLL_PADDING_PX;
  window.scrollTo({
    behavior: "auto",
    top: Math.max(0, top - padding),
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

/**
 * Binds the Contents sheet state and the close paths that Docsify leaves out on phones.
 * @param {HTMLElement} docsRoot Docs root container.
 * @returns {() => void} Cleanup callback.
 */
const bindContentsSheet = (docsRoot) => {
  let closeWatcher = null;
  let sheetOpen = false;
  let releaseSheetHead = null;

  const hideSheet = () => {
    document.body.classList.remove("close");
    docsRoot.classList.remove("close");
  };

  const requestClose = () => {
    docsRoot.querySelector(DOCS_TOGGLE_SELECTOR)?.click();
  };

  const handleEscape = (event) => {
    if (event.key === "Escape") {
      requestClose();
    }
  };

  const releaseCloseRequests = () => {
    closeWatcher?.destroy();
    closeWatcher = null;
    document.removeEventListener("keydown", handleEscape);
    window.removeEventListener("hashchange", hideSheet);
  };

  // Follow the body class: links and outside taps close the sheet without the toggle.
  const syncCloseRequests = () => {
    if (!document.body.classList.contains("close")) {
      releaseCloseRequests();
      return;
    }

    // Back reaches the page behind the sheet wherever no CloseWatcher takes it first.
    window.addEventListener("hashchange", hideSheet);

    // Chromium turns Escape into a close request, so the key only needs a listener without it.
    if (!("CloseWatcher" in window)) {
      document.addEventListener("keydown", handleEscape);
      return;
    }

    if (closeWatcher) {
      return;
    }

    closeWatcher = new window.CloseWatcher();
    closeWatcher.addEventListener("close", () => {
      closeWatcher = null;
      requestClose();
    });
  };

  const syncSheetState = ({ returnFocus = true } = {}) => {
    releaseSheetHead ??= insertContentsSheetHead(docsRoot);
    const open = document.body.classList.contains("close");
    if (open && !sheetOpen) {
      revealCurrentRow(docsRoot);
    }
    if (!open && sheetOpen && returnFocus) {
      returnFocusToToggle(docsRoot);
    }
    sheetOpen = open;
    writeSheetAttributes(docsRoot, open);
    syncCloseRequests();
  };

  // Runs at once, because HTMX clones the page for history before the body observer would.
  const closeForNavigation = () => {
    hideSheet();
    syncSheetState({ returnFocus: false });
  };

  // Docsify closes on any tap when it loaded at 600px or less, and on none above that, so links
  // close here and its body listener never sees the rest of the sheet.
  const handleSheetClick = (event) => {
    if (closestElement(event.target, DOCS_SHEET_HEAD_CLOSE_SELECTOR)) {
      // The close button sits inside the sidebar, so dismiss here before the swallow below eats it.
      event.stopPropagation();
      requestClose();
      return;
    }
    const link = closestElement(event.target, `${DOCS_SIDEBAR_SELECTOR} a`);
    if (link?.hash === window.location.hash) {
      // The current page goes nowhere, so this close counts as a dismissal.
      hideSheet();
    } else if (link) {
      closeForNavigation();
    } else if (closestElement(event.target, ".sidebar")) {
      event.stopPropagation();
    }
  };

  // The first pageshow fires after load and must not close a sheet opened on a slow page.
  const handlePageShow = (event) => {
    if (event.persisted) {
      closeForNavigation();
    }
  };

  // Also catches the toggle: Docsify renders it after this binds, then adds its ready class.
  const bodyObserver = new MutationObserver(() => syncSheetState());
  bodyObserver.observe(document.body, {
    attributeFilter: ["class"],
    attributes: true,
  });
  syncSheetState();

  docsRoot.addEventListener("click", handleSheetClick, true);
  document.addEventListener("htmx:beforeHistorySave", closeForNavigation);
  document.addEventListener("htmx:historyRestore", closeForNavigation);
  window.addEventListener("pageshow", handlePageShow);

  return () => {
    bodyObserver.disconnect();
    releaseSheetHead?.();
    releaseSheetHead = null;
    releaseCloseRequests();
    clearSheetAttributes(docsRoot);
    docsRoot.removeEventListener("click", handleSheetClick, true);
    document.removeEventListener("htmx:beforeHistorySave", closeForNavigation);
    document.removeEventListener("htmx:historyRestore", closeForNavigation);
    window.removeEventListener("pageshow", handlePageShow);
  };
};

/**
 * Gives the toggle and the page back the state they have off phones.
 * @param {HTMLElement} docsRoot Docs root container.
 */
const clearSheetAttributes = (docsRoot) => {
  const toggle = docsRoot.querySelector(DOCS_TOGGLE_SELECTOR);
  toggle?.removeAttribute("aria-expanded");
  toggle?.setAttribute("aria-label", DOCSIFY_TOGGLE_NAME);
  docsRoot.querySelector(".content")?.removeAttribute("inert");
};

/**
 * Inserts the Contents sheet head with a title and close button, so the phone Contents sheet
 * matches the close affordance of the app's other sheets. No-op once the head exists or before
 * Docsify has rendered the sidebar. The close button is handled by the sheet's delegated click
 * listener, so no per-button listener is attached here.
 * @param {HTMLElement} docsRoot Docs root container.
 * @returns {(() => void)|null} Cleanup that removes the head, or null when nothing was inserted.
 */
const insertContentsSheetHead = (docsRoot) => {
  const sidebar = docsRoot.querySelector(".sidebar");
  if (!sidebar || sidebar.querySelector(DOCS_SHEET_HEAD_SELECTOR)) {
    return null;
  }

  const head = document.createElement("div");
  head.className = "docs-sheet-head";

  const title = document.createElement("span");
  title.className = "docs-sheet-head-title";
  title.textContent = DOCS_PHONE_TOGGLE_NAME;

  const close = document.createElement("button");
  close.type = "button";
  close.className = "docs-sheet-head-close";
  const closeLabel = document.createElement("span");
  closeLabel.className = "sr-only";
  closeLabel.textContent = "Close contents";
  close.append(closeLabel);

  head.append(title, close);
  sidebar.prepend(head);

  return () => {
    head.remove();
  };
};

/**
 * Moves focus to the toggle when it would otherwise be lost with the hiding sheet. Focus a tap
 * put elsewhere, such as on a header control, stays there.
 * @param {HTMLElement} docsRoot Docs root container.
 */
const returnFocusToToggle = (docsRoot) => {
  const { activeElement, body } = document;
  if (activeElement === body || docsRoot.querySelector(".sidebar")?.contains(activeElement)) {
    docsRoot.querySelector(DOCS_TOGGLE_SELECTOR)?.focus();
  }
};

/**
 * Scrolls the current row into the open Contents sheet, because Docsify's own sidebar tracking
 * never runs at 600px or less.
 * @param {HTMLElement} docsRoot Docs root container.
 */
const revealCurrentRow = (docsRoot) => {
  const sheet = docsRoot.querySelector(".sidebar");
  const row = [...docsRoot.querySelectorAll(`${DOCS_SIDEBAR_SELECTOR} li.active > a`)].pop();
  if (!sheet || !row) {
    return;
  }

  const sheetBox = sheet.getBoundingClientRect();
  const rowBox = row.getBoundingClientRect();
  if (rowBox.top < sheetBox.top || rowBox.bottom > sheetBox.bottom) {
    // A third of the way down leaves room for the page's sub-rows below it.
    sheet.scrollTop += rowBox.top - sheetBox.top - sheetBox.height / 3;
  }
};

/**
 * Writes the Contents sheet state onto the toggle and the page behind it.
 * @param {HTMLElement} docsRoot Docs root container.
 * @param {boolean} open Whether the sheet is open.
 */
const writeSheetAttributes = (docsRoot, open) => {
  const toggle = docsRoot.querySelector(DOCS_TOGGLE_SELECTOR);
  toggle?.setAttribute("aria-expanded", String(open));
  toggle?.setAttribute("aria-label", DOCS_PHONE_TOGGLE_NAME);
  docsRoot.querySelector(".content")?.toggleAttribute("inert", open);
};
