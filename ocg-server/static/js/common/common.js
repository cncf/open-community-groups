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
 * Dynamically loads Leaflet script if not already loaded.
 * @returns {Promise} Promise that resolves when Leaflet is loaded
 */
const loadLeafletScript = () => {
  return new Promise((resolve, reject) => {
    // Check if Leaflet is already loaded
    if (window.L) {
      resolve();
      return;
    }

    // Create and load the Leaflet script
    const script = document.createElement("script");
    script.type = "text/javascript";
    script.src = "/static/vendor/js/leaflet.v1.9.4.min.js";
    script.onload = resolve;
    script.onerror = reject;
    document.head.appendChild(script);
  });
};

/**
 * Loads and initializes a Leaflet map with a marker and popup.
 * Dynamically loads Leaflet if not already present.
 * @param {string} divId - The ID of the div element to contain the map
 * @param {number} lat - The latitude coordinate for the map center and marker
 * @param {number} long - The longitude coordinate for the map center and marker
 * @returns {Promise} Promise that resolves when the map is loaded
 */
export const loadMap = async (divId, lat, long) => {
  // Ensure Leaflet is loaded
  await loadLeafletScript();

  const map = L.map(divId, { zoomControl: false }).setView([lat, long], 13);

  L.tileLayer(
    `https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}${
      L.Browser.retina ? "@2x.png" : ".png"
    }`,
    {
      attribution: "",
      unloadInvisibleTiles: true,
    },
  ).addTo(map);

  // SVG icon for markers
  const svgIcon = {
    html: '<div class="svg-icon h-[30px] w-[30px] bg-primary-500 icon-marker"></div>',
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
    interactive: false,
    autoPanOnFocus: false,
    bubblingMouseEvents: false,
  });

  // Add popup to marker
  marker.addTo(map);
};

/**
 * Navigates to a URL using HTMX by creating a temporary anchor with hx-boost.
 * This function creates an anchor element with the hx-boost attribute, triggers
 * a click event on it, and then safely removes it from the DOM after a delay.
 * @param {string} url - The URL to navigate to
 */
export const navigateWithHtmx = (url) => {
  // Create a temporary anchor element
  const anchor = document.createElement("a");
  anchor.href = url;
  anchor.setAttribute("hx-boost", "true");
  anchor.style.display = "none";

  // Append to body temporarily
  document.body.appendChild(anchor);

  // Critical: Process with HTMX
  htmx.process(anchor);

  // Trigger click
  anchor.click();

  // Remove the anchor after a small delay to ensure HTMX processes it
  setTimeout(() => {
    if (document.body.contains(anchor)) {
      document.body.removeChild(anchor);
    }
  }, 100);
};
