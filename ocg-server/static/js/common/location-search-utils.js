export const DEFAULT_MAP_ZOOM = 15;

/**
 * Parses a coordinate input value.
 * @param {string} value Coordinate value.
 * @returns {number|null} Parsed coordinate, or null when invalid.
 */
export const parseCoordinate = (value) => {
  if (typeof value !== "string") return null;
  const parsed = Number.parseFloat(value);
  if (Number.isNaN(parsed)) return null;
  return parsed;
};

/**
 * Extracts structured address components from a Nominatim result.
 * @param {Object} result Nominatim search result object.
 * @returns {Object} Extracted address components.
 */
export const extractAddress = (result) => {
  const addr = result.address || {};

  const streetParts = [addr.house_number, addr.road].filter(Boolean);
  const streetAddress = streetParts.join(" ");

  const city = addr.city || addr.town || addr.village || addr.municipality || addr.county || "";
  const zipCode = addr.postcode || "";
  const venueName =
    addr[result.type] || addr[result.addresstype] || addr.amenity || addr.building || addr.name || "";
  const state = addr.state || addr.province || addr.region || "";
  const country = addr.country || "";
  const countryCode = (addr.country_code || "").toUpperCase();

  return {
    venueName,
    venueAddress: streetAddress,
    venueCity: city,
    venueZipCode: zipCode,
    state,
    country,
    countryCode,
    latitude: Number.parseFloat(result.lat),
    longitude: Number.parseFloat(result.lon),
    displayName: result.display_name,
  };
};

/**
 * Choose a zoom level based on the selected Nominatim result.
 * @param {Object} result Nominatim location result.
 * @returns {number} Map zoom.
 */
export const deriveZoomFromLocation = (result) => {
  if (!result || typeof result !== "object") return DEFAULT_MAP_ZOOM;
  const type = (result.type || "").toLowerCase();
  const cls = (result.class || "").toLowerCase();
  const zoomByType = {
    country: 5,
    state: 7,
    region: 7,
    province: 7,
    county: 8,
    city: 11,
    town: 11,
    village: 11,
    hamlet: 12,
    municipality: 11,
    postcode: 12,
    residential: 16,
    suburb: 14,
    road: 15,
    street: 15,
    address: 17,
    building: 17,
    house: 17,
    entrance: 17,
  };

  if (Object.prototype.hasOwnProperty.call(zoomByType, type)) {
    return zoomByType[type];
  }
  if (cls === "boundary") {
    return 8;
  }

  const addr = result.address || {};
  if (addr.city || addr.town || addr.village || addr.municipality) {
    return 11;
  }
  if (addr.state || addr.region || addr.province || addr.county) {
    return 7;
  }
  if (addr.country) {
    return 5;
  }

  return DEFAULT_MAP_ZOOM;
};

/**
 * Normalize bounding box values from the selected result.
 * @param {Array<string>|undefined} boundingbox Nominatim bounding box.
 * @returns {Array<number>|null} Parsed bounding box, or null when invalid.
 */
export const normalizeBoundingBox = (boundingbox) => {
  if (!Array.isArray(boundingbox) || boundingbox.length !== 4) {
    return null;
  }
  const parsed = boundingbox.map((value) => Number.parseFloat(value));
  if (parsed.some((value) => Number.isNaN(value))) {
    return null;
  }
  return parsed;
};

/**
 * Determine if the map preview should fit the bounding box.
 * @param {Object} result Selected Nominatim result object.
 * @returns {boolean} True when the result should fit bounds.
 */
export const shouldFitBoundsForResult = (result) => {
  if (!result || typeof result !== "object") {
    return false;
  }
  const addresstype = (result.addresstype || "").toLowerCase();
  const type = (result.type || "").toLowerCase();
  return addresstype === "country" || type === "country";
};

/**
 * Choose a zoom level based on current manual field values.
 * @param {Object} fields Manual location fields.
 * @returns {number} Map zoom.
 */
export const deriveZoomFromFields = (fields = {}) => {
  const normalize = (value) => (value || "").trim();
  const hasAddress = Boolean(normalize(fields.venueAddress) || normalize(fields.venueZipCode));
  if (hasAddress) {
    return 16;
  }

  if (normalize(fields.venueCity)) {
    return 14;
  }

  if (normalize(fields.state)) {
    return 8;
  }

  if (normalize(fields.countryName)) {
    return 5;
  }

  return DEFAULT_MAP_ZOOM;
};
