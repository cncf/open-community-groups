import { html } from "/static/vendor/js/lit-all.v3.3.1.min.js";
import {
  getLocationDisabledInputClasses,
  isLocationSearchButtonDisabled,
  shouldRenderLocationDropdown,
} from "/static/js/common/location-search-display.js";
import { renderLocationSearchDropdown } from "/static/js/common/location-search-dropdown.js";

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
