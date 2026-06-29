import { html, repeat } from "/static/vendor/js/lit-all.v3.3.3.min.js";
import { ComboboxController } from "/static/js/common/combobox.js";
import { LitWrapper } from "/static/js/common/lit-wrapper.js";

const DEFAULT_PLACEHOLDER = "Search labels";

/**
 * CfsLabelSelector renders a searchable multi-select for CFS labels.
 *
 * @property {boolean} disabled Whether interactions are disabled
 * @property {boolean} closeOnSelect Whether dropdown closes after selecting a label
 * @property {string} legend Helper text displayed under the input
 * @property {Array<Object>} labels Available labels for selection
 * @property {number} maxSelected Maximum number of labels allowed (0 means unlimited)
 * @property {string} name Form field base name used for hidden inputs
 * @property {string} placeholder Search input placeholder
 * @property {Array<string>} selected Selected event_cfs_label_id values
 */
export class CfsLabelSelector extends LitWrapper {
  static properties = {
    closeOnSelect: { type: Boolean, attribute: "close-on-select", reflect: true },
    compact: { type: Boolean, reflect: true },
    disabled: { type: Boolean, reflect: true },
    legend: { type: String, attribute: "legend" },
    labels: { type: Array, attribute: "labels" },
    maxSelected: { type: Number, attribute: "max-selected" },
    name: { type: String, attribute: "name" },
    placeholder: { type: String, attribute: "placeholder" },
    selected: { type: Array, attribute: "selected" },
    selectedInInput: { type: Boolean, attribute: "selected-in-input", reflect: true },
  };

  constructor() {
    super();
    this.closeOnSelect = false;
    this.compact = false;
    this.disabled = false;
    this.legend = "";
    this.labels = [];
    this.maxSelected = 0;
    this.name = "label_ids";
    this.placeholder = DEFAULT_PLACEHOLDER;
    this.selected = [];
    this.selectedInInput = false;

    this._combobox = new ComboboxController(this, {
      getItemCount: () => this._filteredLabels.length,
      isInteractionBlocked: () => this.disabled,
      canOpen: () => this.labels.length > 0,
      onSelect: (index) => {
        const label = this._filteredLabels[index];
        if (label?.event_cfs_label_id) {
          this._toggleSelection(String(label.event_cfs_label_id));
        }
      },
    });
  }

  connectedCallback() {
    super.connectedCallback();
    this._normalizeLabels();
    this._normalizeSelected();
  }

  updated(changedProperties) {
    super.updated(changedProperties);

    if (changedProperties.has("labels")) {
      this._normalizeLabels();
      this._pruneSelected();
    }

    if (changedProperties.has("selected")) {
      this._normalizeSelected();
      this._pruneSelected();
    }

    if (changedProperties.has("disabled") && this.disabled) {
      this._combobox.close();
    }
  }

  /**
   * Gets labels sorted alphabetically by name.
   * @returns {Array<Object>}
   */
  get _sortedLabels() {
    return [...this.labels].sort((left, right) => {
      const leftName = String(left?.name || "").toLowerCase();
      const rightName = String(right?.name || "").toLowerCase();
      if (leftName !== rightName) {
        return leftName.localeCompare(rightName);
      }
      const leftId = String(left?.event_cfs_label_id || "");
      const rightId = String(right?.event_cfs_label_id || "");
      return leftId.localeCompare(rightId);
    });
  }

  /**
   * Gets labels filtered by search query.
   * @returns {Array<Object>}
   */
  get _filteredLabels() {
    const query = (this._combobox.query || "").trim().toLowerCase();
    if (!query) {
      return this._sortedLabels;
    }

    return this._sortedLabels.filter((label) => {
      return String(label?.name || "")
        .toLowerCase()
        .includes(query);
    });
  }

  /**
   * Gets selected label objects in alphabetical order.
   * @returns {Array<Object>}
   */
  get _selectedLabels() {
    const selectedSet = new Set(this.selected || []);
    return this._sortedLabels.filter((label) => selectedSet.has(String(label.event_cfs_label_id)));
  }

  /**
   * Emits a bubbling change event.
   */
  _emitChange() {
    this.dispatchEvent(new Event("change", { bubbles: true }));
  }

  /**
   * Checks if adding a new label selection is allowed.
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
   * Handles search input updates.
   * @param {InputEvent} event The input event
   */
  _handleSearchInput(event) {
    this._combobox.setQuery(event.target?.value || "");
    this._combobox.setActiveIndex(null);
    if (!this._combobox.isOpen && !this.disabled) {
      this._combobox.open();
    }
  }

  /**
   * Handles input focus.
   */
  _handleFocus() {
    this._combobox.open();
  }

  /**
   * Closes dropdown when clicking the trigger while already open.
   * @param {PointerEvent} event
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
   * Normalizes labels input.
   */
  _normalizeLabels() {
    if (!Array.isArray(this.labels)) {
      this.labels = [];
      return;
    }

    const normalizedLabels = [];
    const seen = new Set();

    for (const label of this.labels) {
      const eventCfsLabelId = String(label?.event_cfs_label_id || "");
      const name = String(label?.name || "").trim();
      const color = String(label?.color || "").trim();

      if (!eventCfsLabelId || !name || seen.has(eventCfsLabelId)) {
        continue;
      }

      seen.add(eventCfsLabelId);
      normalizedLabels.push({
        color,
        event_cfs_label_id: eventCfsLabelId,
        name,
      });
    }

    if (!this._areLabelsEqual(this.labels, normalizedLabels)) {
      this.labels = normalizedLabels;
    }
  }

  /**
   * Normalizes selected values into an array of strings.
   */
  _normalizeSelected() {
    if (Array.isArray(this.selected)) {
      const normalizedSelected = this.selected
        .map((value) => String(value || ""))
        .filter((value) => value.length > 0);
      if (!this._areStringArraysEqual(this.selected, normalizedSelected)) {
        this.selected = normalizedSelected;
      }
      return;
    }

    if (this.selected === null || this.selected === undefined) {
      this.selected = [];
      return;
    }

    const value = String(this.selected || "");
    this.selected = value ? [value] : [];
  }

  /**
   * Checks whether two labels arrays contain the same values in order.
   * @param {Array<Object>} left
   * @param {Array<Object>} right
   * @returns {boolean}
   */
  _areLabelsEqual(left, right) {
    if (!Array.isArray(left) || !Array.isArray(right) || left.length !== right.length) {
      return false;
    }

    return left.every((leftLabel, index) => {
      const rightLabel = right[index];
      return (
        String(leftLabel?.event_cfs_label_id || "") === String(rightLabel?.event_cfs_label_id || "") &&
        String(leftLabel?.name || "").trim() === String(rightLabel?.name || "").trim() &&
        String(leftLabel?.color || "").trim() === String(rightLabel?.color || "").trim()
      );
    });
  }

  /**
   * Checks whether two string arrays contain the same values in order.
   * @param {Array<string>} left
   * @param {Array<string>} right
   * @returns {boolean}
   */
  _areStringArraysEqual(left, right) {
    if (!Array.isArray(left) || !Array.isArray(right) || left.length !== right.length) {
      return false;
    }

    return left.every((leftValue, index) => leftValue === right[index]);
  }

  /**
   * Prunes selected values not present in labels.
   */
  _pruneSelected() {
    const validIds = new Set(this.labels.map((label) => String(label.event_cfs_label_id)));
    const pruned = this.selected.filter((value) => validIds.has(value));
    if (pruned.length !== this.selected.length) {
      this.selected = pruned;
      this._emitChange();
    }
  }

  /**
   * Removes an active selection.
   * @param {string} eventCfsLabelId The event CFS label id to remove
   * @param {Event} event The click event
   */
  _removeSelection(eventCfsLabelId, event) {
    event?.stopPropagation();
    if (this.disabled) {
      return;
    }

    const next = this.selected.filter((value) => value !== eventCfsLabelId);
    if (next.length === this.selected.length) {
      return;
    }

    this.selected = next;
    this._emitChange();
  }

  /**
   * Toggles a label selection.
   * @param {string} eventCfsLabelId The event CFS label id to toggle
   */
  _toggleSelection(eventCfsLabelId) {
    if (this.disabled) {
      return;
    }

    let selectionChanged = false;
    const alreadySelected = this.selected.includes(eventCfsLabelId);
    if (alreadySelected) {
      this.selected = this.selected.filter((value) => value !== eventCfsLabelId);
      selectionChanged = true;
      this._emitChange();
    } else {
      if (!this._canAddSelection()) {
        return;
      }

      this.selected = [...this.selected, eventCfsLabelId];
      selectionChanged = true;
      this._emitChange();
    }

    if (selectionChanged && this.closeOnSelect) {
      this._combobox.close();
    }
  }

  /**
   * Clears all selected labels.
   * @param {Event} event
   */
  _clearSelections(event) {
    event?.stopPropagation();
    if (this.disabled || this.selected.length === 0) {
      return;
    }
    this.selected = [];
    this._emitChange();
  }

  render() {
    const filteredLabels = this._filteredLabels;
    const selectedLabels = this._selectedLabels;
    const selectionLimitReached = !this._canAddSelection();
    const inputDisabled = this.disabled || this.labels.length === 0;
    const selectedChipClass = this.compact
      ? "inline-flex h-[22px] items-center gap-0.5 rounded-full border px-2 py-0.5 text-[11px] font-medium text-stone-900 max-w-full"
      : "inline-flex items-center gap-2 rounded-full border px-2.5 py-1 text-xs font-medium text-stone-900 max-w-full";
    const selectedChipIconSizeClass = this.compact ? "size-2.5" : "size-3";
    const inputPlaceholder =
      selectedLabels.length === 0 ? this.placeholder || DEFAULT_PLACEHOLDER : "Add labels";
    const legendText = String(this.legend || "").trim();

    return html`
      <div class=${this.selectedInInput ? "space-y-0" : "space-y-3"}>
        <div>
          <div class="relative">
            <div class="absolute inset-y-0 start-0 flex items-center ps-3 pointer-events-none">
              <div class="svg-icon size-4 icon-search bg-stone-300"></div>
            </div>
            ${
              this.selectedInInput
                ? html`
                    <div
                      class="input-primary min-h-[42px] w-full ps-9 pe-2 py-1 flex flex-wrap items-center gap-1.5"
                    >
                      ${
                      selectedLabels.length > 0
                        ? repeat(
                            selectedLabels,
                            (label) => label.event_cfs_label_id,
                            (label) => {
                              const eventCfsLabelId = String(label.event_cfs_label_id);
                              return html`
                                <span
                                  class=${selectedChipClass}
                                  style="--label-color:${label.color};border-color:var(--label-color);background-color:color-mix(in srgb, var(--label-color) 30%, transparent);"
                                  title=${label.name}
                                >
                                  <span class="truncate max-w-[160px]">${label.name}</span>
                                  <button
                                    type="button"
                                    class="inline-flex size-3 items-center justify-center rounded-full border-0 bg-transparent text-stone-700 hover:text-stone-900"
                                    @click=${(event) => this._removeSelection(eventCfsLabelId, event)}
                                    ?disabled=${this.disabled}
                                    aria-label="Remove ${label.name}"
                                  >
                                    <div
                                      class="svg-icon ${selectedChipIconSizeClass} icon-close bg-current"
                                    ></div>
                                  </button>
                                </span>
                              `;
                            },
                          )
                        : ""
                    }
                      <input
                        type="search"
                        class="min-w-[120px] flex-1 border-0 bg-transparent p-0 text-sm text-stone-900 placeholder:text-stone-400 focus:outline-none focus:ring-0"
                        placeholder=${inputPlaceholder}
                        autocomplete="off"
                        autocorrect="off"
                        autocapitalize="off"
                        spellcheck="false"
                        .value=${this._combobox.query}
                        ?disabled=${inputDisabled}
                        @pointerdown=${(event) => this._handleInputPointerDown(event)}
                        @focus=${() => this._handleFocus()}
                        @input=${(event) => this._handleSearchInput(event)}
                      />
                      ${
                      selectedLabels.length > 0
                        ? html`
                            <button
                              type="button"
                              class="inline-flex shrink-0 items-center justify-center rounded-full bg-transparent p-1 text-stone-400 hover:text-stone-700"
                              @click=${(event) => this._clearSelections(event)}
                              ?disabled=${this.disabled}
                              aria-label="Clear selected labels"
                              title="Clear selected labels"
                            >
                              <div class="svg-icon size-4 icon-close bg-current"></div>
                            </button>
                          `
                        : ""
                    }
                    </div>
                  `
                : html`
                    <input
                      type="search"
                      class="input-primary w-full ps-9 pe-9"
                      placeholder=${this.placeholder || DEFAULT_PLACEHOLDER}
                      autocomplete="off"
                      autocorrect="off"
                      autocapitalize="off"
                      spellcheck="false"
                      .value=${this._combobox.query}
                      ?disabled=${inputDisabled}
                      @pointerdown=${(event) => this._handleInputPointerDown(event)}
                      @focus=${() => this._handleFocus()}
                      @input=${(event) => this._handleSearchInput(event)}
                    />
                  `
            }
            ${
              this._combobox.query && !this.selectedInInput
                ? html`
                    <button
                      type="button"
                      class="absolute inset-y-0 end-0 flex items-center pe-3 text-stone-400 hover:text-stone-700"
                      @click=${() => this._clearQuery()}
                    >
                      <div class="svg-icon size-4 icon-close bg-current"></div>
                    </button>
                  `
                : ""
            }
            ${
              this._combobox.isOpen
                ? html`
                    <ul
                      class="absolute top-full mt-1 left-0 right-0 z-20 max-h-56 overflow-y-auto rounded-lg border border-stone-200 bg-white shadow-sm"
                      role="listbox"
                    >
                      ${
                      filteredLabels.length > 0
                        ? repeat(
                            filteredLabels,
                            (label) => label.event_cfs_label_id,
                            (label, index) => {
                              const eventCfsLabelId = String(label.event_cfs_label_id);
                              const isActive = this._combobox.activeIndex === index;
                              const isSelected = this.selected.includes(eventCfsLabelId);
                              const isDisabled = this.disabled || (selectionLimitReached && !isSelected);

                              return html`
                                <li role="presentation">
                                  <button
                                    type="button"
                                    class="flex w-full items-center justify-between gap-3 px-3 py-2 text-left text-sm ${
                                    isActive ? "bg-stone-50" : "hover:bg-stone-50"
                                  } ${isDisabled ? "cursor-not-allowed opacity-60" : "cursor-pointer"}"
                                    role="option"
                                    aria-selected=${isSelected}
                                    ?disabled=${isDisabled}
                                    @click=${() => this._toggleSelection(eventCfsLabelId)}
                                    @mouseover=${() => this._combobox.setActiveIndex(index)}
                                  >
                                    <span class="flex items-center gap-2 min-w-0">
                                      <span
                                        class="inline-flex size-2.5 rounded-full border border-stone-500/20"
                                        style="background-color:${label.color};"
                                      ></span>
                                      <span class="truncate text-stone-800">${label.name}</span>
                                    </span>
                                    ${
                                    isSelected
                                      ? html`<div class="svg-icon size-3 icon-check bg-primary-500"></div>`
                                      : ""
                                  }
                                  </button>
                                </li>
                              `;
                            },
                          )
                        : html`<li class="px-3 py-2 text-sm text-stone-500">No labels found</li>`
                    }
                    </ul>
                  `
                : ""
            }
          </div>
          ${legendText ? html`<p class="form-legend mt-2">${legendText}</p>` : ""}
        </div>
        ${
          !this.selectedInInput && selectedLabels.length > 0
            ? html`
                <div class="flex flex-wrap gap-2">
                  ${repeat(
                  selectedLabels,
                  (label) => label.event_cfs_label_id,
                  (label) => {
                    const eventCfsLabelId = String(label.event_cfs_label_id);
                    return html`
                      <span
                        class=${selectedChipClass}
                        style="--label-color:${label.color};border-color:var(--label-color);background-color:color-mix(in srgb, var(--label-color) 30%, transparent);"
                        title=${label.name}
                      >
                        <span class="truncate max-w-full">${label.name}</span>
                        <button
                          type="button"
                          class="inline-flex size-3 items-center justify-center rounded-full border-0 bg-transparent text-stone-700 hover:text-stone-900"
                          @click=${(event) => this._removeSelection(eventCfsLabelId, event)}
                          ?disabled=${this.disabled}
                          aria-label="Remove ${label.name}"
                        >
                          <div class="svg-icon ${selectedChipIconSizeClass} icon-close bg-current"></div>
                        </button>
                      </span>
                    `;
                  },
                )}
                </div>
              `
            : ""
        }
        ${repeat(
          this.selected,
          (value) => value,
          (value) => html`<input type="hidden" name="${this.name}[]" value="${value}" />`,
        )}
      </div>
    `;
  }
}

if (!customElements.get("cfs-label-selector")) {
  customElements.define("cfs-label-selector", CfsLabelSelector);
}
