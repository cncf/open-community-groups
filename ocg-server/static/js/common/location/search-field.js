import { html } from "/static/vendor/js/lit-all.v3.3.1.min.js";
import { LitWrapper } from "/static/js/common/lit-wrapper.js";
import { isElementHidden } from "/static/js/common/dom.js";
import {
  getCoordinateFieldConfig,
  getEmptyLocationValues,
  getExternalLocationFieldUpdates,
  getExternalLocationFieldIds,
  getInitialLocationValues,
  getInternalLocationValueUpdates,
  getLocationFieldConfig,
  hasInternalLocationFields,
} from "/static/js/common/location/field-config.js";
import { searchNominatimLocations } from "/static/js/common/location/search-api.js";
import { getLocationSearchKeyAction } from "/static/js/common/location/search-keyboard.js";
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
import {
  getLocationInputId,
  getLocationDisabledInputClasses,
  getLocationTextFieldValueKey,
} from "/static/js/common/location/search-display.js";
import {
  renderLocationCoordinateInputs,
  renderLocationSearchInterface,
  renderLocationTextFields,
} from "/static/js/common/location/search-renderer.js";
import { LocationMapPreview } from "/static/js/common/location/map-preview.js";
import {
  getClearedLocationMapPreviewState,
  getLocationMapPreviewState,
  renderLocationMapPreview,
} from "/static/js/common/location/map-preview-renderer.js";
import {
  DEFAULT_MAP_ZOOM,
  deriveZoomFromFields,
  deriveZoomFromLocation,
  extractAddress,
  normalizeBoundingBox,
  parseCoordinate,
  shouldFitBoundsForResult,
} from "/static/js/common/location/search-utils.js";
import { setTextValue } from "/static/js/common/utils.js";

let mapIdCounter = 0;
const createMapElementId = () => {
  mapIdCounter += 1;
  return `location-search-field-map-${mapIdCounter}`;
};

/**
 * LocationSearchField component for searching and editing location details using Nominatim.
 */
export class LocationSearchField extends LitWrapper {
  /**
   * Component properties definition
   * @property {string} placeholderText - Custom placeholder for search input
   * @property {string} venueNameFieldId - ID of the venue name input field
   * @property {string} venueAddressFieldId - ID of the venue address input field
   * @property {string} venueCityFieldId - ID of the venue city input field
   * @property {string} venueZipCodeFieldId - ID of the venue zip code input field
   * @property {string} stateFieldId - ID of the state/province input field
   * @property {string} countryFieldId - ID of the country input field
   * @property {string} latitudeFieldId - ID of the latitude input field
   * @property {string} longitudeFieldId - ID of the longitude input field
   * @property {string} venueNameFieldName - Input name for venue name field
   * @property {string} venueAddressFieldName - Input name for venue address field
   * @property {string} venueCityFieldName - Input name for venue city field
   * @property {string} venueZipCodeFieldName - Input name for venue zip code field
   * @property {string} stateFieldName - Input name for the state/province field
   * @property {string} countryNameFieldName - Input name for the country name field
   * @property {string} countryCodeFieldName - Input name for the country code field
   * @property {string} latitudeFieldName - Input name for latitude
   * @property {string} longitudeFieldName - Input name for longitude
   * @property {string} initialVenueName - Initial venue name value
   * @property {string} initialVenueAddress - Initial venue address value
   * @property {string} initialVenueCity - Initial venue city value
   * @property {string} initialVenueZipCode - Initial venue zip code value
   * @property {string} initialState - Initial state/province value
   * @property {string} initialCountryName - Initial country name value
   * @property {string} initialCountryCode - Initial country code value
   * @property {boolean} _isSearching - Internal loading indicator state
   * @property {Array} _searchResults - Internal search results collection
   * @property {string} _searchQuery - Internal current search query string
   * @property {number} _highlightedIndex - Internal index of highlighted result
   * @property {boolean} _showDropdown - Whether to render the results dropdown
   */
  static properties = {
    placeholderText: { type: String, attribute: "placeholder-text" },
    venueNameFieldId: { type: String, attribute: "venue-name-field-id" },
    venueAddressFieldId: { type: String, attribute: "venue-address-field-id" },
    venueCityFieldId: { type: String, attribute: "venue-city-field-id" },
    venueZipCodeFieldId: { type: String, attribute: "venue-zip-code-field-id" },
    stateFieldId: { type: String, attribute: "state-field-id" },
    countryFieldId: { type: String, attribute: "country-field-id" },
    latitudeFieldId: { type: String, attribute: "latitude-field-id" },
    longitudeFieldId: { type: String, attribute: "longitude-field-id" },
    venueNameFieldName: { type: String, attribute: "venue-name-field-name" },
    venueAddressFieldName: { type: String, attribute: "venue-address-field-name" },
    venueCityFieldName: { type: String, attribute: "venue-city-field-name" },
    venueZipCodeFieldName: { type: String, attribute: "venue-zip-code-field-name" },
    stateFieldName: { type: String, attribute: "state-field-name" },
    countryNameFieldName: { type: String, attribute: "country-name-field-name" },
    countryCodeFieldName: { type: String, attribute: "country-code-field-name" },
    latitudeFieldName: { type: String, attribute: "latitude-field-name" },
    longitudeFieldName: { type: String, attribute: "longitude-field-name" },
    initialVenueName: { type: String, attribute: "initial-venue-name" },
    initialVenueAddress: { type: String, attribute: "initial-venue-address" },
    initialVenueCity: { type: String, attribute: "initial-venue-city" },
    initialVenueZipCode: { type: String, attribute: "initial-venue-zip-code" },
    initialState: { type: String, attribute: "initial-state" },
    initialCountryName: { type: String, attribute: "initial-country-name" },
    initialCountryCode: { type: String, attribute: "initial-country-code" },
    initialLatitude: { type: String, attribute: "initial-latitude" },
    initialLongitude: { type: String, attribute: "initial-longitude" },
    _isSearching: { type: Boolean, state: true },
    _searchResults: { type: Array, state: true },
    _searchQuery: { type: String, state: true },
    _highlightedIndex: { type: Number, state: true },
    _searchError: { type: String, state: true },
    _abortController: { type: Object, state: true },
    _latitudeValue: { type: String, state: true },
    _longitudeValue: { type: String, state: true },
    _venueNameValue: { type: String, state: true },
    _venueAddressValue: { type: String, state: true },
    _venueCityValue: { type: String, state: true },
    _venueZipCodeValue: { type: String, state: true },
    _stateValue: { type: String, state: true },
    _countryNameValue: { type: String, state: true },
    _countryCodeValue: { type: String, state: true },
    _showDropdown: { type: Boolean, state: true },
    _mapVisible: { type: Boolean, state: true },
    disabled: { type: Boolean },
  };

  constructor() {
    super();
    Object.assign(this, getDefaultLocationSearchProperties());
    const defaultInternalState = getDefaultLocationSearchInternalState();
    this._applySearchState(defaultInternalState);
    this._applyLocationValues(defaultInternalState);
    this._abortController = defaultInternalState.abortController;
    this._outsidePointerHandler = defaultInternalState.outsidePointerHandler;
    this._mapVisible = defaultInternalState.mapVisible;
    this._mapElementId = createMapElementId();
    this._mapZoom = DEFAULT_MAP_ZOOM;
    this._mapBoundingBox = null;
    this._shouldFitBounds = false;
    this._mapPreview = new LocationMapPreview(this._mapElementId);
  }

  get _leafletMap() {
    return this._mapPreview.map;
  }

  set _leafletMap(map) {
    this._mapPreview.map = map;
  }

  get _leafletMarker() {
    return this._mapPreview.marker;
  }

  set _leafletMarker(marker) {
    this._mapPreview.marker = marker;
  }

  connectedCallback() {
    super.connectedCallback();
    this._applyLocationValues(getInitialLocationValues(getInitialLocationSearchValues(this)));
    this._mapZoom = this._deriveZoomFromFields();

    if (this._hasValidCoordinates() && !this._isInsideHiddenContent()) {
      this.updateComplete.then(() => {
        this.showMapPreview();
      });
    }

    if (!this._outsidePointerHandler) {
      this._outsidePointerHandler = (event) => this._handleOutsidePointer(event);
    }
    document.addEventListener("pointerdown", this._outsidePointerHandler);
  }

  disconnectedCallback() {
    super.disconnectedCallback();
    this._abortSearch();
    this._mapPreview.destroy();
    if (this._outsidePointerHandler) {
      document.removeEventListener("pointerdown", this._outsidePointerHandler);
    }
  }

  /**
   * @returns {boolean}
   * @private
   */
  _hasValidCoordinates() {
    const lat = parseCoordinate(this._latitudeValue);
    const lng = parseCoordinate(this._longitudeValue);
    return lat !== null && lng !== null;
  }

  /**
   * Hides the dropdown results and aborts any in-flight search.
   * @private
   */
  _hideDropdown() {
    this._applySearchState(getHiddenLocationSearchState());
    this._abortSearch();
  }

  /**
   * Programmatically focus the input element after the component is rendered.
   */
  focusInput() {
    this.updateComplete.then(() => {
      const input = this.renderRoot?.querySelector?.("#location-search-input");
      if (input) input.focus();
    });
  }

  /**
   * Clears the current query and results and restores the focus to the input.
   * @private
   */
  _clearSearch() {
    this._applySearchState(getClearedLocationSearchState());
    this._abortSearch();
    this.focusInput();
  }

  /**
   * Ensures the map preview is rendered and synced if coordinates are available.
   */
  showMapPreview() {
    if (!this._hasValidCoordinates()) {
      return;
    }
    if (!this._mapVisible) {
      this._mapVisible = true;
      this.updateComplete.then(() => {
        this._syncMapPreview();
      });
      return;
    }
    this._syncMapPreview();
  }

  /**
   * Handles input changes without triggering search (button-triggered now).
   * @param {Event} event - Input event from the search field
   * @private
   */
  _handleSearchInput(event) {
    const query = event.target.value.trim();
    this._searchQuery = query;
    this._hideDropdown();
  }

  /**
   * Triggers the search when the search button is clicked.
   * @private
   */
  _triggerSearch() {
    if (this._searchQuery.length < 3) {
      this._hideDropdown();
      return;
    }
    this._applySearchState(getStartedLocationSearchState());
    this._performSearch(this._searchQuery);
  }

  /**
   * Applies a normalized search-state patch to the component.
   * @param {Object} state Search state patch.
   * @private
   */
  _applySearchState(state) {
    if (Object.prototype.hasOwnProperty.call(state, "showDropdown")) {
      this._showDropdown = state.showDropdown;
    }
    if (Object.prototype.hasOwnProperty.call(state, "searchResults")) {
      this._searchResults = state.searchResults;
    }
    if (Object.prototype.hasOwnProperty.call(state, "highlightedIndex")) {
      this._highlightedIndex = state.highlightedIndex;
    }
    if (Object.prototype.hasOwnProperty.call(state, "isSearching")) {
      this._isSearching = state.isSearching;
    }
    if (Object.prototype.hasOwnProperty.call(state, "searchQuery")) {
      this._searchQuery = state.searchQuery;
    }
    if (Object.prototype.hasOwnProperty.call(state, "searchError")) {
      this._searchError = state.searchError;
    }
  }

  /**
   * Aborts the active location search request.
   * @private
   */
  _abortSearch() {
    if (this._abortController) {
      this._abortController.abort();
      this._abortController = null;
    }
  }

  /**
   * Performs the search request to Nominatim API and updates results.
   * @param {string} query - The search query to send to Nominatim
   * @private
   */
  async _performSearch(query) {
    this._abortController = new AbortController();

    try {
      const results = await searchNominatimLocations(query, this._abortController.signal);
      this._applySearchState(getSuccessfulLocationSearchState(results));
    } catch (err) {
      if (err.name === "AbortError") {
        return;
      }
      console.error("Error searching locations:", err);
      this._applySearchState(getFailedLocationSearchState(err));
    } finally {
      this._applySearchState(getFinishedLocationSearchState());
      this._abortController = null;
    }
  }

  /**
   * Choose a zoom level based on the current manual field values.
   * @returns {number}
   * @private
   */
  _deriveZoomFromFields() {
    return deriveZoomFromFields({
      venueAddress: this._venueAddressValue,
      venueZipCode: this._venueZipCodeValue,
      venueCity: this._venueCityValue,
      state: this._stateValue,
      countryName: this._countryNameValue,
    });
  }

  /**
   * @param {Object} location
   * @private
   */
  _setInternalLocationValues(location) {
    const updates = getInternalLocationValueUpdates(this._getLocationFieldConfig(), location);
    this._applyLocationValues(updates);
  }

  /**
   * Applies normalized location-value updates to the component.
   * @param {Object} updates Location value patch.
   * @private
   */
  _applyLocationValues(updates) {
    applyLocationSearchValueUpdates(this, updates);
  }

  /**
   * Handles selection of a location result and populates form fields.
   * @param {Object} result - Selected Nominatim result object
   * @private
   */
  _selectLocation(result) {
    const location = extractAddress(result);
    this._mapZoom = deriveZoomFromLocation(result);
    this._mapBoundingBox = normalizeBoundingBox(result.boundingbox);
    this._shouldFitBounds = shouldFitBoundsForResult(result);

    this._setInternalLocationValues(location);
    this.showMapPreview();

    for (const update of this._getExternalFieldUpdates(location)) {
      setTextValue(update.fieldId, update.value);
    }

    this.dispatchEvent(
      new CustomEvent("location-selected", {
        detail: location,
        bubbles: true,
      }),
    );

    this._clearSearch();
  }

  /**
   * Clears all configured location fields and removes readonly state.
   * Can be called externally to reset the form fields.
   */
  clearLocationFields() {
    this._applyLocationValues(getEmptyLocationValues());

    for (const fieldId of this._getExternalFieldIds()) {
      setTextValue(fieldId, "");
    }

    this._mapPreview.reset();
    this._applyMapPreviewState(getClearedLocationMapPreviewState());

    this._clearSearch();

    this.dispatchEvent(
      new CustomEvent("location-cleared", {
        bubbles: true,
      }),
    );
  }

  /**
   * Handles keyboard navigation in the dropdown.
   * @param {KeyboardEvent} event - Keyboard event
   * @private
   */
  _handleKeydown(event) {
    const keyAction = getLocationSearchKeyAction({
      event,
      resultsCount: this._searchResults.length,
      highlightedIndex: this._highlightedIndex,
      query: this._searchQuery,
    });

    if (keyAction.preventDefault) {
      event.preventDefault();
    }

    if (keyAction.action === "hide") {
      this._hideDropdown();
      return;
    }
    if (keyAction.action === "search") {
      this._triggerSearch();
      return;
    }
    if (keyAction.action === "clear") {
      this._clearSearch();
      return;
    }
    if (keyAction.action === "highlight") {
      this._highlightedIndex = keyAction.highlightedIndex;
      return;
    }
    if (
      keyAction.action === "select" &&
      this._highlightedIndex >= 0 &&
      this._highlightedIndex < this._searchResults.length
    ) {
      this._selectLocation(this._searchResults[this._highlightedIndex]);
    }
  }

  /**
   * Hides dropdown when clicking outside of the component.
   * @param {Event} event - Pointer event
   * @private
   */
  _handleOutsidePointer(event) {
    if (this.contains(event.target)) return;
    this._hideDropdown();
  }

  /**
   * Hides dropdown when focus leaves the component.
   * @private
   */
  _handleFocusOut() {
    queueMicrotask(() => {
      if (!this.matches(":focus-within")) {
        this._hideDropdown();
      }
    });
  }

  /**
   * Keeps focusout from re-rendering the search area before Chromium fires click.
   * @param {PointerEvent} event - Pointer event from the search button
   * @private
   */
  _handleSearchButtonPointerDown(event) {
    event.preventDefault();
  }

  /**
   * Renders the search interface with input and button.
   * @returns {import('lit').TemplateResult} Search interface template
   * @private
   */
  _renderSearchInterface() {
    return renderLocationSearchInterface({
      disabled: this.disabled,
      highlightedIndex: this._highlightedIndex,
      isSearching: this._isSearching,
      onClearSearch: () => this._clearSearch(),
      onFocusOut: () => this._handleFocusOut(),
      onHighlight: (index) => {
        this._highlightedIndex = index;
      },
      onKeyDown: (event) => this._handleKeydown(event),
      onSearchButtonPointerDown: (event) => this._handleSearchButtonPointerDown(event),
      onSearchInput: (event) => this._handleSearchInput(event),
      onSelect: (result) => this._selectLocation(result),
      onTriggerSearch: () => this._triggerSearch(),
      placeholderText: this.placeholderText,
      searchError: this._searchError,
      searchQuery: this._searchQuery,
      searchResults: this._searchResults,
      showDropdown: this._showDropdown,
    });
  }

  /**
   * @param {string} valueKey Component value key.
   * @param {Event} event Input event.
   * @private
   */
  _setLocationValueFromInput(valueKey, event) {
    this[valueKey] = event.target.value;
  }

  /**
   * @param {string} handlerName Location text field handler name.
   * @returns {Function}
   * @private
   */
  _getTextFieldInputHandler(handlerName) {
    const valueKey = getLocationTextFieldValueKey(handlerName);
    if (!valueKey) {
      return () => {};
    }

    return (event) => this._setLocationValueFromInput(valueKey, event);
  }

  /**
   * @returns {boolean}
   * @private
   */
  _hasInternalFields() {
    return hasInternalLocationFields(this._getLocationFieldConfig());
  }

  /**
   * @returns {Array<string>}
   * @private
   */
  _getExternalFieldIds() {
    return getExternalLocationFieldIds(this._getLocationFieldConfig());
  }

  /**
   * @param {Object} location Selected location values.
   * @returns {Array<{fieldId: string, value: string}>}
   * @private
   */
  _getExternalFieldUpdates(location) {
    return getExternalLocationFieldUpdates(this._getLocationFieldConfig(), location);
  }

  /**
   * @returns {Object}
   * @private
   */
  _getLocationFieldConfig() {
    return getLocationFieldConfig(this);
  }

  /**
   * Determines if this component sits inside a hidden tab content.
   * @returns {boolean}
   * @private
   */
  _isInsideHiddenContent() {
    const contentSection = this.closest("[data-content]");
    return isElementHidden(contentSection);
  }

  /**
   * @param {string} inputName
   * @returns {string}
   * @private
   */
  _getInputId(inputName) {
    return getLocationInputId(this.id, inputName);
  }

  /**
   * @returns {import('lit').TemplateResult}
   * @private
   */
  _renderLocationFields() {
    if (!this._hasInternalFields()) return html``;

    return renderLocationTextFields({
      componentId: this.id,
      countryCodeFieldName: this.countryCodeFieldName,
      countryCodeValue: this._countryCodeValue,
      disabled: this.disabled,
      onInput: (handlerName, event) => this._getTextFieldInputHandler(handlerName)(event),
      venueNameFieldName: this.venueNameFieldName,
      venueAddressFieldName: this.venueAddressFieldName,
      venueCityFieldName: this.venueCityFieldName,
      venueZipCodeFieldName: this.venueZipCodeFieldName,
      stateFieldName: this.stateFieldName,
      countryNameFieldName: this.countryNameFieldName,
      venueNameValue: this._venueNameValue,
      venueAddressValue: this._venueAddressValue,
      venueCityValue: this._venueCityValue,
      venueZipCodeValue: this._venueZipCodeValue,
      stateValue: this._stateValue,
      countryNameValue: this._countryNameValue,
    });
  }

  /**
   * Renders the coordinate inputs for manual mode.
   * @returns {import('lit').TemplateResult} Coordinate inputs template
   * @private
   */
  _renderCoordinateInputs() {
    const { hasCoordinateFields, latitudeName, longitudeName } = getCoordinateFieldConfig(
      this._getLocationFieldConfig(),
    );

    if (!hasCoordinateFields) {
      return html``;
    }

    const disabledClasses = getLocationDisabledInputClasses(this.disabled);

    return renderLocationCoordinateInputs({
      disabled: this.disabled,
      disabledClasses,
      latitudeId: this._getInputId(latitudeName),
      latitudeName,
      latitudeValue: this._latitudeValue,
      longitudeId: this._getInputId(longitudeName),
      longitudeName,
      longitudeValue: this._longitudeValue,
      onInput: (valueKey, event) => this._setLocationValueFromInput(valueKey, event),
    });
  }

  async updated(changedProperties) {
    super.updated?.(changedProperties);

    if (changedProperties.has("_latitudeValue") || changedProperties.has("_longitudeValue")) {
      await this._syncMapPreview();
    }
  }

  /**
   * Schedule a map sync so coordinate changes do not overlap.
   * @returns {Promise<unknown>}
   * @private
   */
  _syncMapPreview() {
    return this._mapPreview.sync(this._getMapPreviewState());
  }

  /**
   * Initialize or update the enabled map/marker with the latest coords.
   * @returns {Promise<void>}
   * @private
   */
  async _syncMapPreviewInternal() {
    await this._mapPreview.syncInternal(this._getMapPreviewState());
  }

  /**
   * @returns {Object}
   * @private
   */
  _getMapPreviewState() {
    return getLocationMapPreviewState({
      mapVisible: this._mapVisible,
      latitudeValue: this._latitudeValue,
      longitudeValue: this._longitudeValue,
      mapZoom: this._mapZoom,
      mapBoundingBox: this._mapBoundingBox,
      shouldFitBounds: this._shouldFitBounds,
    });
  }

  /**
   * Applies normalized map preview state to the component.
   * @param {Object} state Map preview state patch.
   * @private
   */
  _applyMapPreviewState(state) {
    this._mapVisible = state.mapVisible;
    this._mapZoom = state.mapZoom;
    this._mapBoundingBox = state.mapBoundingBox;
    this._shouldFitBounds = state.shouldFitBounds;
  }

  /**
   * @returns {import('lit').TemplateResult}
   * @private
   */
  _renderMapPreview() {
    if (!this._mapVisible || !this._hasValidCoordinates()) return html``;

    return renderLocationMapPreview(this._mapElementId);
  }

  /**
   * Renders the full component (search controls, location fields, and coordinates).
   * @returns {import('lit').TemplateResult} Component template
   */
  render() {
    return html`
      <div class="space-y-6">
        ${this._renderSearchInterface()} ${this._renderLocationFields()} ${this._renderCoordinateInputs()}
        ${this._renderMapPreview()}
      </div>
    `;
  }
}

customElements.define("location-search-field", LocationSearchField);
