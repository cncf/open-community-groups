import { showErrorAlert } from "/static/js/common/alerts.js";
import { getElementById } from "/static/js/common/dom.js";
import { createMapMarker, loadMap } from "/static/js/common/location/maplibre.js";
import { DEFAULT_MAP_ZOOM, parseCoordinate } from "/static/js/common/location/search-utils.js";

/**
 * Coordinates the map preview used by location search fields.
 */
export class LocationMapPreview {
  /**
   * @param {string} mapElementId DOM id for the map container.
   */
  constructor(mapElementId) {
    this.mapElementId = mapElementId;
    this.map = null;
    this.mapErrorShown = false;
    this.marker = null;
    this.syncPromise = Promise.resolve();
    this.syncRevision = 0;
  }

  /**
   * Remove the current map and marker.
   */
  reset() {
    this.syncRevision += 1;
    this.mapErrorShown = false;
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
    const revision = ++this.syncRevision;
    this.syncPromise = this.syncPromise.catch(() => {}).then(() => this.syncInternal(state, revision));
    return this.syncPromise;
  }

  /**
   * Initialize or update the enabled map/marker with the latest coordinates.
   * @param {Object} state Map preview state.
   * @param {number} revision Scheduled sync revision.
   * @returns {Promise<void>}
   */
  async syncInternal(state, revision = this.syncRevision) {
    if (revision !== this.syncRevision) return;
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
      let map;
      try {
        map = await loadMap(this.mapElementId, lat, lng, {
          zoom,
          interactive: true,
          marker: false,
        });
      } catch {
        if (revision === this.syncRevision && container.isConnected && !this.mapErrorShown) {
          this.mapErrorShown = true;
          showErrorAlert("Unable to load the map preview. You can still enter the location details.");
        }
        return;
      }
      if (!map) return;
      if (revision !== this.syncRevision) {
        map.remove();
        return;
      }
      this.map = map;
      this.mapErrorShown = false;
      map.on("remove", () => {
        this.map = null;
        this.marker = null;
      });
    }

    if (this.marker) {
      this.marker.setLngLat([lng, lat]);
    } else {
      this.marker = createMapMarker([lng, lat]).addTo(this.map);
    }

    const canFitBounds =
      state.shouldFitBounds && Array.isArray(state.mapBoundingBox) && state.mapBoundingBox.length === 4;

    if (canFitBounds) {
      const [south, north, west, east] = state.mapBoundingBox;
      this.map.fitBounds(
        [
          [west, south],
          [east, north],
        ],
        { duration: 0 },
      );
    } else {
      this.map.jumpTo({ center: [lng, lat], zoom });
    }

    this.map.resize();
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
