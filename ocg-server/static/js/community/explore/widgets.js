import { fitCohostsLines } from "/static/js/common/cohosts-line.js";
import { getElementById, setElementHidden } from "/static/js/common/dom.js";
import { ocgFetch } from "/static/js/common/fetch.js";
import { escapeHtml } from "/static/js/common/trusted-html.js";

export const CARD_CACHE_MAX_ENTRIES = 1000;
// Matches the shared cache lifetime of the card responses.
export const CARD_CACHE_TTL_MS = 300000;
export const CARD_STATUS = Object.freeze({
  loading: "loading",
  ready: "ready",
  unavailable: "unavailable",
});
// Gives the pointer time to cross the gap between a trigger and its card.
export const POPOVER_CLOSE_DELAY_MS = 100;
export const POPOVER_OPEN_DELAY_MS = 300;
const DEFAULT_TIMERS = Object.freeze({
  clearTimeout: (timeoutId) => window.clearTimeout(timeoutId),
  setTimeout: (callback, delay) => window.setTimeout(callback, delay),
});
const MIDDLE_BUTTON = 1;
const TRIGGER_SOURCE = Object.freeze({
  focus: "focus",
  hover: "hover",
  tooltip: "tooltip",
});

/**
 * Keeps a card open while hovered and forwards card clicks to its trigger.
 * Plain clicks follow the trigger in place; new-tab clicks open its link in a
 * new tab, as they would on the trigger itself.
 * @param {HTMLElement} tooltip - Card tooltip element
 * @param {HTMLAnchorElement} trigger - Link that owns the card
 * @param {object} controller - Card controller created by createCardController
 * @returns {() => void} Cleanup function removing the listeners
 */
export const bindExploreCardTooltip = (tooltip, trigger, controller) => {
  const listeners = {
    auxclick: (event) => {
      if (event.button !== MIDDLE_BUTTON) return;
      event.preventDefault();
      openInNewTab(trigger);
    },
    click: (event) => {
      event.preventDefault();
      if (isPlainLeftClick(event)) {
        trigger.click();
      } else if (event.ctrlKey || event.metaKey || event.shiftKey) {
        openInNewTab(trigger);
      }
    },
    mouseenter: () => controller.activate(TRIGGER_SOURCE.tooltip),
    mouseleave: () => controller.deactivate(TRIGGER_SOURCE.tooltip),
  };
  return addListeners(tooltip, listeners);
};

/**
 * Binds hover, focus, and Escape on a card trigger to its card controller.
 * @param {HTMLElement} trigger - Link that owns the card
 * @param {object} controller - Card controller created by createCardController
 * @returns {() => void} Cleanup function removing the listeners
 */
export const bindExploreCardTrigger = (trigger, controller) => {
  const listeners = {
    blur: () => controller.deactivate(TRIGGER_SOURCE.focus),
    focus: () => controller.activate(TRIGGER_SOURCE.focus),
    keydown: (event) => {
      if (event.key === "Escape" && controller.isActive()) {
        event.stopPropagation();
        controller.dismiss();
      }
    },
    mouseenter: () => controller.activate(TRIGGER_SOURCE.hover),
    mouseleave: () => controller.deactivate(TRIGGER_SOURCE.hover),
  };
  return addListeners(trigger, listeners);
};

/**
 * Creates the controller deciding when an item card opens, renders, and closes.
 * The card request starts on the first activation, in parallel with the open
 * delay, and results never render before the delay or after the card closes.
 * A card that failed to load is requested again on the next activation.
 * @param {object} options - Controller options
 * @param {() => void} options.close - Removes the rendered card
 * @param {object} options.item - Explore item owning the card
 * @param {object} options.loader - Card loader created by createExploreCardLoader
 * @param {(result: object) => void} options.render - Renders a card result
 * @param {object} [options.timers] - Timer functions, replaceable in tests
 * @returns {object} Controller with activate, deactivate, destroy, dismiss, and state readers
 */
export const createCardController = ({ close, item, loader, render, timers = DEFAULT_TIMERS }) => {
  const sources = new Set();
  let closeTimeoutId = null;
  let destroyed = false;
  let open = false;
  let openTimeoutId = null;
  let result = null;
  let token = 0;

  const clearCloseTimeout = () => {
    if (closeTimeoutId !== null) {
      timers.clearTimeout(closeTimeoutId);
      closeTimeoutId = null;
    }
  };

  const hide = () => {
    clearCloseTimeout();
    if (openTimeoutId !== null) {
      timers.clearTimeout(openTimeoutId);
      openTimeoutId = null;
    }
    sources.clear();
    result = null;
    token += 1;
    if (open) {
      open = false;
      close();
    }
  };

  const requestCard = () => {
    token += 1;
    const currentToken = token;
    loader.load(item).then((loaded) => {
      if (currentToken !== token) return;
      result = loaded;
      if (open) render(loaded);
    });
  };

  const show = () => {
    openTimeoutId = null;
    open = true;
    render(result || loader.peek(item) || { status: CARD_STATUS.loading });
  };

  return {
    activate(source) {
      if (destroyed) return;
      clearCloseTimeout();
      sources.add(source);

      // Retry a failed card that stays active through another source
      if (open || openTimeoutId !== null) {
        if (result?.status === CARD_STATUS.unavailable && !loader.peek(item)) requestCard();
        return;
      }

      // Start loading the card while the open delay runs
      requestCard();
      openTimeoutId = timers.setTimeout(show, POPOVER_OPEN_DELAY_MS);
    },
    deactivate(source) {
      sources.delete(source);
      if (sources.size > 0) return;

      // Cancel a pending open right away, and close an open card after a grace delay
      if (!open) {
        hide();
        return;
      }
      clearCloseTimeout();
      closeTimeoutId = timers.setTimeout(() => {
        closeTimeoutId = null;
        if (sources.size === 0) hide();
      }, POPOVER_CLOSE_DELAY_MS);
    },
    destroy() {
      hide();
      destroyed = true;
    },
    dismiss() {
      hide();
    },
    isActive: () => open || openTimeoutId !== null,
    isOpen: () => open,
  };
};

/**
 * Creates a per-item card loader with a bounded, expiring cache.
 * Concurrent loads of the same item share one request, ready and not-found
 * results are cached until they expire, and failures are retried on the next
 * load. Loads never reject and never alert.
 * @param {string} entity - Explore entity type ('events' or 'groups')
 * @param {string} view - Explore view rendering the cards ('calendar' or 'map')
 * @param {object} [options] - Loader options
 * @param {() => number} [options.now] - Clock, replaceable in tests
 * @returns {{entity: string, load: (item: object) => Promise<object>, peek: (item: object) => object|null}} Card loader
 */
export const createExploreCardLoader = (entity, view, { now = () => Date.now() } = {}) => {
  const cache = new globalThis.Map();
  const getItemId = (item) => (entity === "events" ? item.event_id : item.group_id);

  return {
    entity,
    load(item) {
      const id = getItemId(item);
      const cached = readFreshCacheEntry(cache, id, now());
      if (cached) return cached.promise;

      // Fetch the card and keep it only when the outcome is stable
      const entry = { expiresAt: Number.POSITIVE_INFINITY, promise: null, result: null };
      entry.promise = fetchExploreCard(getExploreCardUrl(entity, item, view)).then(({ cacheable, card }) => {
        if (cacheable) {
          entry.expiresAt = now() + CARD_CACHE_TTL_MS;
          entry.result = card;
        } else if (cache.get(id) === entry) {
          cache.delete(id);
        }
        return card;
      });
      cache.set(id, entry);

      // Evict the oldest entries beyond the cache limit
      while (cache.size > CARD_CACHE_MAX_ENTRIES) {
        cache.delete(cache.keys().next().value);
      }
      return entry.promise;
    },
    peek(item) {
      return readFreshCacheEntry(cache, getItemId(item), now())?.result || null;
    },
  };
};

/**
 * Builds the card URL of an explore item.
 * @param {string} entity - Explore entity type ('events' or 'groups')
 * @param {object} item - Explore item
 * @param {string} view - Explore view rendering the card ('calendar' or 'map')
 * @returns {string|undefined} Card URL when the entity is supported
 */
export const getExploreCardUrl = (entity, item, view) => {
  if (entity === "events") {
    return `/explore/events/${encodeURIComponent(item.event_id)}/card?view_mode=${encodeURIComponent(view)}`;
  }

  if (entity === "groups") {
    return `/explore/groups/${encodeURIComponent(item.group_id)}/card`;
  }

  return undefined;
};

/**
 * Builds the destination URL for an explore item.
 * @param {string} entity - Explore entity type ('events' or 'groups')
 * @param {object} item - Explore item
 * @returns {string|undefined} Destination URL when the entity is supported
 */
export const getExploreItemUrl = (entity, item) => {
  if (entity === "events") {
    if (!item.group_slug || !item.slug) {
      return undefined;
    }
    return `/${item.community_name}/group/${item.group_slug_pretty || item.group_slug}/event/${item.slug}`;
  }

  if (entity === "groups") {
    return `/${item.community_name}/group/${item.slug_pretty || item.slug}`;
  }

  return undefined;
};

/**
 * Checks whether a click is an unmodified primary button click.
 * @param {MouseEvent|undefined} event - Click event
 * @returns {boolean} Whether the click should navigate in place
 */
export const isPlainLeftClick = (event) =>
  Boolean(event) &&
  event.button === 0 &&
  !event.metaKey &&
  !event.ctrlKey &&
  !event.shiftKey &&
  !event.altKey;

/**
 * Shows the main widget loading overlay while vendor scripts load.
 * The overlay is hidden again when loading fails so it doesn't get stuck; on
 * success the widget setup callback is responsible for replacing the view.
 * @param {object} options - Loader options
 * @param {string} options.mainLoadingId - Main loading overlay element id
 * @param {() => Promise<void>} options.loadScripts - Vendor scripts loader
 * @param {() => void} options.onReady - Widget setup callback
 */
export const loadWidgetScripts = ({ mainLoadingId, loadScripts, onReady }) => {
  const setMainLoadingVisible = (visible) => {
    setElementHidden(getElementById(document, mainLoadingId), !visible);
  };

  setMainLoadingVisible(true);
  loadScripts()
    .then(onReady)
    .catch(() => setMainLoadingVisible(false));
};

/**
 * Renders a card result inside the shared card shell.
 * Ready results use the server-rendered card; loading and unavailable results
 * show the item name with a short status line.
 * @param {object} result - Card result with a CARD_STATUS status
 * @param {string} name - Item name shown while the card is not ready
 * @returns {string} Card shell HTML
 */
export const renderExploreCard = (result, name) => {
  if (result?.status === CARD_STATUS.ready) {
    return renderPopoverCardShell(result.html);
  }

  const detail =
    result?.status === CARD_STATUS.unavailable ? "Details are not available right now." : "Loading details…";
  return renderPopoverCardShell(
    `<div class="p-4" data-explore-card-status="${result?.status || CARD_STATUS.loading}">` +
      `<p class="line-clamp-2 text-base font-semibold text-stone-900">${escapeHtml(String(name || ""))}</p>` +
      `<p class="mt-1 text-sm text-stone-500">${detail}</p>` +
      "</div>",
  );
};

/**
 * Wraps popover content in the shared explore popover card shell.
 * @param {string} popoverHtml - Server-rendered popover content
 * @returns {string} Popover card shell HTML
 */
export const renderPopoverCardShell = (popoverHtml) =>
  `<div class="explore-popover-card-shell">${popoverHtml}</div>`;

/**
 * Syncs a rendered card tooltip with its result and links it to its trigger.
 * The tooltip stays non-interactive, so its links are removed.
 * @param {object} options - Tooltip options
 * @param {object} options.result - Card result rendered in the tooltip
 * @param {HTMLElement} options.tooltip - Tooltip element holding the rendered card
 * @param {string} options.tooltipId - Tooltip element id
 * @param {HTMLElement} options.trigger - Link described by the tooltip
 */
export const syncExploreCardTooltip = ({ result, tooltip, tooltipId, trigger }) => {
  tooltip.id = tooltipId;
  tooltip.setAttribute("role", "tooltip");
  tooltip.setAttribute("aria-busy", String(result.status === CARD_STATUS.loading));
  tooltip.querySelectorAll("a[href]").forEach((link) => link.removeAttribute("href"));
  if (result.status === CARD_STATUS.ready) fitCohostsLines(tooltip);
  trigger.setAttribute("aria-describedby", tooltipId);
};

/**
 * Updates the "Showing X of Y" notice of a map or calendar view.
 * @param {HTMLElement|null} element - Truncation notice element
 * @param {object} metadata - Result metadata
 * @param {number} metadata.shown - Number of items drawn
 * @param {number} metadata.total - Number of matching items
 * @param {boolean} metadata.truncated - Whether some matches were left out
 */
export const updateTruncationNotice = (element, { shown, total, truncated }) => {
  if (!element) return;
  const shownElement = element.querySelector("[data-truncation-shown]");
  const totalElement = element.querySelector("[data-truncation-total]");
  if (shownElement) shownElement.textContent = String(shown);
  if (totalElement) totalElement.textContent = String(total);
  setElementHidden(element, !truncated);
};

/**
 * Adds event listeners to an element.
 * @param {HTMLElement} element - Element receiving the listeners
 * @param {Record<string, EventListener>} listeners - Listeners keyed by event type
 * @returns {() => void} Cleanup function removing the listeners
 */
const addListeners = (element, listeners) => {
  Object.entries(listeners).forEach(([type, listener]) => element.addEventListener(type, listener));
  return () => {
    Object.entries(listeners).forEach(([type, listener]) => element.removeEventListener(type, listener));
  };
};

/**
 * Fetches a card and classifies whether its outcome can be cached.
 * @param {string} url - Card URL
 * @returns {Promise<{cacheable: boolean, card: object}>} Card result
 */
const fetchExploreCard = async (url) => {
  try {
    const response = await ocgFetch(url, { headers: { Accept: "text/html" } });
    if (response.ok) {
      return { cacheable: true, card: { html: await response.text(), status: CARD_STATUS.ready } };
    }
    if (response.status === 404) {
      return { cacheable: true, card: { status: CARD_STATUS.unavailable } };
    }
  } catch {
    // Network and body read failures are retried on the next load
  }
  return { cacheable: false, card: { status: CARD_STATUS.unavailable } };
};

/**
 * Opens the link of a trigger in a new tab.
 * @param {HTMLAnchorElement} trigger - Link to open
 */
const openInNewTab = (trigger) => {
  if (trigger.href) window.open(trigger.href, "_blank", "noopener");
};

/**
 * Returns a cache entry that has not expired, dropping expired ones.
 * @param {Map} cache - Card cache
 * @param {string} id - Item id
 * @param {number} now - Current time in milliseconds
 * @returns {object|null} Fresh cache entry
 */
const readFreshCacheEntry = (cache, id, now) => {
  const entry = cache.get(id);
  if (!entry) return null;
  if (entry.expiresAt <= now) {
    cache.delete(id);
    return null;
  }
  return entry;
};
