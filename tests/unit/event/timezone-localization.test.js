import { expect } from "@open-wc/testing";

import {
  applyUserTimezoneToEventTimes,
  buildLocalizedTimeLabel,
} from "/static/js/event/timezone-localization.js";
import { resetDom } from "/tests/unit/test-utils/dom.js";

describe("event timezone localization", () => {
  afterEach(() => {
    resetDom();
  });

  it("renders a localized label when user and event timezones differ", () => {
    document.body.innerHTML = `
      <button
        id="user-dropdown-button"
        data-logged-in="true"
        data-user-timezone="America/Los_Angeles"
      ></button>
      <div
        data-localized-time
        data-starts-at="2030-07-14T23:00:00Z"
        data-ends-at="2030-07-15T00:00:00Z"
        data-event-timezone="America/New_York"
        class="hidden"
      ></div>
    `;

    const updated = applyUserTimezoneToEventTimes();
    const localized = document.querySelector("[data-localized-time]");

    expect(updated).to.equal(1);
    expect(localized.classList.contains("hidden")).to.equal(false);
    expect(localized.textContent).to.match(/^\(Your time:/);
  });

  it("keeps labels hidden when the user timezone matches the event timezone", () => {
    document.body.innerHTML = `
      <button
        id="user-dropdown-button"
        data-logged-in="true"
        data-user-timezone="UTC"
      ></button>
      <div
        data-localized-time
        data-starts-at="2030-07-14T23:00:00Z"
        data-event-timezone="UTC"
        class="hidden"
      >old</div>
    `;

    const updated = applyUserTimezoneToEventTimes();
    const localized = document.querySelector("[data-localized-time]");

    expect(updated).to.equal(0);
    expect(localized.classList.contains("hidden")).to.equal(true);
    expect(localized.textContent).to.equal("");
  });

  it("builds a single-time label when no end time is provided", () => {
    const start = new Date("2030-07-14T23:00:00Z");
    const label = buildLocalizedTimeLabel({
      start,
      timezone: "America/Los_Angeles",
    });

    expect(label.startsWith("Your time: ")).to.equal(true);
    expect(label.includes(" - ")).to.equal(false);
  });
});
