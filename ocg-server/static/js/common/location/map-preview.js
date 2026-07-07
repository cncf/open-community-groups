import { loadMap } from "/static/js/common/location/leaflet.js";
import { getElementById } from "/static/js/common/dom.js";
import { DEFAULT_MAP_ZOOM, parseCoordinate } from "/static/js/common/location/search-utils.js";

/**
 * Coordinates the Leaflet map preview used by location search fields.
 */
export class LocationMapPreview {
  /**
   * @param {string} mapElementId DOM id for the map container.
   */
  constructor(mapElementId) {
    this.mapElementId = mapElementId;
    this.map = null;
    this.marker = null;
    this.syncPromise = Promise.resolve();
  }

  /**
   * Remove the current Leaflet map and marker.
   */
  reset() {
    if (this.map) {
      this.map.remove();
      this.map = null;
    }
    this.marker = null;
  }

  /**
   * Clean up all map resources.
   */
  destroy() {
    this.reset();
  }

  /**
   * Schedule a map sync so coordinate changes do not overlap.
   * @param {Object} state Map preview state.
   * @returns {Promise<unknown>}
   */
  sync(state) {
    if (!state.mapVisible || !this._hasValidCoordinates(state)) {
      return Promise.resolve();
    }
    this.syncPromise = this.syncPromise.catch(() => {}).then(() => this.syncInternal(state));
    return this.syncPromise;
  }

  /**
   * Initialize or update the enabled map/marker with the latest coordinates.
   * @param {Object} state Map preview state.
   * @returns {Promise<void>}
   */
  async syncInternal(state) {
    if (!this._hasValidCoordinates(state)) {
      this.reset();
      return;
    }

    const container = getElementById(document, this.mapElementId);
    if (!container) return;

    const lat = parseCoordinate(state.latitudeValue);
    const lng = parseCoordinate(state.longitudeValue);
    if (lat === null || lng === null) return;

    const zoom = state.mapZoom || DEFAULT_MAP_ZOOM;
    if (!this.map) {
      this.map = await loadMap(this.mapElementId, lat, lng, {
        zoom,
        interactive: true,
        marker: false,
      });
    }

    if (this.marker) {
      this.marker.setLatLng([lat, lng]);
    } else if (window.L) {
      const icon = L.divIcon({
        html: '<div class="svg-icon h-[30px] w-[30px] bg-primary-500 icon-marker"></div>',
        iconSize: [30, 30],
        iconAnchor: [15, 30],
        popupAnchor: [0, -25],
        className: "marker-icon",
      });
      this.marker = L.marker(L.latLng(lat, lng), {
        icon,
        interactive: false,
        autoPanOnFocus: false,
        bubblingMouseEvents: false,
      }).addTo(this.map);
    }

    const leaflet = window.L;
    const canFitBounds =
      state.shouldFitBounds &&
      Array.isArray(state.mapBoundingBox) &&
      state.mapBoundingBox.length === 4 &&
      leaflet;

    if (canFitBounds) {
      const [south, north, west, east] = state.mapBoundingBox;
      const bounds = leaflet.latLngBounds([south, west], [north, east]);
      this.map.fitBounds(bounds, { animate: false });
    } else {
      this.map.setView([lat, lng], zoom, { animate: false });
    }

    this.map.invalidateSize?.(false);
  }

  /**
   * @param {Object} state Map preview state.
   * @returns {boolean}
   * @private
   */
  _hasValidCoordinates(state) {
    const lat = parseCoordinate(state.latitudeValue);
    const lng = parseCoordinate(state.longitudeValue);
    return lat !== null && lng !== null;
  }
}
