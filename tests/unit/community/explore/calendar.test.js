import { expect } from "@open-wc/testing";

import { Calendar } from "/static/js/community/explore/calendar.js";
import { createDeferred, waitForMicrotask } from "/tests/unit/test-utils/async.js";
import { resetDom } from "/tests/unit/test-utils/dom.js";
import { mockSwal } from "/tests/unit/test-utils/globals.js";
import { mockFetch } from "/tests/unit/test-utils/network.js";
import { mockWindowTimers } from "/tests/unit/test-utils/timers.js";

const EVENT = {
  community_name: "spain",
  ends_at: 1712003600,
  event_id: "event-1",
  group_slug: "malaga-js",
  group_slug_pretty: "malaga-javascript",
  name: "Meetup",
  slug: "meetup",
  starts_at: 1712000000,
};
const EVENT_URL = "/spain/group/malaga-javascript/event/meetup";
const RESULTS_ERROR_MESSAGE = "Something went wrong loading results. Please try again later.";

/** Builds a successful search or card response. */
const okResponse = ({ body = {}, html = "" } = {}) => ({
  ok: true,
  status: 200,
  json: async () => body,
  text: async () => html,
});

/** Builds an unsuccessful response with the given status. */
const statusResponse = (status) => ({
  ok: false,
  status,
  text: async () => "",
});

describe("community explore calendar", () => {
  const originalAnchorClick = HTMLAnchorElement.prototype.click;
  const originalFullCalendar = globalThis.FullCalendar;
  const originalHtmx = globalThis.htmx;
  const originalReplaceState = window.history.replaceState.bind(window.history);
  let calendarInstances;
  let clickedUrls;
  let fetchMock;
  let replaceStateCalls;
  let swal;
  let windowTimers;

  beforeEach(() => {
    resetDom();
    Calendar._instance = null;
    fetchMock = mockFetch({ impl: async () => statusResponse(404) });
    swal = mockSwal();
    calendarInstances = [];
    clickedUrls = [];
    replaceStateCalls = [];
    HTMLAnchorElement.prototype.click = function click() {
      clickedUrls.push(this.getAttribute("href"));
    };
    globalThis.htmx = { process() {} };
    document.head.querySelectorAll('script[src*="fullcalendar"]').forEach((node) => node.remove());
    document.body.innerHTML = `
      <div id="main-loading-calendar" class="hidden"></div>
      <div id="loading-calendar" class="hidden"></div>
      <p data-explore-truncation-notice class="hidden">
        Showing <span data-truncation-shown></span> of <span data-truncation-total></span>
      </p>
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

    // Mock FullCalendar so script loading creates an inspectable calendar instance.
    globalThis.FullCalendar = {
      Calendar: class {
        constructor(element, config) {
          this.element = element;
          this.config = config;
          this.currentData = { viewTitle: "April 2026" };
          this.destroyCalls = 0;
          this.events = [];
          this.viewDate = new Date("2026-04-01T00:00:00Z");
          calendarInstances.push(this);
        }

        // Render is a no-op because tests inspect the captured calendar state directly.
        render() {}
        destroy() {
          this.destroyCalls += 1;
        }
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
    Calendar._instance?.destroy();
    windowTimers?.restore();
    windowTimers = null;
    resetDom();
    Calendar._instance = null;
    fetchMock.restore();
    swal.restore();
    HTMLAnchorElement.prototype.click = originalAnchorClick;
    globalThis.htmx = originalHtmx;
    window.history.replaceState = originalReplaceState;
    document.head.querySelectorAll('script[src*="fullcalendar"]').forEach((node) => node.remove());
    if (originalFullCalendar) {
      globalThis.FullCalendar = originalFullCalendar;
    } else {
      delete globalThis.FullCalendar;
    }
  });

  const renderCalendar = async (data) => {
    const calendar = new Calendar(data);
    await waitForMicrotask();
    return calendar;
  };

  // Mounts one event segment the way FullCalendar does for each rendered segment.
  const mountEvent = (calendar, event = EVENT, { firstCol = 0, row = 0 } = {}) => {
    const harness = document.createElement("div");
    const element = document.createElement("a");
    element.href = EVENT_URL;
    element.textContent = event.name;
    element.fcSeg = { firstCol, row };
    harness.append(element);
    document.getElementById("calendar-box").append(harness);
    calendar.fullCalendar.config.eventDidMount({ el: element, event: { extendedProps: { event } } });
    return element;
  };

  // Queues each request so tests settle responses in any order.
  const mockQueuedFetch = () => {
    const responses = [];
    fetchMock.setImpl(() => {
      const response = createDeferred();
      responses.push(response);
      return response.promise;
    });
    return responses;
  };

  const getNotice = () => {
    const notice = document.querySelector("[data-explore-truncation-notice]");
    return {
      hidden: notice.classList.contains("hidden"),
      shown: notice.querySelector("[data-truncation-shown]").textContent,
      total: notice.querySelector("[data-truncation-total]").textContent,
    };
  };

  const getTooltip = (element) => element.parentElement.querySelector('[role="tooltip"]');

  it("loads the calendar script, skips malformed events, and renders the valid ones", async () => {
    // Create a calendar with past, upcoming, and malformed events.
    document.documentElement.style.setProperty("--color-primary-50", "#eff6ff");
    document.documentElement.style.setProperty("--color-primary-200", "#bfdbfe");
    const upcomingStartsAt = Math.floor(Date.now() / 1000) + 30 * 24 * 60 * 60;
    const calendar = await renderCalendar({
      events: [
        { ...EVENT, group_color: "#0094ff" },
        {
          ...EVENT,
          ends_at: upcomingStartsAt + 3600,
          event_id: "event-2",
          name: "Upcoming",
          slug: "upcoming",
          starts_at: upcomingStartsAt,
        },
        { ...EVENT, event_id: "event-3", name: "Broken event", starts_at: null },
      ],
      total: 3,
      truncated: false,
    });

    // Past events are dimmed with the default colors, ignoring any group color.
    const [pastEvent, upcomingEvent] = calendar.fullCalendar.events;
    expect(calendar.fullCalendar.events).to.have.length(2);
    expect(pastEvent).to.include({
      className: "cursor-pointer opacity-40",
      title: "Meetup",
      url: EVENT_URL,
    });
    expect(pastEvent).not.to.have.property("backgroundColor");
    expect(pastEvent).not.to.have.property("borderColor");
    expect(pastEvent.extendedProps.event.event_id).to.equal("event-1");

    // Upcoming events use the primary colors and link to their page.
    expect(upcomingEvent).to.include({
      backgroundColor: "#eff6ff",
      borderColor: "#bfdbfe",
      title: "Upcoming",
      url: "/spain/group/malaga-javascript/event/upcoming",
    });
    expect(upcomingEvent.className).not.to.include("opacity-40");

    // The rendered month shows its title without the empty state.
    expect(document.getElementById("calendar-date").textContent).to.equal("April 2026");
    expect(document.getElementById("calendar-box")?.classList.contains("opacity-30")).to.equal(false);
    expect(document.querySelector(".no-results-default")?.classList.contains("hidden")).to.equal(true);
    expect(getNotice().hidden).to.equal(true);
  });

  it("aligns event cards upward and to the right near the calendar edges", async () => {
    // Mount events on the last row and on the first cell.
    const calendar = await renderCalendar({ events: [] });
    windowTimers = mockWindowTimers();
    const edgeEvent = mountEvent(calendar, EVENT, { firstCol: 5, row: 4 });
    const firstCellEvent = mountEvent(calendar, EVENT);

    // Open both cards.
    edgeEvent.dispatchEvent(new MouseEvent("mouseenter"));
    firstCellEvent.dispatchEvent(new MouseEvent("mouseenter"));
    windowTimers.advance(300);

    // Edge cards open upward and right-aligned; others open downward.
    expect(getTooltip(edgeEvent).className).to.include("-translate-y-full");
    expect(getTooltip(edgeEvent).className).to.include("end-0");
    expect(getTooltip(firstCellEvent).className).to.include("pt-1.5");
    expect(getTooltip(firstCellEvent).className).not.to.include("end-0");
  });

  it("fetches the minimal month range, returns the envelope, and updates the notice", async () => {
    // Mock a truncated minimal response for the displayed month.
    const envelope = { events: [EVENT], total: 1500, truncated: true };
    fetchMock.setImpl(async () => okResponse({ body: envelope }));
    const calendar = await renderCalendar({ events: [] });

    // Fetching returns the whole envelope from the search endpoint.
    expect(await calendar.fetchEvents()).to.deep.equal(envelope);
    const url = new URL(fetchMock.calls[0][0], window.location.origin);
    expect(url.pathname).to.equal("/explore/events/search");
    expect(url.searchParams.get("view_mode")).to.equal("calendar");
    expect(url.searchParams.get("date_from")).to.equal("2026-04-01");
    expect(url.searchParams.get("date_to")).to.equal("2026-04-30");
    expect(fetchMock.calls[0][1].headers.get("Accept")).to.equal("application/json");

    // Refreshing draws the events and shows the notice counts.
    await calendar.refresh();
    expect(calendar.fullCalendar.events.map((event) => event.title)).to.deep.equal(["Meetup"]);
    expect(getNotice()).to.deep.equal({ hidden: false, shown: "1", total: "1500" });
    expect(calendar.state.status).to.equal("ready");
  });

  it("fetches month data, syncs date inputs and url, and shows the empty placeholder", async () => {
    // Mock the fetch response.
    fetchMock.setImpl(async () => okResponse({ body: { events: [], total: 0, truncated: false } }));

    // Create the calendar and finish loading the FullCalendar script.
    const calendar = await renderCalendar({ events: [] });

    // Refresh the calendar and verify the rendered events.
    await calendar.refresh();

    // Refreshing an empty month syncs inputs, URL, and placeholder.
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
    expect(calendar.state.status).to.equal("empty");
    expect(document.getElementById("loading-calendar")?.classList.contains("is-loading")).to.equal(false);
    expect(getNotice().hidden).to.equal(true);
  });

  it("clears loading and reports an error when month data cannot load", async () => {
    // Fail the month request of the live calendar.
    fetchMock.setImpl(async () => statusResponse(500));
    const calendar = await renderCalendar({ events: [] });

    // Refresh the calendar and verify the local state recovers from loading.
    await calendar.refresh();
    expect(calendar.state.status).to.equal("error");
    expect(document.getElementById("loading-calendar")?.classList.contains("is-loading")).to.equal(false);
    expect(swal.calls).to.have.length(1);
    expect(swal.calls[0].text).to.equal(RESULTS_ERROR_MESSAGE);
  });

  it("ignores stale month responses and errors", async () => {
    // Start two month requests.
    const calendar = await renderCalendar({ events: [] });
    const responses = mockQueuedFetch();
    const staleRefresh = calendar.refresh();
    const currentRefresh = calendar.refresh();
    expect(fetchMock.calls[0][1].signal.aborted).to.equal(true);
    expect(fetchMock.calls[1][1].signal.aborted).to.equal(false);

    // Answer the current request first, then the stale one.
    responses[1].resolve(okResponse({ body: { events: [EVENT], total: 1, truncated: false } }));
    await currentRefresh;
    responses[0].resolve(
      okResponse({ body: { events: [{ ...EVENT, name: "Stale" }], total: 2000, truncated: true } }),
    );
    await staleRefresh;
    expect(calendar.fullCalendar.events.map((event) => event.title)).to.deep.equal(["Meetup"]);
    expect(getNotice().hidden).to.equal(true);
    expect(calendar.state.status).to.equal("ready");

    // Fail a stale request while the current one is pending.
    const failedRefresh = calendar.refresh();
    const nextRefresh = calendar.refresh();
    responses[2].reject(new TypeError("Failed to fetch"));
    await failedRefresh;
    expect(calendar.state.status).to.equal("loading");
    expect(swal.calls).to.have.length(0);

    // The current request completes normally.
    responses[3].resolve(okResponse({ body: { events: [], total: 0, truncated: false } }));
    await nextRefresh;
    expect(calendar.state.status).to.equal("empty");
    expect(swal.calls).to.have.length(0);
  });

  it("applies nothing from a pending request after the calendar view is left", async () => {
    // Start a month request and a card waiting to open.
    const calendar = await renderCalendar({ events: [] });
    const fullCalendar = calendar.fullCalendar;
    windowTimers = mockWindowTimers();
    const responses = mockQueuedFetch();
    const pendingRefresh = calendar.refresh();
    const signal = fetchMock.calls[0][1].signal;
    const eventElement = mountEvent(calendar);
    eventElement.dispatchEvent(new MouseEvent("mouseenter"));
    expect(windowTimers.pendingCount).to.equal(1);

    // Leaving the view releases the calendar, request, timers, and spinner.
    calendar.destroy();
    expect(fullCalendar.destroyCalls).to.equal(1);
    expect(calendar.fullCalendar).to.equal(null);
    expect(signal.aborted).to.equal(true);
    expect(windowTimers.pendingCount).to.equal(0);
    expect(document.getElementById("loading-calendar").classList.contains("is-loading")).to.equal(false);

    // The late response changes nothing.
    responses[0].resolve(okResponse({ body: { events: [EVENT], total: 2000, truncated: true } }));
    await pendingRefresh;
    expect(fullCalendar.events).to.deep.equal([]);
    expect(getNotice().hidden).to.equal(true);
    expect(swal.calls).to.have.length(0);

    // Released listeners ignore later cleanup and card events.
    document
      .getElementById("calendar-box")
      .dispatchEvent(new CustomEvent("htmx:beforeCleanupElement", { bubbles: true }));
    eventElement.dispatchEvent(new MouseEvent("mouseenter"));
    windowTimers.advance(300);
    expect(fullCalendar.destroyCalls).to.equal(1);
    expect(fetchMock.calls).to.have.length(2);
    expect(getTooltip(eventElement)).to.equal(null);
  });

  it("applies nothing from a pending request after its container is removed", async () => {
    // Start a month request.
    const calendar = await renderCalendar({ events: [] });
    const fullCalendar = calendar.fullCalendar;
    const responses = mockQueuedFetch();
    const pendingRefresh = calendar.refresh();

    // Remove the container without HTMX cleanup or an explicit destroy.
    document.getElementById("calendar-box").remove();

    // The late response changes nothing.
    responses[0].resolve(okResponse({ body: { events: [EVENT], total: 2000, truncated: true } }));
    await pendingRefresh;
    expect(fullCalendar.events).to.deep.equal([]);
    expect(getNotice().hidden).to.equal(true);

    // A late failure raises no alert.
    const failedRefresh = calendar.refresh();
    responses[1].reject(new TypeError("Failed to fetch"));
    await failedRefresh;
    expect(swal.calls).to.have.length(0);
  });

  it("destroys the calendar on HTMX cleanup of its container while a request is pending", async () => {
    // Start a month request.
    const calendar = await renderCalendar({ events: [] });
    const fullCalendar = calendar.fullCalendar;
    const responses = mockQueuedFetch();
    const pendingRefresh = calendar.refresh();

    // Cleanup of an element inside the calendar keeps it alive.
    const child = document.createElement("span");
    document.getElementById("calendar-box").append(child);
    child.dispatchEvent(new CustomEvent("htmx:beforeCleanupElement", { bubbles: true }));
    expect(fullCalendar.destroyCalls).to.equal(0);

    // Cleanup of the calendar container destroys it.
    document
      .getElementById("calendar-box")
      .dispatchEvent(new CustomEvent("htmx:beforeCleanupElement", { bubbles: true }));
    expect(fullCalendar.destroyCalls).to.equal(1);
    expect(fetchMock.calls[0][1].signal.aborted).to.equal(true);

    // The late failure raises no alert.
    responses[0].reject(new TypeError("Failed to fetch"));
    await pendingRefresh;
    expect(swal.calls).to.have.length(0);
    expect(document.getElementById("loading-calendar").classList.contains("is-loading")).to.equal(false);
  });

  it("destroys the previous calendar when it initializes again", async () => {
    // Initialize the calendar for a second calendar view.
    const calendar = await renderCalendar({ events: [] });
    const reused = await renderCalendar({ events: [EVENT] });

    // The controller is reused and only the latest FullCalendar instance is live.
    expect(reused).to.equal(calendar);
    expect(calendarInstances).to.have.length(2);
    expect(calendarInstances[0].destroyCalls).to.equal(1);
    expect(calendarInstances[1].destroyCalls).to.equal(0);
    expect(calendar.fullCalendar).to.equal(calendarInstances[1]);
    expect(calendar.fullCalendar.events).to.have.length(1);
  });

  it("sets up only the latest initialization once scripts load", async () => {
    // Initialize twice before the scripts resolve.
    const calendar = new Calendar({ events: [{ ...EVENT, name: "First" }] });
    new Calendar({ events: [{ ...EVENT, name: "Second" }] });
    await waitForMicrotask();
    expect(calendarInstances).to.have.length(1);
    expect(calendar.fullCalendar.events.map((event) => event.title)).to.deep.equal(["Second"]);

    // Leaving the view before the scripts resolve skips the setup.
    calendar.initialize({ events: [EVENT] });
    calendar.destroy();
    await waitForMicrotask();
    expect(calendarInstances).to.have.length(1);
    expect(calendar.fullCalendar).to.equal(null);
  });

  it("loads event cards on hover and focus and dismisses them with Escape", async () => {
    // Hold the card response of a mounted event.
    const calendar = await renderCalendar({ events: [] });
    windowTimers = mockWindowTimers();
    const card = createDeferred();
    fetchMock.setImpl(() => card.promise);
    const eventElement = mountEvent(calendar);

    // Hovering requests the calendar card right away and opens it after the delay.
    eventElement.dispatchEvent(new MouseEvent("mouseenter"));
    expect(fetchMock.calls.map(([url]) => url)).to.deep.equal([
      "/explore/events/event-1/card?view_mode=calendar",
    ]);
    windowTimers.advance(299);
    expect(getTooltip(eventElement)).to.equal(null);
    windowTimers.advance(1);

    // The loading tooltip is open and describes the event.
    const tooltip = getTooltip(eventElement);
    expect(tooltip.id).to.equal("explore-calendar-card-event-1-1");
    expect(tooltip.hasAttribute("data-open")).to.equal(true);
    expect(tooltip.getAttribute("aria-busy")).to.equal("true");
    expect(tooltip.textContent).to.include("Loading details…");
    expect(eventElement.getAttribute("aria-describedby")).to.equal(tooltip.id);

    // The loaded card replaces the loading state without focusable links.
    card.resolve(okResponse({ html: `<a href="${EVENT_URL}"><article>Meetup card</article></a>` }));
    await waitForMicrotask();
    expect(tooltip.getAttribute("aria-busy")).to.equal("false");
    expect(tooltip.querySelector("a[href]")).to.equal(null);
    expect(tooltip.textContent).to.include("Meetup card");

    // Leaving the event closes the card after the grace delay.
    eventElement.dispatchEvent(new MouseEvent("mouseleave"));
    windowTimers.advance(100);
    expect(getTooltip(eventElement)).to.equal(null);
    expect(eventElement.hasAttribute("aria-describedby")).to.equal(false);

    // Focus reopens the cached card, and Escape dismisses it while keeping focus.
    eventElement.focus();
    windowTimers.advance(300);
    expect(getTooltip(eventElement).textContent).to.include("Meetup card");
    expect(fetchMock.calls).to.have.length(1);
    eventElement.dispatchEvent(new KeyboardEvent("keydown", { bubbles: true, key: "Escape" }));
    expect(getTooltip(eventElement)).to.equal(null);
    expect(eventElement.hasAttribute("aria-describedby")).to.equal(false);
    expect(document.activeElement).to.equal(eventElement);
  });

  it("shows the fallback card, stays open while hovered, and forwards tooltip clicks", async () => {
    // Mount an event whose card no longer exists.
    const calendar = await renderCalendar({ events: [] });
    windowTimers = mockWindowTimers();
    const eventElement = mountEvent(calendar);
    eventElement.dispatchEvent(new MouseEvent("mouseenter"));
    await waitForMicrotask();
    windowTimers.advance(300);

    // The fallback card names the event.
    const tooltip = getTooltip(eventElement);
    expect(tooltip.getAttribute("aria-busy")).to.equal("false");
    expect(tooltip.textContent).to.include("Meetup");
    expect(tooltip.textContent).to.include("Details are not available right now.");
    expect(swal.calls).to.have.length(0);

    // Hovering the tooltip keeps it open after the pointer leaves the event.
    eventElement.dispatchEvent(new MouseEvent("mouseleave"));
    tooltip.dispatchEvent(new MouseEvent("mouseenter"));
    windowTimers.advance(500);
    expect(getTooltip(eventElement)).to.equal(tooltip);

    // Clicking the tooltip follows the event link.
    tooltip.querySelector("p").dispatchEvent(new MouseEvent("click", { bubbles: true, cancelable: true }));
    expect(clickedUrls).to.deep.equal([EVENT_URL]);
  });

  it("keeps the cards of two mounts of the same event independent", async () => {
    // Mount the same event twice, as multi-week events and the more-events popover do.
    const calendar = await renderCalendar({ events: [] });
    windowTimers = mockWindowTimers();
    fetchMock.setImpl(async () => okResponse({ html: "<article>Meetup card</article>" }));
    const firstMount = mountEvent(calendar);
    const secondMount = mountEvent(calendar);
    firstMount.dispatchEvent(new MouseEvent("mouseenter"));
    secondMount.dispatchEvent(new MouseEvent("mouseenter"));
    await waitForMicrotask();
    windowTimers.advance(300);

    // Each mount has its own tooltip id and description, sharing one request.
    const firstTooltip = getTooltip(firstMount);
    const secondTooltip = getTooltip(secondMount);
    expect(firstTooltip.id).to.equal("explore-calendar-card-event-1-1");
    expect(secondTooltip.id).to.equal("explore-calendar-card-event-1-2");
    expect(firstMount.getAttribute("aria-describedby")).to.equal(firstTooltip.id);
    expect(secondMount.getAttribute("aria-describedby")).to.equal(secondTooltip.id);
    expect(fetchMock.calls).to.have.length(1);

    // Unmounting one segment releases only its card.
    calendar.fullCalendar.config.eventWillUnmount({ el: firstMount });
    expect(firstTooltip.isConnected).to.equal(false);
    expect(firstMount.hasAttribute("aria-describedby")).to.equal(false);
    expect(secondTooltip.isConnected).to.equal(true);
    expect(secondMount.getAttribute("aria-describedby")).to.equal(secondTooltip.id);

    // The unmounted segment no longer opens a card.
    firstMount.dispatchEvent(new MouseEvent("mouseleave"));
    firstMount.dispatchEvent(new MouseEvent("mouseenter"));
    windowTimers.advance(300);
    expect(getTooltip(firstMount)).to.equal(null);
  });

  it("navigates plain event clicks through HTMX and leaves other clicks to the browser", async () => {
    // Create the calendar and capture its click handler.
    const calendar = await renderCalendar({ events: [EVENT] });
    const { eventClick } = calendar.fullCalendar.config;
    const url = calendar.fullCalendar.events[0].url;
    const click = (init) => {
      const jsEvent = new MouseEvent("click", { button: 0, cancelable: true, ...init });
      eventClick({ event: { url }, jsEvent });
      return jsEvent;
    };

    // A plain left click navigates in place.
    expect(click().defaultPrevented).to.equal(true);
    expect(clickedUrls).to.deep.equal([EVENT_URL]);

    // Modified and middle clicks keep the browser behavior.
    [{ ctrlKey: true }, { metaKey: true }, { shiftKey: true }, { altKey: true }, { button: 1 }].forEach(
      (init) => {
        expect(click(init).defaultPrevented).to.equal(false);
      },
    );
    expect(clickedUrls).to.have.length(1);

    // Events without a url are not handled.
    const jsEvent = new MouseEvent("click", { button: 0, cancelable: true });
    eventClick({ event: { url: null }, jsEvent });
    expect(jsEvent.defaultPrevented).to.equal(false);
    expect(clickedUrls).to.have.length(1);
  });
});
