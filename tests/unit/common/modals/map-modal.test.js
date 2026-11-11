import { expect } from "@open-wc/testing";

import { initializeMapModals } from "/static/js/common/modals/map-modal.js";
import { resetRestoredModalState } from "/static/js/common/modals/modal-lifecycle.js";
import { THEME_STORAGE_KEY } from "/static/js/common/theme.js";
import {
  waitForAnimationFrames,
  waitForMicrotask,
} from "/tests/unit/test-utils/async.js";
import { resetDom } from "/tests/unit/test-utils/dom.js";
import { mockSwal } from "/tests/unit/test-utils/globals.js";
import { mockMapLibre } from "/tests/unit/test-utils/maps.js";

const BRIGHT_STYLE_URL = "https://tiles.openfreemap.org/styles/bright";
const DARK_STYLE_URL = "https://tiles.openfreemap.org/styles/fiord";

describe("map modal", () => {
  let mapLibre;
  let swal;

  beforeEach(() => {
    resetDom();
    mapLibre = mockMapLibre();
    swal = mockSwal();
    localStorage.setItem(THEME_STORAGE_KEY, "light");

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
        data-trigger-id="event-map-trigger"
      ></div>
      <button id="event-map-trigger" type="button"></button>
      <div
        id="event-map-modal"
        class="hidden"
        aria-hidden="true"
        aria-modal="true"
        role="dialog"
      >
        <button id="close-event-map-modal"></button>
        <div id="backdrop-event-map-modal"></div>
        <div id="event-map-modal-map"></div>
      </div>
    `;
  });

  afterEach(() => {
    // Close open modals so their keyboard listeners do not leak into other tests.
    resetRestoredModalState(document);
    mapLibre.restore();
    swal.restore();
    localStorage.removeItem(THEME_STORAGE_KEY);
    resetDom();
  });

  it("initializes preview maps and lazily loads modal maps", async () => {
    // Initialize the preview map and open the modal from its trigger.
    initializeMapModals();
    await waitForMicrotask();
    document.getElementById("event-map-trigger").click();
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
      style: BRIGHT_STYLE_URL,
      interactive: false,
    });
    expect(mapLibre.maps[1].options.style).to.equal(BRIGHT_STYLE_URL);
    expect(mapLibre.maps[0].options.center).to.deep.equal([-4.4214, 36.7213]);
    expect(mapLibre.maps[1].options.interactive).to.equal(true);
    expect(mapLibre.maps[1].keyboard.rotationDisabled).to.equal(true);
    expect(mapLibre.maps[1].touchZoomRotate.rotationDisabled).to.equal(true);
    expect(mapLibre.maps[0].controls[0].position).to.equal("top-right");
    expect(mapLibre.maps[0].controls[0].control.options.compact).to.equal(
      false,
    );
    expect(mapLibre.maps[0].controls).to.have.length(1);

    // Only the modal map exposes zoom buttons.
    expect(mapLibre.maps[1].controls).to.have.length(2);
    expect(mapLibre.maps[1].controls[1].position).to.equal("top-right");
    expect(mapLibre.maps[1].controls[1].control.options).to.deep.equal({
      showCompass: false,
    });

    // Close actions toggle the modal closed and return focus to the trigger.
    document.getElementById("close-event-map-modal").click();
    expect(
      document.getElementById("event-map-modal")?.classList.contains("hidden"),
    ).to.equal(true);
    expect(document.activeElement?.id).to.equal("event-map-trigger");

    // Attribution clicks inside the preview do not open the modal.
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

  it("loads the preview and modal maps with the dark basemap under the dark color theme", async () => {
    // Initialize the preview and open the modal with Dark stored.
    localStorage.setItem(THEME_STORAGE_KEY, "dark");
    initializeMapModals();
    await waitForMicrotask();
    document.getElementById("event-map-trigger").click();
    await waitForAnimationFrames(2);

    // Verify both maps request the dark style.
    expect(mapLibre.maps.map((map) => map.options.style)).to.deep.equal([
      DARK_STYLE_URL,
      DARK_STYLE_URL,
    ]);
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
    document.getElementById("event-map-trigger").click();
    await waitForAnimationFrames(2);
    expect(swal.calls).to.have.length(2);
    expect(mapLibre.maps).to.have.length(0);

    // Reopen the modal after initialization becomes available again.
    document.getElementById("close-event-map-modal").click();
    mapLibre.api.Map = MapConstructor;
    document.getElementById("event-map-trigger").click();
    await waitForAnimationFrames(2);
    expect(mapLibre.maps.map((map) => map.options.container)).to.deep.equal([
      "event-map-modal-map",
    ]);
    expect(swal.calls).to.have.length(2);
  });

  it("traps Tab and closes with Escape, returning focus to the trigger", async () => {
    // Open the modal from its trigger.
    initializeMapModals();
    await waitForMicrotask();
    const modal = document.getElementById("event-map-modal");
    const trigger = document.getElementById("event-map-trigger");
    trigger.focus();
    trigger.click();
    expect(document.activeElement?.id).to.equal("close-event-map-modal");

    // Tab from the only focusable control stays inside the modal.
    const tab = pressKey("Tab");
    expect(tab.defaultPrevented).to.equal(true);
    expect(document.activeElement?.id).to.equal("close-event-map-modal");

    // Escape closes the modal and returns focus to the trigger.
    const escape = pressKey("Escape");
    expect(escape.defaultPrevented).to.equal(true);
    expect(modal.classList.contains("hidden")).to.equal(true);
    expect(modal.getAttribute("aria-hidden")).to.equal("true");
    expect(document.activeElement).to.equal(trigger);

    // A later Escape no longer reaches the closed modal.
    pressKey("Escape");
    expect(modal.classList.contains("hidden")).to.equal(true);
  });

  it("skips map modals without a trigger", async () => {
    // Remove the trigger the modal opens from.
    document.getElementById("event-map-trigger").remove();

    // The incomplete widget loads no map and stays uninitialized.
    initializeMapModals();
    await waitForMicrotask();
    expect(mapLibre.maps).to.have.length(0);
    expect(document.getElementById("event-map").dataset.mapModalReady).to.equal(
      undefined,
    );
  });
});

// Helpers.

/**
 * Dispatches a keydown event on the document.
 * @param {string} key Keyboard key.
 * @returns {KeyboardEvent} Dispatched event.
 */
const pressKey = (key) => {
  const event = new KeyboardEvent("keydown", {
    bubbles: true,
    cancelable: true,
    key,
  });
  document.dispatchEvent(event);
  return event;
};
