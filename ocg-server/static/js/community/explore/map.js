import { fetchData } from "./explore.js";

export class Map {
  // Initialize map.
  constructor(entity) {
    // Check if map is already initialized
    if (Map._instance) {
      // Invalidate map size to fix the map container
      Map._instance.map.invalidateSize();

      Map._instance.entity = entity;
      Map._instance.setup();
      return Map._instance;
    }

    // Load LeafletJS library
    let script = document.createElement("script");
    script.type = "text/javascript";
    script.src = "https://cdnjs.cloudflare.com/ajax/libs/leaflet/1.9.4/leaflet.js";
    document.getElementsByTagName("head")[0].appendChild(script);

    this.entity = entity;

    // Setup map after script is loaded
    script.onload = () => {
      this.setup();
    };

    // Save map instance
    Map._instance = this;
  }

  // Setup map instance.
  setup() {
    this.map = L.map("map-box", {
      maxZoom: 20,
      minZoom: 3,
      zoomControl: false,
    });

    // Create a layer group to add markers
    this.layerGroup = L.layerGroup();

    // Add zoom control to the map on the top right
    L.control
      .zoom({
        position: "topright",
      })
      .addTo(this.map);

    // Load events after the map is loaded
    this.map.on("load", () => {
      this.refresh(true);
    });

    this.map.on("unload", () => {
      this.layerGroup.clearLayers();
    });

    // Setting the position of the map: lat/long and zoom level
    // TODO - Get the user's location and set the map to that location
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
      this.refresh();
    });
  }

  // Refresh map, updating the markers.
  async refresh(overwriteBounds) {
    const data = await this.fetchData(overwriteBounds);

    fixMapBoxClasses();

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
      }
    }
  }

  // Fetch data from the server.
  async fetchData(overwriteBounds) {
    // Prepare query params
    const params = new URLSearchParams(location.search);

    // Remove view mode and virtual kind from query params
    params.delete("view_mode");
    params.delete("kind", "virtual");

    // Add limit and offset
    params.append("limit", 100);
    params.append("offset", 0);

    if (overwriteBounds) {
      // Get bbox to overwrite bounds on first load
      params.append("include_bbox", true);
    } else {
      // Get current bounds from map
      const bounds = this.map.getBounds();

      // Add bounds to query params
      params.append("bbox_sw_lat", bounds._southWest.lat);
      params.append("bbox_sw_lon", bounds._southWest.lng);
      params.append("bbox_ne_lat", bounds._northEast.lat);
      params.append("bbox_ne_lon", bounds._northEast.lng);
    }

    // Fetch data
    const data = await fetchData(this.entity, params.toString());
    return data;
  }

  // Add markers to the map.
  addMarkers(items, bbox) {
    // Fit map bounds to the bbox
    if (bbox) {
      const southWest = L.latLng(bbox.sw_lat, bbox.sw_lon);
      const northEast = L.latLng(bbox.ne_lat, bbox.ne_lon);
      const bounds = L.latLngBounds(southWest, northEast);
      this.map.fitBounds(bounds);
    }

    // SVG icon for markers
    const svgIcon = {
      html: '<div class="svg-icon h-[30px] w-[30px] bg-primary-500 hover:bg-primary-900 icon-marker"></div>',
      iconSize: [30, 30],
      iconAnchor: [15, 30],
      popupAnchor: [0, -25],
    };

    // Clear previous markers for the layer group
    if (this.map.hasLayer(this.layerGroup)) {
      this.layerGroup.clearLayers();
    }

    // Add markers
    items.forEach((item) => {
      // Skip items without coordinates
      if (
        typeof item.latitude == "undefined" ||
        typeof item.longitude == "undefined" ||
        item.latitude == 0 ||
        item.longitude == 0
      ) {
        return;
      }

      // Create icon for marker
      const icon = L.divIcon({
        ...svgIcon,
        className: `marker-${item.slug}`,
      });

      // Create marker
      const marker = L.marker(L.latLng(item.latitude, item.longitude), {
        icon: icon,
        bubblingMouseEvents: true,
      });

      // Add popup to marker
      marker.bindPopup(
        `<div class="flex flex-1 flex-row items-center min-w-[370px]">${item.popover_html}</div>`,
      );

      // Add marker to layer group
      this.layerGroup.addLayer(marker);

      // Add layer group to the map
      this.map.addLayer(this.layerGroup);
    });
  }
}

// Fix map box classes (issue to refresh map on filters changes).
const fixMapBoxClasses = () => {
  const mapBox = document.getElementById("map-box");
  if (mapBox && !mapBox.classList.contains("leaflet-container")) {
    const classes =
      "leaflet-container leaflet-touch leaflet-retina leaflet-fade-anim leaflet-grab leaflet-touch-drag leaflet-touch-zoom".split(
        " ",
      );
    mapBox.classList.add(...classes);
  }
};
