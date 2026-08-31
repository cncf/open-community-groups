import { loadScriptOnce } from "/static/js/common/dom.js";

const MAPLIBRE_SCRIPT_SRC = "/static/vendor/js/maplibre-gl.v5.24.0.min.js";
// Keep opposite map edges distinct when MapLibre wraps longitude coordinates.
const MAX_LONGITUDE = 180 - 1e-10;

/**
 * Loads an OpenFreeMap map with an optional marker and popup.
 * @param {string} divId Map container ID.
 * @param {number} lat Latitude of the map center.
 * @param {number} lng Longitude of the map center.
 * @param {object} options Map options.
 * @param {number[][]} [options.bounds] Initial longitude/latitude bounds.
 * @returns {Promise<object|null>} MapLibre instance, or null if its container is gone.
 */
export const loadMap = async (divId, lat, lng, options = {}) => {
  const container = document.getElementById(divId);
  await loadMapScript();
  if (!container?.isConnected || document.getElementById(divId) !== container) return null;

  const interactive = options.interactive !== false;
  const map = new maplibregl.Map({
    container: divId,
    style: "https://tiles.openfreemap.org/styles/bright",
    bounds: options.bounds,
    center: [lng, lat],
    zoom: options.zoom ?? 13,
    minZoom: options.minZoom ?? 2,
    maxZoom: 19,
    maxBounds: [
      [-MAX_LONGITUDE, -85.051129],
      [MAX_LONGITUDE, 85.051129],
    ],
    renderWorldCopies: false,
    attributionControl: false,
    interactive,
    dragRotate: false,
    pitchWithRotate: false,
    touchPitch: false,
  });

  map.touchZoomRotate.disableRotation();
  map.keyboard.disableRotation();
  map.addControl(new maplibregl.AttributionControl({ compact: false }), "top-right");
  if (options.navigationControl) {
    map.addControl(new maplibregl.NavigationControl({ showCompass: false }), "top-right");
  }

  if (options.marker !== false) {
    const marker = createMapMarker([lng, lat]).addTo(map);
    if (options.popupContent) {
      const popup = new maplibregl.Popup({
        closeButton: interactive,
        closeOnClick: interactive,
        className: options.popupClassName || "",
        offset: 30,
      }).setHTML(options.popupContent);

      if (interactive) {
        marker.getElement().removeAttribute("aria-hidden");
        marker.setPopup(popup);
        if (options.openPopup !== false) marker.togglePopup();
      } else if (options.openPopup !== false) {
        popup.setLngLat([lng, lat]).addTo(map);
      }
    }
  }

  const handleCleanup = (event) => {
    if (event.target instanceof Element && event.target.contains(container)) map.remove();
  };
  document.addEventListener("htmx:beforeCleanupElement", handleCleanup);
  const removalObserver = new MutationObserver(() => {
    if (!container.isConnected) map.remove();
  });
  removalObserver.observe(document.body, { childList: true, subtree: true });
  map.on("remove", () => {
    removalObserver.disconnect();
    document.removeEventListener("htmx:beforeCleanupElement", handleCleanup);
  });

  return map;
};

/**
 * Creates a marker using the shared pin or a supplied DOM element.
 * @param {number[]} coordinates Longitude and latitude.
 * @param {object} options Marker options.
 * @returns {object} MapLibre marker, ready to add to a map.
 */
export const createMapMarker = (coordinates, options = {}) => {
  const element = options.element || document.createElement("div");
  if (!options.element) {
    element.className = "svg-icon h-[30px] w-[30px] bg-primary-500 icon-marker";
    element.setAttribute("aria-hidden", "true");
  }
  return new maplibregl.Marker({ element, anchor: options.anchor || "bottom" }).setLngLat(coordinates);
};

/**
 * Loads MapLibre once, including when several maps initialize together.
 * @returns {Promise<void>} Resolves when MapLibre is available.
 */
export const loadMapScript = () =>
  loadScriptOnce(MAPLIBRE_SCRIPT_SRC, {
    isLoaded: () => typeof window.maplibregl !== "undefined",
  });
