import { expect } from "@open-wc/testing";

import {
  getClearedLocationSearchState,
  getHiddenLocationSearchState,
  getStartedLocationSearchState,
} from "/static/js/common/location-search-state.js";

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
});
