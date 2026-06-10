/**
 * Determines whether the configured fields describe a venue location.
 * @param {Object} fields Location field configuration.
 * @returns {boolean}
 */
export const isVenueLocationContext = (fields) =>
  Boolean(fields.venueNameFieldName || fields.venueAddressFieldName || fields.venueZipCodeFieldName);

/**
 * Builds a stable id for a location input.
 * @param {string} componentId Location search component id.
 * @param {string} inputName Input field name.
 * @returns {string}
 */
export const getLocationInputId = (componentId, inputName) => {
  if (!inputName) return "";
  return `${componentId || "location-search"}-${inputName}`;
};

/**
 * Gets helper text for a generated location input.
 * @param {"city" | "zip" | "state" | "country"} kind Location input kind.
 * @param {boolean} isVenue Whether the fields describe a venue location.
 * @returns {string}
 */
export const getLocationLegendText = (kind, isVenue) => {
  if (kind === "city") {
    return isVenue ? "City where the venue is located." : "Primary city where the group is located.";
  }
  if (kind === "zip") {
    return "Postal/zip code of the venue.";
  }
  if (kind === "state") {
    return "State, province, or region.";
  }
  if (kind === "country") {
    return isVenue ? "Country where the venue is located." : "Country where the group is located.";
  }

  return "";
};

/**
 * Extracts the primary and secondary display text for a search result.
 * @param {Object} result Nominatim search result.
 * @returns {{mainText: string, secondaryText: string}}
 */
export const getLocationResultText = (result) => {
  const addr = result.address || {};
  const secondaryText = result.display_name || "";
  const mainText = addr.amenity || addr.building || addr.name || addr.road || secondaryText.split(",")[0];
  return { mainText, secondaryText };
};

/**
 * Checks whether the search result dropdown should be rendered.
 * @param {Object} state Search display state.
 * @returns {boolean}
 */
export const shouldRenderLocationDropdown = (state) =>
  state.showDropdown && state.searchQuery !== "" && state.searchQuery.length >= 3;

/**
 * Checks whether the location search button should be disabled.
 * @param {Object} state Search display state.
 * @returns {boolean}
 */
export const isLocationSearchButtonDisabled = (state) =>
  state.disabled || state.searchQuery.length < 3 || state.isSearching;

/**
 * Gets common disabled styling for location search inputs.
 * @param {boolean} disabled Whether the field is disabled.
 * @returns {string}
 */
export const getLocationDisabledInputClasses = (disabled) =>
  disabled ? "cursor-not-allowed bg-stone-100 text-stone-500" : "";

/**
 * Gets the component value key for a generated text field handler.
 * @param {string} handlerName Location text field handler name.
 * @returns {string}
 */
export const getLocationTextFieldValueKey = (handlerName) => {
  const valueKeys = {
    countryName: "_countryNameValue",
    state: "_stateValue",
    venueAddress: "_venueAddressValue",
    venueCity: "_venueCityValue",
    venueName: "_venueNameValue",
    venueZipCode: "_venueZipCodeValue",
  };
  return valueKeys[handlerName] || "";
};

/**
 * Builds the generated location text field definitions.
 * @param {Object} state Location field display state.
 * @returns {Array<Object>} Visible text field definitions.
 */
export const getLocationTextFieldDefinitions = (state) => {
  const isVenue = isVenueLocationContext(state);
  const fields = [
    {
      className: "col-span-full lg:col-span-3",
      fieldName: state.venueNameFieldName,
      handlerName: "venueName",
      label: "Venue Name",
      legend: "Name of the venue where the event takes place.",
      value: state.venueNameValue,
    },
    {
      className: "col-span-full lg:col-span-4",
      fieldName: state.venueAddressFieldName,
      handlerName: "venueAddress",
      label: "Address",
      legend: "Street address of the venue.",
      value: state.venueAddressValue,
    },
    {
      autocomplete: false,
      className: "col-span-full lg:col-span-2",
      fieldName: state.venueCityFieldName,
      handlerName: "venueCity",
      label: "City",
      legend: getLocationLegendText("city", isVenue),
      value: state.venueCityValue,
    },
    {
      className: "col-span-full lg:col-span-2",
      fieldName: state.venueZipCodeFieldName,
      handlerName: "venueZipCode",
      label: "Zip Code",
      legend: getLocationLegendText("zip", isVenue),
      value: state.venueZipCodeValue,
    },
    {
      autocomplete: false,
      className: "col-span-full lg:col-span-2",
      fieldName: state.stateFieldName,
      handlerName: "state",
      label: "State/Province",
      legend: getLocationLegendText("state", isVenue),
      value: state.stateValue,
    },
    {
      autocomplete: false,
      className: "col-span-full lg:col-span-2",
      fieldName: state.countryNameFieldName,
      handlerName: "countryName",
      label: "Country",
      legend: getLocationLegendText("country", isVenue),
      value: state.countryNameValue,
    },
  ];

  return fields.filter((field) => Boolean(field.fieldName));
};
