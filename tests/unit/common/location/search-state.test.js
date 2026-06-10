import { expect } from "@open-wc/testing";

import {
  applyLocationSearchValueUpdates,
  getClearedLocationSearchState,
  getDefaultLocationSearchInternalState,
  getDefaultLocationSearchProperties,
  getFailedLocationSearchState,
  getFinishedLocationSearchState,
  getHiddenLocationSearchState,
  getInitialLocationSearchValues,
  getStartedLocationSearchState,
  getSuccessfulLocationSearchState,
} from "/static/js/common/location/search-state.js";

describe("location search state", () => {
  it("builds hidden dropdown state", () => {
    // Hidden dropdown state clears results and loading indicators.
    expect(getHiddenLocationSearchState()).to.deep.equal({
      showDropdown: false,
      searchResults: [],
      highlightedIndex: -1,
      isSearching: false,
    });
  });

  it("builds started search state", () => {
    // Started search state prepares the dropdown for fresh results.
    expect(getStartedLocationSearchState()).to.deep.equal({
      showDropdown: true,
      searchResults: [],
      searchError: null,
      highlightedIndex: -1,
      isSearching: true,
    });
  });

  it("builds cleared search state", () => {
    // Cleared search state resets the input and hides the dropdown.
    expect(getClearedLocationSearchState()).to.deep.equal({
      searchQuery: "",
      searchError: null,
      showDropdown: false,
      searchResults: [],
      highlightedIndex: -1,
      isSearching: false,
    });
  });

  it("builds completed search result states", () => {
    // Search result states normalize success, failure, and finished loading.
    const results = [{ place_id: 1, display_name: "Malaga" }];
    expect(getSuccessfulLocationSearchState(results)).to.deep.equal({
      searchResults: results,
      searchError: null,
    });
    expect(getFailedLocationSearchState(new Error("Network unavailable"))).to.deep.equal({
      searchResults: [],
      searchError: "Network unavailable",
    });
    expect(getFailedLocationSearchState(null)).to.deep.equal({
      searchResults: [],
      searchError: "Unable to search for locations right now.",
    });
    expect(getFinishedLocationSearchState()).to.deep.equal({
      isSearching: false,
    });
  });

  it("builds default public properties and internal state", () => {
    // Default public properties mirror the component constructor defaults.
    expect(getDefaultLocationSearchProperties()).to.include({
      placeholderText: "Search for a venue or address...",
      venueNameFieldId: "",
      venueNameFieldName: "",
      initialVenueName: "",
      disabled: false,
    });

    // Default internal state starts with empty values and no active search.
    expect(getDefaultLocationSearchInternalState()).to.include({
      isSearching: false,
      searchQuery: "",
      highlightedIndex: -1,
      abortController: null,
      outsidePointerHandler: null,
      latitudeValue: "",
      longitudeValue: "",
      mapVisible: false,
      searchError: null,
    });
  });

  it("builds initial location values from public attributes", () => {
    // Initial value payload keeps only the public initial value fields.
    expect(
      getInitialLocationSearchValues({
        initialVenueName: "Main Hall",
        initialVenueAddress: "1 Main St",
        initialVenueCity: "Malaga",
        initialVenueZipCode: "29001",
        initialState: "Andalusia",
        initialCountryName: "Spain",
        initialCountryCode: "ES",
        initialLatitude: "36.7213",
        initialLongitude: "-4.4214",
        venueNameFieldId: "ignored",
      }),
    ).to.deep.equal({
      initialVenueName: "Main Hall",
      initialVenueAddress: "1 Main St",
      initialVenueCity: "Malaga",
      initialVenueZipCode: "29001",
      initialState: "Andalusia",
      initialCountryName: "Spain",
      initialCountryCode: "ES",
      initialLatitude: "36.7213",
      initialLongitude: "-4.4214",
    });
  });

  it("applies normalized location value updates to private fields", () => {
    // Start with existing values so missing fields can be verified unchanged.
    const target = {
      _venueNameValue: "Old hall",
      _venueAddressValue: "Old address",
      _latitudeValue: "36",
    };

    // Apply a partial normalized location value patch.
    applyLocationSearchValueUpdates(target, {
      venueNameValue: "Main hall",
      latitudeValue: "37",
    });

    // Only supplied value fields are updated.
    expect(target).to.deep.equal({
      _venueNameValue: "Main hall",
      _venueAddressValue: "Old address",
      _latitudeValue: "37",
    });
  });
});
