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
 * Checks if the current path is a dashboard route.
 * @returns {boolean} True when on a dashboard page
 */
export const isDashboardPath = () => {
  const path = window?.location?.pathname || "";
  return path.startsWith("/dashboard");
};

/**
 * Scrolls to the top of the dashboard so alerts stay visible.
 * @returns {void}
 */
export const scrollToDashboardTop = () => {
  if (!isDashboardPath() || typeof window?.scrollTo !== "function") {
    return;
  }

  window.scrollTo({ top: 0, behavior: "auto" });
};

/**
 * Checks whether an element is fully visible in the viewport.
 * @param {HTMLElement} element - Element to check
 * @returns {boolean} True if element is fully visible
 */
export const isElementInView = (element) => {
  if (!element || typeof element.getBoundingClientRect !== "function") {
    return true;
  }

  const rect = element.getBoundingClientRect();
  const viewHeight = window.innerHeight || document.documentElement.clientHeight;
  const viewWidth = window.innerWidth || document.documentElement.clientWidth;

  return rect.top >= 0 && rect.left >= 0 && rect.bottom <= viewHeight && rect.right <= viewWidth;
};

/**
 * Returns a debounced version of the provided function.
 * @param {Function} fn - Function to debounce
 * @param {number} delay - Debounce delay in milliseconds
 * @returns {Function} Debounced function
 */
export const debounce = (fn, delay = 150) => {
  let timeoutId;
  return (...args) => {
    clearTimeout(timeoutId);
    timeoutId = setTimeout(() => fn(...args), delay);
  };
};

/**
 * Locks body scroll by setting overflow to hidden. Uses a counter to handle
 * multiple modals. Only locks scroll when the first modal opens.
 */
export const lockBodyScroll = () => {
  const current = Number.parseInt(document.body.dataset.modalOpenCount || "0", 10);
  const next = Number.isNaN(current) ? 1 : current + 1;
  document.body.dataset.modalOpenCount = String(next);
  if (next === 1) {
    document.body.style.overflow = "hidden";
  }
};

/**
 * Unlocks body scroll by restoring overflow. Uses a counter to handle multiple
 * modals. Only unlocks scroll when all modals are closed (counter reaches 0).
 */
export const unlockBodyScroll = () => {
  const current = Number.parseInt(document.body.dataset.modalOpenCount || "0", 10);
  const next = Number.isNaN(current) ? 0 : Math.max(0, current - 1);
  document.body.dataset.modalOpenCount = String(next);
  if (next === 0) {
    document.body.style.overflow = "";
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
    const willOpen = modal.classList.contains("hidden");
    modal.classList.toggle("hidden");
    if (willOpen) {
      lockBodyScroll();
    } else {
      unlockBodyScroll();
    }
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
export const loadMap = async (divId, lat, long, options = {}) => {
  // Ensure Leaflet is loaded
  await loadLeafletScript();

  const map = L.map(divId, {
    zoomControl: false,
    minZoom: 2,
    maxBounds: L.latLngBounds(L.latLng(-90, -180), L.latLng(90, 180)),
    maxBoundsViscosity: 1.0,
  }).setView([lat, long], options.zoom ?? 13);

  const interactive = options.interactive !== false;

  L.tileLayer(
    `https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}${
      L.Browser.retina ? "@2x.png" : ".png"
    }`,
    {
      attribution: "",
      unloadInvisibleTiles: true,
      noWrap: true,
    },
  ).addTo(map);

  if (options.marker !== false) {
    const svgIcon = {
      html: '<div class="svg-icon h-[30px] w-[30px] bg-primary-500 icon-marker"></div>',
      iconSize: [30, 30],
      iconAnchor: [15, 30],
      popupAnchor: [0, -25],
    };

    const icon = L.divIcon({
      ...svgIcon,
      className: "marker-icon",
    });

    const marker = L.marker(L.latLng(lat, long), {
      icon: icon,
      interactive,
      autoPanOnFocus: false,
      bubblingMouseEvents: false,
    });

    marker.addTo(map);

    if (options.popupContent) {
      const popupOptions = {
        autoPan: false,
        closeButton: interactive,
        closeOnClick: interactive,
        className: options.popupClassName,
      };
      if (!interactive) {
        popupOptions.closeButton = false;
        popupOptions.closeOnClick = false;
      }
      marker.bindPopup(options.popupContent, popupOptions);
      if (options.openPopup !== false) {
        marker.openPopup();
      }
    }
  }

  if (!interactive) {
    if (map.dragging?.disable) {
      map.dragging.disable();
    }
    if (map.touchZoom?.disable) {
      map.touchZoom.disable();
    }
    if (map.scrollWheelZoom?.disable) {
      map.scrollWheelZoom.disable();
    }
    if (map.doubleClickZoom?.disable) {
      map.doubleClickZoom.disable();
    }
    if (map.boxZoom?.disable) {
      map.boxZoom.disable();
    }
    if (map.keyboard?.disable) {
      map.keyboard.disable();
    }
    if (map.tap?.disable) {
      map.tap.disable();
    }
  }

  requestAnimationFrame(() => {
    map.invalidateSize();
  });

  return map;
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
 * Converts a Unix timestamp (seconds) to datetime-local using a timezone.
 *
 * Uses Intl.DateTimeFormat to produce a YYYY-MM-DDTHH:MM string in the
 * provided IANA timezone (e.g. "America/New_York"). Returns empty string
 * if input is invalid.
 *
 * @param {number} tsSeconds - Unix timestamp in seconds.
 * @param {string} timezone - IANA timezone identifier.
 * @returns {string} Datetime string in YYYY-MM-DDTHH:MM or "".
 */
export const convertTimestampToDateTimeLocalInTz = (tsSeconds, timezone) => {
  if (
    typeof tsSeconds !== "number" ||
    !Number.isFinite(tsSeconds) ||
    typeof timezone !== "string" ||
    timezone.length === 0
  ) {
    return "";
  }

  const dtf = new Intl.DateTimeFormat("en-CA", {
    timeZone: timezone,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    hourCycle: "h23",
  });

  const parts = dtf.formatToParts(new Date(tsSeconds * 1000));
  const get = (type) => parts.find((p) => p.type === type)?.value || "";
  const y = get("year");
  const m = get("month");
  const d = get("day");
  const h = get("hour");
  const min = get("minute");
  if (!y || !m || !d || !h || !min) return "";
  return `${y}-${m}-${d}T${h}:${min}`;
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
    (x) =>
      x === null ||
      x === "" ||
      x === false ||
      typeof x === "undefined" ||
      (Array.isArray(x) && x.length === 0),
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
