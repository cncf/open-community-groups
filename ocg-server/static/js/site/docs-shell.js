import { closestElement, getElementById, loadScriptOnce } from "/static/js/common/dom.js";
import {
  getCurrentDocsRoute,
  parseDocsRoute,
  parseSamePageAnchor,
  runDocsEnhancements,
  syncCurrentSidebarSectionState,
} from "/static/js/site/docs-shell-enhancements.js";
import {
  jumpToElement,
  mirrorDocsifyBodyClasses,
  setupDocsTopOffsetSync,
  setupMobileSidebarOutsideDismiss,
  updateDocsAnchorHash,
} from "/static/js/site/docs-shell-interactions.js";
import { setupDocsScopedStyles } from "/static/js/site/docs-shell-styles.js";

const DOCS_ROOT_SELECTOR = ".ocg-docs-root";
const DOCS_APP_SELECTOR = "#ocg-docs-app";
const DOCS_SIDEBAR_SELECTOR = ".sidebar-nav";

const SCRIPT_URLS = {
  copyCode: "/static/vendor/js/docsify-copy-code.v3.0.2.min.js",
  docsify: "/static/vendor/js/docsify.v4.13.1.min.js",
};

let activeDocsRoot = null;
let cleanupCurrentMount = null;
let mountRunId = 0;
let lifecycleListenersBound = false;
const DOCS_LOAD_ERROR_MESSAGE = "We could not load the documentation. Please refresh and try again.";

/**
 * Re-applies sidebar section state after Docsify finishes reacting to anchor clicks.
 */
const scheduleCurrentSidebarSectionStateSync = () => {
  const syncIfMounted = () => {
    if (!activeDocsRoot || !activeDocsRoot.isConnected) {
      return;
    }

    syncCurrentSidebarSectionState(activeDocsRoot);
  };

  syncIfMounted();
  window.requestAnimationFrame(() => {
    syncIfMounted();
    window.requestAnimationFrame(syncIfMounted);
  });
};

/**
 * Keeps a repeated click on the current sidebar page link from collapsing its sections.
 * @param {MouseEvent} event Click event.
 */
const handleCurrentSidebarPageClick = (event) => {
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
 * Handles same-page anchor clicks without smooth scroll animation.
 * @param {MouseEvent} event Click event.
 */
const handleSamePageAnchorClick = (event) => {
  const link = closestElement(event.target, "a[href]");
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
 * Initializes docs routing hash when visiting /docs without one.
 */
const ensureInitialDocsHash = () => {
  if (!window.location.hash) {
    window.history.replaceState(null, "", `${window.location.pathname}#/`);
  }
};

/**
 * Renders a docs load error in the shell mount container.
 * @param {HTMLElement} docsApp Docs app container.
 */
const renderDocsLoadError = (docsApp) => {
  docsApp.replaceChildren();

  const errorMessage = document.createElement("p");
  errorMessage.className = "px-4 py-8 text-center text-sm text-stone-700";
  errorMessage.setAttribute("role", "alert");
  errorMessage.textContent = DOCS_LOAD_ERROR_MESSAGE;

  docsApp.appendChild(errorMessage);
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
 * Creates an animation-frame scheduler for docs enhancements.
 * @param {number} runId Mount run ID.
 * @param {HTMLElement} docsRoot Docs root container.
 * @returns {{schedule: () => void, cancel: () => void}} Scheduler controls.
 */
const createDocsEnhancementsScheduler = (runId, docsRoot) => {
  let frameId = null;

  const flush = () => {
    frameId = null;
    if (!isCurrentMount(runId, docsRoot)) {
      return;
    }

    runDocsEnhancements(docsRoot);
  };

  const schedule = () => {
    if (frameId !== null) {
      return;
    }

    // Coalesce rapid docsify/hashchange triggers into one enhancement pass.
    frameId = window.requestAnimationFrame(flush);
  };

  const cancel = () => {
    if (frameId === null) {
      return;
    }

    window.cancelAnimationFrame(frameId);
    frameId = null;
  };

  return { cancel, schedule };
};

/**
 * Builds docsify plugins for docs shell behavior.
 * @param {number} runId Mount run ID.
 * @param {HTMLElement} docsRoot Docs root container.
 * @param {() => void} scheduleDocsEnhancements Enhancements scheduler.
 * @returns {Function[]} Docsify plugins.
 */
const createDocsifyPlugins = (runId, docsRoot, scheduleDocsEnhancements) => [
  (hook) => {
    hook.doneEach(() => {
      if (!isCurrentMount(runId, docsRoot)) {
        return;
      }

      scheduleDocsEnhancements();
    });
  },
];

/**
 * Unmounts docs lifecycle and listeners.
 */
const unmountDocs = () => {
  mountRunId += 1;
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

  try {
    ensureInitialDocsHash();
    await setupDocsScopedStyles();

    if (!isCurrentMount(runId, docsRoot)) {
      return;
    }

    cleanups.push(setupDocsTopOffsetSync(docsRoot));
    cleanups.push(setupMobileSidebarOutsideDismiss());

    const { cancel: cancelDocsEnhancements, schedule: scheduleDocsEnhancements } =
      createDocsEnhancementsScheduler(runId, docsRoot);
    cleanups.push(cancelDocsEnhancements);

    const docsifyPlugins = createDocsifyPlugins(runId, docsRoot, scheduleDocsEnhancements);

    window.$docsify = {
      alias: {
        "/.*/_sidebar.md": "/_sidebar.md",
      },
      auto2top: true,
      basePath: "/static/docs/",
      el: DOCS_APP_SELECTOR,
      homepage: "index.md",
      loadSidebar: "_sidebar.md",
      maxLevel: 3,
      name: "Documentation",
      plugins: docsifyPlugins,
      relativePath: true,
      subMaxLevel: 2,
    };

    cleanups.push(mirrorDocsifyBodyClasses(docsRoot));
    document.addEventListener("click", handleCurrentSidebarPageClick);
    cleanups.push(() => {
      document.removeEventListener("click", handleCurrentSidebarPageClick);
    });
    document.addEventListener("click", handleSamePageAnchorClick);
    cleanups.push(() => {
      document.removeEventListener("click", handleSamePageAnchorClick);
    });

    const handleRewriteOnHashChange = () => {
      scheduleDocsEnhancements();
    };
    window.addEventListener("hashchange", handleRewriteOnHashChange);
    cleanups.push(() => {
      window.removeEventListener("hashchange", handleRewriteOnHashChange);
    });

    await loadScriptOnce(SCRIPT_URLS.docsify, {
      isLoaded: () => typeof window.Docsify !== "undefined",
    });
    if (!isCurrentMount(runId, docsRoot)) {
      return;
    }

    await loadScriptOnce(SCRIPT_URLS.copyCode);
    if (!isCurrentMount(runId, docsRoot)) {
      return;
    }

    scheduleDocsEnhancements();
  } catch (error) {
    if (!isCurrentMount(runId, docsRoot)) {
      return;
    }

    renderDocsLoadError(docsApp);
  }
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
