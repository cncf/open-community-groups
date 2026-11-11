import { initializeMatchingRoots, initializeOnReadyAndHtmxLoad } from "/static/js/common/dom.js";

const BADGE_CLAMP_SELECTOR = "[data-badge-clamp]";
// Clamp on narrow (mobile-width) layouts only, matching the `md` breakpoint. Width alone keeps it
// working on real phones and when a desktop window is narrowed, unlike the pointer-gated phone query.
export const CLAMP_MEDIA_QUERY = "(width < 48rem)";
const isNarrowViewport = () =>
  typeof window.matchMedia === "function" && window.matchMedia(CLAMP_MEDIA_QUERY).matches;
const TOGGLE_CLASS =
  "custom-badge inline-flex items-center px-2.5 py-0.5 text-stone-600 border-stone-300 " +
  "bg-stone-100 cursor-pointer transition-colors hover:bg-stone-200 hover:text-stone-900 " +
  "focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary-edge";
const COLLAPSE_LABEL = "Show less";
// Visible lines kept on narrow layouts before badges fold behind the toggle. Desktop is untouched.
const VISIBLE_LINES = 2;
// Row grouping and fit checks tolerate sub-pixel layout rounding.
const ROW_TOLERANCE = 1;

/** State of each bound badge row, keyed by its container. */
const boundRows = new Map();

/** Media query list the viewport-change listener is currently attached to. */
let mediaQuery = null;

/**
 * Attaches the viewport-change listener to the current media query list, moving
 * it if `window.matchMedia` now returns a different object (e.g. under a test
 * double). Binding here rather than at import keeps the single listener aligned
 * with the live matchMedia instead of one captured before setup.
 * @returns {void}
 */
const ensureViewportListener = () => {
  const query = window.matchMedia(CLAMP_MEDIA_QUERY);
  if (query === mediaQuery) {
    return;
  }

  mediaQuery?.removeEventListener("change", handleViewportChange);
  mediaQuery = query;
  mediaQuery.addEventListener("change", handleViewportChange);
};

/**
 * Binds the agenda badge rows under a root so they fold past the visible lines
 * behind a "+N" toggle. Server-rendered rows keep every badge, so without
 * JavaScript the full list stays visible.
 * @param {Document|Element} [root=document] Root element to scan from.
 * @returns {void}
 */
export const initializeAgendaBadges = (root = document) => {
  ensureViewportListener();
  boundRows.forEach((_, row) => {
    if (!row.isConnected) {
      releaseRow(row);
    }
  });
  initializeMatchingRoots(root, BADGE_CLAMP_SELECTOR, bindRow);
};

/**
 * Folds the row to the visible lines or expands it, depending on the current
 * state. It first measures the row with every badge shown, so the hidden set is
 * computed from the natural wrapping rather than a previous clamp. Only narrow
 * layouts fold badges; desktop keeps its full, wrapped list unchanged.
 * @param {HTMLElement} row Badge row container.
 * @param {{badges: HTMLElement[], expanded: boolean, toggle: HTMLButtonElement}} state Row state.
 * @returns {void}
 */
const applyClamp = (row, state) => {
  const { badges, toggle } = state;

  // A disconnected row was removed without a re-init to sweep it; drop it now.
  if (!row.isConnected) {
    releaseRow(row);
    return;
  }

  // Reset to the fully expanded layout before measuring.
  badges.forEach((badge) => {
    badge.hidden = false;
  });
  toggle.hidden = true;

  // Desktop keeps every badge wrapped as before; only narrow layouts fold them.
  if (!isNarrowViewport()) {
    return;
  }

  // A row inside a hidden day tab has no width yet; leave it for the next observe.
  if (row.clientWidth === 0) {
    return;
  }

  const rowTop = row.getBoundingClientRect().top;
  const relativeTop = (element) => element.getBoundingClientRect().top - rowTop;
  const tops = lineTops(badges, relativeTop);

  // Everything already fits within the visible lines: no toggle needed.
  if (tops.length <= VISIBLE_LINES) {
    setToggleState(toggle, false, 0);
    return;
  }

  const thresholdTop = tops[VISIBLE_LINES - 1];
  if (state.expanded) {
    setToggleState(toggle, true, hiddenCount(badges, relativeTop, thresholdTop));
    return;
  }

  // Hide every badge below the last visible line, then free space until the toggle fits too.
  badges.forEach((badge) => {
    badge.hidden = relativeTop(badge) > thresholdTop + ROW_TOLERANCE;
  });
  setToggleState(toggle, false, countHidden(badges));
  let visible = badges.filter((badge) => !badge.hidden);
  while (visible.length > 1 && relativeTop(toggle) > thresholdTop + ROW_TOLERANCE) {
    visible.pop().hidden = true;
    setToggleState(toggle, false, countHidden(badges));
    visible = badges.filter((badge) => !badge.hidden);
  }
};

/**
 * Binds one badge row: captures its badges, appends the toggle and observes its
 * width so the clamp re-runs on resize and when a hidden day tab is revealed.
 * @param {HTMLElement} row Badge row container.
 * @returns {void}
 */
const bindRow = (row) => {
  if (boundRows.has(row)) {
    return;
  }

  // An htmx history snapshot serializes a previously injected toggle into the
  // restored HTML; drop any before capturing badges so it is not measured as one.
  row.querySelectorAll(":scope > [data-badge-toggle]").forEach((stale) => stale.remove());

  const badges = Array.from(row.children);
  if (badges.length === 0) {
    return;
  }

  const toggle = buildToggle();
  const state = { badges, expanded: false, lastWidth: null, toggle };
  const listeners = new AbortController();
  // Width changes reflow the badges; height changes only echo our own folding.
  const observer = new ResizeObserver((entries) => {
    const width = entries[entries.length - 1].contentRect.width;
    if (width === state.lastWidth) {
      return;
    }
    state.lastWidth = width;
    applyClamp(row, state);
  });

  toggle.addEventListener(
    "click",
    () => {
      state.expanded = !state.expanded;
      applyClamp(row, state);
    },
    { signal: listeners.signal },
  );
  row.append(toggle);
  observer.observe(row);

  boundRows.set(row, {
    release: () => {
      listeners.abort();
      observer.disconnect();
    },
    state,
  });
};

/**
 * Creates the toggle button shared by both states.
 * @returns {HTMLButtonElement} Toggle button.
 */
const buildToggle = () => {
  const toggle = document.createElement("button");
  toggle.type = "button";
  toggle.hidden = true;
  toggle.dataset.badgeToggle = "";
  toggle.className = TOGGLE_CLASS;
  return toggle;
};

/**
 * Counts the badges currently folded away.
 * @param {HTMLElement[]} badges All badges of the row.
 * @returns {number} Hidden badge count.
 */
const countHidden = (badges) => badges.filter((badge) => badge.hidden).length;

/**
 * Re-measures every bound row when the narrow layout toggles, so desktop
 * restores the full list and narrow layouts re-apply the fold.
 * @returns {void}
 */
const handleViewportChange = () => {
  boundRows.forEach(({ state }, row) => applyClamp(row, state));
};

/**
 * Counts the badges that fall below the last visible line.
 * @param {HTMLElement[]} badges All badges of the row.
 * @param {(element: HTMLElement) => number} relativeTop Top offset within the row.
 * @param {number} thresholdTop Top offset of the last visible line.
 * @returns {number} Hidden badge count.
 */
const hiddenCount = (badges, relativeTop, thresholdTop) =>
  badges.filter((badge) => relativeTop(badge) > thresholdTop + ROW_TOLERANCE).length;

/**
 * Lists the distinct top offsets of the badge lines, in order.
 * @param {HTMLElement[]} badges All badges of the row.
 * @param {(element: HTMLElement) => number} relativeTop Top offset within the row.
 * @returns {number[]} Top offset of each line.
 */
const lineTops = (badges, relativeTop) => {
  const tops = [];
  badges.forEach((badge) => {
    const top = relativeTop(badge);
    if (tops.length === 0 || top > tops[tops.length - 1] + ROW_TOLERANCE) {
      tops.push(top);
    }
  });
  return tops;
};

/**
 * Removes a row's listeners and observer.
 * @param {HTMLElement} row Badge row container.
 * @returns {void}
 */
const releaseRow = (row) => {
  const entry = boundRows.get(row);
  entry?.release();
  entry?.state.toggle.remove();
  boundRows.delete(row);
};

/**
 * Updates the toggle label, visibility and assistive state for a clamp result.
 * @param {HTMLButtonElement} toggle Toggle button.
 * @param {boolean} expanded Whether the row is expanded.
 * @param {number} hidden Number of folded badges.
 * @returns {void}
 */
const setToggleState = (toggle, expanded, hidden) => {
  if (!expanded && hidden === 0) {
    toggle.hidden = true;
    toggle.setAttribute("aria-expanded", "false");
    return;
  }

  toggle.hidden = false;
  toggle.setAttribute("aria-expanded", String(expanded));
  toggle.textContent = expanded ? COLLAPSE_LABEL : `+${hidden}`;
  toggle.setAttribute(
    "aria-label",
    expanded ? "Show fewer labels" : `Show ${hidden} more ${hidden === 1 ? "label" : "labels"}`,
  );
};

initializeOnReadyAndHtmxLoad(initializeAgendaBadges);
