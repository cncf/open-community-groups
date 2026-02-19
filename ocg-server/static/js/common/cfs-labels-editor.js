import { html, repeat } from "/static/vendor/js/lit-all.v3.3.1.min.js";
import { LitWrapper } from "/static/js/common/lit-wrapper.js";

/**
 * CfsLabelsEditor manages event-level CFS labels in event forms.
 *
 * @property {Array<string>} colors Available color palette
 * @property {boolean} disabled Whether edits are disabled
 * @property {string} fieldName Base field name for submitted labels
 * @property {Array<Object>} labels Initial labels to render
 * @property {number} maxItems Maximum labels allowed
 */
export class CfsLabelsEditor extends LitWrapper {
  static properties = {
    colors: { type: Array, attribute: "colors" },
    disabled: { type: Boolean, reflect: true },
    fieldName: { type: String, attribute: "field-name" },
    labels: { type: Array, attribute: "labels" },
    maxItems: { type: Number, attribute: "max-items" },

    _openColorPopoverRowId: { state: true },
    _rows: { state: true },
  };

  constructor() {
    super();
    this.colors = [];
    this.disabled = false;
    this.fieldName = "cfs_labels";
    this.labels = [];
    this.maxItems = 200;

    this._openColorPopoverRowId = null;
    this._rows = [];
    this._nextId = 0;
    this._documentClickHandler = null;
  }

  connectedCallback() {
    super.connectedCallback();
    this._applyInitialLabels(this.labels);
  }

  disconnectedCallback() {
    super.disconnectedCallback();
    this._removeDocumentListener();
  }

  updated(changedProperties) {
    super.updated(changedProperties);

    if (changedProperties.has("labels")) {
      const previous = changedProperties.get("labels");
      if (previous !== this.labels) {
        this._applyInitialLabels(this.labels);
      }
    }

    if (changedProperties.has("disabled") && this.disabled) {
      this._closeColorPopover();
    }
  }

  /**
   * Public helper to replace labels from external scripts.
   * @param {Array<Object>} labels Labels payload
   */
  setLabels(labels) {
    this.labels = labels;
    this._applyInitialLabels(labels);
  }

  /**
   * Adds a new empty row.
   */
  _addRow() {
    if (this.disabled || this._isMaxReached()) {
      return;
    }

    this._rows = [...this._rows, this._createEmptyRow()];
  }

  /**
   * Creates an empty row with the first configured color when available.
   * @returns {Object}
   */
  _createEmptyRow() {
    return {
      _row_id: this._nextRowId(),
      color: this._paletteColors[0] || "",
      event_cfs_label_id: "",
      name: "",
    };
  }

  /**
   * Applies initial labels payload.
   * @param {Array<Object>} labels Labels payload
   */
  _applyInitialLabels(labels) {
    const normalized = this._normalizeRows(labels);
    this._rows = normalized;
    this._nextId = normalized.reduce((acc, row) => Math.max(acc, row._row_id + 1), 0);
    if (normalized.length === 0) {
      this._rows = [this._createEmptyRow()];
    }
    if (
      this._openColorPopoverRowId !== null &&
      !this._rows.some((row) => row._row_id === this._openColorPopoverRowId)
    ) {
      this._closeColorPopover();
    }
  }

  /**
   * Gets the configured palette.
   * @returns {Array<string>}
   */
  get _paletteColors() {
    const palette = Array.isArray(this.colors) ? this.colors : [];
    return palette.map((value) => String(value || "").trim()).filter((value) => value.length > 0);
  }

  /**
   * Checks whether max items limit was reached.
   * @returns {boolean}
   */
  _isMaxReached() {
    return this.maxItems > 0 && this._rows.length >= this.maxItems;
  }

  /**
   * Generates a stable local row id.
   * @returns {number}
   */
  _nextRowId() {
    const value = this._nextId;
    this._nextId += 1;
    return value;
  }

  /**
   * Normalizes incoming label rows.
   * @param {Array<Object>} labels Labels payload
   * @returns {Array<Object>}
   */
  _normalizeRows(labels) {
    if (!Array.isArray(labels) || labels.length === 0) {
      return [];
    }

    const palette = new Set(this._paletteColors);
    const rows = labels
      .map((label) => {
        const eventCfsLabelId = String(label?.event_cfs_label_id || "").trim();
        const name = String(label?.name || "").trim();
        const rawColor = String(label?.color || "").trim();
        const color = palette.has(rawColor) ? rawColor : this._paletteColors[0] || rawColor;

        if (!name) {
          return null;
        }

        return {
          _row_id: this._nextRowId(),
          color,
          event_cfs_label_id: eventCfsLabelId,
          name,
        };
      })
      .filter(Boolean)
      .sort((left, right) => left.name.toLowerCase().localeCompare(right.name.toLowerCase()));

    return rows;
  }

  /**
   * Removes a row by local row id.
   * @param {number} rowId Local row id
   */
  _removeRow(rowId) {
    if (this.disabled) {
      return;
    }

    const remainingRows = this._rows.filter((row) => row._row_id !== rowId);
    this._rows = remainingRows.length > 0 ? remainingRows : [this._createEmptyRow()];
    if (this._openColorPopoverRowId === rowId) {
      this._closeColorPopover();
    }
  }

  /**
   * Updates a row color.
   * @param {number} rowId Local row id
   * @param {string} color Selected color
   */
  _setRowColor(rowId, color) {
    if (this.disabled) {
      return;
    }

    this._rows = this._rows.map((row) => {
      if (row._row_id !== rowId) {
        return row;
      }
      return { ...row, color };
    });
    this._closeColorPopover();
  }

  /**
   * Updates a row name.
   * @param {number} rowId Local row id
   * @param {InputEvent} event Input event
   */
  _setRowName(rowId, event) {
    if (this.disabled) {
      return;
    }

    const value = event.target?.value || "";
    this._rows = this._rows.map((row) => {
      if (row._row_id !== rowId) {
        return row;
      }
      return { ...row, name: value };
    });
  }

  _toggleColorPopover(rowId) {
    if (this.disabled) {
      return;
    }

    if (this._openColorPopoverRowId === rowId) {
      this._closeColorPopover();
      return;
    }

    this._openColorPopoverRowId = rowId;
    this._addDocumentListener();
  }

  _closeColorPopover() {
    this._openColorPopoverRowId = null;
    this._removeDocumentListener();
  }

  _addDocumentListener() {
    if (this._documentClickHandler) {
      return;
    }

    this._documentClickHandler = (event) => {
      const path = event.composedPath();
      if (!path.includes(this)) {
        this._closeColorPopover();
      }
    };
    document.addEventListener("click", this._documentClickHandler);
  }

  _removeDocumentListener() {
    if (!this._documentClickHandler) {
      return;
    }

    document.removeEventListener("click", this._documentClickHandler);
    this._documentClickHandler = null;
  }

  render() {
    const maxReached = this._isMaxReached();
    const paletteColors = this._paletteColors;

    return html`
      <div class="space-y-4">
        ${repeat(
          this._rows,
          (row) => row._row_id,
          (row, index) => {
            const trimmedName = row.name.trim();
            const hasPaletteColors = paletteColors.length > 0;
            const isColorPopoverOpen = this._openColorPopoverRowId === row._row_id;
            const isDeleteDisabled =
              this.disabled ||
              (this._rows.length === 1 &&
                trimmedName.length === 0 &&
                String(row.event_cfs_label_id || "").length === 0);
            return html`
              <div class="py-1">
                <div class="flex items-center gap-2">
                  <div class="flex-1">
                    <label class="sr-only" for="cfs-label-name-${row._row_id}">Label</label>
                    <input
                      id="cfs-label-name-${row._row_id}"
                      type="text"
                      class="input-primary w-full"
                      maxlength="80"
                      placeholder="track / ai + ml"
                      .value=${row.name}
                      ?required=${!this.disabled}
                      ?disabled=${this.disabled}
                      @input=${(event) => this._setRowName(row._row_id, event)}
                    />
                  </div>

                  <div class="relative shrink-0">
                    <button
                      type="button"
                      class="inline-flex size-[38px] items-center justify-center rounded-full border transition hover:ring-1 hover:ring-stone-200"
                      style="--label-color:${row.color ||
                      "transparent"};border-color:var(--label-color);background-color:color-mix(in srgb, var(--label-color) 30%, transparent);"
                      title="Pick label color"
                      aria-label="Pick label color. Selected color is ${row.color}"
                      aria-expanded=${isColorPopoverOpen}
                      aria-controls="cfs-label-color-popover-${row._row_id}"
                      ?disabled=${this.disabled || !hasPaletteColors}
                      @click=${() => this._toggleColorPopover(row._row_id)}
                    >
                      <span
                        class="inline-flex size-[22px] rounded-full"
                        style="background-color:${row.color || "transparent"};"
                      ></span>
                    </button>
                    ${isColorPopoverOpen && hasPaletteColors
                      ? html`
                          <div
                            id="cfs-label-color-popover-${row._row_id}"
                            class="absolute top-full right-0 z-50 mt-2 w-[220px] rounded-xl border border-stone-200 bg-white p-2 shadow-lg"
                            role="listbox"
                            aria-label="Label colors"
                          >
                            <div class="grid grid-cols-5 gap-2 place-items-center">
                              ${repeat(
                                paletteColors,
                                (color) => color,
                                (color) => {
                                  const selected = row.color === color;
                                  return html`
                                    <button
                                      type="button"
                                      class="inline-flex h-8 w-8 items-center justify-center rounded-full border transition ${selected
                                        ? "ring-2 ring-stone-300"
                                        : "hover:ring-1 hover:ring-stone-200"}"
                                      style="--label-color:${color};border-color:var(--label-color);background-color:color-mix(in srgb, var(--label-color) 30%, transparent);"
                                      title="${color}"
                                      role="option"
                                      aria-selected=${selected}
                                      aria-label="Select color ${color}"
                                      ?disabled=${this.disabled}
                                      @click=${() => this._setRowColor(row._row_id, color)}
                                    >
                                      ${selected
                                        ? html`<div class="svg-icon size-3 icon-check bg-black"></div>`
                                        : ""}
                                    </button>
                                  `;
                                },
                              )}
                            </div>
                          </div>
                        `
                      : ""}
                  </div>

                  <button
                    type="button"
                    class="inline-flex size-[38px] shrink-0 items-center justify-center rounded-full border border-stone-200 ${isDeleteDisabled
                      ? ""
                      : "hover:bg-stone-100"}"
                    title="Remove label"
                    aria-label="Remove label"
                    ?disabled=${isDeleteDisabled}
                    @click=${() => this._removeRow(row._row_id)}
                  >
                    <div class="svg-icon size-4 icon-trash bg-stone-600"></div>
                  </button>
                </div>

                ${trimmedName
                  ? html`
                      <input type="hidden" name="${this.fieldName}[${index}][color]" .value=${row.color} />
                      ${row.event_cfs_label_id
                        ? html`
                            <input
                              type="hidden"
                              name="${this.fieldName}[${index}][event_cfs_label_id]"
                              .value=${row.event_cfs_label_id}
                            />
                          `
                        : ""}
                      <input type="hidden" name="${this.fieldName}[${index}][name]" .value=${trimmedName} />
                    `
                  : ""}
              </div>
            `;
          },
        )}

        <button
          type="button"
          class="btn-primary-outline btn-mini"
          ?disabled=${this.disabled || maxReached}
          @click=${() => this._addRow()}
        >
          Add label
        </button>

        ${maxReached
          ? html`<p class="form-legend">Maximum number of labels reached (${this.maxItems}).</p>`
          : ""}
      </div>
    `;
  }
}

if (!customElements.get("cfs-labels-editor")) {
  customElements.define("cfs-labels-editor", CfsLabelsEditor);
}
