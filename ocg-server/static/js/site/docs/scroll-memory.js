const DOCS_SCROLL_MAX_POSITIONS = 50;
const DOCS_SCROLL_POSITIONS_KEY = "ocg-docs-scroll-positions";
const DOCS_SCROLL_RESTORE_KEY = "ocg-docs-scroll-restore";
// Outlasts Docsify's 500ms anchor scroll, which starts just before the first render ends.
const DOCS_SCROLL_RESTORE_HOLD_MS = 600;
const READER_INPUT_EVENTS = ["keydown", "pointerdown", "wheel"];

/**
 * Remembers the scroll position of each docs URL as the reader leaves it.
 * @returns {() => void} Cleanup callback.
 */
export const setupDocsScrollMemory = () => {
  let shownUrl = window.location.href;

  const saveShownPage = () => {
    savePosition(shownUrl, window.scrollY);
    shownUrl = window.location.href;
  };

  // Back has already moved the URL when HTMX saves, so the page on screen is the one to file.
  const saveShownPageOnUrlChange = () => {
    if (shownUrl !== window.location.href) {
      saveShownPage();
    }
  };

  document.addEventListener("htmx:beforeHistorySave", saveShownPage);
  // Popstate comes first on Back, before the browser moves the scroll position itself.
  window.addEventListener("popstate", saveShownPageOnUrlChange);
  window.addEventListener("hashchange", saveShownPageOnUrlChange);

  return () => {
    document.removeEventListener("htmx:beforeHistorySave", saveShownPage);
    window.removeEventListener("popstate", saveShownPageOnUrlChange);
    window.removeEventListener("hashchange", saveShownPageOnUrlChange);
  };
};

/**
 * Asks the next mount to restore the current URL's position, for a reload that replaces a history
 * entry. Nothing else restores, so a fresh visit to a saved URL starts at the top or its anchor.
 */
export const armDocsScrollRestore = () => {
  const armed = { document: window.performance.timeOrigin, url: window.location.href };
  sessionStorageSetItem(DOCS_SCROLL_RESTORE_KEY, JSON.stringify(armed));
};

/**
 * Takes the position armed for the current URL and builds the restore for the first render.
 * @returns {{start: () => void, cancel: () => void}} Restore controls.
 */
export const createDocsScrollRestore = () => {
  const url = window.location.href;
  let frameId = null;
  let targetY = takeArmedPosition(url);

  const cancel = () => {
    if (frameId === null) {
      return;
    }

    window.cancelAnimationFrame(frameId);
    frameId = null;
    READER_INPUT_EVENTS.forEach((type) => window.removeEventListener(type, cancel));
  };

  const start = () => {
    if (targetY === null) {
      return;
    }

    const top = targetY;
    const holdEnd = window.performance.now() + DOCS_SCROLL_RESTORE_HOLD_MS;
    targetY = null;

    // Docsify's anchor scroll and images settling late would both move the page off the target.
    const hold = () => {
      const onSamePage = window.location.href === url;
      if (onSamePage) {
        window.scrollTo({ behavior: "auto", top });
      }

      if (onSamePage && window.performance.now() < holdEnd) {
        frameId = window.requestAnimationFrame(hold);
      } else {
        cancel();
      }
    };

    frameId = window.requestAnimationFrame(hold);
    READER_INPUT_EVENTS.forEach((type) => {
      window.addEventListener(type, cancel, { once: true, passive: true });
    });
  };

  return { cancel, start };
};

/**
 * Reads the armed restore.
 * @returns {{document: number, url: string}|null} Armed restore, or null.
 */
const readArmedRestore = () => {
  try {
    return JSON.parse(sessionStorageGetItem(DOCS_SCROLL_RESTORE_KEY));
  } catch {
    return null;
  }
};

/**
 * Reads the saved positions.
 * @returns {Record<string, number>} Scroll positions by URL.
 */
const readPositions = () => {
  try {
    return JSON.parse(sessionStorageGetItem(DOCS_SCROLL_POSITIONS_KEY)) ?? {};
  } catch {
    return {};
  }
};

/**
 * Saves a position as the newest one, dropping the oldest past the limit. A reload already opens
 * at the top, so that position replaces any older one with nothing to restore.
 * @param {string} url Page URL.
 * @param {number} scrollY Scroll position.
 */
const savePosition = (url, scrollY) => {
  const positions = readPositions();
  delete positions[url];
  if (scrollY > 0) {
    positions[url] = scrollY;
  }

  const entries = Object.entries(positions).slice(-DOCS_SCROLL_MAX_POSITIONS);
  writePositions(Object.fromEntries(entries));
};

/**
 * Reads a session storage item when browser storage is available.
 * @param {string} key Storage key.
 * @returns {string|null} Stored value, or null when unavailable.
 */
const sessionStorageGetItem = (key) => {
  try {
    return window.sessionStorage?.getItem(key) ?? null;
  } catch {
    return null;
  }
};

/**
 * Removes a session storage item when browser storage is available.
 * @param {string} key Storage key.
 */
const sessionStorageRemoveItem = (key) => {
  try {
    window.sessionStorage?.removeItem(key);
  } catch {
    // Ignore unavailable browser storage.
  }
};

/**
 * Stores a session storage item when browser storage is available. HTMX's history cache can leave
 * no room, and a lost position only means the page opens at the top.
 * @param {string} key Storage key.
 * @param {string} value Storage value.
 */
const sessionStorageSetItem = (key, value) => {
  try {
    window.sessionStorage?.setItem(key, value);
  } catch {
    // Ignore unavailable or full browser storage.
  }
};

/**
 * Clears the armed restore and removes its position, so each one applies once.
 * @param {string} url Current URL.
 * @returns {number|null} Position armed for the URL, or null.
 */
const takeArmedPosition = (url) => {
  const armed = readArmedRestore();
  sessionStorageRemoveItem(DOCS_SCROLL_RESTORE_KEY);
  // The document that armed it is still here when its reload was aborted.
  if (armed?.url !== url || armed.document === window.performance.timeOrigin) {
    return null;
  }

  const positions = readPositions();
  const scrollY = positions[url];
  delete positions[url];
  writePositions(positions);

  return Number.isFinite(scrollY) ? scrollY : null;
};

/**
 * Writes the saved positions.
 * @param {Record<string, number>} positions Scroll positions by URL.
 */
const writePositions = (positions) => {
  sessionStorageSetItem(DOCS_SCROLL_POSITIONS_KEY, JSON.stringify(positions));
};
