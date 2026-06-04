import { expect } from "@open-wc/testing";

import { initializeAgendaTabs } from "/static/js/event/agenda-tabs.js";
import { resetDom } from "/tests/unit/test-utils/dom.js";

describe("event agenda tabs", () => {
  afterEach(() => {
    resetDom();
  });

  it("switches the active agenda day", () => {
    // Build the DOM fixture with two agenda days.
    document.body.innerHTML = `
      <button type="button" data-day-tab="day-0" data-active="true"></button>
      <button type="button" data-day-tab="day-1" data-active="false"></button>
      <div data-day-content="day-0"></div>
      <div data-day-content="day-1" hidden></div>
    `;

    // Initialize the tabs and select the second day.
    initializeAgendaTabs();
    document.querySelector('[data-day-tab="day-1"]').click();

    // The selected tab is active and only its panel is visible.
    expect(document.querySelector('[data-day-tab="day-0"]')?.dataset.active).to.equal("false");
    expect(document.querySelector('[data-day-tab="day-1"]')?.dataset.active).to.equal("true");
    expect(document.querySelector('[data-day-content="day-0"]')?.hasAttribute("hidden")).to.equal(
      true,
    );
    expect(document.querySelector('[data-day-content="day-1"]')?.hasAttribute("hidden")).to.equal(
      false,
    );
  });
});
