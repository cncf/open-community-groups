import { expect } from "@open-wc/testing";

import { Calendar } from "/static/js/alliance/explore/calendar.js";
import {
  fetchData,
  updateResults,
  updateResultsFromSummary,
} from "/static/js/alliance/explore/explore.js";
import { Map as ExploreMap } from "/static/js/alliance/explore/map.js";
import {
  initializeExploreWidgets,
  syncNoResultsPlaceholders,
} from "/static/js/alliance/explore/page-controls.js";
import { waitForMicrotask } from "/tests/unit/test-utils/async.js";
import { resetDom } from "/tests/unit/test-utils/dom.js";
import { mockHtmx, mockSwal } from "/tests/unit/test-utils/globals.js";
import { mockFetch } from "/tests/unit/test-utils/network.js";

describe("explore helpers", () => {
  const originalFullCalendar = globalThis.FullCalendar;
  const originalLeaflet = globalThis.L;
  const originalWindowLeaflet = globalThis.window.L;
  let fetchMock;
  let htmx;
  let swal;

  beforeEach(() => {
    resetDom();
    htmx = mockHtmx();
    swal = mockSwal();
    fetchMock = mockFetch();
  });

  afterEach(() => {
    resetDom();
    Calendar._instance = null;
    ExploreMap._instance = null;
    fetchMock.restore();
    htmx.restore();
    swal.restore();
    if (originalFullCalendar) {
      globalThis.FullCalendar = originalFullCalendar;
    } else {
      delete globalThis.FullCalendar;
    }
    if (originalLeaflet) {
      globalThis.L = originalLeaflet;
    } else {
      delete globalThis.L;
    }
    if (originalWindowLeaflet) {
      globalThis.window.L = originalWindowLeaflet;
    } else {
      delete globalThis.window.L;
    }
  });

  it("updates the results container text", () => {
    // Build the DOM fixture with results.
    document.body.innerHTML = `<div id="results"></div>`;

    // Replace the results markup with the fetched response.
    updateResults("<p>Updated</p>");

    // The results container receives text, not trusted markup.
    expect(document.getElementById("results")?.textContent).to.equal("<p>Updated</p>");
    expect(document.getElementById("results")?.innerHTML).to.equal(
      "&lt;p&gt;Updated&lt;/p&gt;",
    );
  });

  it("updates the results container from a declarative summary marker", () => {
    // Build the DOM fixture with results and swapped summary content.
    document.body.innerHTML = `
      <div id="results"></div>
      <div id="cards-list">
        <span data-results-summary class="hidden">1-10 of 20</span>
      </div>
    `;

    // Read the summary marker from the swapped content.
    updateResultsFromSummary(document.getElementById("cards-list"));

    // The results container receives the summary marker text.
    expect(document.getElementById("results")?.textContent).to.equal("1-10 of 20");
  });

  it("updates the results container after an HTMX swap", () => {
    // Build the DOM fixture with results and swapped summary content.
    document.body.innerHTML = `
      <div id="results"></div>
      <div id="cards-list">
        <span data-results-summary class="hidden">11-20 of 20</span>
      </div>
    `;

    // Dispatch the HTMX swap event from the swapped content root.
    document.getElementById("cards-list").dispatchEvent(
      new CustomEvent("htmx:afterSwap", { bubbles: true }),
    );

    // The initialized explore module syncs the summary after swaps.
    expect(document.getElementById("results")?.textContent).to.equal("11-20 of 20");
  });

  it("shows the default no-results placeholder without active filters", () => {
    // Build the DOM fixture with an empty results state and inactive filters.
    document.body.innerHTML = `
      <div id="explore-filters">
        <form id="events-form" class="filters-form"></form>
      </div>
      <div id="cards-list">
        <div class="no-results-default hidden"></div>
        <div class="no-results-filtered hidden"></div>
      </div>
    `;

    // Sync the empty state with the current filters.
    syncNoResultsPlaceholders(document.getElementById("cards-list"));

    // The default placeholder is shown when the empty state is unfiltered.
    expect(document.querySelector(".no-results-default")?.classList.contains("hidden")).to.equal(
      false,
    );
    expect(document.querySelector(".no-results-filtered")?.classList.contains("hidden")).to.equal(
      true,
    );
  });

  it("shows the filtered no-results placeholder with active filters", () => {
    // Build the DOM fixture with an empty results state and active search.
    document.body.innerHTML = `
      <div id="explore-filters">
        <form id="events-form" class="filters-form"></form>
      </div>
      <input name="ts_query" value="conference" />
      <div id="cards-list">
        <div class="no-results-default hidden"></div>
        <div class="no-results-filtered hidden"></div>
      </div>
    `;

    // Sync the empty state with the current filters.
    syncNoResultsPlaceholders(document.getElementById("cards-list"));

    // The filtered placeholder is shown when the empty state has active filters.
    expect(document.querySelector(".no-results-default")?.classList.contains("hidden")).to.equal(
      true,
    );
    expect(document.querySelector(".no-results-filtered")?.classList.contains("hidden")).to.equal(
      false,
    );
  });

  it("leaves calendar no-results placeholders hidden for the calendar renderer", () => {
    // Build the calendar results fixture with inactive filters and hidden placeholders.
    document.body.innerHTML = `
      <div id="explore-filters">
        <form id="events-form" class="filters-form"></form>
      </div>
      <div id="calendar-results">
        <div id="calendar-box"></div>
        <div class="no-results-default hidden"></div>
        <div class="no-results-filtered hidden"></div>
      </div>
    `;

    // Sync the swapped results root before FullCalendar has finished rendering.
    syncNoResultsPlaceholders(document.getElementById("calendar-results"));

    // Calendar placeholders remain owned by the async calendar renderer.
    expect(document.querySelector(".no-results-default")?.classList.contains("hidden")).to.equal(
      true,
    );
    expect(document.querySelector(".no-results-filtered")?.classList.contains("hidden")).to.equal(
      true,
    );
  });

  it("initializes calendar widgets from declarative payloads", async () => {
    let calendarApi;

    // Mock FullCalendar so the declarative initializer can create a calendar.
    globalThis.FullCalendar = {
      Calendar: class {
        constructor(element) {
          this.element = element;
          this.currentData = { viewTitle: "April 2026" };
          this.events = [];
          this.todayCalls = 0;
          this.nextCalls = 0;
          this.previousCalls = 0;
          this.viewDate = new Date("2026-04-01T00:00:00Z");
          calendarApi = this;
        }

        // Render is a no-op because the test inspects the captured API directly.
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
        today() {
          this.todayCalls += 1;
        }
        next() {
          this.nextCalls += 1;
        }
        prev() {
          this.previousCalls += 1;
        }
      },
    };
    document.body.innerHTML = `
      <div id="main-loading-calendar" class="hidden"></div>
      <div id="loading-calendar" class="hidden"></div>
      <div>
        <div id="calendar-box"></div>
        <div class="no-results-default hidden"></div>
        <div class="no-results-filtered hidden"></div>
      </div>
      <div id="calendar-date"></div>
      <form id="events-form" class="filters-form">
        <input name="date_from" value="2026-04-01" />
        <input name="date_to" value="2026-04-30" />
      </form>
      <input name="ts_query" value="" />
      <button id="current-month-btn"></button>
      <button id="prev-month-btn"></button>
      <button id="next-month-btn"></button>
      <script type="application/json" data-explore-calendar-data>
        { "events": [{ "name": "Meetup", "slug": "meetup", "starts_at": 1712000000 }] }
      </script>
    `;

    // Initialize the calendar from the JSON marker and use delegated controls.
    await initializeExploreWidgets(document);
    await waitForMicrotask();
    document.getElementById("current-month-btn").click();
    document.getElementById("prev-month-btn").click();
    document.getElementById("next-month-btn").click();

    // The payload initializes the calendar and the buttons call its public API.
    expect(calendarApi.events).to.have.length(1);
    expect(calendarApi.todayCalls).to.equal(1);
    expect(calendarApi.previousCalls).to.equal(1);
    expect(calendarApi.nextCalls).to.equal(1);
  });

  it("initializes map widgets from declarative payloads", async () => {
    let loadHandler;
    const markerAdds = [];
    const addedLayers = [];
    const leafletMock = {
      Browser: { retina: false },
      latLng(lat, lng) {
        return { lat, lng };
      },
      latLngBounds(sw, ne) {
        return { sw, ne };
      },
      map() {
        return {
          on(name, handler) {
            if (name === "load") {
              loadHandler = handler;
            }
          },
          addLayer(layer) {
            addedLayers.push(layer);
          },
          off() {},
          remove() {},
          invalidateSize() {},
          setView() {},
          getBounds() {
            return {
              _southWest: { lat: 1, lng: 2 },
              _northEast: { lat: 3, lng: 4 },
            };
          },
          flyToBounds() {},
        };
      },
      control: {
        zoom() {
          return { addTo() {} };
        },
      },
      tileLayer() {
        return { addTo() {} };
      },
      markerClusterGroup() {
        return {
          addLayer(layer) {
            markerAdds.push(layer);
          },
        };
      },
      divIcon(config) {
        return config;
      },
      marker(latLng, config) {
        return {
          latLng,
          config,
          on() {},
          bindTooltip() {},
          openTooltip() {},
          getTooltip() {
            return null;
          },
        };
      },
    };
    globalThis.L = leafletMock;
    globalThis.window.L = leafletMock;
    document.body.innerHTML = `
      <div id="main-loading-map" class="hidden"></div>
      <div id="loading-map" class="hidden"></div>
      <div id="map-box"></div>
      <script type="application/json" data-explore-map-data data-entity="groups">
        {
          "groups": [
            {
              "slug": "malaga-js",
              "alliance_name": "spain",
              "latitude": 36.7213,
              "longitude": -4.4214
            }
          ],
          "bbox": { "sw_lat": 1, "sw_lon": 2, "ne_lat": 3, "ne_lon": 4 }
        }
      </script>
    `;

    // Initialize the map from the JSON marker and trigger the first load.
    await initializeExploreWidgets(document);
    await waitForMicrotask();
    await waitForMicrotask();
    loadHandler();

    // The map receives the declarative payload and adds valid markers.
    expect(ExploreMap._instance.entity).to.equal("groups");
    expect(markerAdds).to.have.length(1);
    expect(addedLayers).to.have.length(1);
  });

  it("delegates search and clear actions to the active explore form", () => {
    // Build the DOM fixture with an explore form and search controls.
    document.body.innerHTML = `
      <div id="explore-filters">
        <form id="events-form" class="filters-form"></form>
      </div>
      <input id="ts_query" value="cloud native" />
      <button id="search-btn"></button>
      <button id="clean-search"></button>
    `;

    // Click the delegated search and clear controls.
    document.getElementById("search-btn").click();
    document.getElementById("clean-search").click();

    // The active form is triggered and the search input is cleared.
    expect(document.getElementById("ts_query")?.value).to.equal("");
    expect(htmx.triggerCalls).to.deep.equal([
      [document.getElementById("events-form"), "change"],
      [document.getElementById("events-form"), "change"],
    ]);
  });

  it("delegates sort changes and syncs event sort inputs", () => {
    // Build the DOM fixture with event sort controls.
    document.body.innerHTML = `
      <div id="explore-filters">
        <form id="events-form" class="filters-form"></form>
      </div>
      <input id="sort_by" value="date" />
      <input id="sort_direction" value="asc" />
      <select id="sort_selector">
        <option value="date-desc" selected>Date descending</option>
      </select>
    `;

    // Change the delegated sort selector.
    document.getElementById("sort_selector").dispatchEvent(new Event("change", { bubbles: true }));

    // The hidden sort inputs are synced before the form is triggered.
    expect(document.getElementById("sort_by")?.value).to.equal("date");
    expect(document.getElementById("sort_direction")?.value).to.equal("desc");
    expect(htmx.triggerCalls).to.deep.equal([[document.getElementById("events-form"), "change"]]);
  });

  it("delegates view mode changes and resets kind filters", () => {
    // Build the DOM fixture with view mode and kind controls.
    document.body.innerHTML = `
      <div id="explore-filters">
        <form id="events-form" class="filters-form">
          <input type="checkbox" name="kind[]" checked />
        </form>
      </div>
      <input type="hidden" name="date_from" value="2026-01-01" />
      <input type="hidden" name="date_to" value="2026-01-31" />
      <input type="radio" name="view_mode" value="map" checked />
    `;

    // Change the delegated view mode selector.
    document
      .querySelector('input[name="view_mode"]')
      .dispatchEvent(new Event("change", { bubbles: true }));

    // View mode changes clear kind and date filters before triggering the form.
    expect(document.querySelector('input[name="kind[]"]')?.checked).to.equal(false);
    expect(document.querySelector('input[name="date_from"]')?.value).to.equal("");
    expect(document.querySelector('input[name="date_to"]')?.value).to.equal("");
    expect(htmx.triggerCalls).to.deep.equal([[document.getElementById("events-form"), "change"]]);
  });

  it("delegates mobile filter drawer actions", () => {
    // Build the DOM fixture with mobile drawer controls.
    document.body.innerHTML = `
      <button id="open-filters"></button>
      <button id="close-filters"></button>
      <div id="drawer-filters" class="-translate-x-full"></div>
      <div id="drawer-backdrop" class="hidden"></div>
    `;

    // Open and close the mobile filters drawer through delegated clicks.
    document.getElementById("open-filters").click();
    expect(document.getElementById("drawer-filters")?.classList.contains("-translate-x-full")).to.equal(false);
    expect(document.getElementById("drawer-backdrop")?.classList.contains("hidden")).to.equal(false);
    document.getElementById("close-filters").click();

    // The drawer and backdrop return to the hidden state.
    expect(document.getElementById("drawer-filters")?.classList.contains("-translate-x-full")).to.equal(true);
    expect(document.getElementById("drawer-backdrop")?.classList.contains("hidden")).to.equal(true);
  });

  it("fetches explore data as json", async () => {
    // Mock the fetch response.
    fetchMock.setImpl(async (url, options) => {
      // The request asks the search endpoint for JSON.
      expect(url).to.equal("/explore/events/search?kind=conference");
      expect(options.headers).to.be.instanceOf(Headers);
      expect(options.headers.get("Accept")).to.equal("application/json");
      expect(options.headers.get("X-OCG-Fetch")).to.equal("true");

      // Return the value used by the assertion.
      return {
        ok: true,
        json: async () => ({ items: [1, 2, 3] }),
      };
    });

    // Capture the async result.
    const result = await fetchData("events", "kind=conference");

    // The parsed JSON response is returned without showing an alert.
    expect(result).to.deep.equal({ items: [1, 2, 3] });
    expect(swal.calls).to.have.length(0);
  });

  it("shows an alert and throws when the request fails", async () => {
    // Mock the fetch response.
    fetchMock.setImpl(async () => {
      throw new Error("network error");
    });

    // Set up thrown error.
    let thrownError = null;

    // Run the fetch call that should throw.
    try {
      await fetchData("groups", "region=emea");
    } catch (error) {
      thrownError = error;
    }

    // The original network error is surfaced and the fallback alert is shown.
    expect(thrownError?.message).to.equal("network error");
    expect(swal.calls).to.have.length(1);
    expect(swal.calls[0].text).to.equal(
      "Something went wrong loading results. Please try again later.",
    );
  });

  it("shows an alert and throws when the server responds with an error", async () => {
    // Mock the fetch response.
    fetchMock.setImpl(async () => ({
      ok: false,
      status: 500,
      text: async () => "Internal error",
    }));

    // Set up thrown error.
    let thrownError = null;

    // Run the fetch call that should reject the error response.
    try {
      await fetchData("groups", "region=emea");
    } catch (error) {
      thrownError = error;
    }

    // The error response is reported with the status code and fallback alert.
    expect(thrownError?.message).to.equal(
      "Failed to fetch groups data (status 500)",
    );
    expect(swal.calls).to.have.length(1);
    expect(swal.calls[0].text).to.equal(
      "Something went wrong loading results. Please try again later.",
    );
  });

  it("shows an alert and throws when the response body is not valid json", async () => {
    // Mock the fetch response.
    fetchMock.setImpl(async () => ({
      ok: true,
      json: async () => {
        throw new Error("invalid json");
      },
    }));

    // Set up thrown error.
    let thrownError = null;

    // Run the fetch call that should reject invalid JSON.
    try {
      await fetchData("events", "kind=conference");
    } catch (error) {
      thrownError = error;
    }

    // The JSON parsing error is surfaced with the fallback alert.
    expect(thrownError?.message).to.equal("invalid json");
    expect(swal.calls).to.have.length(1);
    expect(swal.calls[0].text).to.equal(
      "Something went wrong loading results. Please try again later.",
    );
  });
});
