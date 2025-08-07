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
 * @param {number} lat - The latitude coordinate for the map center and marker
 * @param {number} long - The longitude coordinate for the map center and marker
 */
export const loadMap = (divId, lat, long) => {
  const map = L.map(divId, { zoomControl: false, dragging: false }).setView([lat, long], 13);

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
 * a click event on it, and then removes it from the DOM.
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
    document.body.removeChild(anchor);
  }, 100);
};

/**
 * Initializes avatar image loading for a single avatar container.
 * Shows the image when loaded successfully, keeps initials on error.
 * @param {HTMLElement} container - The avatar container element
 */
export const initializeAvatar = (container) => {
  const initialsEl = container.querySelector('.avatar-initials');
  const imgEl = container.querySelector('.avatar-image');
  
  if (imgEl && imgEl.dataset.src) {
    imgEl.src = imgEl.dataset.src;
    
    imgEl.onload = () => {
      initialsEl?.classList.add('hidden');
      imgEl.classList.remove('hidden');
    };
    
    imgEl.onerror = () => {
      // Keep initials visible on error
      imgEl.classList.add('hidden');
    };
  }
};

/**
 * Initializes all avatar containers on the page.
 * Finds all elements with the 'avatar-container' class and initializes them.
 */
export const initializeAvatars = () => {
  document.querySelectorAll('.avatar-container').forEach(initializeAvatar);
};
