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

/**
 * Checks if an HTTP status code indicates success (2xx range).
 * @param {number} status - The HTTP status code
 * @returns {boolean} True if status is between 200-299
 */
export const isSuccessfulXHRStatus = (status) => {
  if (status >= 200 && status < 300) {
    return true;
  } else {
    return false;
  }
};

/**
 * Converts HTML datetime-local input value to PostgreSQL-compatible timestamp format.
 * HTML datetime-local format: YYYY-MM-DDTHH:MM
 * PostgreSQL timestamp format: YYYY-MM-DDTHH:MM:SS
 *
 * @param {string} dateTimeLocal - The datetime-local input value (e.g., "2025-08-23T15:00")
 * @returns {string|null} Timestamp formatted string (e.g., "2025-08-23T15:00:00") or null if input is empty
 *
 * @example
 * convertDateTimeLocalToISO("2025-08-23T15:00") // returns "2025-08-23T15:00:00"
 * convertDateTimeLocalToISO("") // returns null
 */
export const convertDateTimeLocalToISO = (dateTimeLocal) => {
  if (!dateTimeLocal) return null;
  return `${dateTimeLocal}:00`;
};

/**
 * Converts a Unix timestamp (in seconds) to a datetime-local input value.
 *
 * This function transforms Unix timestamps into the format required by HTML5
 * <input type="datetime-local"> elements. The output uses UTC timezone.
 *
 * @param {number} tsSeconds - Unix timestamp in seconds since epoch (1970-01-01 00:00:00 UTC).
 *                             Must be a finite number.
 * @returns {string} Datetime string in YYYY-MM-DDTHH:MM format (UTC timezone)
 *                   Returns empty string if input is invalid (non-number, NaN, Infinity)
 *
 * @example
 * // Valid timestamp
 * convertTimestampToDateTimeLocal(1735689600) // returns "2025-01-01T00:00"
 *
 * // Epoch start
 * convertTimestampToDateTimeLocal(0) // returns "1970-01-01T00:00"
 *
 * // Invalid inputs
 * convertTimestampToDateTimeLocal(null) // returns ""
 * convertTimestampToDateTimeLocal("1735689600") // returns "" (string not accepted)
 * convertTimestampToDateTimeLocal(NaN) // returns ""
 *
 * @note This function uses UTC for conversion. If local timezone is needed,
 *       consider using date.getFullYear(), date.getMonth(), etc. instead of
 *       date.toISOString() to build the string in local time.
 */
export const convertTimestampToDateTimeLocal = (tsSeconds) => {
  if (typeof tsSeconds !== "number" || !Number.isFinite(tsSeconds)) {
    return "";
  }

  const date = new Date(tsSeconds * 1000); // Convert seconds to milliseconds
  return date.toISOString().slice(0, 16); // Format: YYYY-MM-DDTHH:MM
};

/**
 * Checks if an object contains only empty values.
 * Excludes the id field from the check, useful for form validation.
 * @param {Object} obj - The object to check
 * @returns {boolean} True if all values (except id) are empty/null/undefined/empty arrays
 */
export const isObjectEmpty = (obj) => {
  // Remove the id key from the object
  const objectWithoutId = { ...obj };
  delete objectWithoutId.id;
  return Object.values(objectWithoutId).every(
    (x) => x === null || x === "" || typeof x === "undefined" || (Array.isArray(x) && x.length === 0),
  );
};

/**
 * Computes initials from a user's name, with username fallback.
 *
 * - If `name` exists: returns first letter of first and last words (or just
 *   the first letter if only one word) depending on `count` (1 or 2).
 * - If `name` is empty: falls back to the first letter of `username`.
 *
 * @param {string|null|undefined} name - Full name (may be null/undefined)
 * @param {string} username - Username (used as fallback)
 * @param {number} count - Initials count (1 or 2). Defaults to 2.
 * @returns {string} Initials string (uppercase)
 */
export const computeUserInitials = (name, username, count = 2) => {
  const cleanName = (name || "").trim();
  if (cleanName.length === 0) {
    return (username || "").charAt(0).toUpperCase();
  }

  const parts = cleanName.split(/\s+/);
  let initials = "";
  if (parts.length > 0 && parts[0].length > 0) {
    initials += parts[0][0].toUpperCase();
  }
  if (count >= 2 && parts.length > 1 && parts[parts.length - 1].length > 0) {
    initials += parts[parts.length - 1][0].toUpperCase();
  }
  return initials;
};
