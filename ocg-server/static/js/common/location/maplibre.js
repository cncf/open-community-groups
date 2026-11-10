import { loadScriptOnce } from "/static/js/common/dom.js";
import { getResolvedTheme, THEME_CHANGE_EVENT } from "/static/js/common/theme.js";

// Keep locations on the edge of the initial bounds inside the viewport so their pins render.
const BOUNDS_PADDING_PX = 40;
const MAPLIBRE_SCRIPT_SRC = "/static/vendor/js/maplibre-gl.v5.24.0.min.js";
// OpenFreeMap basemap style for each color theme.
const MAP_STYLE_URLS = {
  dark: "https://tiles.openfreemap.org/styles/dark",
  light: "https://tiles.openfreemap.org/styles/bright",
};
// Keep opposite map edges distinct when MapLibre wraps longitude coordinates.
const MAX_LONGITUDE = 180 - 1e-10;

/**
 * Loads an OpenFreeMap map with an optional marker and popup.
 *
 * The basemap follows the color theme: the first paint loads the resolved theme's style, and a
 * color theme change swaps it live.
 * @param {string} divId Map container ID.
 * @param {number} lat Latitude of the map center.
 * @param {number} lng Longitude of the map center.
 * @param {object} options Map options.
 * @param {number[][]} [options.bounds] Initial longitude/latitude bounds, fitted with padding.
 * @param {Function} [options.transformStyle] MapLibre `transformStyle` passed to the basemap swap
 *   of a color theme change, to carry the caller's sources and layers into the next style.
 * @returns {Promise<object|null>} MapLibre instance, or null if its container is gone.
 */
export const loadMap = async (divId, lat, lng, options = {}) => {
  const container = document.getElementById(divId);
  await loadMapScript();
  if (!container?.isConnected || document.getElementById(divId) !== container) return null;

  const interactive = options.interactive !== false;
  let styleUrl = getMapStyleUrl(getResolvedTheme());
  const map = new maplibregl.Map({
    container: divId,
    style: styleUrl,
    bounds: options.bounds,
    fitBoundsOptions: { padding: BOUNDS_PADDING_PX },
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

  // Swap the basemap once per frame, after a burst of color theme changes settles. The default
  // diff mode fetches the next style before dropping the current one, so a failed fetch keeps the
  // current basemap and the next change retries.
  let themeFrame = 0;
  const handleThemeChange = () => {
    if (themeFrame) return;
    themeFrame = requestAnimationFrame(() => {
      themeFrame = 0;
      const nextStyleUrl = getMapStyleUrl(getResolvedTheme());
      if (nextStyleUrl === styleUrl) return;
      styleUrl = nextStyleUrl;
      map.setStyle(nextStyleUrl, { transformStyle: options.transformStyle });
    });
  };
  document.addEventListener(THEME_CHANGE_EVENT, handleThemeChange);

  map.on("remove", () => {
    removalObserver.disconnect();
    document.removeEventListener("htmx:beforeCleanupElement", handleCleanup);
    document.removeEventListener(THEME_CHANGE_EVENT, handleThemeChange);
    cancelAnimationFrame(themeFrame);
    themeFrame = 0;
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
    element.className = "svg-icon h-[30px] w-[30px] bg-primary-fg icon-marker";
    element.setAttribute("aria-hidden", "true");
  }
  return new maplibregl.Marker({ element, anchor: options.anchor || "bottom" }).setLngLat(coordinates);
};

/**
 * Returns the OpenFreeMap style URL for a color theme.
 * @param {string} theme Resolved color theme, `light` or `dark`.
 * @returns {string} Style URL, the light one for any other value.
 */
export const getMapStyleUrl = (theme) =>
  Object.hasOwn(MAP_STYLE_URLS, theme) ? MAP_STYLE_URLS[theme] : MAP_STYLE_URLS.light;

/**
 * Loads MapLibre once, including when several maps initialize together.
 * @returns {Promise<void>} Resolves when MapLibre is available.
 */
export const loadMapScript = () =>
  loadScriptOnce(MAPLIBRE_SCRIPT_SRC, {
    isLoaded: () => typeof window.maplibregl !== "undefined",
  });
