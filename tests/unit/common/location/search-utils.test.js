import { expect } from "@open-wc/testing";

import {
  DEFAULT_MAP_ZOOM,
  deriveZoomFromFields,
  deriveZoomFromLocation,
  extractAddress,
  extractStateCode,
  normalizeBoundingBox,
  parseCoordinate,
  shouldFitBoundsForResult,
} from "/static/js/common/location/search-utils.js";

describe("location search utils", () => {
  it("parses coordinates safely", () => {
    // Build coordinate inputs from form values.
    expect(parseCoordinate("36.7213")).to.equal(36.7213);
    expect(parseCoordinate("-4.4214")).to.equal(-4.4214);
    expect(parseCoordinate("not-a-coordinate")).to.equal(null);
    expect(parseCoordinate(36.7213)).to.equal(null);
  });

  it("extracts structured address fields from nominatim results", () => {
    // Build a representative Nominatim address payload.
    const result = {
      type: "museum",
      lat: "36.7213",
      lon: "-4.4214",
      display_name: "Museum, Malaga, Spain",
      address: {
        house_number: "1",
        road: "Main Street",
        city: "Malaga",
        postcode: "29015",
        museum: "City Museum",
        state: "Andalusia",
        "ISO3166-2-lvl4": "ES-AN",
        country: "Spain",
        country_code: "es",
        "ISO3166-2-lvl6": "ES-MA",
      },
    };

    // The helper maps Nominatim fields into form-friendly values.
    expect(extractAddress(result)).to.deep.equal({
      venueName: "City Museum",
      venueAddress: "1 Main Street",
      venueCity: "Malaga",
      venueZipCode: "29015",
      state: "Andalusia",
      stateCode: "MA",
      country: "Spain",
      countryCode: "ES",
      latitude: 36.7213,
      longitude: -4.4214,
      displayName: "Museum, Malaga, Spain",
    });
  });

  it("extracts the deepest matching subdivision code", () => {
    // Matching country prefixes are ranked by their numeric Nominatim level.
    expect(
      extractStateCode(
        {
          "ISO3166-2-lvl4": "ES-AN",
          "ISO3166-2-lvl6": "es-ma",
        },
        "ES",
      ),
    ).to.equal("MA");

    // Single levels are accepted while missing and mismatched data stay empty.
    expect(extractStateCode({ "ISO3166-2-lvl4": "US-CA" }, "US")).to.equal("CA");
    expect(extractStateCode({ "ISO3166-2-lvl4": "PT-11" }, "ES")).to.equal("");
    expect(extractStateCode({}, "ES")).to.equal("");
  });

  it("derives map zoom from search results and manual fields", () => {
    // Result payloads use type, class, and address detail to infer zoom.
    expect(deriveZoomFromLocation({ type: "country" })).to.equal(5);
    expect(deriveZoomFromLocation({ class: "boundary" })).to.equal(8);
    expect(deriveZoomFromLocation({ address: { city: "Malaga" } })).to.equal(11);
    expect(deriveZoomFromLocation(null)).to.equal(DEFAULT_MAP_ZOOM);

    // Manual fields use the most specific populated location field.
    expect(deriveZoomFromFields({ venueAddress: "Main Street" })).to.equal(16);
    expect(deriveZoomFromFields({ venueCity: "Malaga" })).to.equal(14);
    expect(deriveZoomFromFields({ state: "Andalusia" })).to.equal(8);
    expect(deriveZoomFromFields({ countryName: "Spain" })).to.equal(5);
    expect(deriveZoomFromFields()).to.equal(DEFAULT_MAP_ZOOM);
  });

  it("normalizes bounding boxes and country fit behavior", () => {
    // Bounding boxes are parsed only when all four values are valid.
    expect(normalizeBoundingBox(["1", "2", "3", "4"])).to.deep.equal([1, 2, 3, 4]);
    expect(normalizeBoundingBox(["1", "broken", "3", "4"])).to.equal(null);
    expect(normalizeBoundingBox(["1", "2"])).to.equal(null);

    // Country-level results fit their full bounds.
    expect(shouldFitBoundsForResult({ addresstype: "country" })).to.equal(true);
    expect(shouldFitBoundsForResult({ type: "country" })).to.equal(true);
    expect(shouldFitBoundsForResult({ type: "city" })).to.equal(false);
  });
});
