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
