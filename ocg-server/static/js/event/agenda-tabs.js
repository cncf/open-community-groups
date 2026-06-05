import { markDatasetReady } from "/static/js/common/dom.js";

const DAY_TAB_SELECTOR = "[data-day-tab]";
const DAY_PANEL_SELECTOR = "[data-day-content]";
const DAY_TAB_READY_KEY = "dayTabReady";

/**
 * Shows the agenda panel matching the selected day tab.
 * @param {HTMLElement} selectedTab - Selected day tab button
 * @param {NodeListOf<HTMLElement>} dayTabs - Day tab buttons
 * @param {NodeListOf<HTMLElement>} dayPanels - Day content panels
 */
const selectAgendaDay = (selectedTab, dayTabs, dayPanels) => {
  const target = selectedTab.getAttribute("data-day-tab");
  dayTabs.forEach((tab) => {
    tab.setAttribute("data-active", tab === selectedTab ? "true" : "false");
  });
  dayPanels.forEach((panel) => {
    const isTarget = panel.getAttribute("data-day-content") === target;
    panel.toggleAttribute("hidden", !isTarget);
  });
};

/**
 * Initializes agenda day tabs on event pages.
 * @param {Document|Element} root - Root element containing agenda tabs
 */
export const initializeAgendaTabs = (root = document) => {
  const dayTabs = root.querySelectorAll(DAY_TAB_SELECTOR);
  const dayPanels = root.querySelectorAll(DAY_PANEL_SELECTOR);
  if (dayTabs.length === 0 || dayPanels.length === 0) {
    return;
  }

  dayTabs.forEach((tab) => {
    if (!markDatasetReady(tab, DAY_TAB_READY_KEY)) {
      return;
    }

    tab.addEventListener("click", () => {
      selectAgendaDay(tab, dayTabs, dayPanels);
    });
  });
};

initializeAgendaTabs();
