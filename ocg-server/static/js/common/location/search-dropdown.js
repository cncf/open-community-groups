import { html, repeat } from "/static/vendor/js/lit-all.v3.3.1.min.js";
import { getLocationResultText } from "/static/js/common/location/search-display.js";

/**
 * Renders a single result item in the dropdown list.
 * @param {Object} state Result row state.
 * @returns {import("lit").TemplateResult}
 */
const renderLocationSearchResult = (state) => {
  const { mainText, secondaryText } = getLocationResultText(state.result);
  const rowClass = `flex items-start gap-3 px-4 py-3 cursor-pointer ${
    state.isHighlighted ? "bg-stone-100" : "hover:bg-stone-50"
  }`;

  return html`
    <div
      class=${rowClass}
      role="option"
      aria-selected=${state.isHighlighted}
      @pointerdown=${(event) => {
        event.preventDefault();
        state.onSelect(state.result);
      }}
      @mouseenter=${() => state.onHighlight(state.index)}
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
};

/**
 * Renders the search results dropdown.
 * @param {Object} state Dropdown state and callbacks.
 * @returns {import("lit").TemplateResult}
 */
export const renderLocationSearchDropdown = (state) => html`
  <div
    class="absolute z-50 mt-2 w-full bg-white rounded-lg shadow-lg border border-stone-200
      max-h-80 overflow-y-auto"
    role="listbox"
  >
    ${
      state.isSearching
        ? html`
            <div class="p-4 text-center">
              <div class="inline-flex items-center gap-2 text-stone-600">
                <div
                  class="animate-spin w-4 h-4 border-2 border-stone-300 border-t-stone-600
                  rounded-full"
                ></div>
                Searching...
              </div>
            </div>
          `
        : state.searchError
          ? html`
              <div class="p-4 text-center text-stone-500">
                <p class="text-sm font-medium text-stone-600">Unable to load locations</p>
                <p class="text-sm">${state.searchError}</p>
              </div>
            `
          : state.searchResults.length === 0
            ? html`
                <div class="p-4 text-center text-stone-500">
                  <p class="text-sm">No locations found for "${state.searchQuery}"</p>
                </div>
              `
            : html`
                <div class="py-1">
                  ${repeat(
                    state.searchResults,
                    (result) => result.place_id,
                    (result, index) =>
                      renderLocationSearchResult({
                        index,
                        isHighlighted: index === state.highlightedIndex,
                        onHighlight: state.onHighlight,
                        onSelect: state.onSelect,
                        result,
                      }),
                  )}
                </div>
              `
    }
  </div>
`;
