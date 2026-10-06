import { html, nothing } from "lit";
import { repeat } from "lit/directives/repeat.js";
import { FILTER_CHANGE_EVENT } from "/static/js/community/explore/filters.js";
import { MultiSelect } from "/static/js/common/multi-select.js";

/**
 * Multi-select filter component with search input and badge display.
 * Shows selected items as removable badges and provides a searchable dropdown.
 *
 * Options keep their given order and selection changes emit only
 * `FILTER_CHANGE_EVENT`, because explore listens to both `change` and
 * `filter-change` and would otherwise refresh twice.
 * @extends MultiSelect
 */
export class MultiSelectFilter extends MultiSelect {
  static properties = {
    title: { type: String },
  };

  constructor() {
    super();
    this.keepOrder = true;
    this.name = "name";
    this.title = "";
  }

  /**
   * Emits a selection change event for page-level filter handling.
   */
  _dispatchSelectionChange() {
    this.dispatchEvent(
      new CustomEvent(FILTER_CHANGE_EVENT, {
        bubbles: true,
        composed: true,
      }),
    );
  }

  /**
   * Gets the listbox ID.
   * @returns {string}
   */
  _listboxId() {
    return `${this.name}-filter-listbox`;
  }

  /**
   * Gets the ID of the option rendered at the given filtered index.
   * @param {number} index Filtered option index
   * @returns {string}
   */
  _optionId(index) {
    return `${this.name}-filter-option-${index}`;
  }

  /**
   * Renders one selected badge.
   * @param {{value: string, name: string}} option Selected option
   * @returns {import("lit").TemplateResult}
   */
  _renderChip(option) {
    return html`
      <span
        class="flex items-center justify-between w-full px-2 py-1 text-[0.775rem] text-primary-500 border border-primary-500 rounded-lg"
      >
        <span>${option.name}</span>
        <button
          type="button"
          aria-label=${`Remove ${option.name}`}
          class="text-stone-400 hover:text-stone-700"
          @click=${(event) => this._removeSelection(option.value, event)}
        >
          <div class="svg-icon size-3.5 icon-close bg-current shrink-0"></div>
        </button>
      </span>
    `;
  }

  /**
   * Renders the dropdown listbox while the combobox is open.
   * @param {Array<{value: string, name: string}>} options Filtered options
   * @returns {import("lit").TemplateResult|typeof nothing}
   */
  _renderDropdown(options) {
    if (!this._combobox.isOpen) {
      return nothing;
    }

    return html`
      <div
        data-multi-select-dropdown
        class="absolute top-full left-0 right-0 z-10 mt-1 bg-white rounded-lg shadow-lg border border-stone-200 max-h-48 overflow-y-auto"
      >
        ${
          options.length > 0
            ? html`
                <ul id=${this._listboxId()} class="py-1" role="listbox" aria-multiselectable="true">
                  ${repeat(
                    options,
                    (option) => option.value,
                    (option, index) => this._renderOption(option, index),
                  )}
                </ul>
              `
            : html`<div class="px-3 py-2 text-[0.775rem] text-stone-500">${this.emptyMessage}</div>`
        }
      </div>
    `;
  }

  /**
   * Composes the explore filter panel layout.
   * @param {object} parts Rendered parts
   * @returns {import("lit").TemplateResult}
   */
  _renderLayout({ chips, dropdown, hiddenInputs, search, selected }) {
    return html`
      <div class="px-6 py-7 pt-5 border-b border-stone-100">
        <div class="font-semibold leading-4 md:leading-8 text-sm text-stone-700 mb-3">${this.title}</div>

        <div class="relative">${search} ${dropdown}</div>

        ${selected.length > 0 ? html`<div class="flex flex-col gap-1.5 mt-3">${chips}</div>` : nothing}
        ${hiddenInputs}
      </div>
    `;
  }

  /**
   * Renders one option of the listbox.
   * @param {{value: string, name: string}} option Option to render
   * @param {number} index Filtered option index
   * @returns {import("lit").TemplateResult}
   */
  _renderOption(option, index) {
    const isSelected = this.selected.includes(option.value);
    const isActive = this._combobox.activeIndex === index;

    return html`
      <li
        id=${this._optionId(index)}
        class="w-full px-3 py-2 text-left text-[0.775rem] flex items-center gap-2 cursor-pointer ${
          isActive ? "bg-stone-50" : "hover:bg-stone-50"
        }"
        role="option"
        aria-selected=${String(isSelected)}
        @click=${() => this._toggleSelection(option.value)}
        @mouseover=${() => this._combobox.setActiveIndex(index)}
      >
        <span class="shrink-0 w-4 h-4 flex items-center justify-center">
          ${isSelected ? html`<div class="svg-icon size-3 icon-check bg-primary-500"></div>` : ""}
        </span>
        <span class="text-stone-700">${option.name}</span>
      </li>
    `;
  }

  /**
   * Renders the search box with its combobox input.
   * @returns {import("lit").TemplateResult}
   */
  _renderSearchInput() {
    return html`
      <div
        data-multi-select-search
        class="flex items-center gap-2 min-h-[38px] px-2 py-1.5 bg-white border border-stone-200 rounded-lg"
      >
        <div class="svg-icon size-3 icon-search bg-stone-400 shrink-0"></div>
        <input
          type="text"
          role="combobox"
          aria-autocomplete="list"
          aria-controls=${this._listboxId()}
          aria-expanded=${String(this._combobox.isOpen)}
          aria-haspopup="listbox"
          aria-activedescendant=${this._activeOptionId()}
          aria-label=${`${this.title} filter`}
          class="flex-1 text-base md:text-[0.775rem] bg-transparent border-none focus:ring-0 focus:outline-none placeholder-stone-400 p-0"
          placeholder="${this.placeholder}"
          autocomplete="off"
          .value=${this._combobox.query}
          @input=${(event) => this._handleSearchInput(event)}
          @change=${(event) => event.stopPropagation()}
          @focus=${() => this._handleFocus()}
        />
        ${
          this._combobox.query
            ? html`
                <button
                  type="button"
                  aria-label=${`Clear ${this.title}`}
                  class="text-stone-400 hover:text-stone-700 shrink-0"
                  @click=${() => this._clearQuery()}
                >
                  <div class="svg-icon size-4 md:size-3.5 icon-close bg-current"></div>
                </button>
              `
            : ""
        }
      </div>
    `;
  }
}

if (!customElements.get("multi-select-filter")) {
  customElements.define("multi-select-filter", MultiSelectFilter);
}
