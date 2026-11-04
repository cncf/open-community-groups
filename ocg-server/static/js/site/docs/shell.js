import { loadScriptOnce } from "/static/js/common/dom.js";
import {
  getCurrentDocsRoute,
  parseDocsRoute,
  parseSamePageAnchor,
  runDocsEnhancements,
  syncCurrentSidebarSectionState,
} from "/static/js/site/docs/enhancements.js";
import {
  createCurrentSidebarPageClickHandler,
  createSamePageAnchorClickHandler,
  mirrorDocsifyBodyClasses,
  reloadDocsPage,
  setupDocsPhoneShell,
  setupDocsTopOffsetSync,
  setupMobileSidebarOutsideDismiss,
  syncPhoneDocsTitle,
} from "/static/js/site/docs/interactions.js";
import {
  armDocsScrollRestore,
  createDocsScrollRestore,
  setupDocsScrollMemory,
} from "/static/js/site/docs/scroll-memory.js";
import { setupDocsScopedStyles } from "/static/js/site/docs/styles.js";

const DOCS_ROOT_SELECTOR = ".ocg-docs-root";
const DOCS_APP_SELECTOR = "#ocg-docs-app";

const SCRIPT_URLS = {
  copyCode: "/static/vendor/js/docsify-copy-code.v3.0.2.min.js",
  docsify: "/static/vendor/js/docsify.v4.13.1.min.js",
};

let activeDocsRoot = null;
let cleanupCurrentMount = null;
let mountRunId = 0;
let lifecycleListenersBound = false;
const DOCS_RELOAD_LATCH_MS = 500;
let reloadRequested = false;
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

const handleCurrentSidebarPageClick = createCurrentSidebarPageClickHandler({
  getCurrentDocsRoute,
  parseDocsRoute,
  scheduleCurrentSidebarSectionStateSync,
});

const handleSamePageAnchorClick = createSamePageAnchorClickHandler({
  getCurrentDocsRoute,
  parseSamePageAnchor,
  scheduleCurrentSidebarSectionStateSync,
});

/**
 * Initializes docs routing hash when visiting /docs without one.
 */
const ensureInitialDocsHash = () => {
  if (!window.location.hash) {
    window.history.replaceState(window.history.state, "", `${window.location.pathname}#/`);
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
 * @param {() => void} afterRender Callback for each finished render.
 * @returns {Function[]} Docsify plugins.
 */
const createDocsifyPlugins = (runId, docsRoot, afterRender) => [
  (hook) => {
    hook.doneEach(() => {
      if (!isCurrentMount(runId, docsRoot)) {
        return;
      }

      syncPhoneDocsTitle(docsRoot);
      afterRender();
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

  // A new mount invalidates async work still pending from a previous docs root.
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
    // Taken before anything async, so a mount that never finishes cannot leave it for a later visit.
    const { cancel: cancelScrollRestore, start: startScrollRestore } = createDocsScrollRestore();
    cleanups.push(cancelScrollRestore);

    ensureInitialDocsHash();
    // Docsify injects its own styles, so scoped shell styles must exist first.
    await setupDocsScopedStyles();

    if (!isCurrentMount(runId, docsRoot)) {
      return;
    }

    cleanups.push(setupDocsTopOffsetSync(docsRoot));
    cleanups.push(setupMobileSidebarOutsideDismiss());

    const { cancel: cancelDocsEnhancements, schedule: scheduleDocsEnhancements } =
      createDocsEnhancementsScheduler(runId, docsRoot);
    cleanups.push(cancelDocsEnhancements);

    const docsifyPlugins = createDocsifyPlugins(runId, docsRoot, () => {
      scheduleDocsEnhancements();
      startScrollRestore();
    });

    // Docsify reads this global when its script module executes.
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
    cleanups.push(setupDocsPhoneShell(docsRoot));
    // Docsify scrolls within its own hashchange listener, so this one has to bind first.
    cleanups.push(setupDocsScrollMemory());
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
 * Reloads once, however many lifecycle events ask for it before the page goes.
 */
const reloadDocsOnce = () => {
  if (reloadRequested) {
    return;
  }

  // Covers the events of one restore. A reader can abort the reload and stay on this document.
  reloadRequested = true;
  setTimeout(() => {
    reloadRequested = false;
  }, DOCS_RELOAD_LATCH_MS);
  reloadDocsPage();
};

/**
 * Replaces a page HTMX restored from history, keeping the reader's place.
 */
const reloadRestoredDocs = () => {
  armDocsScrollRestore();
  reloadDocsOnce();
};

/**
 * Synchronizes docs lifecycle with current DOM.
 * @param {Event} [event] Lifecycle event, absent on the first run.
 */
const syncDocsLifecycle = (event) => {
  const docsRoot = document.querySelector(DOCS_ROOT_SELECTOR);

  // A restore always swaps the page and HTMX fires afterSwap first, so even a mount here is only
  // as old as this restore. Snapshots and server markup both need a new start for Docsify.
  if (event?.type === "htmx:historyRestore" && docsRoot) {
    reloadRestoredDocs();
    return;
  }

  // Docsify replaces the app node, so only the root tells a live mount from a new page.
  if (docsRoot === activeDocsRoot && cleanupCurrentMount) {
    return;
  }

  const docsApp = docsRoot?.querySelector(DOCS_APP_SELECTOR);

  // Only a snapshot lacks the app node, when this module first ran after its restore event.
  if (!event && docsRoot && !docsApp) {
    reloadRestoredDocs();
    return;
  }

  if (!docsApp) {
    unmountDocs();
    return;
  }

  // Docsify only starts on script load, so a second mount in this document would never render.
  if (typeof window.Docsify !== "undefined") {
    reloadDocsOnce();
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
