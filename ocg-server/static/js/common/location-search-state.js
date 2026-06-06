/**
 * Builds the component default public property values.
 * @returns {Object}
 */
export const getDefaultLocationSearchProperties = () => ({
  placeholderText: "Search for a venue or address...",
  venueNameFieldId: "",
  venueAddressFieldId: "",
  venueCityFieldId: "",
  venueZipCodeFieldId: "",
  stateFieldId: "",
  countryFieldId: "",
  latitudeFieldId: "",
  longitudeFieldId: "",
  venueNameFieldName: "",
  venueAddressFieldName: "",
  venueCityFieldName: "",
  venueZipCodeFieldName: "",
  stateFieldName: "",
  countryNameFieldName: "",
  countryCodeFieldName: "",
  latitudeFieldName: "",
  longitudeFieldName: "",
  initialVenueName: "",
  initialVenueAddress: "",
  initialVenueCity: "",
  initialVenueZipCode: "",
  initialState: "",
  initialCountryName: "",
  initialCountryCode: "",
  initialLatitude: "",
  initialLongitude: "",
  disabled: false,
});

/**
 * Builds the component default internal state.
 * @returns {Object}
 */
export const getDefaultLocationSearchInternalState = () => ({
  isSearching: false,
  searchResults: [],
  searchQuery: "",
  highlightedIndex: -1,
  abortController: null,
  outsidePointerHandler: null,
  latitudeValue: "",
  longitudeValue: "",
  venueNameValue: "",
  venueAddressValue: "",
  venueCityValue: "",
  venueZipCodeValue: "",
  stateValue: "",
  countryNameValue: "",
  countryCodeValue: "",
  showDropdown: false,
  mapVisible: false,
  searchError: null,
});

const LOCATION_VALUE_PROPERTY_MAP = {
  venueNameValue: "_venueNameValue",
  venueAddressValue: "_venueAddressValue",
  venueCityValue: "_venueCityValue",
  venueZipCodeValue: "_venueZipCodeValue",
  stateValue: "_stateValue",
  countryNameValue: "_countryNameValue",
  countryCodeValue: "_countryCodeValue",
  latitudeValue: "_latitudeValue",
  longitudeValue: "_longitudeValue",
};

/**
 * Applies normalized location value updates to a target object.
 * @param {Object} target Object receiving private location value fields.
 * @param {Object} updates Location value patch.
 * @returns {void}
 */
export const applyLocationSearchValueUpdates = (target, updates) => {
  Object.entries(LOCATION_VALUE_PROPERTY_MAP).forEach(([updateKey, propertyKey]) => {
    if (Object.prototype.hasOwnProperty.call(updates, updateKey)) {
      target[propertyKey] = updates[updateKey];
    }
  });
};

/**
 * Builds initial value payload from public attributes.
 * @param {Object} state Component state.
 * @returns {Object} Initial location values.
 */
export const getInitialLocationSearchValues = (state) => ({
  initialVenueName: state.initialVenueName,
  initialVenueAddress: state.initialVenueAddress,
  initialVenueCity: state.initialVenueCity,
  initialVenueZipCode: state.initialVenueZipCode,
  initialState: state.initialState,
  initialCountryName: state.initialCountryName,
  initialCountryCode: state.initialCountryCode,
  initialLatitude: state.initialLatitude,
  initialLongitude: state.initialLongitude,
});

/**
 * Builds the component state for a hidden location search dropdown.
 * @returns {Object}
 */
export const getHiddenLocationSearchState = () => ({
  showDropdown: false,
  searchResults: [],
  highlightedIndex: -1,
  isSearching: false,
});

/**
 * Builds the component state for a new location search request.
 * @returns {Object}
 */
export const getStartedLocationSearchState = () => ({
  showDropdown: true,
  searchResults: [],
  searchError: null,
  highlightedIndex: -1,
  isSearching: true,
});

/**
 * Builds the component state for clearing the search input and results.
 * @returns {Object}
 */
export const getClearedLocationSearchState = () => ({
  searchQuery: "",
  searchError: null,
  ...getHiddenLocationSearchState(),
});

/**
 * Builds the component state for successful search results.
 * @param {Array<Object>} results Search result payloads.
 * @returns {Object}
 */
export const getSuccessfulLocationSearchState = (results) => ({
  searchResults: results,
  searchError: null,
});

/**
 * Builds the component state for failed search results.
 * @param {Error} error Search error.
 * @returns {Object}
 */
export const getFailedLocationSearchState = (error) => ({
  searchResults: [],
  searchError: error?.message || "Unable to search for locations right now.",
});

/**
 * Builds the component state for a completed search request.
 * @returns {Object}
 */
export const getFinishedLocationSearchState = () => ({
  isSearching: false,
});
