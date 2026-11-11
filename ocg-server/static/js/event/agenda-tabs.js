import {
  closestElement,
  getElementById,
  initializeMatchingRoots,
  initializeOnReadyAndHtmxLoad,
  markDatasetReady,
} from "/static/js/common/dom.js";
import { getNextLoopedIndex } from "/static/js/common/keyboard.js";

const AGENDA_TABS_READY_KEY = "agendaTabsReady";
const AGENDA_TABS_SELECTOR = "[data-agenda-tabs]";
const TAB_SELECTOR = '[role="tab"]';

/**
 * Initializes the agenda day tabs on event pages.
 * @param {Document|Element} root Root element containing agenda tabs
 * @param {object} [context] Initialization context
 * @param {boolean} [context.historyRestore] Whether the root came from the HTMX history cache
 */
export const initializeAgendaTabs = (root = document, { historyRestore = false } = {}) => {
  initializeMatchingRoots(root, AGENDA_TABS_SELECTOR, (tablist) => {
    // Rebind restored snapshots, whose ready marker survives without listeners.
    if (historyRestore) {
      delete tablist.dataset[AGENDA_TABS_READY_KEY];
    }
    if (!markDatasetReady(tablist, AGENDA_TABS_READY_KEY)) {
      return;
    }

    // Select the clicked day.
    tablist.addEventListener("click", (event) => {
      const tab = closestElement(event.target, TAB_SELECTOR);
      if (tab && tablist.contains(tab)) {
        selectAgendaDay(tab);
      }
    });

    // Move the selection and focus with the arrow, Home and End keys.
    tablist.addEventListener("keydown", (event) => {
      const tab = closestElement(event.target, TAB_SELECTOR);
      if (!tab || !tablist.contains(tab)) {
        return;
      }

      const tabs = Array.from(tablist.querySelectorAll(TAB_SELECTOR));
      const targetIndex = getKeyTargetIndex(event, tabs.indexOf(tab), tabs.length);
      if (targetIndex === null) {
        return;
      }

      event.preventDefault();
      selectAgendaDay(tabs[targetIndex], { focus: true });
    });
  });
};

/**
 * Selects an agenda day tab and shows only its panel.
 * @param {HTMLElement} tab Day tab to select
 * @param {object} [options] Selection options
 * @param {boolean} [options.focus] Whether to move focus to the selected tab
 */
export const selectAgendaDay = (tab, { focus = false } = {}) => {
  const tablist = tab.closest(AGENDA_TABS_SELECTOR);
  if (!tablist) {
    return;
  }

  // Sync the selected state, roving tab stop and panel visibility of every tab.
  tablist.querySelectorAll(TAB_SELECTOR).forEach((dayTab) => {
    const selected = dayTab === tab;
    dayTab.setAttribute("aria-selected", String(selected));
    dayTab.dataset.active = String(selected);
    dayTab.tabIndex = selected ? 0 : -1;
    getElementById(document, dayTab.getAttribute("aria-controls"))?.toggleAttribute("hidden", !selected);
  });

  // Focus after the tab stop moves so the focus ring follows the selection.
  if (focus) {
    tab.focus();
  }
};

/**
 * Resolves the tab index an arrow, Home or End key moves to.
 * Modified keys are left to the browser (for example Alt+ArrowLeft goes back in history).
 * @param {KeyboardEvent} event Keydown event
 * @param {number} index Index of the tab that received the key
 * @param {number} count Number of tabs
 * @returns {number|null} Target index, or null when the key does not apply
 */
const getKeyTargetIndex = (event, index, count) => {
  if (event.altKey || event.ctrlKey || event.metaKey || index === -1) {
    return null;
  }

  switch (event.key) {
    case "ArrowRight":
      return getNextLoopedIndex(index, count, 1);
    case "ArrowLeft":
      return getNextLoopedIndex(index, count, -1);
    case "Home":
      return 0;
    case "End":
      return count - 1;
    default:
      return null;
  }
};

initializeOnReadyAndHtmxLoad(initializeAgendaTabs);
