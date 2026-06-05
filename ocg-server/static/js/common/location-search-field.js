import { html, repeat } from "/static/vendor/js/lit-all.v3.3.1.min.js";
import { LitWrapper } from "/static/js/common/lit-wrapper.js";
import { isElementHidden } from "/static/js/common/dom.js";
import {
  getCoordinateFieldConfig,
  getEmptyLocationValues,
  getExternalLocationFieldUpdates,
  getExternalLocationFieldIds,
  getInitialLocationValues,
  getInternalLocationValueUpdates,
  hasInternalLocationFields,
} from "/static/js/common/location-field-config.js";
import { searchNominatimLocations } from "/static/js/common/location-search-api.js";
import { getLocationSearchKeyAction } from "/static/js/common/location-search-keyboard.js";
import {
  getClearedLocationSearchState,
  getHiddenLocationSearchState,
  getStartedLocationSearchState,
} from "/static/js/common/location-search-state.js";
import {
  getLocationInputId,
  getLocationLegendText,
  getLocationResultText,
  getLocationDisabledInputClasses,
  isLocationSearchButtonDisabled,
  isVenueLocationContext,
  shouldRenderLocationDropdown,
} from "/static/js/common/location-search-display.js";
import { LocationMapPreview } from "/static/js/common/location-map-preview.js";
import {
  DEFAULT_MAP_ZOOM,
  deriveZoomFromFields,
  deriveZoomFromLocation,
  extractAddress,
  normalizeBoundingBox,
  parseCoordinate,
  shouldFitBoundsForResult,
} from "/static/js/common/location-search-utils.js";
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
    this.placeholderText = "Search for a venue or address...";
    this.venueNameFieldId = "";
    this.venueAddressFieldId = "";
    this.venueCityFieldId = "";
    this.venueZipCodeFieldId = "";
    this.stateFieldId = "";
    this.countryFieldId = "";
    this.latitudeFieldId = "";
    this.longitudeFieldId = "";
    this.venueNameFieldName = "";
    this.venueAddressFieldName = "";
    this.venueCityFieldName = "";
    this.venueZipCodeFieldName = "";
    this.stateFieldName = "";
    this.countryNameFieldName = "";
    this.countryCodeFieldName = "";
    this.latitudeFieldName = "";
    this.longitudeFieldName = "";
    this.initialVenueName = "";
    this.initialVenueAddress = "";
    this.initialVenueCity = "";
    this.initialVenueZipCode = "";
    this.initialState = "";
    this.initialCountryName = "";
    this.initialCountryCode = "";
    this.initialLatitude = "";
    this.initialLongitude = "";

    this._isSearching = false;
    this._searchResults = [];
    this._searchQuery = "";
    this._highlightedIndex = -1;
    this._abortController = null;
    this._outsidePointerHandler = null;
    this._latitudeValue = "";
    this._longitudeValue = "";
    this._venueNameValue = "";
    this._venueAddressValue = "";
    this._venueCityValue = "";
    this._venueZipCodeValue = "";
    this._stateValue = "";
    this._countryNameValue = "";
    this._countryCodeValue = "";
    this._showDropdown = false;
    this._mapVisible = false;
    this._mapElementId = createMapElementId();
    this._mapZoom = DEFAULT_MAP_ZOOM;
    this._mapBoundingBox = null;
    this._shouldFitBounds = false;
    this._mapPreview = new LocationMapPreview(this._mapElementId);
    this._searchError = null;
    this.disabled = false;
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
    this._applyLocationValues(
      getInitialLocationValues({
        initialVenueName: this.initialVenueName,
        initialVenueAddress: this.initialVenueAddress,
        initialVenueCity: this.initialVenueCity,
        initialVenueZipCode: this.initialVenueZipCode,
        initialState: this.initialState,
        initialCountryName: this.initialCountryName,
        initialCountryCode: this.initialCountryCode,
        initialLatitude: this.initialLatitude,
        initialLongitude: this.initialLongitude,
      }),
    );
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
      this._searchResults = results;
      this._searchError = null;
    } catch (err) {
      if (err.name === "AbortError") {
        return;
      }
      console.error("Error searching locations:", err);
      this._searchResults = [];
      this._searchError = err?.message || "Unable to search for locations right now.";
    } finally {
      this._isSearching = false;
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
    const hasUpdate = (key) => Object.prototype.hasOwnProperty.call(updates, key);
    if (hasUpdate("venueNameValue")) this._venueNameValue = updates.venueNameValue;
    if (hasUpdate("venueAddressValue")) {
      this._venueAddressValue = updates.venueAddressValue;
    }
    if (hasUpdate("venueCityValue")) this._venueCityValue = updates.venueCityValue;
    if (hasUpdate("venueZipCodeValue")) {
      this._venueZipCodeValue = updates.venueZipCodeValue;
    }
    if (hasUpdate("stateValue")) this._stateValue = updates.stateValue;
    if (hasUpdate("countryNameValue")) this._countryNameValue = updates.countryNameValue;
    if (hasUpdate("countryCodeValue")) this._countryCodeValue = updates.countryCodeValue;
    if (hasUpdate("latitudeValue")) this._latitudeValue = updates.latitudeValue;
    if (hasUpdate("longitudeValue")) this._longitudeValue = updates.longitudeValue;
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
    this._mapVisible = false;
    this._mapZoom = DEFAULT_MAP_ZOOM;
    this._mapBoundingBox = null;
    this._shouldFitBounds = false;

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
  _handleKeyDown(event) {
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
    const shouldRenderDropdown = shouldRenderLocationDropdown({
      showDropdown: this._showDropdown,
      searchQuery: this._searchQuery,
    });
    const searchButtonDisabled = isLocationSearchButtonDisabled({
      disabled: this.disabled,
      searchQuery: this._searchQuery,
      isSearching: this._isSearching,
    });
    const disabledClasses = getLocationDisabledInputClasses(this.disabled);

    return html`
      <div @focusout=${this._handleFocusOut}>
        <div class="mt-2 flex gap-2">
            <div class="relative flex-1">
              <div class="absolute top-3 start-0 flex items-center ps-3 pointer-events-none">
                <div class="svg-icon size-4 icon-search bg-stone-300"></div>
              </div>
              <input
                id="location-search-input"
                type="text"
                class="input-primary peer ps-9 ${disabledClasses}"
                placeholder=${this.placeholderText}
                .value=${this._searchQuery}
                @input=${this._handleSearchInput}
                @keydown=${this._handleKeyDown}
                autocomplete="off"
                autocorrect="off"
                autocapitalize="off"
                spellcheck="false"
                aria-expanded=${shouldRenderDropdown}
                aria-haspopup="listbox"
                aria-autocomplete="list"
                aria-label="Search for a location"
                ?disabled=${this.disabled}
              />
              ${
                this._searchQuery
                  ? html`
                      <div class="absolute end-1.5 top-1.5">
                        <button
                          type="button"
                          class="cursor-pointer mt-0.5"
                          @click=${this._clearSearch}
                          ?disabled=${this.disabled}
                        >
                          <div class="svg-icon size-5 bg-stone-400 hover:bg-stone-700 icon-close"></div>
                        </button>
                      </div>
                    `
                  : ""
              }
              ${shouldRenderDropdown ? this._renderDropdown() : ""}
            </div>
            <button
              type="button"
              class="btn-primary"
              @pointerdown=${this._handleSearchButtonPointerDown}
              @click=${this._triggerSearch}
              ?disabled=${searchButtonDisabled}
            >
              Search
            </button>
          </div>
        </div>
        <p class="form-legend mt-3">
          If any fields remain empty or incomplete after the search, fill in the missing details manually.
        </p>
      </div>
    `;
  }

  /**
   * Renders the search results dropdown.
   * @returns {import('lit').TemplateResult} Dropdown template
   * @private
   */
  _renderDropdown() {
    return html`
      <div
        class="absolute z-50 mt-2 w-full bg-white rounded-lg shadow-lg border border-stone-200 max-h-80 overflow-y-auto"
        role="listbox"
      >
        ${this._isSearching
          ? html`
              <div class="p-4 text-center">
                <div class="inline-flex items-center gap-2 text-stone-600">
                  <div
                    class="animate-spin w-4 h-4 border-2 border-stone-300 border-t-stone-600 rounded-full"
                  ></div>
                  Searching...
                </div>
              </div>
            `
          : this._searchError
            ? html`
                <div class="p-4 text-center text-stone-500">
                  <p class="text-sm font-medium text-stone-600">Unable to load locations</p>
                  <p class="text-sm">${this._searchError}</p>
                </div>
              `
            : this._searchResults.length === 0
              ? html`
                  <div class="p-4 text-center text-stone-500">
                    <p class="text-sm">No locations found for "${this._searchQuery}"</p>
                  </div>
                `
              : html`
                  <div class="py-1">
                    ${repeat(
                      this._searchResults,
                      (r) => r.place_id,
                      (r, i) => this._renderResult(r, i),
                    )}
                  </div>
                `}
      </div>
    `;
  }

  /**
   * Handles latitude input change.
   * @param {Event} event - Input event
   * @private
   */
  _handleLatitudeInput(event) {
    this._latitudeValue = event.target.value;
  }

  /**
   * Handles longitude input change.
   * @param {Event} event - Input event
   * @private
   */
  _handleLongitudeInput(event) {
    this._longitudeValue = event.target.value;
  }

  /**
   * @param {Event} event
   * @private
   */
  _handleVenueNameInput(event) {
    this._venueNameValue = event.target.value;
  }

  /**
   * @param {Event} event
   * @private
   */
  _handleVenueAddressInput(event) {
    this._venueAddressValue = event.target.value;
  }

  /**
   * @param {Event} event
   * @private
   */
  _handleVenueCityInput(event) {
    this._venueCityValue = event.target.value;
  }

  /**
   * @param {Event} event
   * @private
   */
  _handleVenueZipCodeInput(event) {
    this._venueZipCodeValue = event.target.value;
  }

  /**
   * @param {Event} event
   * @private
   */
  _handleStateInput(event) {
    this._stateValue = event.target.value;
  }

  /**
   * @param {Event} event
   * @private
   */
  _handleCountryNameInput(event) {
    this._countryNameValue = event.target.value;
  }

  /**
   * @param {Event} event
   * @private
   */
  _handleCountryCodeInput(event) {
    this._countryCodeValue = event.target.value;
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
    return {
      venueNameFieldId: this.venueNameFieldId,
      venueAddressFieldId: this.venueAddressFieldId,
      venueCityFieldId: this.venueCityFieldId,
      venueZipCodeFieldId: this.venueZipCodeFieldId,
      stateFieldId: this.stateFieldId,
      countryFieldId: this.countryFieldId,
      latitudeFieldId: this.latitudeFieldId,
      longitudeFieldId: this.longitudeFieldId,
      venueNameFieldName: this.venueNameFieldName,
      venueAddressFieldName: this.venueAddressFieldName,
      venueCityFieldName: this.venueCityFieldName,
      venueZipCodeFieldName: this.venueZipCodeFieldName,
      stateFieldName: this.stateFieldName,
      countryNameFieldName: this.countryNameFieldName,
      countryCodeFieldName: this.countryCodeFieldName,
    };
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
   * @returns {boolean}
   * @private
   */
  _isVenueContext() {
    return isVenueLocationContext({
      venueNameFieldName: this.venueNameFieldName,
      venueAddressFieldName: this.venueAddressFieldName,
      venueZipCodeFieldName: this.venueZipCodeFieldName,
    });
  }

  /**
   * @param {"city" | "zip" | "state" | "country"} kind
   * @returns {string}
   * @private
   */
  _getLegendText(kind) {
    return getLocationLegendText(kind, this._isVenueContext());
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

    const hiddenCountryCodeInput = this.countryCodeFieldName
      ? html`
          <input
            type="hidden"
            name="${this.countryCodeFieldName}"
            id="${this._getInputId(this.countryCodeFieldName)}"
            .value=${this._countryCodeValue}
          />
        `
      : "";
    const disabledClasses = getLocationDisabledInputClasses(this.disabled);

    return html`
      <div class="mt-8 grid grid-cols-1 gap-x-6 gap-y-8 md:grid-cols-6 max-w-5xl">
        ${hiddenCountryCodeInput}
        ${this.venueNameFieldName
          ? html`
              <div class="col-span-full lg:col-span-3">
                <label for="${this._getInputId(this.venueNameFieldName)}" class="form-label"
                  >Venue Name</label
                >
                <div class="mt-2">
                  <input
                    type="text"
                    name="${this.venueNameFieldName}"
                    id="${this._getInputId(this.venueNameFieldName)}"
                    class="input-primary ${disabledClasses}"
                    .value=${this._venueNameValue}
                    ?disabled=${this.disabled}
                    @input=${this._handleVenueNameInput}
                  />
                </div>
                <p class="form-legend">Name of the venue where the event takes place.</p>
              </div>
            `
          : ""}
        ${this.venueAddressFieldName
          ? html`
              <div class="col-span-full lg:col-span-4">
                <label for="${this._getInputId(this.venueAddressFieldName)}" class="form-label"
                  >Address</label
                >
                <div class="mt-2">
                  <input
                    type="text"
                    name="${this.venueAddressFieldName}"
                    id="${this._getInputId(this.venueAddressFieldName)}"
                    class="input-primary ${disabledClasses}"
                    .value=${this._venueAddressValue}
                    ?disabled=${this.disabled}
                    @input=${this._handleVenueAddressInput}
                  />
                </div>
                <p class="form-legend">Street address of the venue.</p>
              </div>
            `
          : ""}
        ${this.venueCityFieldName
          ? html`
              <div class="col-span-full lg:col-span-2">
                <label for="${this._getInputId(this.venueCityFieldName)}" class="form-label">City</label>
                <div class="mt-2">
                  <input
                    type="text"
                    name="${this.venueCityFieldName}"
                    id="${this._getInputId(this.venueCityFieldName)}"
                    class="input-primary ${disabledClasses}"
                    autocomplete="off"
                    autocorrect="off"
                    autocapitalize="off"
                    spellcheck="false"
                    .value=${this._venueCityValue}
                    ?disabled=${this.disabled}
                    @input=${this._handleVenueCityInput}
                  />
                </div>
                <p class="form-legend">${this._getLegendText("city")}</p>
              </div>
            `
          : ""}
        ${this.venueZipCodeFieldName
          ? html`
              <div class="col-span-full lg:col-span-2">
                <label for="${this._getInputId(this.venueZipCodeFieldName)}" class="form-label"
                  >Zip Code</label
                >
                <div class="mt-2">
                  <input
                    type="text"
                    name="${this.venueZipCodeFieldName}"
                    id="${this._getInputId(this.venueZipCodeFieldName)}"
                    class="input-primary ${disabledClasses}"
                    .value=${this._venueZipCodeValue}
                    ?disabled=${this.disabled}
                    @input=${this._handleVenueZipCodeInput}
                  />
                </div>
                <p class="form-legend">${this._getLegendText("zip")}</p>
              </div>
            `
          : ""}
        ${this.stateFieldName
          ? html`
              <div class="col-span-full lg:col-span-2">
                <label for="${this._getInputId(this.stateFieldName)}" class="form-label"
                  >State/Province</label
                >
                <div class="mt-2">
                  <input
                    type="text"
                    name="${this.stateFieldName}"
                    id="${this._getInputId(this.stateFieldName)}"
                    class="input-primary ${disabledClasses}"
                    autocomplete="off"
                    autocorrect="off"
                    autocapitalize="off"
                    spellcheck="false"
                    .value=${this._stateValue}
                    ?disabled=${this.disabled}
                    @input=${this._handleStateInput}
                  />
                </div>
                <p class="form-legend">${this._getLegendText("state")}</p>
              </div>
            `
          : ""}
        ${this.countryNameFieldName
          ? html`
              <div class="col-span-full lg:col-span-2">
                <label for="${this._getInputId(this.countryNameFieldName)}" class="form-label">Country</label>
                <div class="mt-2">
                  <input
                    type="text"
                    name="${this.countryNameFieldName}"
                    id="${this._getInputId(this.countryNameFieldName)}"
                    class="input-primary ${disabledClasses}"
                    autocomplete="off"
                    autocorrect="off"
                    autocapitalize="off"
                    spellcheck="false"
                    .value=${this._countryNameValue}
                    ?disabled=${this.disabled}
                    @input=${this._handleCountryNameInput}
                  />
                </div>
                <p class="form-legend">${this._getLegendText("country")}</p>
              </div>
            `
          : ""}
      </div>
    `;
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

    return html`
      <div class="grid grid-cols-2 gap-4 mt-6">
        <div>
          <label for="${this._getInputId(latitudeName)}" class="form-label">Latitude</label>
          <div class="mt-2">
            <input
              type="number"
              step="any"
              id="${this._getInputId(latitudeName)}"
              name="${latitudeName}"
              class="input-primary ${disabledClasses}"
              .value=${this._latitudeValue}
              ?disabled=${this.disabled}
              @input=${this._handleLatitudeInput}
            />
          </div>
        </div>
        <div>
          <label for="${this._getInputId(longitudeName)}" class="form-label">Longitude</label>
          <div class="mt-2">
            <input
              type="number"
              step="any"
              id="${this._getInputId(longitudeName)}"
              name="${longitudeName}"
              class="input-primary ${disabledClasses}"
              .value=${this._longitudeValue}
              ?disabled=${this.disabled}
              @input=${this._handleLongitudeInput}
            />
          </div>
        </div>
      </div>
    `;
  }

  /**
   * Renders a single result item in the dropdown list.
   * @param {Object} result - Nominatim result object to render
   * @param {number} index - Index of the result in the list
   * @returns {import('lit').TemplateResult} The result row template
   * @private
   */
  _renderResult(result, index) {
    const { mainText, secondaryText } = getLocationResultText(result);
    const isHighlighted = index === this._highlightedIndex;
    const rowClass = `flex items-start gap-3 px-4 py-3 cursor-pointer ${
      isHighlighted ? "bg-stone-100" : "hover:bg-stone-50"
    }`;

    return html`
      <div
        class=${rowClass}
        role="option"
        aria-selected=${isHighlighted}
        @pointerdown=${(event) => {
          event.preventDefault();
          this._selectLocation(result);
        }}
        @mouseenter=${() => {
          this._highlightedIndex = index;
        }}
      >
        <div class="shrink-0 mt-0.5">
          <div class="svg-icon size-4 bg-stone-400 icon-marker -mt-px"></div>
        </div>
        <div class="flex-1 min-w-0">
          <h3 class="text-sm font-medium text-stone-900 truncate">${mainText}</h3>
          <p class="text-xs text-stone-500 line-clamp-2">${secondaryText}</p>
        </div>
      </div>
    `;
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
    return {
      mapVisible: this._mapVisible,
      latitudeValue: this._latitudeValue,
      longitudeValue: this._longitudeValue,
      mapZoom: this._mapZoom,
      mapBoundingBox: this._mapBoundingBox,
      shouldFitBounds: this._shouldFitBounds,
    };
  }

  /**
   * @returns {import('lit').TemplateResult}
   * @private
   */
  _renderMapPreview() {
    if (!this._mapVisible || !this._hasValidCoordinates()) return html``;

    return html`
      <div class="mt-6 max-w-5xl">
        <label class="form-label">Location Preview</label>
        <div class="mt-2 rounded-lg border border-stone-200 overflow-hidden h-48">
          <div id="${this._mapElementId}" class="w-full h-full"></div>
        </div>
      </div>
    `;
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
