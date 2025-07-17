/**
 * Shows a loading spinner by adding the 'is-loading' class to the element.
 * @param {string} id - The ID of the element to show loading spinner for
 */
export const showLoadingSpinner = (id) => {
  const content = document.getElementById(id);
  if (content) {
    content.classList.add("is-loading");
  }
};

/**
 * Hides a loading spinner by removing the 'is-loading' class from the element.
 * @param {string} id - The ID of the element to hide loading spinner for
 */
export const hideLoadingSpinner = (id) => {
  const content = document.getElementById(id);
  if (content) {
    content.classList.remove("is-loading");
  }
};

/**
 * Toggles the visibility of the mobile navigation bar and its backdrop.
 * Shows/hides both the mobile navbar and backdrop by toggling the 'hidden' class.
 */
export const toggleMobileNavbarVisibility = () => {
  const navbarMobile = document.getElementById("navbar-mobile");
  if (navbarMobile) {
    navbarMobile.classList.toggle("hidden");
  }
  const navbarBackdrop = document.getElementById("navbar-backdrop");
  if (navbarBackdrop) {
    navbarBackdrop.classList.toggle("hidden");
  }
};

/**
 * Toggles the visibility of a modal by adding or removing the 'hidden' class.
 * @param {string} modalId - The ID of the modal element to toggle
 */
export const toggleModalVisibility = (modalId) => {
  const modal = document.getElementById(modalId);
  if (modal) {
    modal.classList.toggle("hidden");
  }
};

/**
 * Loads and initializes a Leaflet map with a marker and popup.
 * @param {string} divId - The ID of the div element to contain the map
 * @param {string} title - The title text to display in the marker popup
 * @param {number} lat - The latitude coordinate for the map center and marker
 * @param {number} long - The longitude coordinate for the map center and marker
 */
export const loadMap = (divId, title, lat, long) => {
  const map = L.map(divId).setView([lat, long], 13);

  L.tileLayer(
    `https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}${
      L.Browser.retina ? "@2x.png" : ".png"
    }`,
    {
      attribution:
        '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors &copy; <a href="https://carto.com/attributions">CARTO</a>',
    },
  ).addTo(map);

  // SVG icon for markers
  const svgIcon = {
    html: '<div class="svg-icon h-[30px] w-[30px] bg-primary-500 hover:bg-primary-900 icon-marker"></div>',
    iconSize: [30, 30],
    iconAnchor: [15, 30],
    popupAnchor: [0, -25],
  };

  // Create icon for marker
  const icon = L.divIcon({
    ...svgIcon,
    className: "marker-icon",
  });

  // Create marker
  const marker = L.marker(L.latLng(lat, long), {
    icon: icon,
    autoPanOnFocus: false,
    bubblingMouseEvents: true,
  });

  // Add popup to marker
  marker.addTo(map).bindPopup(title).openPopup();
};
