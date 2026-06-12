import { expect } from "@open-wc/testing";

import { Map as ExploreMap } from "/static/js/community/explore/map.js";
import { waitForMicrotask } from "/tests/unit/test-utils/async.js";
import { resetDom } from "/tests/unit/test-utils/dom.js";

describe("community explore map", () => {
  const originalLeaflet = globalThis.L;
  const originalHtmx = globalThis.htmx;
  let addedLayers;
  let markerAdds;
  let flyToBoundsCalls;
  let leafletMock;

  beforeEach(() => {
    resetDom();
    ExploreMap._instance = null;
    addedLayers = [];
    markerAdds = [];
    flyToBoundsCalls = [];
    document.head
      .querySelectorAll(
        'script[src*="leaflet.v1.9.4.min.js"], script[src*="leaflet.markercluster.v1.5.3.min.js"]',
      )
      .forEach((node) => node.remove());
    document.body.innerHTML = `
      <div id="main-loading-map" class="hidden"></div>
      <div id="map-box"></div>
    `;
    globalThis.htmx = { process() {} };

    // Run the behavior under test.
    leafletMock = {
      Browser: { retina: false },
      latLng(lat, lng) {
        return { lat, lng };
      },
      latLngBounds(sw, ne) {
        return { sw, ne };
      },
      map() {
        const handlers = {};
        return {
          handlers,
          on(name, handler) {
            handlers[name] = handler;
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
          flyToBounds(bounds) {
            flyToBoundsCalls.push(bounds);
          },
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
        const handlers = {};
        return {
          latLng,
          config,
          handlers,
          on(name, handler) {
            handlers[name] = handler;
          },
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
  });

  afterEach(() => {
    resetDom();
    ExploreMap._instance = null;
    document.head
      .querySelectorAll(
        'script[src*="leaflet.v1.9.4.min.js"], script[src*="leaflet.markercluster.v1.5.3.min.js"]',
      )
      .forEach((node) => node.remove());
    if (originalLeaflet) {
      globalThis.L = originalLeaflet;
      globalThis.window.L = originalLeaflet;
    } else {
      delete globalThis.L;
      delete globalThis.window.L;
    }
    if (originalHtmx) {
      globalThis.htmx = originalHtmx;
    } else {
      delete globalThis.htmx;
    }
  });

  it("loads map scripts, filters invalid coordinates, fits bbox, and navigates to group pages", async () => {
    // Prepare original anchor click for loading map scripts, filters invalid.
    const originalAnchorClick = HTMLAnchorElement.prototype.click;
    const clickedUrls = [];
    HTMLAnchorElement.prototype.click = function click() {
      clickedUrls.push(this.getAttribute("href"));
    };

    // Prepare map for loading map scripts, filters invalid coordinates, fits bbox.
    delete globalThis.L;
    delete globalThis.window.L;
    const map = new ExploreMap("groups", { groups: [] });
    const leafletScript = document.head.querySelector(
      'script[src*="leaflet.v1.9.4.min.js"]',
    );

    // Finish Leaflet first so marker clustering can load after it.
    globalThis.L = { ...leafletMock, markerClusterGroup: undefined };
    globalThis.window.L = globalThis.L;
    leafletScript.onload();
    await waitForMicrotask();
    const clusterScript = document.head.querySelector(
      'script[src*="leaflet.markercluster.v1.5.3.min.js"]',
    );
    globalThis.L = leafletMock;
    globalThis.window.L = leafletMock;
    clusterScript.onload();
    await waitForMicrotask();

    // Add markers while invalid coordinates are present.
    try {
      map.addMarkers(
        [
          {
            slug: "malaga-js",
            slug_pretty: "malaga-javascript",
            community_name: "spain",
            latitude: 36.7213,
            longitude: -4.4214,
            popover_html: "",
          },
          {
            slug: "missing-latitude",
            community_name: "spain",
            latitude: 0,
            longitude: -4.4,
            popover_html: "",
          },
        ],
        { sw_lat: 1, sw_lon: 2, ne_lat: 3, ne_lon: 4 },
      );

      // Verify loads map scripts, filters invalid coordinates, fits bbox.
      expect(markerAdds).to.have.length(1);
      expect(markerAdds[0].config.icon.className).to.equal("marker-malaga-js");
      expect(markerAdds[0].latLng).to.deep.equal({
        lat: 36.7213,
        lng: -4.4214,
      });
      expect(addedLayers).to.have.length(1);
      expect(flyToBoundsCalls).to.deep.equal([
        { sw: { lat: 1, lng: 2 }, ne: { lat: 3, lng: 4 } },
      ]);

      // Verify loads map scripts, filters invalid.
      markerAdds[0].handlers.click();

      // Verify loads map scripts, filters invalid coordinates, fits bbox.
      expect(clickedUrls).to.deep.equal(["/spain/group/malaga-javascript"]);
    } finally {
      HTMLAnchorElement.prototype.click = originalAnchorClick;
    }
  });

  it("builds event urls and ignores invalid bounding boxes", async () => {
    // Prepare original anchor click for building event urls and ignores invalid.
    const originalAnchorClick = HTMLAnchorElement.prototype.click;
    const clickedUrls = [];
    HTMLAnchorElement.prototype.click = function click() {
      clickedUrls.push(this.getAttribute("href"));
    };

    // Verify builds event urls and ignores invalid bounding boxes.
    try {
      delete globalThis.L;
      delete globalThis.window.L;
      const map = new ExploreMap("events", { events: [] });
      globalThis.L = { ...leafletMock, markerClusterGroup: undefined };
      globalThis.window.L = globalThis.L;
      document.head
        .querySelector('script[src*="leaflet.v1.9.4.min.js"]')
        ?.onload();
      await waitForMicrotask();
      globalThis.L = leafletMock;
      globalThis.window.L = leafletMock;
      document.head
        .querySelector('script[src*="leaflet.markercluster.v1.5.3.min.js"]')
        ?.onload();
      await waitForMicrotask();

      // Verify builds event urls and ignores invalid bounding.
      map.addMarkers(
        [
          {
            slug: "open-source-day",
            group_slug: "malaga-js",
            group_slug_pretty: "malaga-javascript",
            community_name: "spain",
            latitude: 36.72,
            longitude: -4.42,
            popover_html: "",
          },
        ],
        { sw_lat: 5, sw_lon: 5, ne_lat: 5, ne_lon: 5 },
      );

      // Assert the map bounds calls.
      expect(flyToBoundsCalls).to.deep.equal([]);

      // Verify builds event urls and ignores invalid.
      markerAdds[0].handlers.click();

      // Assert the updated clicked urls.
      expect(clickedUrls).to.deep.equal([
        "/spain/group/malaga-javascript/event/open-source-day",
      ]);
    } finally {
      HTMLAnchorElement.prototype.click = originalAnchorClick;
    }
  });
});
