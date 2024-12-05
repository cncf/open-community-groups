import { checkIfScriptIsLoaded, fetchData } from './common.js';

// Map
let map = null;

// Load map with events or groups
export const loadMap = (entity) => {
  // Render map on `map-box` element
  const renderMap = () => {
    // Remove previous map
    if (map) {
      map.remove();
    }

    // Initialize map
    map = L.map('map-box', {
      maxZoom: 20,
      minZoom: 3,
      zoomControl: false,
    });

    // Create a layer group to add markers
    const layerGroup = L.layerGroup();

    // Add zoom control to the map on the top right
    L.control.zoom({
      position: 'topright'
    }).addTo(map);

    // Load map data
    const loadMapData = async (currentMap, overwriteBounds) => {
      // Get current bounds
      const bounds = currentMap.getBounds();

      // Get URL params
      const params = new URLSearchParams(location.search);
      // Remove view mode and
      params.delete('view_mode');
      params.delete('kind', 'virtual');

      // Add limit and offset
      params.append('limit', 100);
      params.append('offset', 0);

      // Get bbox to overwrite bounds on first load
      if (overwriteBounds) {
        params.append('include_bbox', true);
      // Get bounds from map
      } else {
        params.append('bbox_sw_lat', bounds._southWest.lat);
        params.append('bbox_sw_lon', bounds._southWest.lng);
        params.append('bbox_ne_lat', bounds._northEast.lat);
        params.append('bbox_ne_lon', bounds._northEast.lng);
      }

      // Fetch data
      const data = await fetchData(entity, params.toString());

      // If data is available
      if (data) {
        // Fit map bounds on first load
        if (overwriteBounds && data.bbox) {
          const southWest = L.latLng(data.bbox.sw_lat, data.bbox.sw_lon);
          const northEast = L.latLng(data.bbox.ne_lat, data.bbox.ne_lon);
          const bounds = L.latLngBounds(southWest, northEast);
          currentMap.fitBounds(bounds);
        }

        // SVG icon for markers
        const svgIcon = {
          html: '<svg stroke="currentColor" fill="currentColor" stroke-width="0" viewBox="0 0 20 20" aria-hidden="true" xmlns="http://www.w3.org/2000/svg"><path fill-rule="evenodd" d="M5.05 4.05a7 7 0 119.9 9.9L10 18.9l-4.95-4.95a7 7 0 010-9.9zM10 11a2 2 0 100-4 2 2 0 000 4z" clip-rule="evenodd"></path></svg>',
          iconSize: [30, 30],
          iconAnchor: [15, 30],
          popupAnchor: [0, -25]
        };

        // New items
        let newItems = [];

        if (entity === 'events') {
          if (data.events && data.events.length > 0) {
            newItems = data.events;
          }
        } else if (entity === 'groups') {
          if (data.groups && data.groups.length > 0) {
            newItems = data.groups;
          }
        }

        if (newItems.length > 0) {
          // Clear previous markers for the layer group
          if (currentMap.hasLayer(layerGroup)) {
            layerGroup.clearLayers();
          }

          // Add new markers
          newItems.forEach((item) => {
            if (typeof(item.latitude) == "undefined" || typeof(item.longitude) == "undefined" || item.latitude == 0 || item.longitude == 0) {
              return;
            }

            // Create marker
            const icon = L.divIcon({...svgIcon, className: `text-primary-500 marker-${item.slug}`});
            const marker = L.marker(L.latLng(item.latitude, item.longitude), { icon: icon, bubblingMouseEvents: true });

            // Add popup to marker
            marker.bindPopup(`<div class="flex flex-1 flex-row items-center min-w-[370px]">${item.popover_html}</div>`);

            // Add marker to layer group
            layerGroup.addLayer(marker);
            currentMap.addLayer(layerGroup);
          });
        }
      }
    }

    // Load events after the map is loaded
    map.on('load', () => {
      loadMapData(map, true);
    });

    // Setting the position of the map: lat/long and zoom level
    // TODO - Get the user's location and set the map to that location
    map.setView([0, 0], 9);

    // Adding the base layer to the map
    L.tileLayer(`https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}${L.Browser.retina ? '@2x.png' : '.png'}`, {
      attribution: '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors &copy; <a href="https://carto.com/attributions">CARTO</a>',
      subdomains: 'abcd',
      maxZoom: 20,
      minZoom: 0
    }).addTo(map);

    // Adding a listener to the map after setting the position to get the bounds
    // when the map is moved (zoom or pan)
    map.on('moveend', () => {
      loadMapData(map);
    });
  };

  // Load LeafletJS library if not loaded
  if (!checkIfScriptIsLoaded('leaflet')) {
    let script = document.createElement('script');
    script.type = 'text/javascript';
    script.src = 'https://cdnjs.cloudflare.com/ajax/libs/leaflet/1.9.4/leaflet.js';
    document.getElementsByTagName('head')[0].appendChild(script);
    script.onload = () => {
      renderMap();
    };
  // Render map if script is already loaded
  } else {
    renderMap();
  }
}
