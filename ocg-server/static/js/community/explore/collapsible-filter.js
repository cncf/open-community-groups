import { html, repeat } from "/static/vendor/js/lit-all.v3.2.1.min.js";
import { LitWrapper } from "/static/js/common/lit-wrapper.js";
import { triggerChangeOnForm } from "/static/js/community/explore/filters.js";

export class CollapsibleFilter extends LitWrapper {
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

  _prepareSelected() {
    if (this.selected === null || this.selected === undefined) {
      this.selected = [];
    } else if (typeof this.selected === "string" || typeof this.selected === "number") {
      this.selected = [this.selected.toString()];
    }
  }

  _checkMaxVisibleItems() {
    if (this.selected.length > this.maxVisibleItems) {
      this.maxVisibleItems = this.selected.length;
    }
  }

  _filterOptions() {
    const sortedOptions = this._sortOptions();
    if (this.isCollapsed) {
      this.visibleOptions = sortedOptions.slice(0, this.maxVisibleItems);
    } else {
      this.visibleOptions = sortedOptions;
    }
  }

  // Sort the options based on the selected order
  _sortOptions() {
    if (this.selected.length === 0) {
      return this.options;
    } else {
      const selectedOptions = [];
      const noSelectedOptions = [];
      this.options.map((opt) => {
        if (this.selected.includes(opt)) {
          selectedOptions.push(opt);
        } else {
          noSelectedOptions.push(opt);
        }
      });

      return selectedOptions.concat(noSelectedOptions);
    }
  }

  _changeCollapseState() {
    this.isCollapsed = !this.isCollapsed;
    this._filterOptions();
  }

  _checkExpandIfHiddenSelected() {
    if (!this.isCollapsed) return;

    // Check if any selected items would be hidden when collapsed
    const sortedOptions = this._sortOptions();
    const hiddenWhenCollapsed = sortedOptions.slice(this.maxVisibleItems);

    // If any selected items are in the hidden section, expand the filter
    const hasSelectedHiddenItems = hiddenWhenCollapsed.some((opt) => this.selected.includes(opt.value));

    if (hasSelectedHiddenItems) {
      this.isCollapsed = false;
      this._filterOptions();
    }
  }

  _getParentFormId() {
    const form = this.closest("form");
    return form ? form.id : null;
  }

  _onSelect(value) {
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
    this.requestUpdate();
  }

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

  render() {
    const canCollapse = this.options.length > this.maxVisibleItems;

    return html`<div class="px-6 py-7 pt-5 border-b border-gray-100">
      <div class="flex justify-between items-center">
        <div class="font-semibold text-black text-[0.8rem]/6">${this.title}</div>
        <div>
          ${canCollapse
            ? html`<button
                type="button"
                @click=${this._changeCollapseState}
                class="group/btn collapse-btn border border-gray-200 hover:bg-gray-700 focus:ring-0 focus:outline-none focus:ring-gray-300 font-medium rounded-full text-sm p-1 text-center inline-flex items-center"
              >
                ${this.isCollapsed
                  ? html`<div
                      class="svg-icon h-3 w-3 bg-gray-500 group-hover/btn:bg-white icon-caret-down"
                    ></div>`
                  : html`<div
                      class="svg-icon h-3 w-3 bg-gray-500 group-hover/btn:bg-white icon-caret-up"
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
            class="inline-flex items-center justify-between w-full px-2 py-1 bg-white border border-gray-200 rounded-lg cursor-pointer select-none ${this
              .selected.length === 0
              ? "border-primary-500 text-primary-500"
              : "text-gray-500 hover:text-gray-600 hover:bg-gray-50"}"
          >
            <div class="text-[0.8rem] text-center text-nowrap">Any</div>
          </button>
        </li>
        ${repeat(
          this.visibleOptions,
          (opt) => opt,
          (opt) =>
            html`<li>
              <label
                class="inline-flex items-center justify-between w-full px-2 py-1 bg-white border border-gray-200 rounded-lg cursor-pointer select-none ${this.selected.includes(
                  opt.value,
                )
                  ? "border-primary-500 text-primary-500"
                  : "text-gray-500 hover:text-gray-600 hover:bg-gray-50"}"
              >
                <input
                  type="checkbox"
                  name="${this.name}"
                  value="${opt.value}"
                  .checked=${this.selected.includes(opt.value)}
                  @change=${() => this._onSelect(opt.value)}
                  class="sr-only"
                />
                <div class="text-[0.8rem] text-center text-nowrap capitalize">${opt.name}</div>
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
              class="text-gray-500 hover:text-gray-700 focus:ring-0 focus:outline-none focus:ring-gray-300 font-medium text-xs"
            >
              ${this.isCollapsed ? "+ Show more" : "- Show less"}
            </button>
          </div>`
        : ""}
    </div>`;
  }
}
customElements.define("collapsible-filter", CollapsibleFilter);
