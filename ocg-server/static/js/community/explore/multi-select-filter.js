import { html, nothing, repeat } from "/static/vendor/js/lit-all.v3.3.1.min.js";
import { ComboboxController } from "/static/js/common/combobox.js";
import { LitWrapper } from "/static/js/common/lit-wrapper.js";

const FILTER_CHANGE_EVENT = "filter-change";

/**
 * Multi-select filter component with search input and badge display.
 * Shows selected items as removable badges and provides a searchable dropdown.
 * @extends LitWrapper
 */
export class MultiSelectFilter extends LitWrapper {
  static properties = {
    title: { type: String },
    name: { type: String },
    options: { type: Array },
    selected: { type: Array },
    placeholder: { type: String },
  };

  constructor() {
    super();
    this.title = "";
    this.name = "name";
    this.options = [];
    this.selected = [];
    this.placeholder = "Type to search";
    this._combobox = new ComboboxController(this, {
      getItemCount: () => this._filteredOptions.length,
      canOpen: () => this.options.length > 0,
      onSelect: (index) => {
        const opt = this._filteredOptions[index];
        if (opt) {
          this._toggleOption(opt.value);
        }
      },
    });
  }

  /**
   * Public method to reset all selected options.
   * Used by parent form reset functionality.
   */
  cleanSelected() {
    this.selected = [];
    this._combobox.setQuery("");
  }

  connectedCallback() {
    super.connectedCallback();
    this._prepareSelected();
  }

  /**
   * Reconciles selected values when options change.
   * @param {Map} changedProperties - Map of changed properties
   */
  updated(changedProperties) {
    super.updated(changedProperties);
    if (changedProperties.has("options")) {
      const validValues = new Set(this.options.map((opt) => opt.value));
      const reconciled = this.selected.filter((v) => validValues.has(v));
      if (reconciled.length !== this.selected.length) {
        this.selected = reconciled;
        this.updateComplete.then(() => this._dispatchFilterChange());
      }
    }
  }

  /**
   * Normalizes selected property to ensure it's always an array.
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
   * Gets filtered options based on current query.
   * @returns {Array} Filtered options
   */
  get _filteredOptions() {
    const normalized = (this._combobox.query || "").trim().toLowerCase();
    if (!normalized) {
      return this.options;
    }
    return this.options.filter((opt) => (opt.name || "").toLowerCase().includes(normalized));
  }

  /**
   * Gets selected option objects with their names.
   * @returns {Array} Selected option objects
   */
  get _selectedOptions() {
    return this.options.filter((opt) => this.selected.includes(opt.value));
  }

  /**
   * Handles search input changes.
   * @param {InputEvent} event - The input event
   * @private
   */
  _handleSearchInput(event) {
    this._combobox.setQuery(event.target.value || "");
    this._combobox.setActiveIndex(null);
  }

  /**
   * Clears the search query.
   * @private
   */
  _clearQuery() {
    this._combobox.setQuery("");
    this._combobox.setActiveIndex(null);
  }

  /**
   * Toggles selection of an option.
   * @param {string} value - The option value
   * @private
   */
  async _toggleOption(value) {
    if (this.selected.includes(value)) {
      this.selected = this.selected.filter((v) => v !== value);
    } else {
      this.selected = [...this.selected, value];
    }

    this.requestUpdate();
    await this.updateComplete;

    this._dispatchFilterChange();
  }

  /**
   * Removes a selected option.
   * @param {string} value - The option value to remove
   * @param {Event} event - Click event
   * @private
   */
  async _removeOption(value, event) {
    event.stopPropagation();
    this.selected = this.selected.filter((v) => v !== value);

    this.requestUpdate();
    await this.updateComplete;

    this._dispatchFilterChange();
  }

  /**
   * Emits a selection change event for page-level filter handling.
   * @private
   */
  _dispatchFilterChange() {
    this.dispatchEvent(
      new CustomEvent(FILTER_CHANGE_EVENT, {
        bubbles: true,
        composed: true,
      }),
    );
  }

  /**
   * Handles focus on the input.
   * @private
   */
  _handleFocus() {
    this._combobox.open();
  }

  render() {
    const selectedOptions = this._selectedOptions;
    const listboxId = `${this.name}-filter-listbox`;
    const activeOptionId =
      this._combobox.activeIndex === null
        ? nothing
        : `${this.name}-filter-option-${this._combobox.activeIndex}`;

    return html`
      <div class="px-6 py-7 pt-5 border-b border-stone-100">
        <div class="font-semibold leading-4 md:leading-8 text-sm text-stone-700 mb-3">${this.title}</div>

        <div class="relative">
          <div
            class="flex items-center gap-2 min-h-[38px] px-2 py-1.5 bg-white border border-stone-200 rounded-lg"
          >
            <div class="svg-icon size-3 icon-search bg-stone-400 shrink-0"></div>
            <input
              type="text"
              role="combobox"
              aria-autocomplete="list"
              aria-controls=${listboxId}
              aria-expanded=${String(this._combobox.isOpen)}
              aria-haspopup="listbox"
              aria-activedescendant=${activeOptionId}
              aria-label=${`${this.title} filter`}
              class="flex-1 text-base md:text-[0.775rem] bg-transparent border-none focus:ring-0 focus:outline-none placeholder-stone-400 p-0"
              placeholder="${this.placeholder}"
              autocomplete="off"
              .value=${this._combobox.query}
              @input=${(event) => this._handleSearchInput(event)}
              @change=${(event) => event.stopPropagation()}
              @focus=${() => this._handleFocus()}
            />
            ${this._combobox.query
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
              : ""}
          </div>

          ${this._combobox.isOpen
            ? html`
                <div
                  class="absolute top-full left-0 right-0 z-10 mt-1 bg-white rounded-lg shadow-lg border border-stone-200 max-h-48 overflow-y-auto"
                >
                  ${this._filteredOptions.length > 0
                    ? html`
                        <ul id=${listboxId} class="py-1" role="listbox">
                          ${repeat(
                            this._filteredOptions,
                            (opt) => opt.value,
                            (opt, index) => {
                              const isSelected = this.selected.includes(opt.value);
                              const isActive = this._combobox.activeIndex === index;

                              return html`
                                <li
                                  id=${`${this.name}-filter-option-${index}`}
                                  class="w-full px-3 py-2 text-left text-[0.775rem] flex items-center gap-2 cursor-pointer ${isActive
                                    ? "bg-stone-50"
                                    : "hover:bg-stone-50"}"
                                  role="option"
                                  aria-selected=${String(isSelected)}
                                  @click=${() => {
                                    this._toggleOption(opt.value);
                                  }}
                                  @mouseover=${() => this._combobox.setActiveIndex(index)}
                                >
                                  <span class="shrink-0 w-4 h-4 flex items-center justify-center">
                                    ${isSelected
                                      ? html`<div class="svg-icon size-3 icon-check bg-primary-500"></div>`
                                      : ""}
                                  </span>
                                  <span class="text-stone-700">${opt.name}</span>
                                </li>
                              `;
                            },
                          )}
                        </ul>
                      `
                    : html`<div class="px-3 py-2 text-[0.775rem] text-stone-500">No results found</div>`}
                </div>
              `
            : ""}
        </div>

        ${selectedOptions.length > 0
          ? html`
              <div class="flex flex-col gap-1.5 mt-3">
                ${repeat(
                  selectedOptions,
                  (opt) => opt.value,
                  (opt) => html`
                    <span
                      class="flex items-center justify-between w-full px-2 py-1 text-[0.775rem] text-primary-500 border border-primary-500 rounded-lg"
                    >
                      <span>${opt.name}</span>
                      <button
                        type="button"
                        aria-label=${`Remove ${opt.name}`}
                        class="text-stone-400 hover:text-stone-700"
                        @click=${(event) => this._removeOption(opt.value, event)}
                      >
                        <div class="svg-icon size-3.5 icon-close bg-current shrink-0"></div>
                      </button>
                    </span>
                  `,
                )}
              </div>
            `
          : ""}
        ${repeat(
          this.selected,
          (value) => value,
          (value) => html`<input type="hidden" name="${this.name}[]" value="${value}" />`,
        )}
      </div>
    `;
  }
}

customElements.define("multi-select-filter", MultiSelectFilter);
