import { expect } from "@open-wc/testing";

import {
  getLocationInputId,
  getLocationLegendText,
  getLocationResultText,
  getLocationDisabledInputClasses,
  isLocationSearchButtonDisabled,
  isVenueLocationContext,
  shouldRenderLocationDropdown,
} from "/static/js/common/location-search-display.js";

describe("location search display", () => {
  it("detects venue location field configurations", () => {
    // Venue field names mark the location context as venue-specific.
    expect(isVenueLocationContext({ venueNameFieldName: "venue_name" })).to.equal(true);
    expect(isVenueLocationContext({ venueAddressFieldName: "venue_address" })).to.equal(true);
    expect(isVenueLocationContext({ venueZipCodeFieldName: "venue_zip" })).to.equal(true);
    expect(isVenueLocationContext({ countryNameFieldName: "country" })).to.equal(false);
  });

  it("builds stable ids for generated location inputs", () => {
    // Input ids include the component id when available.
    expect(getLocationInputId("event-location", "venue_city")).to.equal(
      "event-location-venue_city",
    );
    expect(getLocationInputId("", "venue_city")).to.equal("location-search-venue_city");
    expect(getLocationInputId("event-location", "")).to.equal("");
  });

  it("returns venue-aware helper text", () => {
    // City and country helper text changes for venue contexts.
    expect(getLocationLegendText("city", true)).to.equal("City where the venue is located.");
    expect(getLocationLegendText("city", false)).to.equal(
      "Primary city where the group is located.",
    );
    expect(getLocationLegendText("country", true)).to.equal("Country where the venue is located.");
    expect(getLocationLegendText("zip", false)).to.equal("Postal/zip code of the venue.");
    expect(getLocationLegendText("state", false)).to.equal("State, province, or region.");
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
    expect(getLocationResultText({ display_name: "Málaga, Andalusia, Spain" })).to.deep.equal({
      mainText: "Málaga",
      secondaryText: "Málaga, Andalusia, Spain",
    });
  });

  it("detects dropdown and search button display states", () => {
    // Dropdown only renders after the user searches with enough text.
    expect(shouldRenderLocationDropdown({ showDropdown: true, searchQuery: "Málaga" })).to.equal(
      true,
    );
    expect(shouldRenderLocationDropdown({ showDropdown: true, searchQuery: "Má" })).to.equal(
      false,
    );

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
});
