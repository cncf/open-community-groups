import { expect } from "@open-wc/testing";

import { initializeMapModals } from "/static/js/common/modals/map-modal.js";
import { waitForAnimationFrames, waitForMicrotask } from "/tests/unit/test-utils/async.js";
import { resetDom } from "/tests/unit/test-utils/dom.js";

describe("map modal", () => {
  const originalLeaflet = globalThis.L;
  const originalWindowLeaflet = globalThis.window.L;
  let mapCalls;

  beforeEach(() => {
    resetDom();
    mapCalls = [];
    const leafletMock = {
      Browser: { retina: false },
      latLng(lat, lng) {
        return { lat, lng };
      },
      latLngBounds(sw, ne) {
        return { sw, ne };
      },
      map(id) {
        const map = {
          id,
          dragging: { disable() {} },
          touchZoom: { disable() {} },
          scrollWheelZoom: { disable() {} },
          doubleClickZoom: { disable() {} },
          boxZoom: { disable() {} },
          keyboard: { disable() {} },
          tap: { disable() {} },
          setView(center, zoom) {
            map.center = center;
            map.zoom = zoom;
            return map;
          },
          invalidateSize() {},
        };
        mapCalls.push(map);
        return map;
      },
      tileLayer() {
        return { addTo() {} };
      },
      divIcon(config) {
        return config;
      },
      marker(latLng, config) {
        return {
          latLng,
          config,
          addTo() {},
        };
      },
    };
    globalThis.L = leafletMock;
    globalThis.window.L = leafletMock;
  });

  afterEach(() => {
    resetDom();
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

  it("initializes preview maps and lazily loads modal maps", async () => {
    // Build the DOM fixture with a declarative map modal.
    document.body.innerHTML = `
      <div
        id="event-map"
        data-map-modal
        data-lat="36.7213"
        data-lng="-4.4214"
        data-modal-id="event-map-modal"
        data-modal-map-id="event-map-modal-map"
        data-close-button-id="close-event-map-modal"
        data-backdrop-id="backdrop-event-map-modal"
        tabindex="0"
      ></div>
      <div id="event-map-modal" class="hidden">
        <button id="close-event-map-modal"></button>
        <div id="backdrop-event-map-modal"></div>
        <div id="event-map-modal-map"></div>
      </div>
    `;

    // Initialize the preview map and open the modal with the keyboard.
    initializeMapModals();
    await waitForMicrotask();
    document.getElementById("event-map").dispatchEvent(
      new KeyboardEvent("keydown", { key: "Enter", bubbles: true }),
    );
    await waitForAnimationFrames(2);

    // The preview loads immediately and the modal map loads only after opening.
    expect(mapCalls.map((map) => map.id)).to.deep.equal(["event-map", "event-map-modal-map"]);
    expect(document.getElementById("event-map-modal")?.classList.contains("hidden")).to.equal(
      false,
    );

    // Close actions toggle the modal closed.
    document.getElementById("close-event-map-modal").click();
    expect(document.getElementById("event-map-modal")?.classList.contains("hidden")).to.equal(
      true,
    );
  });
});
