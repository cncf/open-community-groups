import { expect } from "@open-wc/testing";

import { initializeAgendaTabs } from "/static/js/event/agenda-tabs.js";
import { resetDom } from "/tests/unit/test-utils/dom.js";

describe("event agenda tabs", () => {
  afterEach(() => {
    resetDom();
  });

  it("selects a day on click and syncs aria-selected, data-active, tabindex and panel hidden", () => {
    // Render three agenda days and initialize the tabs.
    renderAgendaTabs();
    initializeAgendaTabs();

    // Select the second day.
    getTab(1).click();

    // Only the second tab is selected and a tab stop, and only its panel is visible.
    expectSelectedDay(1);
  });

  it("moves selection and focus with ArrowRight/ArrowLeft (wrapping), Home and End", () => {
    // Render three agenda days, initialize the tabs and focus the first one.
    renderAgendaTabs();
    initializeAgendaTabs();
    getTab(0).focus();

    // Each key selects and focuses its target tab.
    const steps = [
      ["ArrowRight", 1],
      ["ArrowRight", 2],
      ["ArrowRight", 0],
      ["ArrowLeft", 2],
      ["Home", 0],
      ["End", 2],
    ];
    steps.forEach(([key, expectedIndex]) => {
      const event = pressKey(document.activeElement, key);
      expect(event.defaultPrevented, key).to.equal(true);
      expect(document.activeElement, key).to.equal(getTab(expectedIndex));
      expectSelectedDay(expectedIndex);
    });
  });

  it("ignores arrow keys with alt, ctrl or meta", () => {
    // Render three agenda days, initialize the tabs and focus the first one.
    renderAgendaTabs();
    initializeAgendaTabs();
    getTab(0).focus();

    // Modified arrow keys are left to the browser.
    ["altKey", "ctrlKey", "metaKey"].forEach((modifier) => {
      const event = pressKey(getTab(0), "ArrowRight", { [modifier]: true });
      expect(event.defaultPrevented, modifier).to.equal(false);
      expect(document.activeElement, modifier).to.equal(getTab(0));
      expectSelectedDay(0);
    });
  });

  it("binds once across repeated initialization", () => {
    // Render the agenda and record the listeners bound on the tablist.
    renderAgendaTabs();
    const tablist = document.querySelector("[data-agenda-tabs]");
    const boundTypes = [];
    const originalAddEventListener = tablist.addEventListener.bind(tablist);
    tablist.addEventListener = (type, listener, options) => {
      boundTypes.push(type);
      return originalAddEventListener(type, listener, options);
    };

    // Initialize from the document and from the tablist itself several times.
    initializeAgendaTabs();
    initializeAgendaTabs();
    initializeAgendaTabs(tablist);

    // Each delegated listener is bound only once.
    expect(boundTypes).to.deep.equal(["click", "keydown"]);
  });

  it("rebinds after an htmx history restore", () => {
    // Render a restored snapshot that kept the ready marker but lost its listeners.
    renderAgendaTabs({ selectedIndex: 1 });
    document.querySelector("[data-agenda-tabs]").dataset.agendaTabsReady = "true";

    // Restore the snapshot through htmx and select the first day.
    document.body.dispatchEvent(new CustomEvent("htmx:historyRestore", { bubbles: true }));
    getTab(0).click();

    // The restored tabs respond again.
    expectSelectedDay(0);
  });
});

/**
 * Asserts that only the given day tab is selected and only its panel is visible.
 * @param {number} selectedIndex Index of the expected selected day
 */
const expectSelectedDay = (selectedIndex) => {
  document.querySelectorAll('[role="tab"]').forEach((tab, index) => {
    const selected = index === selectedIndex;
    expect(tab.getAttribute("aria-selected"), tab.id).to.equal(String(selected));
    expect(tab.dataset.active, tab.id).to.equal(String(selected));
    expect(tab.tabIndex, tab.id).to.equal(selected ? 0 : -1);
  });
  document.querySelectorAll('[role="tabpanel"]').forEach((panel, index) => {
    expect(panel.hidden, panel.id).to.equal(index !== selectedIndex);
  });
};

/**
 * Returns the agenda day tab at the given index.
 * @param {number} index Day index
 * @returns {HTMLElement} Day tab
 */
const getTab = (index) => document.getElementById(`agenda-tab-${index}`);

/**
 * Dispatches a keydown event on a target.
 * @param {Element} target Event target
 * @param {string} key Key name
 * @param {KeyboardEventInit} [init] Extra event fields
 * @returns {KeyboardEvent} Dispatched event
 */
const pressKey = (target, key, init = {}) => {
  const event = new KeyboardEvent("keydown", { bubbles: true, cancelable: true, key, ...init });
  target.dispatchEvent(event);
  return event;
};

/**
 * Renders a three-day agenda tablist with panels linked by ids.
 * @param {object} [options] Fixture options
 * @param {number} [options.selectedIndex] Index of the initially selected day
 */
const renderAgendaTabs = ({ selectedIndex = 0 } = {}) => {
  const days = [0, 1, 2];
  const tabs = days
    .map((index) => {
      const selected = index === selectedIndex;
      return `
        <button type="button" role="tab" id="agenda-tab-${index}"
                aria-controls="agenda-panel-${index}" aria-selected="${selected}"
                tabindex="${selected ? 0 : -1}" data-day-tab data-active="${selected}">
          Day ${index + 1}
        </button>
      `;
    })
    .join("");
  const panels = days
    .map(
      (index) => `
        <div role="tabpanel" id="agenda-panel-${index}" aria-labelledby="agenda-tab-${index}"
             tabindex="0" data-agenda-day ${index === selectedIndex ? "" : "hidden"}>
          Sessions of day ${index + 1}
        </div>
      `,
    )
    .join("");
  document.body.innerHTML = `
    <div role="tablist" aria-label="Agenda days" data-agenda-tabs>${tabs}</div>
    ${panels}
  `;
};
