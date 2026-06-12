/**
 * Public property snapshot consumed by field sync helpers.
 * @param {Object} component Location search component.
 * @returns {Object} Location field configuration.
 */
export const getLocationFieldConfig = (component) => ({
  venueNameFieldId: component.venueNameFieldId,
  venueAddressFieldId: component.venueAddressFieldId,
  venueCityFieldId: component.venueCityFieldId,
  venueZipCodeFieldId: component.venueZipCodeFieldId,
  stateFieldId: component.stateFieldId,
  countryFieldId: component.countryFieldId,
  latitudeFieldId: component.latitudeFieldId,
  longitudeFieldId: component.longitudeFieldId,
  venueNameFieldName: component.venueNameFieldName,
  venueAddressFieldName: component.venueAddressFieldName,
  venueCityFieldName: component.venueCityFieldName,
  venueZipCodeFieldName: component.venueZipCodeFieldName,
  stateFieldName: component.stateFieldName,
  countryNameFieldName: component.countryNameFieldName,
  countryCodeFieldName: component.countryCodeFieldName,
  latitudeFieldName: component.latitudeFieldName,
  longitudeFieldName: component.longitudeFieldName,
});

/**
 * True when the component should render its own location form fields.
 * @param {Object} fields Location field configuration.
 * @returns {boolean}
 */
export const hasInternalLocationFields = (fields) =>
  Boolean(
    fields.venueNameFieldName ||
    fields.venueAddressFieldName ||
    fields.venueCityFieldName ||
    fields.venueZipCodeFieldName ||
    fields.stateFieldName ||
    fields.countryNameFieldName ||
    fields.countryCodeFieldName,
  );

/**
 * External DOM ids that need syncing when selection or clear changes.
 * @param {Object} fields Location field configuration.
 * @returns {Array<string>}
 */
export const getExternalLocationFieldIds = (fields) =>
  [
    fields.venueNameFieldId,
    fields.venueAddressFieldId,
    fields.venueCityFieldId,
    fields.venueZipCodeFieldId,
    fields.stateFieldId,
    fields.countryFieldId,
    fields.latitudeFieldId,
    fields.longitudeFieldId,
  ].filter(Boolean);

/**
 * Only returns value keys backed by internal field names or coordinate targets.
 * @param {Object} fields Location field configuration.
 * @param {Object} location Selected location values.
 * @returns {Object}
 */
export const getInternalLocationValueUpdates = (fields, location) => {
  const updates = {};
  if (fields.venueNameFieldName) updates.venueNameValue = location.venueName || "";
  if (fields.venueAddressFieldName) updates.venueAddressValue = location.venueAddress || "";
  if (fields.venueCityFieldName) updates.venueCityValue = location.venueCity || "";
  if (fields.venueZipCodeFieldName) updates.venueZipCodeValue = location.venueZipCode || "";
  if (fields.stateFieldName) updates.stateValue = location.state || "";
  if (fields.countryNameFieldName) updates.countryNameValue = location.country || "";
  if (fields.countryCodeFieldName) updates.countryCodeValue = location.countryCode || "";
  if (fields.latitudeFieldName || fields.latitudeFieldId) {
    updates.latitudeValue = String(location.latitude);
  }
  if (fields.longitudeFieldName || fields.longitudeFieldId) {
    updates.longitudeValue = String(location.longitude);
  }
  return updates;
};

/**
 * Only returns field updates for DOM ids configured by the host template.
 * @param {Object} fields Location field configuration.
 * @param {Object} location Selected location values.
 * @returns {Array<{fieldId: string, value: string}>}
 */
export const getExternalLocationFieldUpdates = (fields, location) =>
  [
    { fieldId: fields.venueNameFieldId, value: location.venueName },
    { fieldId: fields.venueAddressFieldId, value: location.venueAddress },
    { fieldId: fields.venueCityFieldId, value: location.venueCity },
    { fieldId: fields.venueZipCodeFieldId, value: location.venueZipCode },
    { fieldId: fields.stateFieldId, value: location.state },
    { fieldId: fields.countryFieldId, value: location.country },
    { fieldId: fields.latitudeFieldId, value: String(location.latitude) },
    { fieldId: fields.longitudeFieldId, value: String(location.longitude) },
  ].filter((update) => update.fieldId);

/**
 * Normalizes reflected initial attributes into mutable location value state.
 * @param {Object} values Initial location values.
 * @returns {Object}
 */
export const getInitialLocationValues = (values) => ({
  venueNameValue: values.initialVenueName || "",
  venueAddressValue: values.initialVenueAddress || "",
  venueCityValue: values.initialVenueCity || "",
  venueZipCodeValue: values.initialVenueZipCode || "",
  stateValue: values.initialState || "",
  countryNameValue: values.initialCountryName || "",
  countryCodeValue: values.initialCountryCode || "",
  latitudeValue: values.initialLatitude || "",
  longitudeValue: values.initialLongitude || "",
});

/**
 * Blank value object used after clearing both search and selection state.
 * @returns {Object} Empty location values.
 */
export const getEmptyLocationValues = () => ({
  venueNameValue: "",
  venueAddressValue: "",
  venueCityValue: "",
  venueZipCodeValue: "",
  stateValue: "",
  countryNameValue: "",
  countryCodeValue: "",
  latitudeValue: "",
  longitudeValue: "",
});

/**
 * Coordinate names can come from rendered fields or synced external inputs.
 * @param {Object} fields Location field configuration.
 * @returns {{hasCoordinateFields: boolean, latitudeName: string, longitudeName: string}}
 */
export const getCoordinateFieldConfig = (fields) => {
  const latitudeName = fields.latitudeFieldName || fields.latitudeFieldId || "";
  const longitudeName = fields.longitudeFieldName || fields.longitudeFieldId || "";

  return {
    hasCoordinateFields: Boolean(latitudeName || longitudeName),
    latitudeName,
    longitudeName,
  };
};
