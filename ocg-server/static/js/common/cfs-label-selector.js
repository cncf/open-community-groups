import { html, repeat } from "/static/vendor/js/lit-all.v3.3.1.min.js";
import { LitWrapper } from "/static/js/common/lit-wrapper.js";

const DEFAULT_PLACEHOLDER = "Search labels";

/**
 * CfsLabelSelector renders a searchable multi-select for CFS labels.
 *
 * @property {boolean} disabled Whether interactions are disabled
 * @property {Array<Object>} labels Available labels for selection
 * @property {number} maxSelected Maximum number of labels allowed (0 means unlimited)
 * @property {string} name Form field base name used for hidden inputs
 * @property {string} placeholder Search input placeholder
 * @property {Array<string>} selected Selected event_cfs_label_id values
 */
export class CfsLabelSelector extends LitWrapper {
  static properties = {
    disabled: { type: Boolean, reflect: true },
    labels: { type: Array, attribute: "labels" },
    maxSelected: { type: Number, attribute: "max-selected" },
    name: { type: String, attribute: "name" },
    placeholder: { type: String, attribute: "placeholder" },
    selected: { type: Array, attribute: "selected" },

    _activeIndex: { state: true },
    _isOpen: { state: true },
    _query: { state: true },
  };

  constructor() {
    super();
    this.disabled = false;
    this.labels = [];
    this.maxSelected = 0;
    this.name = "label_ids";
    this.placeholder = DEFAULT_PLACEHOLDER;
    this.selected = [];

    this._activeIndex = null;
    this._isOpen = false;
    this._query = "";

    this._documentClickHandler = null;
    this._keydownHandler = null;
  }

  connectedCallback() {
    super.connectedCallback();
    this._normalizeLabels();
    this._normalizeSelected();
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
      this._closeDropdown();
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
    const query = (this._query || "").trim().toLowerCase();
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
    this._query = "";
    this._activeIndex = null;
  }

  /**
   * Handles search input updates.
   * @param {InputEvent} event The input event
   */
  _handleSearchInput(event) {
    this._query = event.target?.value || "";
    this._activeIndex = null;
    if (!this._isOpen && !this.disabled) {
      this._openDropdown();
    }
  }

  /**
   * Handles keyboard navigation.
   * @param {KeyboardEvent} event The keyboard event
   */
  _handleKeydown(event) {
    if (event.defaultPrevented || this.disabled || !this._isOpen) {
      return;
    }

    if (event.key === "Escape") {
      event.preventDefault();
      this._closeDropdown();
      return;
    }

    const filteredLabels = this._filteredLabels;
    if (filteredLabels.length === 0) {
      return;
    }

    switch (event.key) {
      case "ArrowDown":
        event.preventDefault();
        if (this._activeIndex === null) {
          this._activeIndex = 0;
        } else {
          this._activeIndex = (this._activeIndex + 1) % filteredLabels.length;
        }
        break;
      case "ArrowUp":
        event.preventDefault();
        if (this._activeIndex === null) {
          this._activeIndex = 0;
        } else {
          this._activeIndex = (this._activeIndex - 1 + filteredLabels.length) % filteredLabels.length;
        }
        break;
      case "Enter":
        event.preventDefault();
        if (this._activeIndex !== null) {
          const label = filteredLabels[this._activeIndex];
          if (label?.event_cfs_label_id) {
            this._toggleSelection(String(label.event_cfs_label_id));
          }
        }
        break;
      default:
        break;
    }
  }

  /**
   * Handles input focus.
   */
  _handleFocus() {
    this._openDropdown();
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

    this.labels = normalizedLabels;
  }

  /**
   * Normalizes selected values into an array of strings.
   */
  _normalizeSelected() {
    if (Array.isArray(this.selected)) {
      this.selected = this.selected.map((value) => String(value || "")).filter((value) => value.length > 0);
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
   * Opens the dropdown.
   */
  _openDropdown() {
    if (this.disabled || this.labels.length === 0) {
      return;
    }

    this._isOpen = true;
    this._activeIndex = null;
    this._addDocumentListener();
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

    const alreadySelected = this.selected.includes(eventCfsLabelId);
    if (alreadySelected) {
      this.selected = this.selected.filter((value) => value !== eventCfsLabelId);
      this._emitChange();
      return;
    }

    if (!this._canAddSelection()) {
      return;
    }

    this.selected = [...this.selected, eventCfsLabelId];
    this._emitChange();
  }

  /**
   * Closes the dropdown.
   */
  _closeDropdown() {
    this._isOpen = false;
    this._activeIndex = null;
    this._removeDocumentListener();
  }

  /**
   * Registers the outside click listener.
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
   */
  _removeDocumentListener() {
    if (!this._documentClickHandler) {
      return;
    }

    document.removeEventListener("click", this._documentClickHandler);
    this._documentClickHandler = null;
  }

  render() {
    const filteredLabels = this._filteredLabels;
    const selectedLabels = this._selectedLabels;
    const selectionLimitReached = !this._canAddSelection();
    const inputDisabled = this.disabled || this.labels.length === 0;

    return html`
      <div class="space-y-3">
        <div class="relative">
          <div class="absolute inset-y-0 start-0 flex items-center ps-3 pointer-events-none">
            <div class="svg-icon size-4 icon-search bg-stone-300"></div>
          </div>
          <input
            type="search"
            class="input-primary w-full ps-9 pe-9"
            placeholder=${this.placeholder || DEFAULT_PLACEHOLDER}
            autocomplete="off"
            autocorrect="off"
            autocapitalize="off"
            spellcheck="false"
            .value=${this._query}
            ?disabled=${inputDisabled}
            @focus=${() => this._handleFocus()}
            @input=${(event) => this._handleSearchInput(event)}
          />
          ${this._query
            ? html`
                <button
                  type="button"
                  class="absolute inset-y-0 end-0 flex items-center pe-3 text-stone-400 hover:text-stone-700"
                  @click=${() => this._clearQuery()}
                >
                  <div class="svg-icon size-4 icon-close bg-current"></div>
                </button>
              `
            : ""}
        </div>

        ${this._isOpen
          ? html`
              <div class="relative">
                <ul
                  class="absolute left-0 right-0 z-20 max-h-56 overflow-y-auto rounded-lg border border-stone-200 bg-white shadow-sm"
                  role="listbox"
                >
                  ${filteredLabels.length > 0
                    ? repeat(
                        filteredLabels,
                        (label) => label.event_cfs_label_id,
                        (label, index) => {
                          const eventCfsLabelId = String(label.event_cfs_label_id);
                          const isActive = this._activeIndex === index;
                          const isSelected = this.selected.includes(eventCfsLabelId);
                          const isDisabled = this.disabled || (selectionLimitReached && !isSelected);

                          return html`
                            <li role="presentation">
                              <button
                                type="button"
                                class="flex w-full items-center justify-between gap-3 px-3 py-2 text-left text-sm ${isActive
                                  ? "bg-stone-50"
                                  : "hover:bg-stone-50"} ${isDisabled
                                  ? "cursor-not-allowed opacity-60"
                                  : "cursor-pointer"}"
                                role="option"
                                aria-selected=${isSelected}
                                ?disabled=${isDisabled}
                                @click=${() => this._toggleSelection(eventCfsLabelId)}
                                @mouseover=${() => (this._activeIndex = index)}
                              >
                                <span class="flex items-center gap-2 min-w-0">
                                  <span
                                    class="inline-flex size-2.5 rounded-full border border-stone-500/20"
                                    style="background-color:${label.color};"
                                  ></span>
                                  <span class="truncate text-stone-800">${label.name}</span>
                                </span>
                                ${isSelected
                                  ? html`<div class="svg-icon size-3 icon-check bg-primary-500"></div>`
                                  : ""}
                              </button>
                            </li>
                          `;
                        },
                      )
                    : html`<li class="px-3 py-2 text-sm text-stone-500">No labels found</li>`}
                </ul>
              </div>
            `
          : ""}
        ${selectedLabels.length > 0
          ? html`
              <div class="flex flex-wrap gap-2">
                ${repeat(
                  selectedLabels,
                  (label) => label.event_cfs_label_id,
                  (label) => {
                    const eventCfsLabelId = String(label.event_cfs_label_id);
                    return html`
                      <span
                        class="inline-flex items-center gap-2 rounded-full border border-stone-300 px-2.5 py-1 text-xs font-medium text-stone-900"
                        style="background-color:${label.color};"
                        title=${label.name}
                      >
                        <span class="truncate max-w-[200px]">${label.name}</span>
                        <button
                          type="button"
                          class="inline-flex items-center justify-center rounded-full text-stone-700 hover:text-stone-900"
                          @click=${(event) => this._removeSelection(eventCfsLabelId, event)}
                          ?disabled=${this.disabled}
                          aria-label="Remove ${label.name}"
                        >
                          <div class="svg-icon size-3 icon-close bg-current"></div>
                        </button>
                      </span>
                    `;
                  },
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

if (!customElements.get("cfs-label-selector")) {
  customElements.define("cfs-label-selector", CfsLabelSelector);
}
