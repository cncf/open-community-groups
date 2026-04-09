import { expect } from "@open-wc/testing";

import { Calendar } from "/static/js/community/explore/calendar.js";
import { resetDom } from "/tests/unit/test-utils/dom.js";

describe("community explore calendar", () => {
  const originalFullCalendar = globalThis.FullCalendar;

  beforeEach(() => {
    resetDom();
    Calendar._instance = null;
    document.body.innerHTML = `
      <div id="main-loading-calendar" class="hidden"></div>
      <div>
        <div id="calendar-box"></div>
        <div class="no-results-default hidden"></div>
        <div class="no-results-filtered hidden"></div>
      </div>
      <div id="calendar-date"></div>
    `;

    globalThis.FullCalendar = {
      Calendar: class {
        constructor(element) {
          this.element = element;
          this.currentData = { viewTitle: "April 2026" };
          this.events = [];
        }

        render() {}
        getDate() {
          return new Date("2026-04-01T00:00:00Z");
        }
        removeAllEvents() {
          this.events = [];
        }
        addEventSource(events) {
          this.events = events;
        }
        today() {}
        next() {}
        prev() {}
      },
    };
  });

  afterEach(() => {
    resetDom();
    Calendar._instance = null;
    if (originalFullCalendar) {
      globalThis.FullCalendar = originalFullCalendar;
    } else {
      delete globalThis.FullCalendar;
    }
  });

  it("loads the calendar script and renders initial events", () => {
    const calendar = new Calendar({
      events: [
        {
          name: "Meetup",
          slug: "meetup",
          starts_at: 1712000000,
          ends_at: 1712003600,
          group_color: "#0094ff",
        },
      ],
    });

    document.head.querySelector('script[src*="fullcalendar"]')?.onload();

    expect(calendar.fullCalendar.events).to.have.length(1);
    expect(document.getElementById("calendar-date").textContent).to.equal("April 2026");
  });
});
