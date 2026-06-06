import { expect } from "@open-wc/testing";

import {
  getCoordinateFieldConfig,
  getEmptyLocationValues,
  getExternalLocationFieldUpdates,
  getExternalLocationFieldIds,
  getInitialLocationValues,
  getInternalLocationValueUpdates,
  getLocationFieldConfig,
  hasInternalLocationFields,
} from "/static/js/common/location-field-config.js";

describe("location field config", () => {
  it("builds field config from component properties", () => {
    // Component config keeps public property access outside the component class.
    expect(
      getLocationFieldConfig({
        venueNameFieldId: "venue-name-id",
        venueAddressFieldId: "venue-address-id",
        venueCityFieldId: "venue-city-id",
        venueZipCodeFieldId: "venue-zip-id",
        stateFieldId: "state-id",
        countryFieldId: "country-id",
        latitudeFieldId: "lat-id",
        longitudeFieldId: "lng-id",
        venueNameFieldName: "venue_name",
        venueAddressFieldName: "venue_address",
        venueCityFieldName: "venue_city",
        venueZipCodeFieldName: "venue_zip_code",
        stateFieldName: "venue_state",
        countryNameFieldName: "venue_country",
        countryCodeFieldName: "venue_country_code",
        latitudeFieldName: "venue_latitude",
        longitudeFieldName: "venue_longitude",
      }),
    ).to.deep.equal({
      venueNameFieldId: "venue-name-id",
      venueAddressFieldId: "venue-address-id",
      venueCityFieldId: "venue-city-id",
      venueZipCodeFieldId: "venue-zip-id",
      stateFieldId: "state-id",
      countryFieldId: "country-id",
      latitudeFieldId: "lat-id",
      longitudeFieldId: "lng-id",
      venueNameFieldName: "venue_name",
      venueAddressFieldName: "venue_address",
      venueCityFieldName: "venue_city",
      venueZipCodeFieldName: "venue_zip_code",
      stateFieldName: "venue_state",
      countryNameFieldName: "venue_country",
      countryCodeFieldName: "venue_country_code",
      latitudeFieldName: "venue_latitude",
      longitudeFieldName: "venue_longitude",
    });
  });

  it("detects configured internal location fields", () => {
    // Any generated field name means the component should render internal fields.
    expect(hasInternalLocationFields({ venueNameFieldName: "venue_name" })).to.equal(true);
    expect(hasInternalLocationFields({ venueCityFieldName: "venue_city" })).to.equal(true);
    expect(hasInternalLocationFields({ countryCodeFieldName: "venue_country_code" })).to.equal(
      true,
    );
    expect(hasInternalLocationFields({ latitudeFieldName: "venue_latitude" })).to.equal(false);
  });

  it("returns only configured external field ids", () => {
    // Empty ids are skipped before the component syncs or clears external fields.
    expect(
      getExternalLocationFieldIds({
        venueNameFieldId: "venue-name",
        venueAddressFieldId: "",
        venueCityFieldId: "venue-city",
        stateFieldId: null,
        countryFieldId: "venue-country",
        latitudeFieldId: undefined,
        longitudeFieldId: "venue-lng",
      }),
    ).to.deep.equal(["venue-name", "venue-city", "venue-country", "venue-lng"]);
  });

  it("builds internal value updates for configured fields", () => {
    // Only configured internal fields are included in the update payload.
    const updates = getInternalLocationValueUpdates(
      {
        venueNameFieldName: "venue_name",
        venueCityFieldName: "venue_city",
        latitudeFieldName: "venue_latitude",
      },
      {
        venueName: "Main Hall",
        venueCity: "Málaga",
        venueAddress: "Hidden address",
        latitude: 36.7213,
        longitude: -4.4214,
      },
    );

    expect(updates).to.deep.equal({
      venueNameValue: "Main Hall",
      venueCityValue: "Málaga",
      latitudeValue: "36.7213",
    });
  });

  it("builds external field updates for configured ids", () => {
    // Empty external ids are skipped before the component writes DOM values.
    const updates = getExternalLocationFieldUpdates(
      {
        venueNameFieldId: "venue-name",
        venueAddressFieldId: "",
        countryFieldId: "venue-country",
        longitudeFieldId: "venue-lng",
      },
      {
        venueName: "Main Hall",
        venueAddress: "Hidden address",
        country: "Spain",
        latitude: 36.7213,
        longitude: -4.4214,
      },
    );

    expect(updates).to.deep.equal([
      { fieldId: "venue-name", value: "Main Hall" },
      { fieldId: "venue-country", value: "Spain" },
      { fieldId: "venue-lng", value: "-4.4214" },
    ]);
  });

  it("builds initial and empty location value state", () => {
    // Initial values default missing fields to empty strings.
    expect(
      getInitialLocationValues({
        initialVenueName: "Main Hall",
        initialCountryName: "Spain",
        initialLatitude: "36.7213",
      }),
    ).to.deep.equal({
      venueNameValue: "Main Hall",
      venueAddressValue: "",
      venueCityValue: "",
      venueZipCodeValue: "",
      stateValue: "",
      countryNameValue: "Spain",
      countryCodeValue: "",
      latitudeValue: "36.7213",
      longitudeValue: "",
    });

    // Empty values reset every generated location field value.
    expect(getEmptyLocationValues()).to.deep.equal({
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
  });

  it("builds coordinate field render configuration", () => {
    // Coordinate field names prefer explicit field names before external ids.
    expect(
      getCoordinateFieldConfig({
        latitudeFieldName: "venue_latitude",
        latitudeFieldId: "venue-lat",
        longitudeFieldId: "venue-lng",
      }),
    ).to.deep.equal({
      hasCoordinateFields: true,
      latitudeName: "venue_latitude",
      longitudeName: "venue-lng",
    });
    expect(getCoordinateFieldConfig({})).to.deep.equal({
      hasCoordinateFields: false,
      latitudeName: "",
      longitudeName: "",
    });
  });
});
