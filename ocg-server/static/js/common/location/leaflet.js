import { loadScriptOnce } from "/static/js/common/dom.js";

const LEAFLET_SCRIPT_SRC = "/static/vendor/js/leaflet.v1.9.4.min.js";

/**
 * Dynamically loads Leaflet script if not already loaded.
 * @returns {Promise<void>} Promise that resolves when Leaflet is loaded.
 */
const loadLeafletScript = () => {
  return loadScriptOnce(LEAFLET_SCRIPT_SRC, {
    isLoaded: () => typeof window.L !== "undefined",
  });
};

/**
 * Loads and initializes a Leaflet map with an optional marker and popup.
 * @param {string} divId ID of the div element to contain the map.
 * @param {number} lat Latitude coordinate for the map center and marker.
 * @param {number} long Longitude coordinate for the map center and marker.
 * @param {object} options Map options.
 * @returns {Promise<object>} Promise that resolves to the Leaflet map.
 */
export const loadMap = async (divId, lat, long, options = {}) => {
  await loadLeafletScript();

  const map = L.map(divId, {
    zoomControl: false,
    minZoom: 2,
    maxBounds: L.latLngBounds(L.latLng(-90, -180), L.latLng(90, 180)),
    maxBoundsViscosity: 1.0,
  }).setView([lat, long], options.zoom ?? 13);

  const interactive = options.interactive !== false;

  L.tileLayer(
    `https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}${
      L.Browser.retina ? "@2x.png" : ".png"
    }`,
    {
      attribution: "",
      unloadInvisibleTiles: true,
      noWrap: true,
    },
  ).addTo(map);

  if (options.marker !== false) {
    const svgIcon = {
      html: '<div class="svg-icon h-[30px] w-[30px] bg-primary-500 icon-marker"></div>',
      iconSize: [30, 30],
      iconAnchor: [15, 30],
      popupAnchor: [0, -25],
    };

    const icon = L.divIcon({
      ...svgIcon,
      className: "marker-icon",
    });

    const marker = L.marker(L.latLng(lat, long), {
      icon,
      interactive,
      autoPanOnFocus: false,
      bubblingMouseEvents: false,
    });

    marker.addTo(map);

    if (options.popupContent) {
      const popupOptions = {
        autoPan: false,
        closeButton: interactive,
        closeOnClick: interactive,
        className: options.popupClassName,
      };
      if (!interactive) {
        popupOptions.closeButton = false;
        popupOptions.closeOnClick = false;
      }
      marker.bindPopup(options.popupContent, popupOptions);
      if (options.openPopup !== false) {
        marker.openPopup();
      }
    }
  }

  if (!interactive) {
    map.dragging?.disable?.();
    map.touchZoom?.disable?.();
    map.scrollWheelZoom?.disable?.();
    map.doubleClickZoom?.disable?.();
    map.boxZoom?.disable?.();
    map.keyboard?.disable?.();
    map.tap?.disable?.();
  }

  requestAnimationFrame(() => {
    map.invalidateSize();
  });

  return map;
};
