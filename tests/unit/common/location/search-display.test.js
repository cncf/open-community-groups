import { expect } from "@open-wc/testing";

import {
  getLocationInputId,
  getLocationLegendText,
  getLocationResultText,
  getLocationDisabledInputClasses,
  getLocationTextFieldDefinitions,
  getLocationTextFieldValueKey,
  isLocationSearchButtonDisabled,
  isVenueLocationContext,
  shouldRenderLocationDropdown,
} from "/static/js/common/location/search-display.js";

describe("location search display", () => {
  it("detects venue location field configurations", () => {
    // Venue field names mark the location context as venue-specific.
    expect(
      isVenueLocationContext({ venueNameFieldName: "venue_name" }),
    ).to.equal(true);
    expect(
      isVenueLocationContext({ venueAddressFieldName: "venue_address" }),
    ).to.equal(true);
    expect(
      isVenueLocationContext({ venueZipCodeFieldName: "venue_zip" }),
    ).to.equal(true);
    expect(
      isVenueLocationContext({ countryNameFieldName: "country" }),
    ).to.equal(false);
  });

  it("builds stable ids for generated location inputs", () => {
    // Input ids include the component id when available.
    expect(getLocationInputId("event-location", "venue_city")).to.equal(
      "event-location-venue_city",
    );
    expect(getLocationInputId("", "venue_city")).to.equal(
      "location-search-venue_city",
    );
    expect(getLocationInputId("event-location", "")).to.equal("");
  });

  it("returns venue-aware helper text", () => {
    // City and country helper text changes for venue contexts.
    expect(getLocationLegendText("city", true)).to.equal(
      "City where the venue is located.",
    );
    expect(getLocationLegendText("city", false)).to.equal(
      "Primary city where the group is located.",
    );
    expect(getLocationLegendText("country", true)).to.equal(
      "Country where the venue is located.",
    );
    expect(getLocationLegendText("zip", false)).to.equal(
      "Postal/zip code of the venue.",
    );
    expect(getLocationLegendText("state", false)).to.equal(
      "State, province, or region.",
    );
    expect(getLocationLegendText("unknown", false)).to.equal("");
  });

  it("extracts primary and secondary result display text", () => {
    // Result display prefers named address fields before the full display name.
    expect(
      getLocationResultText({
        display_name: "Main Hall, Málaga, Spain",
        address: { amenity: "Main Hall" },
      }),
    ).to.deep.equal({
      mainText: "Main Hall",
      secondaryText: "Main Hall, Málaga, Spain",
    });
    expect(
      getLocationResultText({ display_name: "Málaga, Andalusia, Spain" }),
    ).to.deep.equal({
      mainText: "Málaga",
      secondaryText: "Málaga, Andalusia, Spain",
    });
  });

  it("detects dropdown and search button display states", () => {
    // Dropdown only renders after the user searches with enough text.
    expect(
      shouldRenderLocationDropdown({
        showDropdown: true,
        searchQuery: "Málaga",
      }),
    ).to.equal(true);
    expect(
      shouldRenderLocationDropdown({ showDropdown: true, searchQuery: "Má" }),
    ).to.equal(false);

    // Search is disabled for disabled fields, short queries, or active requests.
    expect(
      isLocationSearchButtonDisabled({
        disabled: false,
        searchQuery: "Málaga",
        isSearching: false,
      }),
    ).to.equal(false);
    expect(
      isLocationSearchButtonDisabled({
        disabled: false,
        searchQuery: "Má",
        isSearching: false,
      }),
    ).to.equal(true);
  });

  it("returns disabled input classes only when fields are disabled", () => {
    // Disabled classes are shared by generated location inputs.
    expect(getLocationDisabledInputClasses(true)).to.equal(
      "cursor-not-allowed bg-stone-100 text-stone-500",
    );
    expect(getLocationDisabledInputClasses(false)).to.equal("");
  });

  it("places the address above the city and zip code row", () => {
    const fields = getLocationTextFieldDefinitions({
      venueAddressFieldName: "venue_address",
      venueCityFieldName: "venue_city",
      venueZipCodeFieldName: "venue_zip_code",
    });

    expect(fields.map((field) => field.className)).to.deep.equal([
      "col-span-full",
      "col-span-full lg:col-span-3",
      "col-span-full lg:col-span-3",
    ]);
  });

  it("returns value keys for generated text field handlers", () => {
    // Handler names map generated inputs to their component value fields.
    expect(getLocationTextFieldValueKey("venueName")).to.equal(
      "_venueNameValue",
    );
    expect(getLocationTextFieldValueKey("venueAddress")).to.equal(
      "_venueAddressValue",
    );
    expect(getLocationTextFieldValueKey("venueCity")).to.equal(
      "_venueCityValue",
    );
    expect(getLocationTextFieldValueKey("venueZipCode")).to.equal(
      "_venueZipCodeValue",
    );
    expect(getLocationTextFieldValueKey("state")).to.equal("_stateValue");
    expect(getLocationTextFieldValueKey("stateCode")).to.equal(
      "_stateCodeValue",
    );
    expect(getLocationTextFieldValueKey("countryName")).to.equal(
      "_countryNameValue",
    );
    expect(getLocationTextFieldValueKey("countryCode")).to.equal(
      "_countryCodeValue",
    );
    expect(getLocationTextFieldValueKey("unknown")).to.equal("");
  });

  it("builds visible location text field definitions", () => {
    // Only configured field names create generated text fields.
    const fields = getLocationTextFieldDefinitions({
      venueNameFieldName: "venue_name",
      venueCityFieldName: "venue_city",
      stateFieldName: "venue_state_name",
      stateCodeFieldName: "venue_state_code",
      countryNameFieldName: "venue_country",
      countryCodeFieldName: "venue_country_code",
      venueNameValue: "Main Hall",
      venueCityValue: "Malaga",
      stateValue: "Andalusia",
      stateCodeValue: "MA",
      countryNameValue: "Spain",
      countryCodeValue: "ES",
    });

    // The definitions preserve render order and venue-aware helper text.
    expect(fields.map((field) => field.fieldName)).to.deep.equal([
      "venue_name",
      "venue_city",
      "venue_state_name",
      "venue_country",
      "venue_state_code",
      "venue_country_code",
    ]);
    expect(fields.map((field) => field.handlerName)).to.deep.equal([
      "venueName",
      "venueCity",
      "state",
      "countryName",
      "stateCode",
      "countryCode",
    ]);
    expect(fields[0]).to.include({
      label: "Venue Name",
      legend: "Name of the venue where the event takes place.",
      value: "Main Hall",
    });
    expect(fields[1]).to.include({
      autocomplete: false,
      legend: "City where the venue is located.",
      value: "Malaga",
    });
    expect(fields[2]).to.include({
      autocomplete: false,
      className: "col-span-full lg:col-span-3 lg:col-start-1",
      value: "Andalusia",
    });
    expect(fields[3]).to.include({
      autocomplete: false,
      className: "col-span-full lg:col-span-3",
      legend: "Country where the venue is located.",
      value: "Spain",
    });
    expect(fields[4]).to.include({
      autocomplete: false,
      className: "col-span-full lg:col-span-3 lg:col-start-1",
      label: "State/Province Code",
      legend: "State or province code used to calculate taxes.",
      value: "MA",
    });
    expect(fields[5]).to.include({
      autocomplete: false,
      className: "col-span-full lg:col-span-3",
      label: "Country Code",
      legend: "Country code used to calculate taxes.",
      requiredForPaidTickets: true,
      value: "ES",
    });
  });
});
