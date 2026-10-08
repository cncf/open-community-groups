import { html, nothing } from "lit";
import { repeat } from "lit/directives/repeat.js";
import { ComboboxController } from "/static/js/common/combobox.js";
import { DropdownPlacementController } from "/static/js/common/dropdown-placement.js";
import { labelColorStyle } from "/static/js/common/labels.js";
import { LitWrapper } from "/static/js/common/lit-wrapper.js";

const DEFAULT_EMPTY_MESSAGE = "No results found";
const DEFAULT_PLACEHOLDER = "Type to search";

// Counter used to build unique ID prefixes for elements without an id.
let generatedIdPrefixCount = 0;

/**
 * MultiSelect renders a searchable multi-select combobox that submits the
 * selected values as `name[]` hidden inputs.
 *
 * Subclasses customize the markup by overriding the render hooks
 * (`_renderLayout`, `_renderSearchInput`, `_renderDropdown`, `_renderOption`,
 * `_renderChips`, `_renderChip` and `_renderHiddenInputs`) and the emitted
 * event by overriding `_dispatchSelectionChange`.
 *
 * @property {boolean} closeOnSelect Whether the dropdown closes after a selection
 * @property {boolean} compact Whether selected chips use the compact size
 * @property {boolean} disabled Whether interactions are disabled
 * @property {string} emptyMessage Text displayed when no option matches the search
 * @property {boolean} keepOrder Whether options keep their given order instead of
 *   being sorted alphabetically
 * @property {string} label Accessible name for the search input
 * @property {string} labelledby ID of the element naming the search input
 * @property {string} legend Helper text displayed under the input
 * @property {number} maxSelected Maximum number of selections (0 means unlimited)
 * @property {string} name Form field base name used for hidden inputs
 * @property {Array<{value: string, name: string, color?: string}>} options
 *   Available options
 * @property {string} placeholder Search input placeholder
 * @property {Array<string>} selected Selected option values
 * @property {boolean} selectedInInput Whether selected chips render inside the input
 * @fires change Bubbling native event dispatched after a selection change renders
 */
export class MultiSelect extends LitWrapper {
  static properties = {
    closeOnSelect: { type: Boolean, attribute: "close-on-select", reflect: true },
    compact: { type: Boolean, reflect: true },
    disabled: { type: Boolean, reflect: true },
    emptyMessage: { type: String, attribute: "empty-message" },
    keepOrder: { type: Boolean, attribute: "keep-order", reflect: true },
    label: { type: String },
    labelledby: { type: String },
    legend: { type: String },
    maxSelected: { type: Number, attribute: "max-selected" },
    name: { type: String },
    options: { type: Array },
    placeholder: { type: String },
    selected: { type: Array },
    selectedInInput: { type: Boolean, attribute: "selected-in-input", reflect: true },
  };

  constructor() {
    super();
    this.closeOnSelect = false;
    this.compact = false;
    this.disabled = false;
    this.emptyMessage = DEFAULT_EMPTY_MESSAGE;
    this.keepOrder = false;
    this.label = "";
    this.labelledby = "";
    this.legend = "";
    this.maxSelected = 0;
    this.name = "";
    this.options = [];
    this.placeholder = DEFAULT_PLACEHOLDER;
    this.selected = [];
    this.selectedInInput = false;

    // Texts subclasses may replace to match their domain.
    this._addMorePlaceholder = "Add more";
    this._clearSelectionLabel = "Clear selection";

    this._filteredCache = { query: "", source: null, value: [] };
    this._generatedIdPrefix = "";
    this._sortedCache = { keepOrder: false, source: null, value: [] };

    this._combobox = new ComboboxController(this, {
      canOpen: () => this.options.length > 0,
      getItemCount: () => this._filteredOptions.length,
      isInteractionBlocked: () => this.disabled,
      onActiveIndexMove: () => this._scrollActiveOptionIntoView(),
      onSelect: (index) => {
        const option = this._filteredOptions[index];
        if (option) {
          this._toggleSelection(option.value);
        }
      },
    });
    this._dropdownPlacement = new DropdownPlacementController(this, {
      getAnchor: () => this._searchAnchorElement(),
      getDropdown: () => this._dropdownElement(),
    });
  }

  /**
   * Clears every selection and the search query without emitting events.
   * Used by parent form reset flows.
   */
  cleanSelected() {
    this.selected = [];
    this._combobox.setQuery("");
  }

  /**
   * Normalizes options and selections before rendering.
   * @param {Map<string, unknown>} changedProperties Changed reactive properties
   */
  willUpdate(changedProperties) {
    super.willUpdate(changedProperties);

    const optionsChanged = changedProperties.has("options");
    const selectedChanged = changedProperties.has("selected");
    if (optionsChanged) {
      this.options = normalizeOptions(this.options);
    }
    if (selectedChanged) {
      this.selected = normalizeSelected(this.selected);
    }
    if (optionsChanged || selectedChanged) {
      this._pruneSelected();
    }
  }

  updated(changedProperties) {
    super.updated(changedProperties);

    if (changedProperties.has("disabled") && this.disabled) {
      this._combobox.close();
    }
  }

  /**
   * Gets options filtered by the search query.
   * @returns {Array<{value: string, name: string, color?: string}>}
   */
  get _filteredOptions() {
    const sorted = this._sortedOptions;
    const query = (this._combobox.query || "").trim().toLowerCase();
    const cache = this._filteredCache;
    if (cache.source !== sorted || cache.query !== query) {
      const value = query ? sorted.filter((option) => option.name.toLowerCase().includes(query)) : sorted;
      this._filteredCache = { query, source: sorted, value };
    }
    return this._filteredCache.value;
  }

  /**
   * Gets the prefix used to build stable element IDs.
   * @returns {string}
   */
  get _idPrefix() {
    if (this.id) {
      return this.id;
    }
    if (!this._generatedIdPrefix) {
      generatedIdPrefixCount += 1;
      const base = sanitizeIdPart(this.name) || "options";
      this._generatedIdPrefix = `multi-select-${base}-${generatedIdPrefixCount}`;
    }
    return this._generatedIdPrefix;
  }

  /**
   * Gets selected option objects in display order.
   * @returns {Array<{value: string, name: string, color?: string}>}
   */
  get _selectedOptions() {
    const selectedSet = new Set(this.selected);
    return this._sortedOptions.filter((option) => selectedSet.has(option.value));
  }

  /**
   * Gets options in display order: alphabetical unless keepOrder is set.
   * @returns {Array<{value: string, name: string, color?: string}>}
   */
  get _sortedOptions() {
    const cache = this._sortedCache;
    if (cache.source !== this.options || cache.keepOrder !== this.keepOrder) {
      const value = this.keepOrder ? this.options : [...this.options].sort(compareOptions);
      this._sortedCache = { keepOrder: this.keepOrder, source: this.options, value };
    }
    return this._sortedCache.value;
  }

  /**
   * Gets the ID of the highlighted option while the dropdown is open.
   * @returns {string|typeof nothing}
   */
  _activeOptionId() {
    const index = this._combobox.activeIndex;
    return this._combobox.isOpen && index !== null ? this._optionId(index) : nothing;
  }

  /**
   * Gets the accessible name for the input when no labelling element is set.
   * @returns {string|typeof nothing}
   */
  _ariaLabel() {
    return !this.labelledby && this.label ? this.label : nothing;
  }

  /**
   * Checks if adding a new selection is allowed.
   * @returns {boolean}
   */
  _canAddSelection() {
    if (this.maxSelected <= 0) {
      return true;
    }
    return this.selected.length < this.maxSelected;
  }

  /**
   * Clears the search query.
   */
  _clearQuery() {
    this._combobox.setQuery("");
    this._combobox.setActiveIndex(null);
  }

  /**
   * Clears every selection.
   * @param {Event} [event] Click event
   */
  async _clearSelections(event) {
    event?.stopPropagation();
    if (this.disabled || this.selected.length === 0) {
      return;
    }

    this.selected = [];
    await this.updateComplete;
    this._dispatchSelectionChange();
  }

  /**
   * Dispatches the selection change event once the new state has rendered.
   */
  _dispatchSelectionChange() {
    this.dispatchEvent(new Event("change", { bubbles: true }));
  }

  /**
   * Finds the positioned dropdown element.
   * @returns {Element|null}
   */
  _dropdownElement() {
    return this.querySelector("[data-multi-select-dropdown]");
  }

  /**
   * Opens the dropdown when the input gets focus.
   */
  _handleFocus() {
    this._combobox.open();
  }

  /**
   * Closes the dropdown when clicking the input while it is already open.
   * @param {PointerEvent} event Pointer event
   */
  _handleInputPointerDown(event) {
    if (this.disabled) {
      return;
    }

    if (this._combobox.isOpen) {
      event.preventDefault();
      this._combobox.close();
    }
  }

  /**
   * Handles search input updates.
   * @param {InputEvent} event Input event
   */
  _handleSearchInput(event) {
    this._combobox.setQuery(event.target?.value || "");
    this._combobox.setActiveIndex(null);
    if (!this._combobox.isOpen && !this.disabled) {
      this._combobox.open();
    }
  }

  /**
   * Gets the legend ID when a legend is rendered.
   * @returns {string|typeof nothing}
   */
  _legendId() {
    return String(this.legend || "").trim() ? `${this._idPrefix}-legend` : nothing;
  }

  /**
   * Gets the listbox ID.
   * @returns {string}
   */
  _listboxId() {
    return `${this._idPrefix}-listbox`;
  }

  /**
   * Gets the ID of the option rendered at the given filtered index.
   * @param {number} index Filtered option index
   * @returns {string}
   */
  _optionId(index) {
    return `${this._idPrefix}-option-${index}`;
  }

  /**
   * Drops selected values that are not available options.
   */
  async _pruneSelected() {
    const validValues = new Set(this.options.map((option) => option.value));
    const pruned = this.selected.filter((value) => validValues.has(value));
    if (pruned.length === this.selected.length) {
      return;
    }

    this.selected = pruned;
    await this.updateComplete;
    this._dispatchSelectionChange();
  }

  /**
   * Removes a selection.
   * @param {string} value Option value to remove
   * @param {Event} [event] Click event
   */
  async _removeSelection(value, event) {
    event?.stopPropagation();
    if (this.disabled || !this.selected.includes(value)) {
      return;
    }

    this.selected = this.selected.filter((selectedValue) => selectedValue !== value);
    await this.updateComplete;
    this._dispatchSelectionChange();
  }

  /**
   * Renders one selected chip, coloured when the option has a color.
   * @param {{value: string, name: string, color?: string}} option Selected option
   * @returns {import("lit").TemplateResult}
   */
  _renderChip(option) {
    const sizeClass = this.compact ? "h-[22px] gap-0.5 px-2 py-0.5 text-[11px]" : "gap-2 px-2.5 py-1 text-xs";
    const colorClass = option.color ? "" : "border-stone-300 bg-stone-100";
    const colorStyle = option.color ? labelColorStyle(option.color) : nothing;
    const iconSizeClass = this.compact ? "size-2.5" : "size-3";

    return html`
      <span
        class="inline-flex items-center rounded-full border font-medium text-stone-900 max-w-full ${sizeClass} ${colorClass}"
        style=${colorStyle}
        title=${option.name}
      >
        <span class="truncate ${this.selectedInInput ? "max-w-[160px]" : "max-w-full"}">${option.name}</span>
        <button
          type="button"
          class="inline-flex size-3 items-center justify-center rounded-full border-0 bg-transparent text-stone-700 hover:text-stone-900"
          @click=${(event) => this._removeSelection(option.value, event)}
          ?disabled=${this.disabled}
          aria-label="Remove ${option.name}"
        >
          <div class="svg-icon ${iconSizeClass} icon-close bg-current" aria-hidden="true"></div>
        </button>
      </span>
    `;
  }

  /**
   * Renders the selected chips.
   * @param {Array<{value: string, name: string, color?: string}>} selected Selected options
   * @returns {import("lit").TemplateResult|typeof nothing}
   */
  _renderChips(selected) {
    if (selected.length === 0) {
      return nothing;
    }
    return html`${repeat(
      selected,
      (option) => option.value,
      (option) => this._renderChip(option),
    )}`;
  }

  /**
   * Renders the dropdown listbox while the combobox is open.
   * @param {Array<{value: string, name: string, color?: string}>} options Filtered options
   * @returns {import("lit").TemplateResult|typeof nothing}
   */
  _renderDropdown(options) {
    if (!this._combobox.isOpen) {
      return nothing;
    }

    return html`
      <ul
        id=${this._listboxId()}
        data-multi-select-dropdown
        class="absolute top-full mt-1 left-0 right-0 z-20 max-h-56 overflow-y-auto rounded-lg border border-stone-200 bg-white shadow-sm"
        role="listbox"
        aria-multiselectable="true"
      >
        ${
          options.length > 0
            ? repeat(
                options,
                (option) => option.value,
                (option, index) => this._renderOption(option, index),
              )
            : html`<li role="presentation" class="px-3 py-2 text-sm text-stone-500">${this.emptyMessage}</li>`
        }
      </ul>
    `;
  }

  /**
   * Renders the selected values as hidden form inputs.
   * @returns {import("lit").TemplateResult|typeof nothing}
   */
  _renderHiddenInputs() {
    if (!this.name) {
      return nothing;
    }
    return html`${repeat(
      this.selected,
      (value) => value,
      (value) => html`<input type="hidden" name="${this.name}[]" value="${value}" />`,
    )}`;
  }

  /**
   * Composes the rendered parts into the component layout.
   * @param {object} parts Rendered parts
   * @param {unknown} parts.chips Selected chips
   * @param {unknown} parts.dropdown Dropdown listbox
   * @param {unknown} parts.hiddenInputs Hidden form inputs
   * @param {unknown} parts.search Search input
   * @param {Array<object>} parts.selected Selected options
   * @returns {import("lit").TemplateResult}
   */
  _renderLayout({ chips, dropdown, hiddenInputs, search, selected }) {
    const legendText = String(this.legend || "").trim();
    const hasSelection = selected.length > 0;

    return html`
      <div class=${this.selectedInInput ? "space-y-0" : "space-y-3"}>
        <div>
          <div class="relative" data-multi-select-search>
            <div class="absolute inset-y-0 start-0 flex items-center ps-3 pointer-events-none">
              <div class="svg-icon size-4 icon-search bg-stone-300" aria-hidden="true"></div>
            </div>
            ${
              this.selectedInInput
                ? html`
                    <div
                      class="input-primary min-h-[42px] w-full ps-9 pe-2 py-1 flex flex-wrap items-center gap-1.5"
                    >
                      ${chips} ${search}
                      ${
                        hasSelection
                          ? html`
                              <button
                                type="button"
                                class="inline-flex shrink-0 items-center justify-center rounded-full bg-transparent p-1 text-stone-400 hover:text-stone-700"
                                @click=${(event) => this._clearSelections(event)}
                                ?disabled=${this.disabled}
                                aria-label=${this._clearSelectionLabel}
                                title=${this._clearSelectionLabel}
                              >
                                <div class="svg-icon size-4 icon-close bg-current" aria-hidden="true"></div>
                              </button>
                            `
                          : nothing
                      }
                    </div>
                  `
                : search
            }
            ${
              this._combobox.query && !this.selectedInInput
                ? html`
                    <button
                      type="button"
                      class="absolute inset-y-0 end-0 flex items-center pe-3 text-stone-400 hover:text-stone-700"
                      aria-label="Clear search"
                      @click=${() => this._clearQuery()}
                    >
                      <div class="svg-icon size-4 icon-close bg-current" aria-hidden="true"></div>
                    </button>
                  `
                : nothing
            }
            ${dropdown}
          </div>
          ${legendText ? html`<p id=${this._legendId()} class="form-legend mt-2">${legendText}</p>` : nothing}
        </div>
        ${!this.selectedInInput && hasSelection ? html`<div class="flex flex-wrap gap-2">${chips}</div>` : nothing}
        ${hiddenInputs}
      </div>
    `;
  }

  /**
   * Renders one option of the listbox.
   * @param {{value: string, name: string, color?: string}} option Option to render
   * @param {number} index Filtered option index
   * @returns {import("lit").TemplateResult}
   */
  _renderOption(option, index) {
    const isActive = this._combobox.activeIndex === index;
    const isSelected = this.selected.includes(option.value);
    const isDisabled = this.disabled || (!isSelected && !this._canAddSelection());

    return html`
      <li
        id=${this._optionId(index)}
        class="flex w-full items-center justify-between gap-3 px-3 py-2 text-left text-sm ${
          isActive ? "bg-stone-100" : "hover:bg-stone-50"
        } ${isDisabled ? "cursor-not-allowed opacity-60" : "cursor-pointer"}"
        role="option"
        aria-selected=${String(isSelected)}
        aria-disabled=${isDisabled ? "true" : nothing}
        @mousedown=${(event) => event.preventDefault()}
        @click=${() => this._toggleSelection(option.value)}
        @mouseover=${() => this._combobox.setActiveIndex(index)}
      >
        <span class="flex items-center gap-2 min-w-0">
          ${
            option.color
              ? html`<span
                  class="inline-flex size-2.5 shrink-0 rounded-full border border-stone-500/20"
                  style="background-color:${option.color};"
                  aria-hidden="true"
                ></span>`
              : nothing
          }
          <span class="truncate text-stone-800">${option.name}</span>
        </span>
        ${
          isSelected
            ? html`<div class="svg-icon size-3 shrink-0 icon-check bg-primary-500" aria-hidden="true"></div>`
            : nothing
        }
      </li>
    `;
  }

  /**
   * Renders the search combobox input.
   * @returns {import("lit").TemplateResult}
   */
  _renderSearchInput() {
    const hasSelection = this.selected.length > 0;
    const placeholder =
      this.selectedInInput && hasSelection
        ? this._addMorePlaceholder
        : this.placeholder || DEFAULT_PLACEHOLDER;
    const inputClass = this.selectedInInput
      ? "min-w-[120px] flex-1 border-0 bg-transparent p-0 text-sm text-stone-900 placeholder:text-stone-400 focus:outline-none focus:ring-0"
      : "input-primary w-full ps-9 pe-9";

    return html`
      <input
        type="search"
        class=${inputClass}
        placeholder=${placeholder}
        autocomplete="off"
        autocorrect="off"
        autocapitalize="off"
        spellcheck="false"
        role="combobox"
        aria-autocomplete="list"
        aria-haspopup="listbox"
        aria-controls=${this._listboxId()}
        aria-expanded=${String(this._combobox.isOpen)}
        aria-activedescendant=${this._activeOptionId()}
        aria-label=${this._ariaLabel()}
        aria-labelledby=${this.labelledby || nothing}
        aria-describedby=${this._legendId()}
        .value=${this._combobox.query}
        ?disabled=${this.disabled || this.options.length === 0}
        @pointerdown=${(event) => this._handleInputPointerDown(event)}
        @focus=${() => this._handleFocus()}
        @input=${(event) => this._handleSearchInput(event)}
        @change=${(event) => event.stopPropagation()}
      />
    `;
  }

  /**
   * Scrolls the active option into view after keyboard navigation.
   */
  async _scrollActiveOptionIntoView() {
    await this.updateComplete;
    const index = this._combobox.activeIndex;
    if (index === null) {
      return;
    }
    this.querySelector(`#${CSS.escape(this._optionId(index))}`)?.scrollIntoView({ block: "nearest" });
  }

  /**
   * Finds the element the dropdown opens from.
   * @returns {Element|null}
   */
  _searchAnchorElement() {
    return this.querySelector("[data-multi-select-search]");
  }

  /**
   * Toggles an option selection, honoring the maximum selection count.
   * @param {string} value Option value to toggle
   */
  async _toggleSelection(value) {
    if (this.disabled) {
      return;
    }

    const isSelected = this.selected.includes(value);
    if (!isSelected && !this._canAddSelection()) {
      return;
    }

    this.selected = isSelected
      ? this.selected.filter((selectedValue) => selectedValue !== value)
      : [...this.selected, value];
    if (this.closeOnSelect) {
      this._combobox.close();
    }

    await this.updateComplete;
    this._dispatchSelectionChange();
  }

  render() {
    const filtered = this._filteredOptions;
    const selected = this._selectedOptions;

    return this._renderLayout({
      chips: this._renderChips(selected),
      dropdown: this._renderDropdown(filtered),
      hiddenInputs: this._renderHiddenInputs(),
      search: this._renderSearchInput(),
      selected,
    });
  }
}

/**
 * Compares options by name, then by value.
 * @param {{value: string, name: string}} left
 * @param {{value: string, name: string}} right
 * @returns {number}
 */
const compareOptions = (left, right) => {
  const leftName = left.name.toLowerCase();
  const rightName = right.name.toLowerCase();
  if (leftName !== rightName) {
    return leftName.localeCompare(rightName);
  }
  return left.value.localeCompare(right.value);
};

/**
 * Normalizes options into unique `{value, name, color?}` entries.
 * @param {unknown} options Raw options
 * @returns {Array<{value: string, name: string, color?: string}>}
 */
const normalizeOptions = (options) => {
  if (!Array.isArray(options)) {
    return [];
  }

  const normalized = [];
  const seen = new Set();
  for (const option of options) {
    const value = String(option?.value ?? "").trim();
    const name = String(option?.name ?? "").trim();
    const color = String(option?.color ?? "").trim();
    if (!value || !name || seen.has(value)) {
      continue;
    }

    seen.add(value);
    normalized.push(color ? { color, name, value } : { name, value });
  }
  return normalized;
};

/**
 * Normalizes selected values into unique non-empty strings.
 * @param {unknown} selected Raw selected value or values
 * @returns {Array<string>}
 */
const normalizeSelected = (selected) => {
  const values = Array.isArray(selected) ? selected : [selected];
  const normalized = values
    .filter((value) => value !== null && value !== undefined)
    .map((value) => String(value).trim())
    .filter((value) => value.length > 0);
  return [...new Set(normalized)];
};

/**
 * Turns a form field name into a safe ID fragment.
 * @param {string} value Raw value
 * @returns {string}
 */
const sanitizeIdPart = (value) =>
  String(value || "")
    .replace(/[^A-Za-z0-9_-]+/g, "-")
    .replace(/-+/g, "-")
    .replace(/^-|-$/g, "");

if (!customElements.get("multi-select")) {
  customElements.define("multi-select", MultiSelect);
}
