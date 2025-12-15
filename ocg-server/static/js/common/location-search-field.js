import { html, repeat } from "/static/vendor/js/lit-all.v3.3.1.min.js";
import { LitWrapper } from "/static/js/common/lit-wrapper.js";
import { loadMap } from "/static/js/common/common.js";
import { setTextValue } from "/static/js/common/utils.js";

let mapIdCounter = 0;
const createMapElementId = () => {
  mapIdCounter += 1;
  return `location-search-field-map-${mapIdCounter}`;
};
const DEFAULT_MAP_ZOOM = 15;

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
    this._leafletMap = null;
    this._leafletMarker = null;
    this._mapPreviewSyncPromise = Promise.resolve();
    this.disabled = false;
  }

  connectedCallback() {
    super.connectedCallback();
    this._venueNameValue = this.initialVenueName || "";
    this._venueAddressValue = this.initialVenueAddress || "";
    this._venueCityValue = this.initialVenueCity || "";
    this._venueZipCodeValue = this.initialVenueZipCode || "";
    this._stateValue = this.initialState || "";
    this._countryNameValue = this.initialCountryName || "";
    this._countryCodeValue = this.initialCountryCode || "";
    this._latitudeValue = this.initialLatitude || "";
    this._longitudeValue = this.initialLongitude || "";
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
    if (this._abortController) {
      this._abortController.abort();
    }
    if (this._leafletMap) {
      this._leafletMap.remove();
      this._leafletMap = null;
    }
    this._leafletMarker = null;
    if (this._outsidePointerHandler) {
      document.removeEventListener("pointerdown", this._outsidePointerHandler);
    }
  }

  /**
   * @param {string} value
   * @returns {number|null}
   * @private
   */
  _parseCoordinate(value) {
    if (typeof value !== "string") return null;
    const parsed = Number.parseFloat(value);
    if (Number.isNaN(parsed)) return null;
    return parsed;
  }

  /**
   * @returns {boolean}
   * @private
   */
  _hasValidCoordinates() {
    const lat = this._parseCoordinate(this._latitudeValue);
    const lng = this._parseCoordinate(this._longitudeValue);
    return lat !== null && lng !== null;
  }

  /**
   * Hides the dropdown results and aborts any in-flight search.
   * @private
   */
  _hideDropdown() {
    this._showDropdown = false;
    this._searchResults = [];
    this._highlightedIndex = -1;
    this._isSearching = false;
    if (this._abortController) {
      this._abortController.abort();
      this._abortController = null;
    }
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
    this._searchQuery = "";
    this._hideDropdown();
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
    this._showDropdown = true;
    this._searchResults = [];
    this._highlightedIndex = -1;
    this._isSearching = true;
    this._performSearch(this._searchQuery);
  }

  /**
   * Performs the search request to Nominatim API and updates results.
   * @param {string} query - The search query to send to Nominatim
   * @private
   */
  async _performSearch(query) {
    this._abortController = new AbortController();

    try {
      const params = new URLSearchParams({
        q: query,
        format: "json",
        addressdetails: "1",
        limit: "10", // default limit
        dedupe: "1",
      });

      const response = await fetch(`https://nominatim.openstreetmap.org/search?${params.toString()}`, {
        signal: this._abortController.signal,
        headers: {
          Accept: "application/json",
          "User-Agent": "OpenCommunityGroups/0.5.0 (https://github.com/open-community-groups)",
        },
      });

      if (!response.ok) {
        throw new Error(`HTTP error! status: ${response.status}`);
      }

      const results = await response.json();
      this._searchResults = results;
    } catch (err) {
      if (err.name === "AbortError") {
        return;
      }
      console.error("Error searching locations:", err);
      this._searchResults = [];
    } finally {
      this._isSearching = false;
      this._abortController = null;
    }
  }

  /**
   * Extracts structured address components from a Nominatim result.
   * @param {Object} result - Nominatim search result object
   * @returns {Object} Extracted address components
   * @private
   */
  _extractAddress(result) {
    const addr = result.address || {};

    const streetParts = [addr.house_number, addr.road].filter(Boolean);
    const streetAddress = streetParts.join(" ");

    const city = addr.city || addr.town || addr.village || addr.municipality || addr.county || "";

    const zipCode = addr.postcode || "";

    const venueName =
      addr[result.type] || addr[result.addresstype] || addr.amenity || addr.building || addr.name || "";

    const state = addr.state || addr.province || addr.region || "";

    const country = addr.country || "";
    const countryCode = (addr.country_code || "").toUpperCase();

    console.log("Address", result);

    return {
      venueName,
      venueAddress: streetAddress,
      venueCity: city,
      venueZipCode: zipCode,
      state,
      country,
      countryCode,
      latitude: parseFloat(result.lat),
      longitude: parseFloat(result.lon),
      displayName: result.display_name,
    };
  }

  /**
   * Choose a zoom level based on the selected Nominatim result.
   * @param {Object} result - Nominatim location result
   * @returns {number}
   * @private
   */
  _deriveZoomFromLocation(result) {
    if (!result || typeof result !== "object") return DEFAULT_MAP_ZOOM;
    const type = (result.type || "").toLowerCase();
    const cls = (result.class || "").toLowerCase();
    const zoomByType = {
      country: 5,
      state: 7,
      region: 7,
      province: 7,
      county: 8,
      city: 11,
      town: 11,
      village: 11,
      hamlet: 12,
      municipality: 11,
      postcode: 12,
      residential: 16,
      suburb: 14,
      road: 15,
      street: 15,
      address: 17,
      building: 17,
      house: 17,
      entrance: 17,
    };

    if (Object.prototype.hasOwnProperty.call(zoomByType, type)) {
      return zoomByType[type];
    }
    if (cls === "boundary") {
      return 8;
    }

    const addr = result.address || {};
    if (addr.city || addr.town || addr.village || addr.municipality) {
      return 11;
    }
    if (addr.state || addr.region || addr.province || addr.county) {
      return 7;
    }
    if (addr.country) {
      return 5;
    }

    return DEFAULT_MAP_ZOOM;
  }

  /**
   * Choose a zoom level based on the current manual field values.
   * @returns {number}
   * @private
   */
  _deriveZoomFromFields() {
    const normalize = (value) => (value || "").trim();
    const hasAddress = Boolean(normalize(this._venueAddressValue) || normalize(this._venueZipCodeValue));
    if (hasAddress) {
      return 16;
    }

    if (normalize(this._venueCityValue)) {
      return 12;
    }

    if (normalize(this._stateValue)) {
      return 8;
    }

    if (normalize(this._countryNameValue)) {
      return 5;
    }

    return DEFAULT_MAP_ZOOM;
  }

  /**
   * @param {Object} location
   * @private
   */
  _setInternalLocationValues(location) {
    if (this.venueNameFieldName) this._venueNameValue = location.venueName || "";
    if (this.venueAddressFieldName) this._venueAddressValue = location.venueAddress || "";
    if (this.venueCityFieldName) this._venueCityValue = location.venueCity || "";
    if (this.venueZipCodeFieldName) this._venueZipCodeValue = location.venueZipCode || "";
    if (this.stateFieldName) this._stateValue = location.state || "";
    if (this.countryNameFieldName) this._countryNameValue = location.country || "";
    if (this.countryCodeFieldName) this._countryCodeValue = location.countryCode || "";
    if (this.latitudeFieldName || this.latitudeFieldId) this._latitudeValue = String(location.latitude);
    if (this.longitudeFieldName || this.longitudeFieldId) this._longitudeValue = String(location.longitude);
  }

  /**
   * Handles selection of a location result and populates form fields.
   * @param {Object} result - Selected Nominatim result object
   * @private
   */
  _selectLocation(result) {
    const location = this._extractAddress(result);
    this._mapZoom = this._deriveZoomFromLocation(result);

    this._setInternalLocationValues(location);

    if (this.venueNameFieldId) {
      setTextValue(this.venueNameFieldId, location.venueName);
    }
    if (this.venueAddressFieldId) {
      setTextValue(this.venueAddressFieldId, location.venueAddress);
    }
    if (this.venueCityFieldId) {
      setTextValue(this.venueCityFieldId, location.venueCity);
    }
    if (this.venueZipCodeFieldId) {
      setTextValue(this.venueZipCodeFieldId, location.venueZipCode);
    }
    if (this.stateFieldId) {
      setTextValue(this.stateFieldId, location.state);
    }
    if (this.countryFieldId) {
      setTextValue(this.countryFieldId, location.country);
    }
    if (this.latitudeFieldId) {
      setTextValue(this.latitudeFieldId, String(location.latitude));
    }
    if (this.longitudeFieldId) {
      setTextValue(this.longitudeFieldId, String(location.longitude));
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
    this._venueNameValue = "";
    this._venueAddressValue = "";
    this._venueCityValue = "";
    this._venueZipCodeValue = "";
    this._stateValue = "";
    this._countryNameValue = "";
    this._countryCodeValue = "";
    this._latitudeValue = "";
    this._longitudeValue = "";

    const fieldIds = [
      this.venueNameFieldId,
      this.venueAddressFieldId,
      this.venueCityFieldId,
      this.venueZipCodeFieldId,
      this.stateFieldId,
      this.countryFieldId,
      this.latitudeFieldId,
      this.longitudeFieldId,
    ];

    for (const fieldId of fieldIds) {
      if (fieldId) {
        setTextValue(fieldId, "");
      }
    }

    if (this._leafletMap) {
      this._leafletMap.remove();
      this._leafletMap = null;
    }
    this._leafletMarker = null;
    this._mapVisible = false;
    this._mapZoom = DEFAULT_MAP_ZOOM;

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
    if (event.key === "Enter" && this._searchResults.length === 0) {
      event.preventDefault();
      this._triggerSearch();
      return;
    }

    if (this._searchResults.length === 0) return;

    switch (event.key) {
      case "ArrowDown":
        event.preventDefault();
        this._highlightedIndex = Math.min(this._highlightedIndex + 1, this._searchResults.length - 1);
        break;
      case "ArrowUp":
        event.preventDefault();
        this._highlightedIndex = Math.max(this._highlightedIndex - 1, 0);
        break;
      case "Enter":
        event.preventDefault();
        if (this._highlightedIndex >= 0 && this._highlightedIndex < this._searchResults.length) {
          this._selectLocation(this._searchResults[this._highlightedIndex]);
        }
        break;
      case "Escape":
        event.preventDefault();
        this._clearSearch();
        break;
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
   * Renders the search interface with input and button.
   * @returns {import('lit').TemplateResult} Search interface template
   * @private
   */
  _renderSearchInterface() {
    const shouldRenderDropdown =
      this._showDropdown && this._searchQuery !== "" && this._searchQuery.length >= 3;
    const disabledClasses = this.disabled ? "cursor-not-allowed bg-stone-100 text-stone-500" : "";

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
                          class="cursor-pointer mt-[2px]"
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
              @click=${this._triggerSearch}
              ?disabled=${this.disabled || this._searchQuery.length < 3 || this._isSearching}
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
        class="absolute z-50 mt-2 w-full bg-white rounded-lg shadow-lg border border-stone-200 max-h-[320px] overflow-y-auto"
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
    return Boolean(
      this.venueNameFieldName ||
      this.venueAddressFieldName ||
      this.venueCityFieldName ||
      this.venueZipCodeFieldName ||
      this.stateFieldName ||
      this.countryNameFieldName ||
      this.countryCodeFieldName,
    );
  }

  /**
   * Determines if this component sits inside a hidden tab content.
   * @returns {boolean}
   * @private
   */
  _isInsideHiddenContent() {
    const contentSection = this.closest("[data-content]");
    return Boolean(contentSection && contentSection.classList.contains("hidden"));
  }

  /**
   * @returns {boolean}
   * @private
   */
  _isVenueContext() {
    return Boolean(this.venueNameFieldName || this.venueAddressFieldName || this.venueZipCodeFieldName);
  }

  /**
   * @param {"city" | "zip" | "state" | "country"} kind
   * @returns {string}
   * @private
   */
  _getLegendText(kind) {
    const isVenue = this._isVenueContext();

    if (kind === "city") {
      return isVenue ? "City where the venue is located." : "Primary city where the group is located.";
    }
    if (kind === "zip") {
      return "Postal/zip code of the venue.";
    }
    if (kind === "state") {
      return "State, province, or region.";
    }
    if (kind === "country") {
      return isVenue ? "Country where the venue is located." : "Country where the group is located.";
    }

    return "";
  }

  /**
   * @param {string} inputName
   * @returns {string}
   * @private
   */
  _getInputId(inputName) {
    if (!inputName) return "";
    return `${this.id || "location-search"}-${inputName}`;
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
    const disabledClasses = this.disabled ? "cursor-not-allowed bg-stone-100 text-stone-500" : "";

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
    if (
      !this.latitudeFieldName &&
      !this.latitudeFieldId &&
      !this.longitudeFieldName &&
      !this.longitudeFieldId
    ) {
      return html``;
    }

    const latitudeName = this.latitudeFieldName || this.latitudeFieldId;
    const longitudeName = this.longitudeFieldName || this.longitudeFieldId;

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
              class="input-primary ${this.disabled ? "cursor-not-allowed bg-stone-100 text-stone-500" : ""}"
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
              class="input-primary ${this.disabled ? "cursor-not-allowed bg-stone-100 text-stone-500" : ""}"
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
    const addr = result.address || {};
    const mainText =
      addr.amenity || addr.building || addr.name || addr.road || result.display_name.split(",")[0];
    const secondaryText = result.display_name;

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
        <div class="flex-shrink-0 mt-0.5">
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
    if (!this._mapVisible || !this._hasValidCoordinates()) {
      return Promise.resolve();
    }
    this._mapPreviewSyncPromise = this._mapPreviewSyncPromise
      .catch(() => {})
      .then(() => this._syncMapPreviewInternal());
    return this._mapPreviewSyncPromise;
  }

  /**
   * Initialize or update the enabled map/marker with the latest coords.
   * @returns {Promise<void>}
   * @private
   */
  async _syncMapPreviewInternal() {
    if (!this._hasValidCoordinates()) {
      if (this._leafletMap) {
        this._leafletMap.remove();
        this._leafletMap = null;
      }
      this._leafletMarker = null;
      return;
    }

    const container = document.getElementById(this._mapElementId);
    if (!container) return;

    const lat = this._parseCoordinate(this._latitudeValue);
    const lng = this._parseCoordinate(this._longitudeValue);
    if (lat === null || lng === null) return;

    const zoom = this._mapZoom || DEFAULT_MAP_ZOOM;
    if (!this._leafletMap) {
      this._leafletMap = await loadMap(this._mapElementId, lat, lng, {
        zoom,
        interactive: true,
        marker: false,
      });
    }

    if (this._leafletMarker) {
      this._leafletMarker.setLatLng([lat, lng]);
    } else if (window.L) {
      const icon = L.divIcon({
        html: '<div class="svg-icon h-[30px] w-[30px] bg-primary-500 icon-marker"></div>',
        iconSize: [30, 30],
        iconAnchor: [15, 30],
        popupAnchor: [0, -25],
        className: "marker-icon",
      });
      this._leafletMarker = L.marker(L.latLng(lat, lng), {
        icon,
        interactive: false,
        autoPanOnFocus: false,
        bubblingMouseEvents: false,
      }).addTo(this._leafletMap);
    }

    this._leafletMap.setView([lat, lng], zoom, { animate: false });
    this._leafletMap.invalidateSize?.(false);
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
