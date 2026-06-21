import { getElementById, setElementHidden } from "/static/js/common/dom.js";
import { clearTimeoutId, replaceTimeout } from "/static/js/common/timers.js";

const POPOVER_OPEN_DELAY_MS = 300;

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
    return `/${item.alliance_name}/group/${item.group_slug_pretty || item.group_slug}/event/${item.slug}`;
  }

  if (entity === "groups") {
    return `/${item.alliance_name}/group/${item.slug_pretty || item.slug}`;
  }

  return undefined;
};

/**
 * Wraps popover content in the shared explore popover card shell.
 * @param {string} popoverHtml - Server-rendered popover content
 * @returns {string} Popover card shell HTML
 */
export const renderPopoverCardShell = (popoverHtml) =>
  `<div class="explore-popover-card-shell">${popoverHtml}</div>`;

/**
 * Schedules a delayed popover open for a hovered element, replacing pending ones.
 * @param {WeakMap} timers - Per-element popover timers
 * @param {object} key - Hovered element or marker that owns the timer
 * @param {() => void} callback - Popover open callback
 */
export const scheduleDelayedPopover = (timers, key, callback) => {
  timers.set(key, replaceTimeout(timers.get(key), callback, POPOVER_OPEN_DELAY_MS));
};

/**
 * Cancels a pending delayed popover for an element.
 * @param {WeakMap} timers - Per-element popover timers
 * @param {object} key - Hovered element or marker that owns the timer
 */
export const cancelDelayedPopover = (timers, key) => {
  clearTimeoutId(timers.get(key));
  timers.delete(key);
};

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
