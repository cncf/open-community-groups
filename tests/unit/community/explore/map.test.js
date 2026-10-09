import { expect } from "@open-wc/testing";

import { Map as ExploreMap } from "/static/js/community/explore/map.js";
import {
  createDeferred,
  waitForMicrotask,
} from "/tests/unit/test-utils/async.js";
import { resetDom } from "/tests/unit/test-utils/dom.js";
import { mockSwal } from "/tests/unit/test-utils/globals.js";
import { mockMapLibre } from "/tests/unit/test-utils/maps.js";
import { mockFetch } from "/tests/unit/test-utils/network.js";
import { mockWindowTimers } from "/tests/unit/test-utils/timers.js";

const GROUP = {
  group_id: "group-1",
  slug: "malaga-js",
  slug_pretty: "malaga-javascript",
  name: "Málaga JavaScript",
  community_name: "spain",
  latitude: 36.7213,
  longitude: -4.4214,
};
const SECOND_GROUP = {
  ...GROUP,
  group_id: "group-2",
  name: "Málaga Web",
  slug: "malaga-web",
  slug_pretty: "malaga-web",
};
const EVENT = {
  ...GROUP,
  event_id: "event-1",
  group_slug: GROUP.slug,
  group_slug_pretty: GROUP.slug_pretty,
  name: "Open Source Day",
  slug: "open-source-day",
};
const RESULTS_ERROR_MESSAGE =
  "Something went wrong loading results. Please try again later.";

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

describe("community explore map", () => {
  const originalAnchorClick = HTMLAnchorElement.prototype.click;
  const originalHtmx = globalThis.htmx;
  let clickedUrls;
  let fetchMock;
  let mapLibre;
  let swal;
  let windowTimers;

  beforeEach(() => {
    // Create the map fixture and mock browser integrations.
    resetDom();
    ExploreMap._instance = null;
    mapLibre = mockMapLibre();
    swal = mockSwal();
    fetchMock = mockFetch({ impl: async () => statusResponse(404) });
    clickedUrls = [];
    HTMLAnchorElement.prototype.click = function click() {
      clickedUrls.push(this.getAttribute("href"));
    };
    globalThis.htmx = { process() {} };
    document.body.innerHTML = `
      <div id="main-loading-map" class="hidden"></div>
      <div id="loading-map"></div>
      <p data-explore-truncation-notice class="hidden">
        Showing <span data-truncation-shown></span> of
        <span data-truncation-total></span>
      </p>
      <div id="map-box"></div>
    `;
  });

  afterEach(() => {
    // Release map resources and restore the browser globals.
    mapLibre.restore();
    swal.restore();
    fetchMock.restore();
    windowTimers?.restore();
    windowTimers = null;
    ExploreMap._instance = null;
    HTMLAnchorElement.prototype.click = originalAnchorClick;
    globalThis.htmx = originalHtmx;
    document.head
      .querySelector('script[src*="maplibre-gl.v5.24.0.min.js"]')
      ?.remove();
    resetDom();
  });

  const initializeMap = async (
    entity = "groups",
    data = { groups: [GROUP] },
  ) => {
    const controller = new ExploreMap(entity, data);
    await waitForMicrotask();
    await controller.setupPromise;
    const map = mapLibre.maps.at(-1);
    map.emit("load").emit("render");
    return { controller, map, source: map.getSource("explore-locations") };
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

  it("loads only MapLibre and configures Bright with attribution and zoom controls at the top", async () => {
    // Resolve the requested vendor script before initializing the map.
    delete globalThis.maplibregl;
    const controller = new ExploreMap("groups", { groups: [] });
    const script = document.head.querySelector(
      'script[src*="maplibre-gl.v5.24.0.min.js"]',
    );
    expect(script).not.to.equal(null);
    globalThis.maplibregl = mapLibre.api;
    script.onload();
    await waitForMicrotask();
    await controller.setupPromise;

    // Verify the map style, controls, and clustered source.
    const map = mapLibre.maps[0];
    map.emit("load").emit("render");
    expect(map.options.style).to.equal(
      "https://tiles.openfreemap.org/styles/bright",
    );
    expect(map.options.minZoom).to.equal(2);
    expect(map.controls.map((control) => control.position)).to.deep.equal([
      "top-right",
      "top-right",
    ]);
    expect(map.getSource("explore-locations").cluster).to.equal(true);
    expect(map.getSource("explore-locations").maxzoom).to.be.greaterThan(
      map.getSource("explore-locations").clusterMaxZoom,
    );
    expect(
      document.getElementById("main-loading-map").classList.contains("hidden"),
    ).to.equal(true);
  });

  it("sets the result bounds before the map loads without a later camera jump", async () => {
    // Create the map with bounds already supplied by the explore response.
    const controller = new ExploreMap("groups", {
      groups: [GROUP],
      bbox: { sw_lat: 1, sw_lon: 2, ne_lat: 3, ne_lon: 4 },
    });
    await waitForMicrotask();
    await controller.setupPromise;
    const map = mapLibre.maps[0];

    // Configure the first view before the style and result markers load.
    expect(map.options.bounds).to.deep.equal([
      [2, 1],
      [4, 3],
    ]);
    expect(map.fitBoundsCalls).to.deep.equal([]);
    expect(map.getSource("explore-locations")).not.to.exist;

    // Loading the results must not reposition the camera a second time.
    map.emit("load").emit("render");
    expect(map.fitBoundsCalls).to.deep.equal([]);
    expect(document.querySelector(".marker-malaga-js")).not.to.equal(null);
  });

  it("filters invalid locations, sets longitude-first bounds, and navigates through linked pins", async () => {
    // Initialize valid locations, including zero and boundary coordinates.
    const withoutLatitude = { ...GROUP, slug: "missing-latitude" };
    delete withoutLatitude.latitude;
    const { controller, map, source } = await initializeMap("groups", {
      groups: [
        GROUP,
        { ...GROUP, slug: "zero-latitude", latitude: 0 },
        { ...GROUP, slug: "zero-longitude", latitude: 51.4779, longitude: 0 },
        { ...GROUP, slug: "null-island", latitude: 0, longitude: 0 },
        { ...GROUP, slug: "world-corner", latitude: -90, longitude: 180 },
        withoutLatitude,
        { ...GROUP, slug: "null-coordinates", latitude: null, longitude: null },
        { ...GROUP, slug: "empty-latitude", latitude: "" },
        { ...GROUP, slug: "invalid-longitude", longitude: "invalid" },
        { ...GROUP, slug: "infinite-latitude", latitude: Infinity },
        { ...GROUP, slug: "latitude-out-of-range", latitude: 90.5 },
        { ...GROUP, slug: "longitude-out-of-range", longitude: -180.5 },
      ],
      bbox: { sw_lat: 1, sw_lon: 2, ne_lat: 3, ne_lon: 4 },
    });

    // Verify only present, finite, in-range locations are drawn.
    expect(
      source.data.features.map((feature) => feature.geometry.coordinates),
    ).to.deep.equal([
      [-4.4214, 36.7213],
      [-4.4214, 0],
      [0, 51.4779],
      [0, 0],
      [180, -90],
    ]);
    expect(document.querySelector(".marker-zero-latitude")).not.to.equal(null);
    expect(document.querySelector(".marker-zero-longitude")).not.to.equal(null);
    expect(document.querySelector(".marker-missing-latitude")).to.equal(null);
    expect(map.options.bounds).to.deep.equal([
      [2, 1],
      [4, 3],
    ]);
    expect(controller.state.status).to.equal("ready");

    // Navigate through the accessible location pin.
    const pin = document.querySelector(".marker-malaga-js");
    expect(pin.getAttribute("role")).to.equal("link");
    expect(pin.getAttribute("aria-label")).to.equal("Málaga JavaScript");
    pin.dispatchEvent(
      new MouseEvent("click", { bubbles: true, cancelable: true }),
    );
    expect(clickedUrls).to.deep.equal(["/spain/group/malaga-javascript"]);
  });

  it("builds event links and ignores invalid bounding boxes", async () => {
    // Initialize an event with a degenerate bounding box.
    const { map } = await initializeMap("events", {
      events: [
        {
          ...GROUP,
          slug: "open-source-day",
          group_slug: GROUP.slug,
          group_slug_pretty: GROUP.slug_pretty,
        },
      ],
      bbox: { sw_lat: 5, sw_lon: 5, ne_lat: 5, ne_lon: 5 },
    });

    // Verify the event destination without moving to invalid bounds.
    expect(map.options.bounds).not.to.exist;
    expect(map.fitBoundsCalls).to.deep.equal([]);
    document
      .querySelector(".marker-open-source-day")
      .dispatchEvent(
        new MouseEvent("click", { bubbles: true, cancelable: true }),
      );
    expect(clickedUrls).to.deep.equal([
      "/spain/group/malaga-javascript/event/open-source-day",
    ]);
  });

  it("uses public map bounds and preserves the eastern world edge in requests", async () => {
    // Set bounds that exceed the server's accepted coordinate ranges.
    const { controller, map } = await initializeMap();
    map.bounds.getSouthWest = () => ({ lat: -100, lng: -200 });
    map.bounds.getNorthEast = () => ({ lat: 100, lng: 200 });
    const fetchMock = mockFetch({
      response: { ok: true, json: async () => ({ groups: [] }) },
    });
    try {
      // Fetch minimal locations and verify normalized request coordinates.
      const abortController = new AbortController();
      await controller.fetchLocationData(abortController.signal);
      const url = new URL(fetchMock.calls[0][0], window.location.origin);
      expect(url.pathname).to.equal("/explore/groups/search");
      expect(fetchMock.calls[0][1].headers.get("Accept")).to.equal(
        "application/json",
      );
      expect(fetchMock.calls[0][1].signal).to.equal(abortController.signal);
      expect(url.searchParams.get("bbox_sw_lat")).to.equal("-90");
      expect(url.searchParams.get("bbox_sw_lon")).to.equal("-180");
      expect(url.searchParams.get("bbox_ne_lat")).to.equal("90");
      expect(url.searchParams.get("bbox_ne_lon")).to.equal("180");
    } finally {
      // Restore the request implementation.
      fetchMock.restore();
    }
  });

  it("requests viewport locations in map mode", async () => {
    // Start from a URL carrying list view pagination.
    const { controller } = await initializeMap();
    const originalUrl = window.location.href;
    window.history.replaceState(
      null,
      "",
      "?entity=groups&view_mode=list&offset=20",
    );
    const fetchMock = mockFetch({
      response: { ok: true, json: async () => ({ groups: [] }) },
    });
    try {
      // Fetch locations and verify the server receives map mode.
      await controller.fetchLocationData();
      const url = new URL(fetchMock.calls[0][0], window.location.origin);
      expect(url.searchParams.getAll("view_mode")).to.deep.equal(["map"]);
      expect(url.searchParams.get("entity")).to.equal("groups");
    } finally {
      // Restore the request implementation and page URL.
      fetchMock.restore();
      window.history.replaceState(null, "", originalUrl);
    }
  });

  it("deduplicates cluster markers and zooms into their locations", async () => {
    // Render duplicate source features for one cluster.
    const { controller, map, source } = await initializeMap();
    const feature = {
      type: "Feature",
      geometry: { type: "Point", coordinates: [-4.42, 36.72] },
      properties: {
        cluster: true,
        cluster_id: 12,
        point_count: 2,
        point_count_abbreviated: 2,
        revision: controller.dataRevision,
      },
    };
    map.sourceFeatures = [feature, feature];
    map.emit("render");
    expect(document.querySelectorAll(".map-cluster")).to.have.length(1);
    expect(document.querySelector(".marker-malaga-js")).to.equal(null);
    const cluster = document.querySelector(".map-cluster");
    expect(cluster.getAttribute("aria-label")).to.equal("Show 2 locations");

    // Ignore repeated activation while expansion is pending.
    source.getClusterExpansionZoom = async () => 12;
    cluster.focus();
    cluster.click();
    cluster.click();
    await waitForMicrotask();
    expect(map.easeToCalls).to.deep.equal([
      { center: [-4.42, 36.72], zoom: 12 },
    ]);
    expect(cluster.disabled).to.equal(false);

    // Keep keyboard focus within the map after the cluster separates.
    map.sourceFeatures = source.data.features;
    map.emit("render");
    expect(cluster.isConnected).to.equal(false);
    expect(document.activeElement).to.equal(map.getCanvas());
  });

  it("lists maximum-zoom locations and restores focus after popup dismissal", async () => {
    // Initialize two groups that share the same location.
    const secondGroup = {
      ...GROUP,
      name: "Málaga Web",
      slug: "malaga-web",
      slug_pretty: "malaga-web",
    };
    const { controller, map, source } = await initializeMap("groups", {
      groups: [GROUP, secondGroup],
    });
    map.sourceFeatures = [
      {
        type: "Feature",
        geometry: { type: "Point", coordinates: [-4.4214, 36.7213] },
        properties: {
          cluster: true,
          cluster_id: 12,
          point_count: 2,
          point_count_abbreviated: 2,
          revision: controller.dataRevision,
        },
      },
    ];
    source.getClusterExpansionZoom = async () => 20;

    // Zoom to the limit before showing the location list.
    map.emit("render");
    document.querySelector(".map-cluster").click();
    await waitForMicrotask();
    expect(map.easeToCalls).to.deep.equal([
      { center: [-4.4214, 36.7213], zoom: 19 },
    ]);
    expect(document.querySelector(".maplibregl-popup")).to.equal(null);

    // Open the list from its focused cluster trigger.
    const cluster = document.querySelector(".map-cluster");
    cluster.focus();
    cluster.click();
    await waitForMicrotask();

    const links = [...document.querySelectorAll(".maplibregl-popup a")];
    expect(links.map((link) => link.textContent)).to.deep.equal([
      "Málaga JavaScript",
      "Málaga Web",
    ]);
    expect(links.map((link) => link.getAttribute("href"))).to.deep.equal([
      "/spain/group/malaga-javascript",
      "/spain/group/malaga-web",
    ]);
    expect(map.easeToCalls).to.have.length(1);
    expect(document.activeElement).to.equal(links[0]);

    // Dismiss with Escape and return focus to the cluster.
    links[0].dispatchEvent(
      new KeyboardEvent("keydown", { key: "Escape", bubbles: true }),
    );
    expect(document.querySelector(".maplibregl-popup")).to.equal(null);
    expect(controller.clusterPopup).to.equal(null);
    expect(document.activeElement).to.equal(cluster);

    // Restore trigger focus when the popup closes through another path.
    cluster.click();
    await waitForMicrotask();
    controller.clusterPopup.remove();
    expect(document.activeElement).to.equal(cluster);
  });

  it("loads pin cards on focus into a described, non-interactive tooltip", async () => {
    // Hold the card response while the focused pin waits to open its card.
    const { map } = await initializeMap();
    windowTimers = mockWindowTimers();
    const card = createDeferred();
    fetchMock.setImpl(() => card.promise);
    const pin = document.querySelector(".marker-malaga-js");

    // Focus starts the card request before the open delay ends.
    pin.focus();
    expect(fetchMock.calls).to.have.length(1);
    expect(fetchMock.calls[0][0]).to.equal("/explore/groups/group-1/card");
    expect(fetchMock.calls[0][1].headers.get("Accept")).to.equal("text/html");
    windowTimers.advance(299);
    expect(document.querySelector(".explore-map-tooltip")).to.equal(null);

    // The delayed tooltip shows a busy loading state described by the pin.
    windowTimers.advance(1);
    const tooltip = document.querySelector(".explore-map-tooltip");
    expect(tooltip.parentElement).to.equal(map.getContainer());
    expect(tooltip.getAttribute("role")).to.equal("tooltip");
    expect(tooltip.getAttribute("aria-busy")).to.equal("true");
    expect(pin.getAttribute("aria-describedby")).to.equal(tooltip.id);
    expect(tooltip.textContent).to.include("Málaga JavaScript");
    expect(tooltip.textContent).to.include("Loading details…");

    // The loaded card replaces the loading state without focusable links.
    card.resolve(
      okResponse({
        html: '<a href="/spain/group/malaga-javascript"><article>Málaga JavaScript card</article></a>',
      }),
    );
    await waitForMicrotask();
    expect(tooltip.getAttribute("aria-busy")).to.equal("false");
    expect(tooltip.querySelector("a[href]")).to.equal(null);
    expect(tooltip.textContent).to.equal("Málaga JavaScript card");
    expect(document.activeElement).to.equal(pin);

    // Dismiss the description without moving focus away from its pin.
    pin.dispatchEvent(
      new KeyboardEvent("keydown", { key: "Escape", bubbles: true }),
    );
    expect(document.querySelector(".explore-map-tooltip")).to.equal(null);
    expect(pin.hasAttribute("aria-describedby")).to.equal(false);
    expect(document.activeElement).to.equal(pin);
  });

  it("loads event cards on hover, falls back when missing, and forwards tooltip clicks", async () => {
    // Render an event pin whose card no longer exists.
    await initializeMap("events", { events: [EVENT] });
    windowTimers = mockWindowTimers();
    fetchMock.setImpl(async () => statusResponse(404));
    const pin = document.querySelector(".marker-open-source-day");

    // Hovering the pin requests the map card of the event.
    pin.dispatchEvent(new MouseEvent("mouseenter"));
    expect(fetchMock.calls.map(([url]) => url)).to.deep.equal([
      "/explore/events/event-1/card?view_mode=map",
    ]);
    await waitForMicrotask();
    windowTimers.advance(300);

    // The fallback card names the event and is no longer busy.
    const tooltip = document.querySelector(".explore-map-tooltip");
    expect(tooltip.getAttribute("aria-busy")).to.equal("false");
    expect(tooltip.textContent).to.include("Open Source Day");
    expect(tooltip.textContent).to.include(
      "Details are not available right now.",
    );
    expect(swal.calls).to.have.length(0);

    // Hovering the tooltip keeps it open after the pointer leaves the pin.
    pin.dispatchEvent(new MouseEvent("mouseleave"));
    tooltip.dispatchEvent(new MouseEvent("mouseenter"));
    windowTimers.advance(500);
    expect(document.querySelector(".explore-map-tooltip")).to.equal(tooltip);

    // Clicking the tooltip follows the pin link.
    tooltip
      .querySelector("p")
      .dispatchEvent(
        new MouseEvent("click", { bubbles: true, cancelable: true }),
      );
    expect(clickedUrls).to.deep.equal([
      "/spain/group/malaga-javascript/event/open-source-day",
    ]);

    // Leaving the tooltip closes it after the grace delay.
    tooltip.dispatchEvent(new MouseEvent("mouseleave"));
    windowTimers.advance(100);
    expect(document.querySelector(".explore-map-tooltip")).to.equal(null);
    expect(pin.hasAttribute("aria-describedby")).to.equal(false);

    // Hovering again reuses the cached fallback card.
    pin.dispatchEvent(new MouseEvent("mouseenter"));
    windowTimers.advance(300);
    expect(fetchMock.calls).to.have.length(1);
    expect(document.querySelector(".explore-map-tooltip")).not.to.equal(null);
  });

  it("destroys card controllers when markers are cleaned up", async () => {
    // Open one pin card and leave another pending.
    const { map } = await initializeMap("groups", {
      groups: [GROUP, SECOND_GROUP],
    });
    windowTimers = mockWindowTimers();
    fetchMock.setImpl(() => new Promise(() => {}));
    document
      .querySelector(".marker-malaga-js")
      .dispatchEvent(new MouseEvent("mouseenter"));
    windowTimers.advance(300);
    document
      .querySelector(".marker-malaga-web")
      .dispatchEvent(new MouseEvent("mouseenter"));
    expect(document.querySelector(".explore-map-tooltip")).not.to.equal(null);
    expect(windowTimers.pendingCount).to.equal(1);

    // Remove the map through HTMX cleanup.
    document
      .getElementById("map-box")
      .dispatchEvent(
        new CustomEvent("htmx:beforeCleanupElement", { bubbles: true }),
      );

    // Cards, pending timers, and markers are released.
    expect(map.removed).to.equal(true);
    expect(windowTimers.pendingCount).to.equal(0);
    expect(document.querySelector(".explore-map-tooltip")).to.equal(null);
    expect(document.querySelector(".maplibregl-marker")).to.equal(null);
    windowTimers.advance(300);
    expect(document.querySelector(".explore-map-tooltip")).to.equal(null);
  });

  it("applies only the latest viewport response", async () => {
    // Start two viewport requests.
    const { controller, map, source } = await initializeMap();
    const responses = mockQueuedFetch();
    const firstRefresh = controller.refresh();
    const secondRefresh = controller.refresh();

    // The newer request aborts the older one.
    expect(fetchMock.calls).to.have.length(2);
    expect(fetchMock.calls[0][0]).to.match(/^\/explore\/groups\/search\?/);
    expect(fetchMock.calls[0][1].signal.aborted).to.equal(true);
    expect(fetchMock.calls[1][1].signal.aborted).to.equal(false);

    // Answer the newer request first, then the older one.
    responses[1].resolve(
      okResponse({ body: { groups: [SECOND_GROUP], total: 1 } }),
    );
    await secondRefresh;
    map.emit("render");
    responses[0].resolve(
      okResponse({ body: { groups: [GROUP, SECOND_GROUP], total: 2 } }),
    );
    await firstRefresh;
    map.emit("render");

    // Only the newer locations are drawn.
    expect(source.data.features).to.have.length(1);
    expect(document.querySelector(".marker-malaga-web")).not.to.equal(null);
    expect(document.querySelector(".marker-malaga-js")).to.equal(null);
    expect(controller.state.status).to.equal("ready");
    expect(swal.calls).to.have.length(0);
  });

  it("ignores stale network, http, and json failures", async () => {
    const { controller, map, source } = await initializeMap();
    const responses = mockQueuedFetch();
    const failures = [
      (response) => response.reject(new TypeError("Failed to fetch")),
      (response) => response.resolve(statusResponse(500)),
      (response) =>
        response.resolve({
          ok: true,
          status: 200,
          json: async () => {
            throw new SyntaxError("Unexpected token");
          },
        }),
    ];

    for (const fail of failures) {
      // Fail a replaced request while the newer one is still pending.
      const staleRefresh = controller.refresh();
      const currentRefresh = controller.refresh();
      const revision = controller.dataRevision;
      fail(responses.at(-2));
      await staleRefresh;
      expect(controller.state.status).to.equal("loading");
      expect(controller.dataRevision).to.equal(revision);

      // The newer request still completes normally.
      responses.at(-1).resolve(okResponse({ body: { groups: [GROUP] } }));
      await currentRefresh;
      map.emit("render");
      expect(controller.state.status).to.equal("ready");
      expect(source.data.features).to.have.length(1);
    }

    // No stale failure reached the user.
    expect(swal.calls).to.have.length(0);
  });

  it("reports failures of the current request once", async () => {
    // Fail the only pending viewport request.
    const { controller } = await initializeMap();
    fetchMock.setImpl(async () => statusResponse(500));
    await controller.refresh();

    // The error state and one results alert are shown.
    expect(controller.state.status).to.equal("error");
    expect(swal.calls).to.have.length(1);
    expect(swal.calls[0].text).to.equal(RESULTS_ERROR_MESSAGE);
    expect(document.querySelector(".marker-malaga-js")).not.to.equal(null);
  });

  it("ignores responses and aborted requests after the map is removed", async () => {
    // Start two viewport requests that outlive the map.
    const { controller, map, source } = await initializeMap();
    const responses = mockQueuedFetch();
    const refresh = controller.refresh();
    const signal = fetchMock.calls[0][1].signal;
    const data = source.data;

    // Removing the map aborts the pending request.
    document.getElementById("map-box").remove();
    await waitForMicrotask();
    expect(map.removed).to.equal(true);
    expect(signal.aborted).to.equal(true);

    // The aborted request settles without alerts or source updates.
    responses[0].reject(new DOMException("Aborted", "AbortError"));
    await refresh;
    expect(source.data).to.equal(data);
    expect(swal.calls).to.have.length(0);
  });

  it("commits the truncation notice only after the source update completes", async () => {
    // Initialize a truncated result set.
    const { controller, map, source } = await initializeMap("groups", {
      groups: [GROUP],
      total: 1284,
      truncated: true,
    });
    expect(getNotice()).to.deep.equal({
      hidden: false,
      shown: "1",
      total: "1284",
    });

    // A pending source update keeps the previous notice.
    source.loaded = false;
    await controller.refresh({
      groups: [GROUP, SECOND_GROUP],
      total: 2,
      truncated: false,
    });
    map.emit("render");
    expect(getNotice()).to.deep.equal({
      hidden: false,
      shown: "1",
      total: "1284",
    });

    // The completed source update commits its notice.
    source.loaded = true;
    map.emit("render");
    expect(getNotice()).to.deep.equal({ hidden: true, shown: "2", total: "2" });

    // A failed source update keeps the previous notice.
    source.loaded = false;
    await controller.refresh({ groups: [GROUP], total: 5000, truncated: true });
    map.emit("error", { sourceId: "explore-locations" });
    source.loaded = true;
    map.emit("render");
    expect(getNotice()).to.deep.equal({ hidden: true, shown: "2", total: "2" });
    expect(controller.state.status).to.equal("error");
  });

  it("preserves focused locations across refreshes and falls back when they disappear", async () => {
    // Focus a pin while the next viewport response is pending.
    const { controller, map } = await initializeMap();
    let resolveRequest;
    controller.fetchLocationData = () =>
      new Promise((resolve) => {
        resolveRequest = resolve;
      });
    const pendingRefresh = controller.refresh();
    const originalPin = document.querySelector(".marker-malaga-js");
    originalPin.focus();
    resolveRequest({
      groups: [
        { ...GROUP, slug: "malaga-web", slug_pretty: "malaga-web" },
        GROUP,
      ],
    });
    await pendingRefresh;

    // Restore the same location even when its source index changes.
    expect(document.activeElement).to.equal(originalPin);
    map.emit("render");
    const replacementPin = document.querySelector(".marker-malaga-js");
    expect(replacementPin).not.to.equal(originalPin);
    expect(document.activeElement).to.equal(replacementPin);

    // Keep keyboard navigation within the map when the location disappears.
    await controller.refresh({ groups: [] });
    map.emit("render");
    expect(document.activeElement).to.equal(map.getCanvas());
  });

  it("does not restore marker focus after the user moves to another control", async () => {
    // Start replacing the focused location while another control is available.
    const { controller, map } = await initializeMap();
    const filter = document.createElement("button");
    filter.textContent = "Filter locations";
    document.body.append(filter);
    document.querySelector(".marker-malaga-js").focus();
    await controller.refresh({ groups: [GROUP] });

    // Honor the user's new focus when the source finishes rendering.
    filter.focus();
    map.emit("render");
    expect(document.activeElement).to.equal(filter);
  });

  it("keeps existing pins visible until replacement source data is ready", async () => {
    // Delay source processing while a viewport response replaces its locations.
    const { controller, map, source } = await initializeMap();
    const originalPin = document.querySelector(".marker-malaga-js");
    source.loaded = false;
    await controller.refresh({
      groups: [{ ...GROUP, slug: "malaga-web", slug_pretty: "malaga-web" }],
    });
    map.emit("render");

    // Preserve the current pins and loading state while the worker is pending.
    expect(document.querySelector(".marker-malaga-js")).to.equal(originalPin);
    expect(document.querySelector(".marker-malaga-web")).to.equal(null);
    expect(controller.state.status).to.equal("loading");

    // Replace the pins together when the new source finishes processing.
    source.loaded = true;
    map.emit("render");
    expect(document.querySelector(".marker-malaga-js")).to.equal(null);
    expect(document.querySelector(".marker-malaga-web")).not.to.equal(null);
    expect(controller.state.status).to.equal("ready");
  });

  it("prevents stale clusters from expanding while their replacement is pending", async () => {
    // Render a focused cluster whose source will be replaced.
    const { controller, map, source } = await initializeMap();
    map.sourceFeatures = [
      {
        geometry: { coordinates: [-4.42, 36.72] },
        properties: {
          cluster: true,
          cluster_id: 12,
          point_count: 2,
          point_count_abbreviated: 2,
          revision: controller.dataRevision,
        },
      },
    ];
    map.emit("render");
    const cluster = document.querySelector(".map-cluster");
    cluster.focus();

    // Keep the old cluster visible without allowing stale worker requests.
    source.loaded = false;
    await controller.refresh({ groups: [GROUP] });
    map.emit("render");
    cluster.click();
    expect(document.querySelector(".map-cluster")).to.equal(cluster);
    expect(cluster.disabled).to.equal(true);
    expect(document.activeElement).to.equal(map.getCanvas());
    expect(map.easeToCalls).to.deep.equal([]);

    // Expose the current locations when their source becomes ready.
    source.loaded = true;
    map.sourceFeatures = null;
    map.emit("render");
    expect(document.querySelector(".map-cluster")).to.equal(null);
    expect(document.querySelector(".marker-malaga-js")).not.to.equal(null);
  });

  it("keeps a newer request loading when an older source update finishes", async () => {
    // Start a new request before the preceding source update can render.
    const { controller, map, source } = await initializeMap();
    source.loaded = false;
    await controller.refresh({ groups: [GROUP] });
    let resolveRequest;
    controller.fetchLocationData = () =>
      new Promise((resolve) => {
        resolveRequest = resolve;
      });
    const pendingRefresh = controller.refresh();

    // The old source cannot end the newer request's loading state.
    source.loaded = true;
    map.emit("render");
    expect(controller.state.status).to.equal("loading");

    // End loading only after the newest response is ready to display.
    resolveRequest({ groups: [] });
    await pendingRefresh;
    map.emit("render");
    expect(controller.state.status).to.equal("empty");
    expect(document.querySelector(".maplibregl-marker")).to.equal(null);
  });

  it("retains existing pins when source processing fails and recovers on retry", async () => {
    // Fail source processing after receiving replacement locations.
    const { controller, map, source } = await initializeMap();
    const originalPin = document.querySelector(".marker-malaga-js");
    source.loaded = false;
    await controller.refresh({ groups: [] });
    map.emit("error", { sourceId: "explore-locations" });
    source.loaded = true;
    map.emit("render");

    // Preserve the displayed locations without leaving the loading state stuck.
    expect(document.querySelector(".marker-malaga-js")).to.equal(originalPin);
    expect(controller.state.status).to.equal("error");
    expect(swal.calls).to.have.length(0);

    // Allow a later response to complete the replacement.
    await controller.refresh({ groups: [] });
    map.emit("render");
    expect(document.querySelector(".maplibregl-marker")).to.equal(null);
    expect(controller.state.status).to.equal("empty");
  });

  it("clears old markers for empty results and ignores stale source features", async () => {
    // Preserve old source features while replacing the results with an empty set.
    const { controller, map, source } = await initializeMap();
    const oldFeatures = source.data.features;
    await controller.refresh({ groups: [{ ...GROUP, latitude: 95 }] });
    map.sourceFeatures = oldFeatures;
    map.emit("render");

    // Verify stale features cannot restore removed locations.
    expect(source.data.features).to.deep.equal([]);
    expect(document.querySelector(".maplibregl-marker")).to.equal(null);
    expect(controller.state.status).to.equal("empty");
    expect(
      document.getElementById("loading-map").classList.contains("is-loading"),
    ).to.equal(false);
  });

  it("ignores stale responses and clears loading after request failures", async () => {
    // Hold an older location request while applying newer empty results.
    const { controller, map, source } = await initializeMap();
    let resolveOldRequest;
    controller.fetchLocationData = () =>
      new Promise((resolve) => {
        resolveOldRequest = resolve;
      });
    const pendingRefresh = controller.refresh();
    expect(controller.state.status).to.equal("loading");
    await controller.refresh({ groups: [] });
    map.emit("render");
    resolveOldRequest({ groups: [GROUP] });
    await pendingRefresh;
    expect(source.data.features).to.deep.equal([]);
    expect(controller.state.status).to.equal("empty");

    // End the loading state when the next request fails.
    controller.fetchLocationData = async () => {
      throw new Error("network error");
    };
    await controller.refresh();
    expect(controller.state.status).to.equal("error");
    expect(
      document.getElementById("loading-map").classList.contains("is-loading"),
    ).to.equal(false);
    expect(swal.calls).to.have.length(1);
    expect(swal.calls[0].text).to.equal(RESULTS_ERROR_MESSAGE);
  });

  it("explains map-construction failures and offers a recovery path", async () => {
    // Simulate a browser that cannot initialize a WebGL map.
    mapLibre.api.Map = class UnavailableMap {
      constructor() {
        throw new Error("Failed to initialize WebGL");
      }
    };
    const controller = new ExploreMap("groups", { groups: [GROUP] });
    await waitForMicrotask();
    await controller.setupPromise;

    // End the loading state and explain how to recover without a working map.
    expect(controller.map).not.to.exist;
    expect(controller.state.status).to.equal("error");
    expect(swal.calls).to.have.length(1);
    expect(swal.calls[0]).to.include({
      icon: "error",
      text: "Unable to load the map. Switch to list view or reload the page to try again.",
    });
    expect(swal.calls[0]).not.to.have.property("timer");
    expect(
      document.getElementById("main-loading-map").classList.contains("hidden"),
    ).to.equal(true);
  });

  it("explains style-load failures without leaving a blank loading state", async () => {
    // Initialize the map without completing its remote style load.
    const controller = new ExploreMap("groups", { groups: [GROUP] });
    await waitForMicrotask();
    await controller.setupPromise;
    const map = mapLibre.maps[0];

    // Report repeated resource errors through one persistent feedback alert.
    map.emit("error").emit("error");
    expect(controller.state.status).to.equal("error");
    expect(swal.calls).to.have.length(1);
    expect(swal.calls[0]).to.include({
      icon: "error",
      text: "Unable to load the map. Switch to list view or reload the page to try again.",
    });
    expect(swal.calls[0]).not.to.have.property("timer");
    expect(
      document.getElementById("main-loading-map").classList.contains("hidden"),
    ).to.equal(true);
  });

  it("ignores resource errors after the map has loaded", async () => {
    // Initialize a working map before a later tile or glyph request fails.
    const { controller, map } = await initializeMap();
    map.emit("error").emit("error");

    // Keep the loaded map usable without displaying a persistent failure alert.
    expect(controller.state.status).to.equal("ready");
    expect(document.querySelector(".marker-malaga-js")).not.to.equal(null);
    expect(swal.calls).to.have.length(0);
  });

  it("lets users retry a cluster expansion after a worker failure", async () => {
    // Reject the expansion request for an otherwise available cluster.
    const { controller, source } = await initializeMap();
    const feature = {
      geometry: { coordinates: [-4.42, 36.72] },
      properties: { cluster_id: 12, revision: controller.dataRevision },
    };
    const cluster = document.createElement("button");
    source.getClusterExpansionZoom = async () => {
      throw new Error("worker failure");
    };

    // Restore activation and explain the failure without discarding locations.
    await controller.expandCluster(feature, cluster);
    expect(cluster.disabled).to.equal(false);
    expect(document.querySelector(".marker-malaga-js")).not.to.equal(null);
    expect(swal.calls[0].text).to.equal(
      "Unable to expand these locations. Please try again.",
    );
  });
});
