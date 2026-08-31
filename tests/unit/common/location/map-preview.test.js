import { expect } from "@open-wc/testing";

import { LocationMapPreview } from "/static/js/common/location/map-preview.js";
import { loadMap } from "/static/js/common/location/maplibre.js";
import { waitForMicrotask } from "/tests/unit/test-utils/async.js";
import { resetDom } from "/tests/unit/test-utils/dom.js";
import { mockSwal } from "/tests/unit/test-utils/globals.js";
import { mockMapLibre } from "/tests/unit/test-utils/maps.js";

const LOCATION = {
  mapVisible: true,
  latitudeValue: "36.7213",
  longitudeValue: "-4.4214",
  mapZoom: 13,
};

describe("location map preview", () => {
  let mapLibre;
  let preview;
  let swal;

  beforeEach(() => {
    // Create the preview container and replace the browser map library.
    resetDom();
    mapLibre = mockMapLibre();
    swal = mockSwal();
    document.body.innerHTML = '<div id="location-map"></div>';
    preview = new LocationMapPreview("location-map");
  });

  afterEach(() => {
    // Release pending map work and restore the DOM and library.
    preview.destroy();
    mapLibre.restore();
    swal.restore();
    document.head
      .querySelector('script[src*="maplibre-gl.v5.24.0.min.js"]')
      ?.remove();
    resetDom();
  });

  it("updates the same map and pin with longitude-first coordinates", async () => {
    // Move the preview between two selected locations.
    await preview.sync(LOCATION);
    await preview.sync({
      ...LOCATION,
      latitudeValue: "40.4168",
      longitudeValue: "-3.7038",
    });

    // Reuse the existing map and marker with the new coordinates.
    expect(mapLibre.maps).to.have.length(1);
    expect(mapLibre.markers).to.have.length(1);
    expect(mapLibre.markers[0].coordinates).to.deep.equal([-3.7038, 40.4168]);
    expect(mapLibre.maps[0].jumpToCalls.at(-1)).to.deep.equal({
      center: [-3.7038, 40.4168],
      zoom: 13,
    });
  });

  it("discards a map initialization when the location is cleared while loading", async () => {
    // Clear the location before its map initialization completes.
    const pendingSync = preview.syncInternal(LOCATION);
    preview.reset();
    await pendingSync;

    // Discard the stale map without adding a marker.
    expect(preview.map).to.equal(null);
    expect(mapLibre.maps[0].removed).to.equal(true);
    expect(mapLibre.markers).to.have.length(0);
  });

  it("explains initialization failures and retries without discarding coordinates", async () => {
    // Reject map creation while retaining the selected location.
    const MapConstructor = mapLibre.api.Map;
    mapLibre.api.Map = class UnavailableMap {
      constructor() {
        throw new Error("Failed to initialize WebGL");
      }
    };
    await preview.sync(LOCATION);
    expect(preview.map).to.equal(null);
    expect(swal.calls[0].text).to.equal(
      "Unable to load the map preview. You can still enter the location details.",
    );

    // Allow coordinate edits without repeating the same initialization alert.
    await preview.sync({ ...LOCATION, latitudeValue: "40.4168" });
    expect(swal.calls).to.have.length(1);

    // Retry the same location after map creation becomes available.
    mapLibre.api.Map = MapConstructor;
    await preview.sync(LOCATION);
    expect(mapLibre.markers[0].coordinates).to.deep.equal([-4.4214, 36.7213]);
    expect(swal.calls).to.have.length(1);
  });

  it("ignores initialization errors after the preview has been reset", async () => {
    // Clear the preview before its failing initialization finishes.
    mapLibre.api.Map = class UnavailableMap {
      constructor() {
        throw new Error("Failed to initialize WebGL");
      }
    };
    const pendingSync = preview.syncInternal(LOCATION);
    preview.reset();
    await pendingSync;

    // Keep obsolete failures from interrupting the current page.
    expect(swal.calls).to.have.length(0);
    expect(preview.map).to.equal(null);
  });

  it("releases maps when their container is removed without HTMX", async () => {
    // Remove the initialized preview through the DOM.
    await preview.sync(LOCATION);
    document.getElementById("location-map").remove();
    await waitForMicrotask();

    // Release the map and clear the preview's references.
    expect(mapLibre.maps[0].removed).to.equal(true);
    expect(preview.map).to.equal(null);
    expect(preview.marker).to.equal(null);
  });

  it("does not initialize a removed container after the library finishes loading", async () => {
    // Remove the container while the vendor script is still loading.
    delete globalThis.maplibregl;
    const pendingMap = loadMap("location-map", 36.7213, -4.4214);
    document.getElementById("location-map").remove();

    // Complete the script load after the preview has disappeared.
    globalThis.maplibregl = mapLibre.api;
    document.head
      .querySelector('script[src*="maplibre-gl.v5.24.0.min.js"]')
      .onload();

    // Leave the removed preview uninitialized.
    expect(await pendingMap).to.equal(null);
    expect(mapLibre.maps).to.have.length(0);
  });
});
