import { html, repeat } from "/static/vendor/js/lit-all.v3.3.1.min.js";
import { LitWrapper } from "/static/js/common/lit-wrapper.js";

const DEFAULT_COLORS = [
  "#CCFBF1",
  "#CFFAFE",
  "#DBEAFE",
  "#DCFCE7",
  "#ECFCCB",
  "#EDE9FE",
  "#FCE7F3",
  "#FEE2E2",
  "#FEF3C7",
  "#FFEDD5",
];

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

    _rows: { state: true },
  };

  constructor() {
    super();
    this.colors = DEFAULT_COLORS;
    this.disabled = false;
    this.fieldName = "cfs_labels";
    this.labels = [];
    this.maxItems = 200;

    this._rows = [];
    this._nextId = 0;
  }

  connectedCallback() {
    super.connectedCallback();
    this._applyInitialLabels(this.labels);
  }

  updated(changedProperties) {
    super.updated(changedProperties);

    if (changedProperties.has("labels")) {
      const previous = changedProperties.get("labels");
      if (previous !== this.labels) {
        this._applyInitialLabels(this.labels);
      }
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

    const defaultColor = this._paletteColors[0];
    this._rows = [
      ...this._rows,
      {
        _row_id: this._nextRowId(),
        color: defaultColor,
        event_cfs_label_id: "",
        name: "",
      },
    ];
  }

  /**
   * Applies initial labels payload.
   * @param {Array<Object>} labels Labels payload
   */
  _applyInitialLabels(labels) {
    const normalized = this._normalizeRows(labels);
    this._rows = normalized;
    this._nextId = normalized.reduce((acc, row) => Math.max(acc, row._row_id + 1), 0);
  }

  /**
   * Gets the configured palette with a safe fallback.
   * @returns {Array<string>}
   */
  get _paletteColors() {
    const palette = Array.isArray(this.colors) ? this.colors : [];
    const normalized = palette.map((value) => String(value || "").trim()).filter((value) => value.length > 0);
    return normalized.length > 0 ? normalized : DEFAULT_COLORS;
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
        const color = palette.has(rawColor) ? rawColor : this._paletteColors[0];

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

    this._rows = this._rows.filter((row) => row._row_id !== rowId);
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

  render() {
    const maxReached = this._isMaxReached();

    return html`
      <div class="space-y-4">
        ${this._rows.length === 0
          ? html`
              <div
                class="rounded-lg border border-dashed border-stone-300 bg-stone-50 px-4 py-3 text-sm text-stone-600"
              >
                No labels yet. Add labels to help categorize submissions.
              </div>
            `
          : ""}
        ${repeat(
          this._rows,
          (row) => row._row_id,
          (row, index) => {
            const trimmedName = row.name.trim();
            return html`
              <div class="rounded-lg border border-stone-200 bg-white p-3">
                <div class="flex flex-col gap-3 md:flex-row md:items-start">
                  <div class="flex-1">
                    <label class="form-label" for="cfs-label-name-${row._row_id}">Label name</label>
                    <input
                      id="cfs-label-name-${row._row_id}"
                      type="text"
                      class="input-primary mt-2"
                      maxlength="80"
                      placeholder="track / ai + ml"
                      .value=${row.name}
                      ?required=${!this.disabled}
                      ?disabled=${this.disabled}
                      @input=${(event) => this._setRowName(row._row_id, event)}
                    />
                  </div>

                  <div class="w-full md:w-auto">
                    <div class="form-label">Color</div>
                    <div class="mt-2 flex flex-wrap gap-2">
                      ${repeat(
                        this._paletteColors,
                        (color) => color,
                        (color) => {
                          const selected = row.color === color;
                          return html`
                            <button
                              type="button"
                              class="inline-flex h-8 w-8 items-center justify-center rounded-full border ${selected
                                ? "border-stone-700 ring-2 ring-stone-300"
                                : "border-stone-300 hover:border-stone-500"}"
                              style="background-color:${color};"
                              title="${color}"
                              ?disabled=${this.disabled}
                              @click=${() => this._setRowColor(row._row_id, color)}
                            >
                              ${selected
                                ? html`<div class="svg-icon size-3 icon-check bg-stone-700"></div>`
                                : ""}
                            </button>
                          `;
                        },
                      )}
                    </div>
                  </div>

                  <div class="md:pt-7">
                    <button
                      type="button"
                      class="btn-primary-outline btn-mini"
                      ?disabled=${this.disabled}
                      @click=${() => this._removeRow(row._row_id)}
                    >
                      Remove
                    </button>
                  </div>
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
