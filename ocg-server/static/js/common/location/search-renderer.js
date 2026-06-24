import { html } from "/static/vendor/js/lit-all.v3.3.3.min.js";
import {
  getLocationDisabledInputClasses,
  getLocationInputId,
  getLocationTextFieldDefinitions,
  isLocationSearchButtonDisabled,
  shouldRenderLocationDropdown,
} from "/static/js/common/location/search-display.js";
import { renderLocationSearchDropdown } from "/static/js/common/location/search-dropdown.js";

/**
 * Renders the location search input, button, and dropdown.
 * @param {Object} state Search interface state and handlers.
 * @returns {import('lit').TemplateResult}
 */
export const renderLocationSearchInterface = (state) => {
  const shouldRenderDropdown = shouldRenderLocationDropdown({
    showDropdown: state.showDropdown,
    searchQuery: state.searchQuery,
  });
  const searchButtonDisabled = isLocationSearchButtonDisabled({
    disabled: state.disabled,
    searchQuery: state.searchQuery,
    isSearching: state.isSearching,
  });
  const disabledClasses = getLocationDisabledInputClasses(state.disabled);

  return html`
    <div @focusout=${state.onFocusOut}>
      <div class="mt-2 flex gap-2">
        <div class="relative flex-1">
          <div class="absolute top-3 start-0 flex items-center ps-3 pointer-events-none">
            <div class="svg-icon size-4 icon-search bg-stone-300"></div>
          </div>
          <input
            id="location-search-input"
            type="text"
            class="input-primary peer ps-9 ${disabledClasses}"
            placeholder=${state.placeholderText}
            .value=${state.searchQuery}
            @input=${state.onSearchInput}
            @keydown=${state.onKeyDown}
            autocomplete="off"
            autocorrect="off"
            autocapitalize="off"
            spellcheck="false"
            aria-expanded=${shouldRenderDropdown}
            aria-haspopup="listbox"
            aria-autocomplete="list"
            aria-label="Search for a location"
            ?disabled=${state.disabled}
          />
          ${state.searchQuery
            ? html`
                <div class="absolute end-1.5 top-1.5">
                  <button
                    type="button"
                    class="cursor-pointer mt-0.5"
                    @click=${state.onClearSearch}
                    ?disabled=${state.disabled}
                  >
                    <div class="svg-icon size-5 bg-stone-400 hover:bg-stone-700 icon-close"></div>
                  </button>
                </div>
              `
            : ""}
          ${shouldRenderDropdown
            ? renderLocationSearchDropdown({
                highlightedIndex: state.highlightedIndex,
                isSearching: state.isSearching,
                onHighlight: state.onHighlight,
                onSelect: state.onSelect,
                searchError: state.searchError,
                searchQuery: state.searchQuery,
                searchResults: state.searchResults,
              })
            : ""}
        </div>
        <button
          type="button"
          class="btn-primary"
          @pointerdown=${state.onSearchButtonPointerDown}
          @click=${state.onTriggerSearch}
          ?disabled=${searchButtonDisabled}
        >
          Search
        </button>
      </div>
      <p class="form-legend mt-3">
        If any fields remain empty or incomplete after the search, fill in the missing details manually.
      </p>
    </div>
  `;
};

/**
 * Renders one generated text field for a location field definition.
 * @param {Object} options Text field render options.
 * @returns {import('lit').TemplateResult}
 */
const renderLocationTextField = ({ disabled, disabledClasses, field, getInputId, onInput }) => {
  const inputId = getInputId(field.fieldName);

  return html`
    <div class="${field.className}">
      <label for="${inputId}" class="form-label">${field.label}</label>
      <div class="mt-2">
        <input
          type="text"
          name="${field.fieldName}"
          id="${inputId}"
          class="input-primary ${disabledClasses}"
          autocomplete=${field.autocomplete === false ? "off" : "on"}
          autocorrect=${field.autocomplete === false ? "off" : "on"}
          autocapitalize=${field.autocomplete === false ? "off" : "on"}
          spellcheck=${field.autocomplete === false ? "false" : "true"}
          .value=${field.value}
          ?disabled=${disabled}
          @input=${(event) => onInput(field.handlerName, event)}
        />
      </div>
      <p class="form-legend">${field.legend}</p>
    </div>
  `;
};

/**
 * Renders generated location text fields.
 * @param {Object} state Location text field render state.
 * @returns {import('lit').TemplateResult}
 */
export const renderLocationTextFields = (state) => {
  const hiddenCountryCodeInput = state.countryCodeFieldName
    ? html`
        <input
          type="hidden"
          name="${state.countryCodeFieldName}"
          id="${getLocationInputId(state.componentId, state.countryCodeFieldName)}"
          .value=${state.countryCodeValue}
        />
      `
    : "";
  const disabledClasses = getLocationDisabledInputClasses(state.disabled);
  const textFields = getLocationTextFieldDefinitions(state);
  const getInputId = (inputName) => getLocationInputId(state.componentId, inputName);

  return html`
    <div class="mt-8 grid grid-cols-1 gap-x-6 gap-y-8 md:grid-cols-6 max-w-5xl">
      ${hiddenCountryCodeInput}
      ${textFields.map((field) =>
        renderLocationTextField({
          disabled: state.disabled,
          disabledClasses,
          field,
          getInputId,
          onInput: state.onInput,
        }),
      )}
    </div>
  `;
};

/**
 * Renders one coordinate input for latitude or longitude.
 * @param {Object} field Coordinate field render state.
 * @returns {import("lit").TemplateResult}
 */
const renderCoordinateInput = (field) => html`
  <div>
    <label for="${field.inputId}" class="form-label">${field.label}</label>
    <div class="mt-2">
      <input
        type="number"
        step="any"
        id="${field.inputId}"
        name="${field.name}"
        class="input-primary ${field.disabledClasses}"
        .value=${field.value}
        ?disabled=${field.disabled}
        @input=${(event) => field.onInput(field.valueKey, event)}
      />
    </div>
  </div>
`;

/**
 * Renders latitude and longitude inputs.
 * @param {Object} state Coordinate input state.
 * @returns {import("lit").TemplateResult}
 */
export const renderLocationCoordinateInputs = (state) => html`
  <div class="grid grid-cols-2 gap-4 mt-6">
    ${renderCoordinateInput({
      disabled: state.disabled,
      disabledClasses: state.disabledClasses,
      inputId: state.latitudeId,
      label: "Latitude",
      name: state.latitudeName,
      onInput: state.onInput,
      value: state.latitudeValue,
      valueKey: "_latitudeValue",
    })}
    ${renderCoordinateInput({
      disabled: state.disabled,
      disabledClasses: state.disabledClasses,
      inputId: state.longitudeId,
      label: "Longitude",
      name: state.longitudeName,
      onInput: state.onInput,
      value: state.longitudeValue,
      valueKey: "_longitudeValue",
    })}
  </div>
`;
