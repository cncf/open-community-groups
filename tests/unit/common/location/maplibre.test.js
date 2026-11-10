import { expect } from "@open-wc/testing";

import {
  createMapMarker,
  getMapStyleUrl,
  loadMap,
} from "/static/js/common/location/maplibre.js";
import { THEME_CHANGE_EVENT, THEME_STORAGE_KEY } from "/static/js/common/theme.js";
import { waitForAnimationFrames } from "/tests/unit/test-utils/async.js";
import { resetDom } from "/tests/unit/test-utils/dom.js";
import { mockMapLibre } from "/tests/unit/test-utils/maps.js";

const BRIGHT_STYLE_URL = "https://tiles.openfreemap.org/styles/bright";
const DARK_STYLE_URL = "https://tiles.openfreemap.org/styles/dark";

/**
 * Stores a color theme choice and announces it, as theme.js does after a switch.
 * @param {"light"|"dark"} theme - Color theme to apply.
 * @returns {void}
 */
const switchTheme = (theme) => {
  localStorage.setItem(THEME_STORAGE_KEY, theme);
  document.dispatchEvent(
    new CustomEvent(THEME_CHANGE_EVENT, { detail: { theme } }),
  );
};

describe("shared MapLibre map", () => {
  let mapLibre;

  beforeEach(() => {
    // Create the map container, mock the browser library and start in light.
    resetDom();
    mapLibre = mockMapLibre();
    localStorage.setItem(THEME_STORAGE_KEY, "light");
    document.body.innerHTML = '<div id="location-map"></div>';
  });

  afterEach(() => {
    // Restore the map resources, storage and DOM.
    mapLibre.restore();
    localStorage.removeItem(THEME_STORAGE_KEY);
    resetDom();
  });

  it("maps each color theme to its basemap style and falls back to bright", () => {
    expect(getMapStyleUrl("light")).to.equal(BRIGHT_STYLE_URL);
    expect(getMapStyleUrl("dark")).to.equal(DARK_STYLE_URL);
    expect(getMapStyleUrl("system")).to.equal(BRIGHT_STYLE_URL);
    expect(getMapStyleUrl("constructor")).to.equal(BRIGHT_STYLE_URL);
    expect(getMapStyleUrl(undefined)).to.equal(BRIGHT_STYLE_URL);
  });

  it("loads the basemap style of the resolved color theme", async () => {
    // Load one map in light and one in dark.
    const lightMap = await loadMap("location-map", 36.7213, -4.4214);
    localStorage.setItem(THEME_STORAGE_KEY, "dark");
    document.body.insertAdjacentHTML(
      "beforeend",
      '<div id="dark-location-map"></div>',
    );
    const darkMap = await loadMap("dark-location-map", 36.7213, -4.4214);

    // Verify each first paint requests its theme's style.
    expect(lightMap.options.style).to.equal(BRIGHT_STYLE_URL);
    expect(darkMap.options.style).to.equal(DARK_STYLE_URL);
  });

  it("swaps the basemap once per color theme change", async () => {
    // Load a map with a style transform, then switch to dark twice within one frame.
    const transformStyle = (previousStyle, nextStyle) => nextStyle;
    const map = await loadMap("location-map", 36.7213, -4.4214, {
      transformStyle,
    });
    switchTheme("dark");
    switchTheme("dark");
    expect(map.setStyleCalls).to.have.length(0);
    await waitForAnimationFrames(2);

    // Verify one diffed swap to dark that carries the transform.
    expect(map.setStyleCalls).to.have.length(1);
    expect(map.setStyleCalls[0].url).to.equal(DARK_STYLE_URL);
    expect(map.setStyleCalls[0].options).to.deep.equal({ transformStyle });

    // Switch back to light and verify the second swap.
    switchTheme("light");
    await waitForAnimationFrames(2);
    expect(map.setStyleCalls.map(({ url }) => url)).to.deep.equal([
      DARK_STYLE_URL,
      BRIGHT_STYLE_URL,
    ]);
  });

  it("applies only the last color theme of a burst", async () => {
    // Switch to dark and back to light within one frame.
    const map = await loadMap("location-map", 36.7213, -4.4214);
    switchTheme("dark");
    switchTheme("light");
    await waitForAnimationFrames(2);

    // Verify the basemap already matches, so nothing is swapped.
    expect(map.setStyleCalls).to.have.length(0);
  });

  it("keeps the basemap when the style URL does not change", async () => {
    // Announce a change that resolves to the current light theme.
    const map = await loadMap("location-map", 36.7213, -4.4214);
    switchTheme("light");
    await waitForAnimationFrames(2);

    // Verify no style request is made.
    expect(map.setStyleCalls).to.have.length(0);
  });

  it("stops following the color theme once the map is removed", async () => {
    // Switch to dark and remove the map before the queued frame runs.
    const map = await loadMap("location-map", 36.7213, -4.4214);
    switchTheme("dark");
    map.remove();
    await waitForAnimationFrames(2);

    // Verify neither the queued frame nor a later change swaps the style.
    switchTheme("light");
    switchTheme("dark");
    await waitForAnimationFrames(2);
    expect(map.setStyleCalls).to.have.length(0);
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

  it("pads the initial bounds so locations on their edges stay inside the viewport", async () => {
    // Initialize the shared map fitted to a result extent.
    const bounds = [
      [-122.3321, 40.7128],
      [-74.006, 47.6062],
    ];
    const map = await loadMap("location-map", 0, 0, { bounds });

    // Verify the extent is applied with padding on the first fit only.
    expect(map.options.bounds).to.deep.equal(bounds);
    expect(map.options.fitBoundsOptions.padding).to.be.greaterThan(0);
    expect(map.fitBoundsCalls).to.deep.equal([]);
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

  it("paints the default pin with the primary foreground role", async () => {
    // Load a map with its default pin.
    await loadMap("location-map", 36.7213, -4.4214);

    // Verify the pin takes the foreground role, which follows the color theme.
    const pin = mapLibre.markers[0].getElement();
    expect(pin.classList.contains("bg-primary-fg")).to.equal(true);
    expect(pin.classList.contains("bg-primary-500")).to.equal(false);
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
