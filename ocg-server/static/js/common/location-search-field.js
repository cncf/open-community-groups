import { html, repeat } from "/static/vendor/js/lit-all.v3.3.1.min.js";
import { LitWrapper } from "/static/js/common/lit-wrapper.js";
import { loadMap } from "/static/js/common/common.js";
import { setTextValue } from "/static/js/common/utils.js";

/** Default mode for location selection */
const DEFAULT_MODE = "search";

let mapIdCounter = 0;
const createMapElementId = () => {
  mapIdCounter += 1;
  return `location-search-field-map-${mapIdCounter}`;
};

/**
 * LocationSearchField component for searching and selecting locations using Nominatim.
 *
 * Supports two modes:
 * - Search Location: Search with button click, fields become readonly after selection
 * - Enter Manually: No search interface, all fields editable including coordinates
 */
export class LocationSearchField extends LitWrapper {
  /**
   * Component properties definition
   * @property {string} placeholderText - Custom placeholder for search input
   * @property {boolean} mapEnabled - Whether to render the internal map preview
   * @property {string} mapDivId - Legacy: ID of the map container element
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
   * @property {string} initialMode - Initial mode: "search" or "manual"
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
   * @property {string} _mode - Current mode: "search" or "manual"
   * @property {boolean} _showDropdown - Whether to render the results dropdown
   */
  static properties = {
    placeholderText: { type: String, attribute: "placeholder-text" },
    mapEnabled: { type: Boolean, attribute: "map-enabled" },
    mapDivId: { type: String, attribute: "map-div-id" },
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
    initialMode: { type: String, attribute: "initial-mode" },
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
    _mode: { type: String, state: true },
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
  };

  constructor() {
    super();
    this.placeholderText = "Search for a venue or address...";
    this.mapEnabled = false;
    this.mapDivId = "";
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
    this.initialMode = DEFAULT_MODE;
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
    this._mode = DEFAULT_MODE;
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

    this._mapElementId = createMapElementId();
    this._leafletMap = null;
    this._mapPreviewSyncPromise = Promise.resolve();
  }

  connectedCallback() {
    super.connectedCallback();
    this._mode = this.initialMode || DEFAULT_MODE;
    this._venueNameValue = this.initialVenueName || "";
    this._venueAddressValue = this.initialVenueAddress || "";
    this._venueCityValue = this.initialVenueCity || "";
    this._venueZipCodeValue = this.initialVenueZipCode || "";
    this._stateValue = this.initialState || "";
    this._countryNameValue = this.initialCountryName || "";
    this._countryCodeValue = this.initialCountryCode || "";
    this._latitudeValue = this.initialLatitude || "";
    this._longitudeValue = this.initialLongitude || "";

    if (this.mapDivId) {
      this.mapEnabled = true;
    }

    if (!this.latitudeFieldId && !this.latitudeFieldName && (this.mapEnabled || this.mapDivId)) {
      this.latitudeFieldId = "latitude";
      this.latitudeFieldName = "latitude";
    }
    if (!this.longitudeFieldId && !this.longitudeFieldName && (this.mapEnabled || this.mapDivId)) {
      this.longitudeFieldId = "longitude";
      this.longitudeFieldName = "longitude";
    }

    if (!this._outsidePointerHandler) {
      this._outsidePointerHandler = (event) => this._handleOutsidePointer(event);
    }
    document.addEventListener("pointerdown", this._outsidePointerHandler);

    this._updateFieldsReadonly(this._mode === "search");
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
    if (this._outsidePointerHandler) {
      document.removeEventListener("pointerdown", this._outsidePointerHandler);
    }
  }

  firstUpdated() {
    if (this._hasValidCoordinates()) {
      this._syncMapPreview();
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

    const venueName = addr[result.type] || addr.amenity || addr.building || addr.name || "";

    const state = addr.state || addr.province || addr.region || "";

    const country = addr.country || "";
    const countryCode = (addr.country_code || "").toUpperCase();

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

    this._updateFieldsReadonly(true);

    this.dispatchEvent(
      new CustomEvent("location-selected", {
        detail: location,
        bubbles: true,
      }),
    );

    this._clearSearch();
  }

  /**
   * Sets or removes the readonly attribute on a field.
   * @param {string} fieldId - ID of the field to modify
   * @param {boolean} readonly - Whether to set or remove readonly
   * @private
   */
  _setFieldReadonly(fieldId, readonly) {
    const field = document.getElementById(fieldId);
    if (field) {
      if (readonly) {
        field.setAttribute("readonly", "");
      } else {
        field.removeAttribute("readonly");
      }
    }
  }

  /**
   * Updates readonly state for all configured fields.
   * @param {boolean} readonly - Whether fields should be readonly
   * @private
   */
  _updateFieldsReadonly(readonly) {
    const fieldIds = [
      this.venueNameFieldId,
      this.venueAddressFieldId,
      this.venueCityFieldId,
      this.venueZipCodeFieldId,
      this.stateFieldId,
      this.countryFieldId,
    ];

    for (const fieldId of fieldIds) {
      if (fieldId) {
        this._setFieldReadonly(fieldId, readonly);
      }
    }
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
        this._setFieldReadonly(fieldId, false);
      }
    }

    this._updateFieldsReadonly(this._mode === "search");

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
   * Handles mode change when radio button is clicked.
   * @param {Event} event - Change event from radio input
   * @private
   */
  _handleModeChange(event) {
    const newMode = event.target.value;
    if (newMode === this._mode) return;

    this._mode = newMode;
    this._clearSearch();
    this._updateFieldsReadonly(newMode === "search");

    this.dispatchEvent(
      new CustomEvent("mode-changed", {
        detail: { mode: newMode },
        bubbles: true,
      }),
    );
  }

  /**
   * Renders a selectable mode card.
   * @param {Object} option - Card data with value, title, description
   * @returns {import('lit').TemplateResult} Mode card element
   * @private
   */
  _renderModeOption(option) {
    const isSelected = this._mode === option.value;

    return html`
      <label class="block h-full">
        <input
          type="radio"
          class="sr-only"
          name="location-mode"
          value="${option.value}"
          .checked="${isSelected}"
          @change="${this._handleModeChange}"
        />
        <div
          class="h-full rounded-xl border transition bg-white p-4 md:p-5 flex cursor-pointer ${isSelected
            ? "border-primary-400 ring-2 ring-primary-200"
            : "border-stone-200 hover:border-primary-300"}"
        >
          <div class="flex items-start gap-3">
            <span class="mt-1 inline-flex">
              <span
                class="${[
                  "relative flex h-5 w-5 items-center justify-center rounded-full",
                  "border",
                  isSelected ? "border-primary-500" : "border-stone-300",
                ].join(" ")}"
              >
                ${isSelected ? html`<span class="h-2.5 w-2.5 rounded-full bg-primary-500"></span>` : ""}
              </span>
            </span>
            <div class="space-y-1">
              <div class="text-base font-semibold text-stone-900">${option.title}</div>
              <p class="form-legend">${option.description}</p>
            </div>
          </div>
        </div>
      </label>
    `;
  }

  /**
   * Renders the search interface with input and button.
   * @returns {import('lit').TemplateResult} Search interface template
   * @private
   */
  _renderSearchInterface() {
    const shouldRenderDropdown =
      this._showDropdown && this._searchQuery !== "" && this._searchQuery.length >= 3;

    return html`
      <div class="mt-6 space-y-4" @focusout=${this._handleFocusOut}>
        <div>
          <label for="location-search-input" class="form-label">Location Search</label>
          <div class="mt-2 flex gap-2">
            <div class="relative flex-1">
              <div class="absolute top-3 start-0 flex items-center ps-3 pointer-events-none">
                <div class="svg-icon size-4 icon-search bg-stone-300"></div>
              </div>
              <input
                id="location-search-input"
                type="text"
                class="input-primary peer ps-9"
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
              />
              ${this._searchQuery
                ? html`
                    <div class="absolute end-1.5 top-1.5">
                      <button type="button" class="cursor-pointer mt-[2px]" @click=${this._clearSearch}>
                        <div class="svg-icon size-5 bg-stone-400 hover:bg-stone-700 icon-close"></div>
                      </button>
                    </div>
                  `
                : ""}
              ${shouldRenderDropdown ? this._renderDropdown() : ""}
            </div>
            <button
              type="button"
              class="btn-primary"
              @click=${this._triggerSearch}
              ?disabled=${this._searchQuery.length < 3 || this._isSearching}
            >
              Search
            </button>
          </div>
        </div>
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

    const readonly = this._mode === "search";
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
                    class="input-primary"
                    placeholder="Conference Center Amsterdam"
                    .value=${this._venueNameValue}
                    ?readonly=${readonly}
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
                    class="input-primary"
                    placeholder="123 Main Street"
                    .value=${this._venueAddressValue}
                    ?readonly=${readonly}
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
                    class="input-primary"
                    placeholder="Amsterdam"
                    autocomplete="off"
                    autocorrect="off"
                    autocapitalize="off"
                    spellcheck="false"
                    .value=${this._venueCityValue}
                    ?readonly=${readonly}
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
                    class="input-primary"
                    placeholder="1012 AB"
                    .value=${this._venueZipCodeValue}
                    ?readonly=${readonly}
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
                    class="input-primary"
                    autocomplete="off"
                    autocorrect="off"
                    autocapitalize="off"
                    spellcheck="false"
                    .value=${this._stateValue}
                    ?readonly=${readonly}
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
                    class="input-primary"
                    autocomplete="off"
                    autocorrect="off"
                    autocapitalize="off"
                    spellcheck="false"
                    .value=${this._countryNameValue}
                    ?readonly=${readonly}
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
              class="input-primary"
              placeholder="52.3676"
              .value=${this._latitudeValue}
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
              class="input-primary"
              placeholder="4.9041"
              .value=${this._longitudeValue}
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

  /**
   * Renders hidden inputs for lat/lng in search mode.
   * @returns {import('lit').TemplateResult} Hidden inputs template
   * @private
   */
  _renderHiddenCoordinates() {
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
      <input
        type="hidden"
        id="${this._getInputId(latitudeName)}"
        name="${latitudeName}"
        .value=${this._latitudeValue}
      />
      <input
        type="hidden"
        id="${this._getInputId(longitudeName)}"
        name="${longitudeName}"
        .value=${this._longitudeValue}
      />
    `;
  }

  async updated(changedProperties) {
    super.updated?.(changedProperties);

    if (changedProperties.has("_latitudeValue") || changedProperties.has("_longitudeValue")) {
      await this._syncMapPreview();
    }
  }

  /**
   * @private
   */
  _syncMapPreview() {
    this._mapPreviewSyncPromise = this._mapPreviewSyncPromise
      .catch(() => {})
      .then(() => this._syncMapPreviewInternal());
    return this._mapPreviewSyncPromise;
  }

  /**
   * @private
   */
  async _syncMapPreviewInternal() {
    if (!this.mapEnabled) return;

    if (!this._hasValidCoordinates()) {
      if (this._leafletMap) {
        this._leafletMap.remove();
        this._leafletMap = null;
      }
      return;
    }

    const container = document.getElementById(this._mapElementId);
    if (!container) return;

    const lat = this._parseCoordinate(this._latitudeValue);
    const lng = this._parseCoordinate(this._longitudeValue);
    if (lat === null || lng === null) return;

    if (this._leafletMap) {
      this._leafletMap.remove();
      this._leafletMap = null;
    }

    this._leafletMap = await loadMap(this._mapElementId, lat, lng, { zoom: 15, interactive: false });
  }

  /**
   * @returns {import('lit').TemplateResult}
   * @private
   */
  _renderMapPreview() {
    if (!this.mapEnabled || !this._hasValidCoordinates()) return html``;

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
   * Renders the full component (radio buttons, search interface or coordinate inputs).
   * @returns {import('lit').TemplateResult} Component template
   */
  render() {
    const modeOptions = [
      {
        value: "search",
        title: "Search Location",
        description: "Search for a location to auto-fill venue details.",
      },
      {
        value: "manual",
        title: "Enter Manually",
        description: "Enter location details manually including coordinates.",
      },
    ];

    return html`
      <div class="space-y-6">
        <div class="grid grid-cols-1 gap-4 lg:grid-cols-2">
          ${modeOptions.map((option) => this._renderModeOption(option))}
        </div>

        ${this._mode === "search" ? this._renderSearchInterface() : ""} ${this._renderLocationFields()}
        ${this._mode === "search" ? this._renderHiddenCoordinates() : this._renderCoordinateInputs()}
        ${this._renderMapPreview()}
      </div>
    `;
  }
}

customElements.define("location-search-field", LocationSearchField);
