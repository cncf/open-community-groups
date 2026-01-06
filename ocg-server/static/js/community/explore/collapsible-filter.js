import { html, repeat } from "/static/vendor/js/lit-all.v3.3.1.min.js";
import { LitWrapper } from "/static/js/common/lit-wrapper.js";
import { triggerChangeOnForm } from "/static/js/community/explore/filters.js";

/**
 * Collapsible filter component for managing multiple selection options.
 * Supports both single and multiple selection modes with collapse/expand functionality.
 * Automatically detects parent form and manages selection state.
 * @extends LitWrapper
 */
export class CollapsibleFilter extends LitWrapper {
  /**
   * Component properties definition
   * @property {string} title - Filter section title displayed to users
   * @property {string} name - Form input name attribute for checkbox elements
   * @property {Array} options - Array of filter options with value and name properties
   * @property {Array} formattedOptions - Internal processed options array
   * @property {Array} selected - Array of currently selected option values
   * @property {number} maxVisibleItems - Maximum options visible when collapsed
   * @property {boolean} isCollapsed - Whether the filter is in collapsed state
   * @property {'rows'|'cols'} viewType - Layout orientation for options display
   * @property {boolean} singleSelection - Whether only one option can be selected
   * @property {Array} visibleOptions - Filtered options array for current view
   */
  static properties = {
    title: { type: String },
    name: { type: String },
    options: { type: Array },
    formattedOptions: { type: Array },
    selected: { type: Array },
    maxVisibleItems: { type: Number },
    isCollapsed: { type: Boolean },
    viewType: { type: String },
    singleSelection: { type: Boolean },
    visibleOptions: { type: Array },
  };

  constructor() {
    super();
    this.title = "";
    this.name = "name";
    this.options = [];
    this.formattedOptions = [];
    this.selected = [];
    this.maxVisibleItems = 5;
    this.isCollapsed = true;
    this.viewType = "cols";
    this.visibleOptions = [];
    this.singleSelection = false;
  }

  /**
   * Public method to reset all selected options.
   * Used by parent form reset functionality.
   */
  cleanSelected() {
    this.selected = [];
    this._filterOptions();
  }

  connectedCallback() {
    super.connectedCallback();

    this._prepareSelected();
    this._checkMaxVisibleItems();
    this._filterOptions();
    this._checkExpandIfHiddenSelected();
  }

  /**
   * Normalizes selected property to ensure it's always an array.
   * Handles cases where selected is null, undefined, or a single value.
   * @private
   */
  _prepareSelected() {
    if (this.selected === null || this.selected === undefined) {
      this.selected = [];
    } else if (typeof this.selected === "string" || typeof this.selected === "number") {
      this.selected = [this.selected.toString()];
    }
  }

  /**
   * Adjusts maxVisibleItems to ensure all selected options are visible.
   * Prevents hiding selected options when collapsed.
   * @private
   */
  _checkMaxVisibleItems() {
    if (this.selected.length > this.maxVisibleItems) {
      this.maxVisibleItems = this.selected.length;
    }
  }

  /**
   * Determines which options to display based on collapse state.
   * Shows limited options when collapsed, all options when expanded.
   * @private
   */
  _filterOptions() {
    if (this.isCollapsed) {
      this.visibleOptions = this.options.slice(0, this.maxVisibleItems);
    } else {
      this.visibleOptions = this.options;
    }
  }

  /**
   * Toggles the collapse state of the filter.
   * Called when user clicks the expand/collapse button.
   * @private
   */
  _changeCollapseState() {
    this.isCollapsed = !this.isCollapsed;
    this._filterOptions();
  }

  /**
   * Automatically expands the filter if any selected items would be hidden.
   * Ensures users can always see their selected options.
   * @private
   */
  _checkExpandIfHiddenSelected() {
    if (!this.isCollapsed) return;

    // Check if any selected items would be hidden when collapsed
    const hiddenWhenCollapsed = this.options.slice(this.maxVisibleItems);

    // If any selected items are in the hidden section, expand the filter
    const hasSelectedHiddenItems = hiddenWhenCollapsed.some((opt) => this.selected.includes(opt.value));

    if (hasSelectedHiddenItems) {
      this.isCollapsed = false;
      this._filterOptions();
    }
  }

  /**
   * Dynamically finds and returns the parent form ID.
   * Uses DOM traversal to locate the nearest form element.
   * @returns {string|null} Parent form ID or null if no form found
   * @private
   */
  _getParentFormId() {
    const form = this.closest("form");
    return form ? form.id : null;
  }

  /**
   * Handles option selection/deselection.
   * Supports both single and multiple selection modes.
   * @param {string} value - The value of the selected option
   * @private
   */
  async _onSelect(value) {
    if (!this.singleSelection) {
      if (!this.selected.includes(value)) {
        this.selected = [...this.selected, value];
      } else {
        this.selected = this.selected.filter((item) => item !== value);
      }
    } else {
      this.selected = [value];
    }
    this._checkMaxVisibleItems();
    this._checkExpandIfHiddenSelected();
    this._filterOptions();

    // Request update and wait for it to complete
    this.requestUpdate();
    await this.updateComplete;

    const parentFormId = this._getParentFormId();
    if (parentFormId) {
      // Trigger change event on the form
      triggerChangeOnForm(parentFormId);
    }
  }

  /**
   * Handles "Any" option selection by clearing all selections.
   * Triggers form change event after component update.
   * @private
   */
  async _onSelectAny() {
    // Clear all selections when "Any" is clicked
    this.selected = [];
    this._filterOptions();

    // Request update and wait for it to complete
    this.requestUpdate();
    await this.updateComplete;

    const parentFormId = this._getParentFormId();
    if (parentFormId) {
      // Trigger change event on the form
      triggerChangeOnForm(parentFormId);
    }
  }

  /**
   * Renders the complete collapsible filter component.
   * Includes title, collapse button, option list, and show more/less button.
   * @returns {import('lit').TemplateResult} Component template
   */
  render() {
    const canCollapse = this.options.length > this.maxVisibleItems;

    return html`<div class="px-6 py-7 pt-5 border-b border-stone-100">
      <div class="flex justify-between items-center">
        <div class="font-semibold leading-4 md:leading-8 text-[0.775rem] text-stone-700">${this.title}</div>
        <div>
          ${canCollapse
            ? html`<button
                type="button"
                @click=${this._changeCollapseState}
                class="group/btn collapse-btn border border-stone-200 hover:bg-stone-700 focus:ring-0 focus:outline-none focus:ring-stone-300 font-medium rounded-full text-sm p-1 text-center inline-flex items-center"
              >
                ${this.isCollapsed
                  ? html`<div
                      class="svg-icon h-3 w-3 bg-stone-500 group-hover/btn:bg-white icon-caret-down"
                    ></div>`
                  : html`<div
                      class="svg-icon h-3 w-3 bg-stone-500 group-hover/btn:bg-white icon-caret-up"
                    ></div>`}
              </button>`
            : ""}
        </div>
      </div>
      <ul class="flex w-full gap-2 mt-3 ${this.viewType === "rows" ? "flex-col" : "flex-wrap"}">
        <li>
          <button
            type="button"
            @click=${this._onSelectAny}
            class="inline-flex items-center justify-between w-full px-2 py-1 bg-white border rounded-lg cursor-pointer select-none ${this
              .selected.length === 0
              ? "border-primary-500 text-primary-500"
              : "text-stone-500 border-stone-200 hover:text-stone-600 hover:bg-stone-50"}"
          >
            <div class="text-[0.775rem] text-center text-nowrap">Any</div>
          </button>
        </li>
        ${repeat(
          this.visibleOptions,
          (opt) => opt,
          (opt) =>
            html`<li>
              <label
                class="inline-flex items-center justify-between w-full px-2 py-1 bg-white border rounded-lg cursor-pointer select-none ${this.selected.includes(
                  opt.value,
                )
                  ? "border-primary-500 text-primary-500"
                  : "text-stone-500 border-stone-200 hover:text-stone-600 hover:bg-stone-50"}"
              >
                <input
                  type="checkbox"
                  name="${this.name}[]"
                  value=${opt.value}
                  .checked=${this.selected.includes(opt.value)}
                  @change=${() => this._onSelect(opt.value)}
                  class="sr-only"
                />
                <div class="text-[0.775rem] text-center text-nowrap capitalize">${opt.name}</div>
              </label>
            </li>`,
        )}
      </ul>
      ${canCollapse
        ? html`<div class="mt-4 -mb-1.5">
            <button
              data-label="{{ label }}"
              type="button"
              @click=${this._changeCollapseState}
              class="text-xs/6 text-stone-500/75 hover:text-stone-700 focus:ring-0 focus:outline-none focus:ring-stone-300 font-medium"
            >
              ${this.isCollapsed ? "+ Show more" : "- Show less"}
            </button>
          </div>`
        : ""}
    </div>`;
  }
}
customElements.define("collapsible-filter", CollapsibleFilter);
