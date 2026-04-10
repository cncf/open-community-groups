import { expect } from "@open-wc/testing";

import { Map as ExploreMap } from "/static/js/community/explore/map.js";
import { resetDom } from "/tests/unit/test-utils/dom.js";

describe("community explore map", () => {
  const originalLeaflet = globalThis.L;
  const originalHtmx = globalThis.htmx;
  let addedLayers;
  let markerAdds;
  let flyToBoundsCalls;

  beforeEach(() => {
    resetDom();
    ExploreMap._instance = null;
    addedLayers = [];
    markerAdds = [];
    flyToBoundsCalls = [];
    document.head
      .querySelectorAll('script[src*="leaflet.v1.9.4.min.js"], script[src*="leaflet.markercluster.v1.5.3.min.js"]')
      .forEach((node) => node.remove());
    document.body.innerHTML = `
      <div id="main-loading-map" class="hidden"></div>
      <div id="map-box"></div>
    `;
    globalThis.htmx = { process() {} };

    globalThis.L = {
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
    globalThis.window.L = globalThis.L;
  });

  afterEach(() => {
    resetDom();
    ExploreMap._instance = null;
    document.head
      .querySelectorAll('script[src*="leaflet.v1.9.4.min.js"], script[src*="leaflet.markercluster.v1.5.3.min.js"]')
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

  it("loads map scripts, filters invalid coordinates, fits bbox, and navigates to group pages", () => {
    const originalAnchorClick = HTMLAnchorElement.prototype.click;
    const clickedUrls = [];
    HTMLAnchorElement.prototype.click = function click() {
      clickedUrls.push(this.getAttribute("href"));
    };

    const map = new ExploreMap("groups", { groups: [] });
    const leafletScript = document.head.querySelector('script[src*="leaflet.v1.9.4.min.js"]');

    leafletScript.onload();
    const clusterScript = document.head.querySelector('script[src*="leaflet.markercluster.v1.5.3.min.js"]');
    clusterScript.onload();

    try {
      map.addMarkers(
        [
          {
            slug: "malaga-js",
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

      expect(markerAdds).to.have.length(1);
      expect(markerAdds[0].config.icon.className).to.equal("marker-malaga-js");
      expect(markerAdds[0].latLng).to.deep.equal({ lat: 36.7213, lng: -4.4214 });
      expect(addedLayers).to.have.length(1);
      expect(flyToBoundsCalls).to.deep.equal([{ sw: { lat: 1, lng: 2 }, ne: { lat: 3, lng: 4 } }]);

      markerAdds[0].handlers.click();

      expect(clickedUrls).to.deep.equal(["/spain/group/malaga-js"]);
    } finally {
      HTMLAnchorElement.prototype.click = originalAnchorClick;
    }
  });

  it("builds event urls and ignores invalid bounding boxes", () => {
    const originalAnchorClick = HTMLAnchorElement.prototype.click;
    const clickedUrls = [];
    HTMLAnchorElement.prototype.click = function click() {
      clickedUrls.push(this.getAttribute("href"));
    };

    try {
      const map = new ExploreMap("events", { events: [] });
      document.head.querySelector('script[src*="leaflet.v1.9.4.min.js"]')?.onload();
      document.head.querySelector('script[src*="leaflet.markercluster.v1.5.3.min.js"]')?.onload();

      map.addMarkers(
        [
          {
            slug: "open-source-day",
            group_slug: "malaga-js",
            community_name: "spain",
            latitude: 36.72,
            longitude: -4.42,
            popover_html: "",
          },
        ],
        { sw_lat: 5, sw_lon: 5, ne_lat: 5, ne_lon: 5 },
      );

      expect(flyToBoundsCalls).to.deep.equal([]);

      markerAdds[0].handlers.click();

      expect(clickedUrls).to.deep.equal(["/spain/group/malaga-js/event/open-source-day"]);
    } finally {
      HTMLAnchorElement.prototype.click = originalAnchorClick;
    }
  });
});
