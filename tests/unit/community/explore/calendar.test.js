import { expect } from "@open-wc/testing";

import { Calendar } from "/static/js/community/explore/calendar.js";
import { resetDom } from "/tests/unit/test-utils/dom.js";
import { mockFetch } from "/tests/unit/test-utils/network.js";

describe("community explore calendar", () => {
  const originalFullCalendar = globalThis.FullCalendar;
  const originalReplaceState = window.history.replaceState.bind(window.history);
  let fetchMock;
  let replaceStateCalls;

  beforeEach(() => {
    resetDom();
    Calendar._instance = null;
    fetchMock = mockFetch();
    replaceStateCalls = [];
    document.head.querySelectorAll('script[src*="fullcalendar"]').forEach((node) => node.remove());
    document.body.innerHTML = `
      <div id="main-loading-calendar" class="hidden"></div>
      <div id="loading-calendar" class="hidden"></div>
      <div>
        <div id="calendar-box"></div>
        <div class="no-results-default hidden"></div>
        <div class="no-results-filtered hidden"></div>
      </div>
      <div id="calendar-date"></div>
      <form id="events-form">
        <input name="date_from" value="" />
        <input name="date_to" value="" />
      </form>
      <input name="ts_query" value="" />
    `;
    history.replaceState({}, "", "/explore");
    window.history.replaceState = (...args) => {
      replaceStateCalls.push(args);
      return originalReplaceState(...args);
    };

    globalThis.FullCalendar = {
      Calendar: class {
        constructor(element, config) {
          this.element = element;
          this.config = config;
          this.currentData = { viewTitle: "April 2026" };
          this.events = [];
          this.viewDate = new Date("2026-04-01T00:00:00Z");
        }

        render() {}
        getDate() {
          return this.viewDate;
        }
        removeAllEvents() {
          this.events = [];
        }
        addEventSource(events) {
          this.events = events.filter(Boolean);
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
    fetchMock.restore();
    window.history.replaceState = originalReplaceState;
    document.head.querySelectorAll('script[src*="fullcalendar"]').forEach((node) => node.remove());
    if (originalFullCalendar) {
      globalThis.FullCalendar = originalFullCalendar;
    } else {
      delete globalThis.FullCalendar;
    }
  });

  it("loads the calendar script, skips malformed events, and renders the valid ones", () => {
    const calendar = new Calendar({
      events: [
        {
          name: "Meetup",
          slug: "meetup",
          starts_at: 1712000000,
          ends_at: 1712003600,
          group_color: "#0094ff",
        },
        {
          name: "Broken event",
          slug: "broken-event",
          ends_at: 1712003600,
          group_color: "#0094ff",
        },
      ],
    });

    document.head.querySelector('script[src*="fullcalendar"]')?.onload();

    expect(calendar.fullCalendar.events).to.have.length(1);
    expect(calendar.fullCalendar.events[0]).to.include({
      title: "Meetup",
      className: "cursor-pointer opacity-40",
      borderColor: "#0094ff",
    });
    expect(calendar.fullCalendar.events[0].extendedProps.event.slug).to.equal("meetup");
    expect(document.getElementById("calendar-date").textContent).to.equal("April 2026");
    expect(document.getElementById("calendar-box")?.classList.contains("opacity-30")).to.equal(false);
    expect(document.querySelector(".no-results-default")?.classList.contains("hidden")).to.equal(true);
  });

  it("fetches month data, syncs date inputs and url, and shows the empty placeholder", async () => {
    fetchMock.setImpl(async () => ({
      ok: true,
      async json() {
        return { events: [] };
      },
    }));

    const calendar = new Calendar({ events: [] });
    document.head.querySelector('script[src*="fullcalendar"]')?.onload();

    await calendar.refresh();

    expect(fetchMock.calls).to.have.length(1);
    expect(fetchMock.calls[0][0]).to.include("/explore/events/search?");
    expect(fetchMock.calls[0][0]).to.include("view_mode=calendar");
    expect(fetchMock.calls[0][0]).to.include("date_from=2026-04-01");
    expect(fetchMock.calls[0][0]).to.include("date_to=2026-04-30");
    expect(document.querySelector('input[name="date_from"]')?.value).to.equal("2026-04-01");
    expect(document.querySelector('input[name="date_to"]')?.value).to.equal("2026-04-30");
    expect(window.location.search).to.include("view_mode=calendar");
    expect(window.location.search).to.include("date_from=2026-04-01");
    expect(window.location.search).to.include("date_to=2026-04-30");
    expect(replaceStateCalls).to.have.length.greaterThan(0);
    expect(document.getElementById("calendar-box")?.classList.contains("opacity-30")).to.equal(true);
    expect(document.querySelector(".no-results-default")?.classList.contains("hidden")).to.equal(false);
  });
});
