import { showErrorAlert } from "/static/js/common/alerts.js";
import { navigateWithHtmx } from "/static/js/common/htmx-navigation.js";
import { hideLoadingSpinner, showLoadingSpinner } from "/static/js/common/loading-spinner.js";
import { createMapMarker, loadMap, loadMapScript } from "/static/js/common/location/maplibre.js";
import {
  createLatestRequest,
  fetchWidgetData,
  isAbortError,
  reportFetchError,
} from "/static/js/community/explore/results.js";
import {
  bindExploreCardTooltip,
  bindExploreCardTrigger,
  createCardController,
  createExploreCardLoader,
  getExploreItemUrl,
  isPlainLeftClick,
  loadWidgetScripts,
  renderExploreCard,
  syncExploreCardTooltip,
  updateTruncationNotice,
} from "/static/js/community/explore/widgets.js";

const LOCATIONS_SOURCE_ID = "explore-locations";
const MAIN_LOADING_MAP_ID = "main-loading-map";
const MAP_ELEMENT_ID = "map-box";
const MAP_ERROR_MESSAGE = "Unable to load the map. Switch to list view or reload the page to try again.";
const MAP_LOADING_ID = "loading-map";
const MAP_STATUS = Object.freeze({
  empty: "empty",
  error: "error",
  idle: "idle",
  loading: "loading",
  ready: "ready",
});
const TRUNCATION_NOTICE_SELECTOR = "[data-explore-truncation-notice]";

/**
 * Community explore map with native clustering and custom HTML markers.
 */
export class Map {
  /**
   * Reuses the explore controller when HTMX replaces the map view.
   * @param {string} entity Explore entity type ('events' or 'groups').
   * @param {object} data Initial map data containing items to display.
   */
  constructor(entity, data) {
    // Check if map is already initialized
    const controller = Map._instance || this;
    if (!Map._instance) {
      this.markers = new globalThis.Map();
      this.pendingSourceUpdate = null;
      this.dataRevision = 0;
      this.request = createLatestRequest();
      this.setupPromise = Promise.resolve();
      this.state = { status: MAP_STATUS.idle };

      // Save map instance
      Map._instance = this;
    }

    // Keep cached cards while the entity stays the same
    if (controller.cardLoader?.entity !== entity) {
      controller.cardLoader = createExploreCardLoader(entity, "map");
    }
    controller.entity = entity;
    controller.enabledMoveEnd = false;
    loadWidgetScripts({
      mainLoadingId: MAIN_LOADING_MAP_ID,
      loadScripts: loadMapScript,
      onReady: () => {
        controller.setupPromise = controller.setupPromise.catch(() => {}).then(() => controller.setup(data));
        return controller.setupPromise;
      },
    });
    return controller;
  }

  /**
   * Updates the source while retaining markers until the replacement is ready.
   * @param {Array} items Explore items with coordinates.
   * @param {object} truncation Notice metadata committed once the source update completes.
   * @param {number} requestId Request whose results are drawn.
   */
  addMarkers(items, truncation, requestId) {
    this.markers.forEach((entry) => {
      const element = entry.marker.getElement();
      if (element instanceof HTMLButtonElement) {
        if (document.activeElement === element) this.map.getCanvas().focus({ preventScroll: true });
        element.disabled = true;
      }
    });
    this.items = items.filter(hasValidCoordinates);
    this.dataRevision += 1;
    this.pendingSourceUpdate = { failed: false, requestId, truncation };
    this.map.getSource(LOCATIONS_SOURCE_ID).setData({
      type: "FeatureCollection",
      features: this.items.map((item, index) => ({
        type: "Feature",
        properties: { index, revision: this.dataRevision },
        geometry: {
          type: "Point",
          coordinates: [Number(item.longitude), Number(item.latitude)],
        },
      })),
    });
  }

  /**
   * Removes HTML markers, popups, and pending card controllers.
   */
  clearMarkers() {
    if (this.clusterPopup?.getElement()?.contains(document.activeElement)) {
      this.map?.getCanvas().focus({ preventScroll: true });
    }
    this.markers.forEach((entry) => this.removeMarker(entry));
    this.markers.clear();
    this.clusterPopup?.remove();
    this.clusterPopup = null;
  }

  /**
   * Creates a clickable cluster count using the existing map colors.
   * @param {object} feature Cluster feature returned by the source.
   * @returns {object} Marker entry.
   */
  createClusterMarker(feature) {
    const element = document.createElement("button");
    element.type = "button";
    element.className = "map-cluster";
    element.setAttribute("aria-label", `Show ${feature.properties.point_count} locations`);
    const count = document.createElement("span");
    count.textContent = feature.properties.point_count_abbreviated;
    element.append(count);
    element.addEventListener("click", () => this.expandCluster(feature, element));
    return {
      marker: createMapMarker(feature.geometry.coordinates, { element, anchor: "center" }),
    };
  }

  /**
   * Creates a linked pin with a delayed hover or keyboard-focus card loaded on demand.
   * @param {object} feature Point feature returned by the source.
   * @returns {object} Marker entry with its card controller.
   */
  createItemMarker(feature) {
    const item = this.items[feature.properties.index];
    const name = item.name || item.slug;
    const element = createItemLink(this.entity, item);
    element.className = `marker-${item.slug}`;
    element.setAttribute("aria-label", name);
    const pin = document.createElement("div");
    pin.className = "svg-icon h-[30px] w-[30px] bg-primary-500 hover:bg-primary-900 icon-marker";
    pin.setAttribute("aria-hidden", "true");
    element.replaceChildren(pin);
    const marker = createMapMarker([Number(item.longitude), Number(item.latitude)], { element });
    const popup = new maplibregl.Popup({
      className: "explore-map-tooltip",
      closeButton: false,
      closeOnClick: false,
      focusAfterOpen: false,
      maxWidth: "none",
      offset: 30,
    });
    const tooltipId = `explore-map-tooltip-${this.dataRevision}-${feature.properties.index}`;
    let releaseTooltip = null;

    // Render the card in a non-interactive tooltip described by the pin
    const controller = createCardController({
      item,
      loader: this.cardLoader,
      close: () => {
        releaseTooltip?.();
        releaseTooltip = null;
        popup.remove();
        element.removeAttribute("aria-describedby");
      },
      render: (result) => {
        if (!this.map) return;
        popup.setHTML(renderExploreCard(result, name));
        if (!popup.isOpen()) popup.setLngLat(marker.getLngLat()).addTo(this.map);
        const tooltip = popup.getElement();
        syncExploreCardTooltip({ result, tooltip, tooltipId, trigger: element });
        releaseTooltip ||= bindExploreCardTooltip(tooltip, element, controller);
      },
    });
    const releaseTrigger = bindExploreCardTrigger(element, controller);
    return { controller, marker, popup, releaseTrigger };
  }

  /**
   * Zooms into a cluster or lists locations that cannot separate at maximum zoom.
   * @param {object} feature Cluster feature returned by the source.
   * @param {HTMLButtonElement} element Cluster button.
   */
  async expandCluster(feature, element) {
    if (element.disabled || feature.properties.revision !== this.dataRevision) return;
    const map = this.map;
    const revision = this.dataRevision;
    const source = map.getSource(LOCATIONS_SOURCE_ID);
    const clusterId = feature.properties.cluster_id;
    const clusterHadFocus = document.activeElement === element;
    element.disabled = true;
    if (clusterHadFocus) map.getCanvas().focus({ preventScroll: true });
    try {
      const zoom = await source.getClusterExpansionZoom(clusterId);
      if (map !== this.map || revision !== this.dataRevision) return;
      if (map.getZoom() < map.getMaxZoom()) {
        map.easeTo({ center: feature.geometry.coordinates, zoom: Math.min(zoom, map.getMaxZoom()) });
        return;
      }

      const leaves = await source.getClusterLeaves(clusterId, feature.properties.point_count, 0);
      if (map !== this.map || revision !== this.dataRevision) return;
      const list = document.createElement("ul");
      list.className = "max-h-60 overflow-y-auto space-y-2 p-2";
      leaves.forEach((leaf) => {
        const listItem = document.createElement("li");
        const link = createItemLink(this.entity, this.items[leaf.properties.index]);
        link.className = "block underline";
        listItem.append(link);
        list.append(listItem);
      });
      this.clusterPopup?.remove();
      const popup = new maplibregl.Popup({ maxWidth: "320px" })
        .setLngLat(feature.geometry.coordinates)
        .setDOMContent(list)
        .addTo(map);
      const popupElement = popup.getElement();
      const handleKeydown = (event) => {
        if (event.key === "Escape") {
          event.preventDefault();
          event.stopPropagation();
          popup.remove();
        }
      };
      popupElement.addEventListener("keydown", handleKeydown);
      popup.on("close", () => {
        popupElement.removeEventListener("keydown", handleKeydown);
        if (this.clusterPopup === popup) this.clusterPopup = null;
        if (
          element.isConnected &&
          (document.activeElement === document.body || popupElement.contains(document.activeElement))
        ) {
          element.focus();
        }
      });
      this.clusterPopup = popup;
    } catch {
      if (map === this.map && revision === this.dataRevision) {
        this.setStatus(MAP_STATUS.error);
        showErrorAlert("Unable to expand these locations. Please try again.");
      }
    } finally {
      element.disabled = false;
    }
  }

  /**
   * Fetches every location in view using the current filters and map bounds.
   * @param {AbortSignal} signal Signal aborting the request.
   * @returns {Promise<object>} Minimal explore response payload.
   */
  async fetchLocationData(signal) {
    const params = new URLSearchParams(location.search);
    params.set("view_mode", "map");
    params.delete("kind", "virtual");

    const bounds = this.map.getBounds();
    const southWest = bounds.getSouthWest();
    const northEast = bounds.getNorthEast();
    params.append("bbox_sw_lat", normalizeLatitude(southWest.lat));
    params.append("bbox_sw_lon", normalizeLongitude(southWest.lng));
    params.append("bbox_ne_lat", normalizeLatitude(northEast.lat));
    params.append("bbox_ne_lon", normalizeLongitude(northEast.lng));
    return fetchWidgetData(this.entity, params.toString(), { signal });
  }

  /**
   * Checks whether the map is still mounted in the document.
   * @returns {boolean} Whether results can be applied.
   */
  isAttached() {
    return Boolean(this.map?.getContainer()?.isConnected);
  }

  /**
   * Refreshes locations without letting older requests replace newer results.
   * @param {object|null} currentData Optional data instead of a network request.
   */
  async refresh(currentData = null) {
    // Replace any pending request with this one
    const { id: requestId, signal } = this.request.start();
    this.setStatus(MAP_STATUS.loading);

    // Fetch the locations in view unless the data was provided
    let data = currentData;
    if (!data) {
      try {
        data = await this.fetchLocationData(signal);
      } catch (error) {
        if (this.request.isCurrent(requestId) && !isAbortError(error) && this.isAttached()) {
          this.setStatus(MAP_STATUS.error);
          reportFetchError(error);
        }
        return;
      }
    }

    // Ignore results of replaced requests or removed maps
    if (!this.request.isCurrent(requestId) || !this.isAttached()) return;
    if (!data) {
      this.setStatus(MAP_STATUS.error);
      return;
    }

    // Draw every returned location and keep the notice metadata for the source update
    const items = data[this.entity] || [];
    this.addMarkers(
      items,
      {
        shown: items.length,
        total: data.total ?? items.length,
        truncated: Boolean(data.truncated),
      },
      requestId,
    );
  }

  /**
   * Releases one marker and its card.
   * @param {object} entry Cached marker entry.
   */
  removeMarker(entry) {
    if (entry.marker.getElement() === document.activeElement) {
      this.map?.getCanvas().focus({ preventScroll: true });
    }
    entry.controller?.destroy();
    entry.releaseTrigger?.();
    entry.popup?.remove();
    entry.marker.remove();
  }

  /**
   * Stores the map status and updates loading indicators.
   * @param {string} status Map status.
   */
  setStatus(status) {
    this.state = { status };
    if (status === MAP_STATUS.loading) {
      showLoadingSpinner(MAP_LOADING_ID);
    } else {
      hideLoadingSpinner(MAP_LOADING_ID);
      document.getElementById(MAIN_LOADING_MAP_ID)?.classList.add("hidden");
    }
  }

  /**
   * Creates the map, clustered GeoJSON source, and viewport listeners.
   * @param {object} data Initial explore response.
   */
  async setup(data) {
    this.map?.remove();
    const container = document.getElementById(MAP_ELEMENT_ID);
    if (!container) return;
    this.enabledMoveEnd = false;
    let map;
    try {
      map = await loadMap(MAP_ELEMENT_ID, 0, 0, {
        bounds: getMapBounds(data?.bbox),
        marker: false,
        minZoom: 2,
        navigationControl: true,
        zoom: 3,
      });
    } catch {
      if (container.isConnected && document.getElementById(MAP_ELEMENT_ID) === container) {
        this.setStatus(MAP_STATUS.error);
        showErrorAlert(MAP_ERROR_MESSAGE, false, true);
      }
      return;
    }
    if (!map) return;
    this.map = map;
    let mapErrorShown = false;
    let mapLoaded = false;
    map.on("load", () => {
      mapLoaded = true;
      map.addSource(LOCATIONS_SOURCE_ID, {
        type: "geojson",
        data: { type: "FeatureCollection", features: [] },
        cluster: true,
        clusterRadius: 80,
        maxzoom: map.getMaxZoom() + 1,
        clusterMaxZoom: map.getMaxZoom(),
        clusterProperties: { revision: ["max", ["get", "revision"]] },
      });
      // A source layer keeps tiles loaded while HTML markers display the features.
      map.addLayer({
        id: LOCATIONS_SOURCE_ID,
        type: "circle",
        source: LOCATIONS_SOURCE_ID,
        paint: { "circle-radius": 1, "circle-opacity": 0 },
      });
      this.refresh(data);
      this.enabledMoveEnd = true;
    });
    map.on("moveend", () => {
      if (this.enabledMoveEnd) this.refresh();
    });
    map.on("render", () => this.syncMarkers());
    map.on("error", (event) => {
      if (mapLoaded) {
        if (event?.sourceId === LOCATIONS_SOURCE_ID && this.pendingSourceUpdate) {
          this.pendingSourceUpdate.failed = true;
          if (this.request.isCurrent(this.pendingSourceUpdate.requestId)) this.setStatus(MAP_STATUS.error);
        }
        return;
      }
      this.setStatus(MAP_STATUS.error);
      if (!mapErrorShown) {
        mapErrorShown = true;
        showErrorAlert(MAP_ERROR_MESSAGE, false, true);
      }
    });
    map.on("remove", () => {
      this.request.cancel();
      this.pendingSourceUpdate = null;
      this.clearMarkers();
      this.map = null;
    });
  }

  /**
   * Syncs visible HTML markers with the source's clustered features.
   */
  syncMarkers() {
    if (this.pendingSourceUpdate?.failed) return;
    if (!this.map?.getSource(LOCATIONS_SOURCE_ID) || !this.map.isSourceLoaded(LOCATIONS_SOURCE_ID)) return;
    const focusedMarker = [...this.markers.values()].find(
      (entry) => entry.marker.getElement() === document.activeElement,
    );
    const focusedLocationUrl = focusedMarker?.marker.getElement().getAttribute("href");
    const visibleIds = new Set();
    const bounds = this.map.getBounds();
    this.map.querySourceFeatures(LOCATIONS_SOURCE_ID).forEach((feature) => {
      const properties = feature.properties;
      if (properties.revision !== this.dataRevision || !bounds.contains(feature.geometry.coordinates)) return;
      const featureId = properties.cluster ? `cluster-${properties.cluster_id}` : `item-${properties.index}`;
      const id = `${properties.revision}-${featureId}`;
      if (visibleIds.has(id)) return;
      visibleIds.add(id);
      if (!this.markers.has(id)) {
        const entry = properties.cluster ? this.createClusterMarker(feature) : this.createItemMarker(feature);
        entry.marker.addTo(this.map);
        this.markers.set(id, entry);
      }
    });
    if (this.pendingSourceUpdate) {
      if (this.clusterPopup?.getElement()?.contains(document.activeElement)) {
        this.map.getCanvas().focus({ preventScroll: true });
      }
      this.clusterPopup?.remove();
      this.clusterPopup = null;
    }
    this.markers.forEach((entry, id) => {
      if (!visibleIds.has(id)) {
        this.removeMarker(entry);
        this.markers.delete(id);
      }
    });
    if (focusedLocationUrl && document.activeElement === this.map.getCanvas()) {
      const replacement = [...this.markers.values()].find(
        (entry) => entry.marker.getElement().getAttribute("href") === focusedLocationUrl,
      );
      replacement?.marker.getElement().focus({ preventScroll: true });
    }
    if (this.pendingSourceUpdate) {
      updateTruncationNotice(
        document.querySelector(TRUNCATION_NOTICE_SELECTOR),
        this.pendingSourceUpdate.truncation,
      );
      if (this.request.isCurrent(this.pendingSourceUpdate.requestId)) {
        this.setStatus(this.items.length ? MAP_STATUS.ready : MAP_STATUS.empty);
      }
      this.pendingSourceUpdate = null;
    }
  }
}

/**
 * Builds an accessible location link while preserving HTMX navigation.
 * @param {string} entity Explore entity type.
 * @param {object} item Explore item.
 * @returns {HTMLAnchorElement} Location link.
 */
const createItemLink = (entity, item) => {
  const link = document.createElement("a");
  link.setAttribute("role", "link");
  const url = getExploreItemUrl(entity, item);
  link.textContent = item.name || item.slug;
  if (url) {
    link.href = url;
    link.addEventListener("click", (event) => {
      if (!isPlainLeftClick(event)) return;
      event.preventDefault();
      navigateWithHtmx(url);
    });
  }
  return link;
};

/**
 * Converts response bounds to MapLibre's longitude-first coordinate order.
 * @param {object} bbox Optional response bounding box.
 * @returns {number[][]|undefined} Map bounds when the response has an extent.
 */
const getMapBounds = (bbox) => {
  if (!bbox || new Set(Object.values(bbox)).size === 1) return undefined;
  return [
    [bbox.sw_lon, bbox.sw_lat],
    [bbox.ne_lon, bbox.ne_lat],
  ];
};

/**
 * Checks for present, finite, in-range coordinates used by explore locations.
 * @param {object} item Explore item.
 * @returns {boolean} Whether a marker can be rendered.
 */
const hasValidCoordinates = (item) =>
  isCoordinateInRange(item.latitude, 90) && isCoordinateInRange(item.longitude, 180);

/**
 * Checks that a coordinate is present, finite, and within its absolute limit.
 * @param {unknown} value Coordinate value.
 * @param {number} limit Maximum absolute value.
 * @returns {boolean} Whether the coordinate is usable.
 */
const isCoordinateInRange = (value, limit) => {
  if (value === null || value === undefined || value === "") return false;
  const coordinate = Number(value);
  return Number.isFinite(coordinate) && Math.abs(coordinate) <= limit;
};

/**
 * Clamps latitude to the server's accepted range.
 * @param {number} latitude Latitude.
 * @returns {number} Normalized latitude.
 */
const normalizeLatitude = (latitude) => Math.max(-90, Math.min(90, latitude));

/**
 * Clamps longitude to the server's accepted range without wrapping world edges.
 * @param {number} longitude Longitude.
 * @returns {number} Normalized longitude.
 */
const normalizeLongitude = (longitude) => Math.max(-180, Math.min(180, longitude));
