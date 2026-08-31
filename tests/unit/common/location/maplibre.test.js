import { expect } from "@open-wc/testing";

import {
  createMapMarker,
  loadMap,
} from "/static/js/common/location/maplibre.js";
import { resetDom } from "/tests/unit/test-utils/dom.js";
import { mockMapLibre } from "/tests/unit/test-utils/maps.js";

describe("shared MapLibre map", () => {
  let mapLibre;

  beforeEach(() => {
    // Create the map container and mock the browser library.
    resetDom();
    mapLibre = mockMapLibre();
    document.body.innerHTML = '<div id="location-map"></div>';
  });

  afterEach(() => {
    // Restore the map resources and DOM.
    mapLibre.restore();
    resetDom();
  });

  it("keeps flat maps within Web Mercator bounds and the configured zoom limit", async () => {
    // Initialize the shared map at a known location.
    const map = await loadMap("location-map", 36.7213, -4.4214);

    // Verify the world edges stay distinct after longitude wrapping.
    const [[west, south], [east, north]] = map.options.maxBounds;
    expect(west).to.be.greaterThan(-180);
    expect(west).to.be.closeTo(-180, 1e-6);
    expect(east).to.be.lessThan(180);
    expect(east).to.be.closeTo(180, 1e-6);
    expect([south, north]).to.deep.equal([-85.051129, 85.051129]);

    // Verify the zoom limit and disabled rotation controls.
    expect(map.options.maxZoom).to.equal(19);
    expect(map.options).to.include({
      dragRotate: false,
      pitchWithRotate: false,
      touchPitch: false,
      renderWorldCopies: false,
    });
    expect(map.keyboard.rotationDisabled).to.equal(true);
    expect(map.touchZoomRotate.rotationDisabled).to.equal(true);
  });

  it("opens a styled popup and exposes its interactive pin to assistive technology", async () => {
    // Load a map with a styled, initially open popup.
    await loadMap("location-map", 36.7213, -4.4214, {
      popupContent: "<p>Venue details</p>",
      popupClassName: "location-popup",
    });

    // Verify the popup content, position, and close controls.
    const popup = document.querySelector(".location-popup");
    expect(popup.textContent).to.equal("Venue details");
    expect(mapLibre.popups[0].coordinates).to.deep.equal([-4.4214, 36.7213]);
    expect(mapLibre.popups[0].options).to.include({
      closeButton: true,
      closeOnClick: true,
    });

    // Verify the pin remains keyboard accessible.
    const pin = mapLibre.markers[0].getElement();
    expect(pin.getAttribute("aria-hidden")).to.equal(null);
    expect(pin.getAttribute("role")).to.equal("button");
    expect(pin.tabIndex).to.equal(0);
  });

  it("keeps a popup closed until opened when openPopup is false", async () => {
    // Initialize the popup without opening it.
    await loadMap("location-map", 36.7213, -4.4214, {
      popupContent: "<p>Venue details</p>",
      openPopup: false,
    });

    // Verify the popup starts closed.
    expect(document.querySelector(".maplibregl-popup")).to.equal(null);

    // Open the popup through its marker.
    mapLibre.markers[0].togglePopup();

    // Verify the venue details become visible.
    expect(document.querySelector(".maplibregl-popup").textContent).to.equal(
      "Venue details",
    );
  });

  it("shows noninteractive popup content without close controls or an interactive pin", async () => {
    // Load the venue popup on a noninteractive preview.
    const map = await loadMap("location-map", 36.7213, -4.4214, {
      popupContent: "<p>Venue details</p>",
      interactive: false,
    });

    // Verify the content remains visible without interactive controls.
    expect(map.options.interactive).to.equal(false);
    expect(document.querySelector(".maplibregl-popup").textContent).to.equal(
      "Venue details",
    );
    expect(mapLibre.popups[0].options).to.include({
      closeButton: false,
      closeOnClick: false,
    });
    expect(
      mapLibre.markers[0].getElement().getAttribute("aria-hidden"),
    ).to.equal("true");
  });

  it("omits the pin and popup when marker is false", async () => {
    // Load the map without a location pin.
    await loadMap("location-map", 36.7213, -4.4214, {
      marker: false,
      popupContent: "<p>Venue details</p>",
    });

    // Verify neither a marker nor a popup is created.
    expect(mapLibre.markers).to.have.length(0);
    expect(mapLibre.popups).to.have.length(0);
  });

  it("uses the supplied DOM element for custom markers", () => {
    // Create a marker from a custom DOM element.
    const element = document.createElement("button");
    const marker = createMapMarker([-4.4214, 36.7213], {
      element,
      anchor: "center",
    });

    // Verify the marker preserves its element, coordinates, and anchor.
    expect(marker.getElement()).to.equal(element);
    expect(marker.coordinates).to.deep.equal([-4.4214, 36.7213]);
    expect(marker.options.anchor).to.equal("center");
  });
});
