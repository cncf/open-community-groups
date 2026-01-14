import { html, repeat } from "/static/vendor/js/lit-all.v3.3.1.min.js";
import { LitWrapper } from "/static/js/common/lit-wrapper.js";
import { triggerChangeOnForm } from "/static/js/community/explore/filters.js";

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
    _isOpen: { state: true },
    _query: { state: true },
    _activeIndex: { state: true },
  };

  constructor() {
    super();
    this.title = "";
    this.name = "name";
    this.options = [];
    this.selected = [];
    this.placeholder = "Type to search";
    this._isOpen = false;
    this._query = "";
    this._activeIndex = null;
    this._documentClickHandler = null;
    this._keydownHandler = null;
  }

  /**
   * Public method to reset all selected options.
   * Used by parent form reset functionality.
   */
  cleanSelected() {
    this.selected = [];
    this._query = "";
  }

  connectedCallback() {
    super.connectedCallback();
    this._prepareSelected();
    this._keydownHandler = this._handleKeydown.bind(this);
    this.addEventListener("keydown", this._keydownHandler);
  }

  disconnectedCallback() {
    super.disconnectedCallback();
    this._removeDocumentListener();
    if (this._keydownHandler) {
      this.removeEventListener("keydown", this._keydownHandler);
      this._keydownHandler = null;
    }
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
        const parentFormId = this._getParentFormId();
        if (parentFormId) {
          triggerChangeOnForm(parentFormId);
        }
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
    const normalized = (this._query || "").trim().toLowerCase();
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
    const value = event.target.value || "";
    this._query = value;
    this._activeIndex = null;
  }

  /**
   * Clears the search query.
   * @private
   */
  _clearQuery() {
    this._query = "";
    this._activeIndex = null;
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

    const parentFormId = this._getParentFormId();
    if (parentFormId) {
      triggerChangeOnForm(parentFormId);
    }
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

    const parentFormId = this._getParentFormId();
    if (parentFormId) {
      triggerChangeOnForm(parentFormId);
    }
  }

  /**
   * Dynamically finds and returns the parent form ID.
   * @returns {string|null} Parent form ID or null
   * @private
   */
  _getParentFormId() {
    const form = this.closest("form");
    return form ? form.id : null;
  }

  /**
   * Opens the dropdown.
   * @private
   */
  _openDropdown() {
    if (this.options.length === 0) {
      return;
    }
    this._isOpen = true;
    this._activeIndex = null;
    this._addDocumentListener();
  }

  /**
   * Closes the dropdown.
   * @private
   */
  _closeDropdown() {
    this._isOpen = false;
    this._activeIndex = null;
    this._removeDocumentListener();
  }

  /**
   * Handles focus on the input.
   * @private
   */
  _handleFocus() {
    this._openDropdown();
  }

  /**
   * Registers a click listener on document to detect outside clicks.
   * @private
   */
  _addDocumentListener() {
    if (this._documentClickHandler) {
      return;
    }
    this._documentClickHandler = (event) => {
      const path = event.composedPath();
      if (!path.includes(this)) {
        this._closeDropdown();
      }
    };
    document.addEventListener("click", this._documentClickHandler);
  }

  /**
   * Removes the outside click listener.
   * @private
   */
  _removeDocumentListener() {
    if (!this._documentClickHandler) {
      return;
    }
    document.removeEventListener("click", this._documentClickHandler);
    this._documentClickHandler = null;
  }

  /**
   * Handles keyboard navigation.
   * @param {KeyboardEvent} event - Keyboard event
   * @private
   */
  _handleKeydown(event) {
    if (event.defaultPrevented) {
      return;
    }

    if (!this._isOpen) {
      return;
    }

    if (event.key === "Escape") {
      event.preventDefault();
      this._closeDropdown();
      return;
    }

    if (this._filteredOptions.length === 0) {
      return;
    }

    switch (event.key) {
      case "ArrowDown":
        event.preventDefault();
        if (this._activeIndex === null) {
          this._activeIndex = 0;
        } else {
          this._activeIndex = (this._activeIndex + 1) % this._filteredOptions.length;
        }
        break;
      case "ArrowUp":
        event.preventDefault();
        if (this._activeIndex === null) {
          this._activeIndex = 0;
        } else {
          this._activeIndex =
            (this._activeIndex - 1 + this._filteredOptions.length) % this._filteredOptions.length;
        }
        break;
      case "Enter":
        event.preventDefault();
        if (this._activeIndex !== null) {
          const opt = this._filteredOptions[this._activeIndex];
          if (opt) {
            this._toggleOption(opt.value);
          }
        }
        break;
      default:
        break;
    }
  }

  render() {
    const selectedOptions = this._selectedOptions;

    return html`
      <div class="px-6 py-7 pt-5 border-b border-stone-100">
        <div class="font-semibold leading-4 md:leading-8 text-[0.775rem] text-stone-700 mb-3">
          ${this.title}
        </div>

        <div class="relative">
          <div
            class="flex items-center gap-2 min-h-[38px] px-2 py-1.5 bg-white border border-stone-200 rounded-lg"
          >
            <div class="svg-icon size-3 icon-search bg-stone-400 shrink-0"></div>
            <input
              type="text"
              class="flex-1 text-[0.775rem] bg-transparent border-none focus:ring-0 focus:outline-none placeholder-stone-400 p-0"
              placeholder="${this.placeholder}"
              autocomplete="off"
              .value=${this._query}
              @input=${(e) => this._handleSearchInput(e)}
              @change=${(event) => event.stopPropagation()}
              @focus=${() => this._handleFocus()}
            />
            ${this._query
              ? html`
                  <button
                    type="button"
                    class="text-stone-400 hover:text-stone-700 shrink-0"
                    @click=${() => this._clearQuery()}
                  >
                    <div class="svg-icon size-3.5 icon-close bg-current"></div>
                  </button>
                `
              : ""}
          </div>

          ${this._isOpen
            ? html`
                <div
                  class="absolute top-full left-0 right-0 z-10 mt-1 bg-white rounded-lg shadow-lg border border-stone-200 max-h-48 overflow-y-auto"
                >
                  ${this._filteredOptions.length > 0
                    ? html`
                        <ul class="py-1" role="listbox">
                          ${repeat(
                            this._filteredOptions,
                            (opt) => opt.value,
                            (opt, index) => {
                              const isSelected = this.selected.includes(opt.value);
                              const isActive = this._activeIndex === index;

                              return html`
                                <li role="presentation">
                                  <button
                                    type="button"
                                    class="w-full px-3 py-2 text-left text-[0.775rem] flex items-center gap-2 ${isActive
                                      ? "bg-stone-50"
                                      : "hover:bg-stone-50"}"
                                    role="option"
                                    aria-selected=${isSelected}
                                    @click=${() => {
                                      this._toggleOption(opt.value);
                                    }}
                                    @mouseover=${() => (this._activeIndex = index)}
                                  >
                                    <span class="shrink-0 w-4 h-4 flex items-center justify-center">
                                      ${isSelected
                                        ? html`<div class="svg-icon size-3 icon-check bg-primary-500"></div>`
                                        : ""}
                                    </span>
                                    <span class="text-stone-700">${opt.name}</span>
                                  </button>
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
                      class="flex items-center justify-between w-full px-2 py-1 text-[0.775rem] font-medium text-primary-500 border border-primary-500 rounded-lg"
                    >
                      <span>${opt.name}</span>
                      <button
                        type="button"
                        class="text-stone-400 hover:text-stone-700"
                        @click=${(e) => this._removeOption(opt.value, e)}
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
