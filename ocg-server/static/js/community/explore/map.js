import { hideLoadingSpinner, showLoadingSpinner, navigateWithHtmx } from "/static/js/common/common.js";
import { fetchData } from "/static/js/community/explore/explore.js";

export class Map {
  /**
   * Initializes the map with Leaflet.js and marker clustering.
   * Uses singleton pattern to ensure only one map instance exists.
   * @param {string} entity - The type of entity to display ('events' or 'groups')
   * @param {object} data - Initial map data containing items to display
   */
  constructor(entity, data) {
    // Check if map is already initialized
    if (Map._instance) {
      Map._instance.entity = entity;
      Map._instance.enabledMoveEnd = false;
      Map._instance.setup(data);
      return Map._instance;
    }

    // Display main loading spinner
    const mainLoading = document.getElementById("main-loading-map");
    if (mainLoading) {
      mainLoading.classList.remove("hidden");
    }

    // Load LeafletJS library
    let script = document.createElement("script");
    script.type = "text/javascript";
    script.src = "/static/vendor/js/leaflet.v1.9.4.min.js";
    document.getElementsByTagName("head")[0].appendChild(script);

    // Load markercluster script
    let markerClusterScript = document.createElement("script");
    markerClusterScript.type = "text/javascript";
    markerClusterScript.src = "/static/vendor/js/leaflet.markercluster.v1.5.3.min.js";

    this.entity = entity;
    this.enabledMoveEnd = false;
    this.tooltipTimers = new WeakMap();

    // Load markercluster library after LeafletJS is loaded
    script.onload = () => {
      document.getElementsByTagName("head")[0].appendChild(markerClusterScript);
    };

    // Setup map after scripts are loaded
    markerClusterScript.onload = () => {
      this.setup(data);
    };

    // Save map instance
    Map._instance = this;
  }

  /**
   * Sets up the Leaflet map instance with tile layers and event listeners.
   * @param {object} data - Map data containing items to display
   */
  setup(data) {
    this.map = L.map("map-box", {
      maxZoom: 20,
      minZoom: 3,
      zoomControl: false,
      maxBounds: L.latLngBounds(L.latLng(-90, -180), L.latLng(90, 180)),
      maxBoundsViscosity: 1.0,
    });

    // Add zoom control to the map on the top right
    L.control
      .zoom({
        position: "topright",
      })
      .addTo(this.map);

    // Load events after the map is loaded
    this.map.on("load", () => {
      this.refresh(true, data);
    });

    // Remove map on unload, invalidating the size and removing event listeners
    this.map.on("unload", () => {
      this.map.invalidateSize();
      this.map.off();
      this.map.remove();
    });

    // Center map view
    this.map.setView([0, 0], 0);

    // Adding the base layer to the map
    L.tileLayer(
      `https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}${
        L.Browser.retina ? "@2x.png" : ".png"
      }`,
      {
        attribution:
          '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors &copy; <a href="https://carto.com/attributions">CARTO</a>',
        subdomains: "abcd",
        maxZoom: 20,
        minZoom: 0,
      },
    ).addTo(this.map);

    // Adding a listener to the map after setting the position to get the bounds
    // when the map is moved (zoom or pan)
    this.map.on("moveend", () => {
      if (this.enabledMoveEnd) {
        this.refresh();
      }
      this.enabledMoveEnd = true;
    });
  }

  /**
   * Refreshes the map by updating markers with new data.
   * @param {boolean} overwriteBounds - Whether to overwrite map bounds with new data
   * @param {object} currentData - Optional current data to use instead of fetching
   */
  async refresh(overwriteBounds = false, currentData = null) {
    let data;
    // If currentData is provided, use it instead of fetching
    // This is useful for initial load when we already have data
    // or when we want to overwrite bounds with a specific bbox
    if (currentData) {
      data = currentData;
    } else {
      // Show loading spinner
      showLoadingSpinner("loading-map");

      // Fetch data based on current map bounds
      try {
        data = await this.fetchLocationData(overwriteBounds);
      } catch (error) {
        // If fetch fails (e.g., due to invalid bbox), hide loading and ignore error
        hideLoadingSpinner("loading-map");
        return;
      }
    }

    if (data) {
      // Get items from data
      let items = [];
      if (this.entity === "events") {
        if (data.events && data.events.length > 0) {
          items = data.events;
        }
      } else if (this.entity === "groups") {
        if (data.groups && data.groups.length > 0) {
          items = data.groups;
        }
      }

      // Refresh map markers
      if (items.length > 0) {
        this.addMarkers(items, overwriteBounds ? data.bbox : null);
      } else {
        // Hide loading spinner
        hideLoadingSpinner("loading-map");
      }
    }
  }

  /**
   * Fetches data from the server based on current map bounds and filters.
   * @param {boolean} overwriteBounds - Whether to include bbox in request
   * @returns {Promise<object>} The fetched data containing items and optional bbox
   */
  async fetchLocationData(overwriteBounds) {
    // Prepare query params
    const params = new URLSearchParams(location.search);

    // Remove view mode and virtual kind from query params
    params.delete("view_mode");
    params.delete("kind", "virtual");

    if (overwriteBounds) {
      // Get bbox to overwrite bounds on first load
      params.append("include_bbox", true);
    } else {
      // Get current bounds from map
      const bounds = this.map.getBounds();

      // Add bounds to query params, normalizing coordinate values to stay within
      // valid ranges. Latitude: -90 to 90, Longitude: -180 to 180. Leaflet can
      // return values outside these ranges when wrapping around or at extreme zoom.
      params.append("bbox_sw_lat", normalizeLatitude(bounds._southWest.lat));
      params.append("bbox_sw_lon", normalizeLongitude(bounds._southWest.lng));
      params.append("bbox_ne_lat", normalizeLatitude(bounds._northEast.lat));
      params.append("bbox_ne_lon", normalizeLongitude(bounds._northEast.lng));
    }

    // Fetch data from the server
    // This will return either events or groups based on the entity type
    // and will include bbox if requested
    const data = await fetchData(this.entity, params.toString());
    return data;
  }

  /**
   * Adds markers to the map with clustering and delayed tooltip functionality.
   * @param {Array} items - Array of items (events or groups) to add as markers
   * @param {object} bbox - Optional bounding box to fit the map view
   */
  addMarkers(items, bbox) {
    // Fit map bounds to the bbox
    if (bbox && checkValidBbox(bbox)) {
      const southWest = L.latLng(bbox.sw_lat, bbox.sw_lon);
      const northEast = L.latLng(bbox.ne_lat, bbox.ne_lon);
      const bounds = L.latLngBounds(southWest, northEast);
      this.map.flyToBounds(bounds, { animate: false, noMoveStart: true });
    }

    // SVG icon for markers
    const svgIcon = {
      html: '<div class="svg-icon h-[30px] w-[30px] bg-primary-500 hover:bg-primary-900 icon-marker"></div>',
      iconSize: [30, 30],
      iconAnchor: [15, 30],
      popupAnchor: [0, -25],
    };

    // Create marker cluster group
    const markers = window.L.markerClusterGroup({
      showCoverageOnHover: false,
    });

    // Add markers
    items.forEach((item) => {
      const latitude = item.latitude;
      const longitude = item.longitude;

      // Skip items without valid coordinates
      if (
        typeof latitude == "undefined" ||
        typeof longitude == "undefined" ||
        latitude == 0 ||
        longitude == 0
      ) {
        return;
      }

      // Create icon for marker
      const icon = L.divIcon({
        ...svgIcon,
        className: `marker-${item.slug}`,
      });

      // Create marker
      const marker = L.marker(L.latLng(latitude, longitude), {
        icon: icon,
        autoPanOnFocus: false,
        bubblingMouseEvents: true,
      });

      if (item.popover_html) {
        const tooltipContent = `<div class="flex flex-1 flex-row items-center min-w-[370px]">${item.popover_html}</div>`;
        const tooltipOptions = {
          direction: "top",
          permanent: false,
          sticky: true,
          offset: [0, 0],
          opacity: 1,
        };

        /** Starts a 300ms delay before opening the tooltip. */
        const startTooltipTimer = () => {
          clearTimeout(this.tooltipTimers.get(marker));
          const timer = setTimeout(() => {
            if (!marker.getTooltip()) {
              marker.bindTooltip(tooltipContent, tooltipOptions);
            }
            marker.openTooltip();
          }, 300);
          this.tooltipTimers.set(marker, timer);
        };

        /** Clears the tooltip delay timer. */
        const stopTooltipTimer = () => {
          clearTimeout(this.tooltipTimers.get(marker));
          this.tooltipTimers.delete(marker);
        };

        marker.on("mouseover", startTooltipTimer);
        marker.on("mouseout", () => {
          stopTooltipTimer();
          if (marker.getTooltip()) {
            marker.closeTooltip();
            marker.unbindTooltip();
          }
        });

        marker.on("remove", () => {
          stopTooltipTimer();
          if (marker.getTooltip()) {
            marker.unbindTooltip();
          }
        });
      }

      // Add click handler to navigate to item page
      marker.on("click", () => {
        let url;
        if (this.entity === "events") {
          url = `/${item.community_name}/group/${item.group_slug}/event/${item.slug}`;
        } else if (this.entity === "groups") {
          url = `/${item.community_name}/group/${item.slug}`;
        }
        navigateWithHtmx(url);
      });

      // Add marker to the marker cluster group
      markers.addLayer(marker);
    });

    // Add marker cluster group to the map
    this.map.addLayer(markers);

    // Hide loading spinner
    hideLoadingSpinner("loading-map");
  }
}

/**
 * Normalizes a latitude value to be within the -90 to 90 range.
 * @param {number} lat - Latitude value to normalize
 * @returns {number} Normalized latitude value between -90 and 90
 */
function normalizeLatitude(lat) {
  // Clamp latitude to valid range (map projections don't wrap vertically)
  return Math.max(-90, Math.min(90, lat));
}

/**
 * Normalizes a longitude value to be within the -180 to 180 range.
 * Leaflet can return values outside this range when wrapping around the map.
 * @param {number} lng - Longitude value to normalize
 * @returns {number} Normalized longitude value between -180 and 180
 */
function normalizeLongitude(lng) {
  // Normalize to -180 to 180 range using modulo operation
  lng = ((lng + 180) % 360) - 180;
  // Handle negative modulo results
  if (lng < -180) {
    lng += 360;
  }
  return lng;
}

/**
 * Checks if a bounding box object contains valid, non-identical coordinates.
 * @param {object} bbox - Bounding box object with coordinate properties
 * @returns {boolean} True if bbox is valid (coordinates are not all the same)
 */
function checkValidBbox(bbox) {
  const allEqual = new Set(Object.values(bbox)).size === 1;
  return !allEqual;
}
