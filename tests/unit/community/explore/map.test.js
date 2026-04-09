import { expect } from "@open-wc/testing";

import { Map as ExploreMap } from "/static/js/community/explore/map.js";
import { resetDom } from "/tests/unit/test-utils/dom.js";

describe("community explore map", () => {
  const originalLeaflet = globalThis.L;
  let addedLayers;
  let markerAdds;

  beforeEach(() => {
    resetDom();
    ExploreMap._instance = null;
    addedLayers = [];
    markerAdds = [];
    document.body.innerHTML = `
      <div id="main-loading-map" class="hidden"></div>
      <div id="map-box"></div>
    `;

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
            addedLayers.push(bounds);
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
    globalThis.window.L = globalThis.L;
  });

  afterEach(() => {
    resetDom();
    ExploreMap._instance = null;
    if (originalLeaflet) {
      globalThis.L = originalLeaflet;
      globalThis.window.L = originalLeaflet;
    } else {
      delete globalThis.L;
      delete globalThis.window.L;
    }
  });

  it("loads map scripts and adds markers for valid coordinates", () => {
    const map = new ExploreMap("groups", { groups: [] });
    const leafletScript = document.head.querySelector('script[src*="leaflet.v1.9.4.min.js"]');

    leafletScript.onload();
    const clusterScript = document.head.querySelector('script[src*="leaflet.markercluster.v1.5.3.min.js"]');
    clusterScript.onload();

    map.addMarkers(
      [
        { slug: "one", latitude: 10, longitude: 20, popover_html: "" },
        { slug: "two", latitude: 0, longitude: 20, popover_html: "" },
      ],
      { sw_lat: 1, sw_lon: 2, ne_lat: 3, ne_lon: 4 },
    );

    expect(markerAdds).to.have.length(1);
    expect(addedLayers).to.not.deep.equal([]);
  });
});
