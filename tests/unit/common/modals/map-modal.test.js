import { expect } from "@open-wc/testing";

import { initializeMapModals } from "/static/js/common/modals/map-modal.js";
import {
  waitForAnimationFrames,
  waitForMicrotask,
} from "/tests/unit/test-utils/async.js";
import { resetDom } from "/tests/unit/test-utils/dom.js";
import { mockSwal } from "/tests/unit/test-utils/globals.js";
import { mockMapLibre } from "/tests/unit/test-utils/maps.js";

describe("map modal", () => {
  let mapLibre;
  let swal;

  beforeEach(() => {
    resetDom();
    mapLibre = mockMapLibre();
    swal = mockSwal();

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
  });

  afterEach(() => {
    mapLibre.restore();
    swal.restore();
    resetDom();
  });

  it("initializes preview maps and lazily loads modal maps", async () => {
    // Initialize the preview map and open the modal with the keyboard.
    initializeMapModals();
    await waitForMicrotask();
    document
      .getElementById("event-map")
      .dispatchEvent(
        new KeyboardEvent("keydown", { key: "Enter", bubbles: true }),
      );
    await waitForAnimationFrames(2);

    // The preview loads immediately and the modal map loads only after opening.
    expect(mapLibre.maps.map((map) => map.options.container)).to.deep.equal([
      "event-map",
      "event-map-modal-map",
    ]);
    expect(
      document.getElementById("event-map-modal")?.classList.contains("hidden"),
    ).to.equal(false);

    expect(mapLibre.maps[0].options).to.include({
      style: "https://tiles.openfreemap.org/styles/bright",
      interactive: false,
    });
    expect(mapLibre.maps[0].options.center).to.deep.equal([-4.4214, 36.7213]);
    expect(mapLibre.maps[1].options.interactive).to.equal(true);
    expect(mapLibre.maps[1].keyboard.rotationDisabled).to.equal(true);
    expect(mapLibre.maps[1].touchZoomRotate.rotationDisabled).to.equal(true);
    expect(mapLibre.maps[0].controls[0].position).to.equal("top-right");
    expect(mapLibre.maps[0].controls[0].control.options.compact).to.equal(
      false,
    );

    // Close actions toggle the modal closed.
    document.getElementById("close-event-map-modal").click();
    expect(
      document.getElementById("event-map-modal")?.classList.contains("hidden"),
    ).to.equal(true);

    // Attribution clicks do not open the preview's modal.
    const attribution = document.createElement("a");
    attribution.className = "maplibregl-ctrl";
    document.getElementById("event-map").append(attribution);
    attribution.click();
    expect(
      document.getElementById("event-map-modal").classList.contains("hidden"),
    ).to.equal(true);

    // HTMX cleanup releases the preview's map resources.
    document
      .getElementById("event-map")
      .dispatchEvent(
        new CustomEvent("htmx:beforeCleanupElement", { bubbles: true }),
      );
    expect(mapLibre.maps[0].removed).to.equal(true);
    expect(mapLibre.maps[1].removed).not.to.equal(true);
  });

  it("reports preview failures and retries a modal after initialization fails", async () => {
    // Simulate unavailable WebGL for the preview and the first modal opening.
    const MapConstructor = mapLibre.api.Map;
    mapLibre.api.Map = class UnavailableMap {
      constructor() {
        throw new Error("Failed to initialize WebGL");
      }
    };
    initializeMapModals();
    await waitForMicrotask();
    expect(swal.calls[0].text).to.equal(
      "Unable to load the map. Reload the page to try again.",
    );
    document.getElementById("event-map").click();
    await waitForAnimationFrames(2);
    expect(swal.calls).to.have.length(2);
    expect(mapLibre.maps).to.have.length(0);

    // Reopen the modal after initialization becomes available again.
    document.getElementById("close-event-map-modal").click();
    mapLibre.api.Map = MapConstructor;
    document.getElementById("event-map").click();
    await waitForAnimationFrames(2);
    expect(mapLibre.maps.map((map) => map.options.container)).to.deep.equal([
      "event-map-modal-map",
    ]);
    expect(swal.calls).to.have.length(2);
  });
});
