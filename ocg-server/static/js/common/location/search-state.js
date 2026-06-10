/**
 * Default public properties before Lit reflects attributes onto the element.
 * @returns {Object} Public property defaults.
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
 * Private state for a new location search component instance.
 * @returns {Object} Internal state defaults.
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

/**
 * Maps public location value patch keys to private component backing fields.
 * @type {Object<string, string>}
 */
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
 * Copies known value keys onto the component's private backing fields.
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
 * Initial values read from public properties before internal state is seeded.
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
 * Dropdown state shared by blur, clear, and empty-query flows.
 * @returns {Object} Hidden dropdown state.
 */
export const getHiddenLocationSearchState = () => ({
  showDropdown: false,
  searchResults: [],
  highlightedIndex: -1,
  isSearching: false,
});

/**
 * Visible loading state used while an address search request is in flight.
 * @returns {Object} Started search state.
 */
export const getStartedLocationSearchState = () => ({
  showDropdown: true,
  searchResults: [],
  searchError: null,
  highlightedIndex: -1,
  isSearching: true,
});

/**
 * Empty query state used when the selected or typed location is reset.
 * @returns {Object} Cleared search state.
 */
export const getClearedLocationSearchState = () => ({
  searchQuery: "",
  searchError: null,
  ...getHiddenLocationSearchState(),
});

/**
 * Stores fresh result payloads without changing the active search query.
 * @param {Array<Object>} results Search result payloads.
 * @returns {Object} Successful search state.
 */
export const getSuccessfulLocationSearchState = (results) => ({
  searchResults: results,
  searchError: null,
});

/**
 * Clears stale results and keeps a user-facing failure message.
 * @param {Error} error Search error.
 * @returns {Object} Failed search state.
 */
export const getFailedLocationSearchState = (error) => ({
  searchResults: [],
  searchError: error?.message || "Unable to search for locations right now.",
});

/**
 * Common completion patch for request handlers that always unset loading.
 * @returns {Object} Finished search state.
 */
export const getFinishedLocationSearchState = () => ({
  isSearching: false,
});
