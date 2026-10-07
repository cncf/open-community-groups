import { html } from "lit";
import { repeat } from "lit/directives/repeat.js";
import { labelColorStyle } from "/static/js/common/labels.js";
import { LitWrapper } from "/static/js/common/lit-wrapper.js";
import { readTrustedHtml } from "/static/js/common/trusted-html.js";
import { renderTrustedHtml } from "/static/js/common/trusted-lit-html.js";

const DEFAULT_MAX_NAME_LENGTH = 80;
const LABEL_NAME_REQUIRED_MESSAGE = "Label name is required";
const LABELS_CHANGED_EVENT = "labels-changed";

/**
 * LabelsEditor manages the event labels shared by sessions and CFS submissions.
 *
 * Every row keeps a stable `event_label_id`. Rows already saved in the
 * database always submit their id, so a blank name is blocked by validation
 * instead of deleting the label. New rows get a browser-generated id and are
 * submitted with `is_new=true` only once they have a name.
 *
 * @property {Array<string>} colors Available color palette
 * @property {boolean} disabled Whether edits are disabled
 * @property {string} fieldName Base field name for submitted labels
 * @property {string} legend Helper text rendered under the label rows
 * @property {Array<Object>} labels Initial labels to render
 * @property {number} maxItems Maximum labels allowed
 * @property {number} maxNameLength Maximum label name length
 * @fires labels-changed Bubbling event with `detail.labels` (named labels) and
 *   `detail.ids` (every row id) after the rows change
 */
export class LabelsEditor extends LitWrapper {
  static properties = {
    colors: { type: Array, attribute: "colors" },
    disabled: { type: Boolean, reflect: true },
    fieldName: { type: String, attribute: "field-name" },
    legend: { type: String, attribute: "legend" },
    labels: { type: Array, attribute: "labels" },
    maxItems: { type: Number, attribute: "max-items" },
    maxNameLength: { type: Number, attribute: "max-name-length" },

    _openColorPopoverRowId: { state: true },
    _rows: { state: true },
  };

  constructor() {
    super();
    this.colors = [];
    this.disabled = false;
    this.fieldName = "labels";
    this.legend = "";
    this.labels = [];
    this.maxItems = 200;
    this.maxNameLength = DEFAULT_MAX_NAME_LENGTH;

    this._appliedLabels = undefined;
    this._documentClickHandler = null;
    this._legendHtml = "";
    this._openColorPopoverRowId = null;
    this._rows = [];
  }

  connectedCallback() {
    this._captureLegendHtml();
    super.connectedCallback();
    if (this._appliedLabels !== this.labels) {
      this._applyInitialLabels(this.labels);
    }
  }

  disconnectedCallback() {
    super.disconnectedCallback();
    this._removeDocumentListener();
  }

  updated(changedProperties) {
    super.updated(changedProperties);

    if (changedProperties.has("labels") && this._appliedLabels !== this.labels) {
      this._applyInitialLabels(this.labels);
    }

    if (changedProperties.has("disabled") && this.disabled) {
      this._closeColorPopover();
    }

    this._syncNameValidity();
  }

  /**
   * Returns every row id, including rows whose name is currently blank.
   * @returns {Array<string>}
   */
  getIds() {
    return this._rows.map((row) => row.event_label_id);
  }

  /**
   * Returns the labels that currently have a non-blank name.
   * @returns {Array<{color: string, event_label_id: string, name: string}>}
   */
  getLabels() {
    return this._rows
      .map((row) => ({ color: row.color, event_label_id: row.event_label_id, name: row.name.trim() }))
      .filter((label) => label.name.length > 0);
  }

  /**
   * Public helper to replace labels from external scripts. Labels without an
   * id are treated as new labels.
   * @param {Array<Object>} labels Labels payload
   */
  setLabels(labels) {
    this.labels = labels;
    this._applyInitialLabels(labels);
  }

  /**
   * Registers the document listener that closes the color popover.
   */
  _addDocumentListener() {
    if (this._documentClickHandler) {
      return;
    }

    this._documentClickHandler = (event) => {
      const path = event.composedPath();
      if (!this._isActiveColorPopoverInteraction(path)) {
        this._closeColorPopover();
      }
    };
    document.addEventListener("click", this._documentClickHandler);
  }

  /**
   * Adds a new empty row.
   */
  _addRow() {
    if (this.disabled || this._isMaxReached()) {
      return;
    }

    this._setRows([...this._rows, this._createEmptyRow()]);
  }

  /**
   * Applies initial labels payload.
   * @param {Array<Object>} labels Labels payload
   */
  _applyInitialLabels(labels) {
    this._appliedLabels = labels;
    const rows = this._normalizeRows(labels);
    if (
      this._openColorPopoverRowId !== null &&
      !rows.some((row) => row.event_label_id === this._openColorPopoverRowId)
    ) {
      this._closeColorPopover();
    }
    this._setRows(rows);
  }

  /**
   * Captures the slotted legend markup before Lit renders the component.
   */
  _captureLegendHtml() {
    const legendNode = this.querySelector('[slot="legend"]');
    if (!legendNode) {
      const renderedLegendNode = this.querySelector('.form-legend[data-custom-legend="true"]');
      if (!renderedLegendNode) {
        this._legendHtml = "";
      }
      return;
    }

    this._legendHtml = readTrustedHtml(legendNode).trim();
  }

  /**
   * Closes the color popover and removes its document listener.
   */
  _closeColorPopover() {
    this._openColorPopoverRowId = null;
    this._removeDocumentListener();
  }

  /**
   * Creates an empty new row with a color derived from its index.
   * @returns {Object}
   */
  _createEmptyRow() {
    return {
      color: this._getPaletteColorForIndex(this._rows.length),
      event_label_id: crypto.randomUUID(),
      is_new: true,
      name: "",
    };
  }

  /**
   * Dispatches the current labels and row ids.
   */
  _emitLabelsChanged() {
    this.dispatchEvent(
      new CustomEvent(LABELS_CHANGED_EVENT, {
        bubbles: true,
        composed: true,
        detail: { ids: this.getIds(), labels: this.getLabels() },
      }),
    );
  }

  /**
   * Returns a palette color for the provided index.
   * @param {number} index
   * @returns {string}
   */
  _getPaletteColorForIndex(index) {
    const paletteColors = this._paletteColors;
    if (paletteColors.length === 0) {
      return "";
    }

    return paletteColors[index % paletteColors.length];
  }

  /**
   * Checks whether the click happened within the active color trigger or popover.
   * @param {Array<EventTarget>} path Event path
   * @returns {boolean}
   */
  _isActiveColorPopoverInteraction(path) {
    if (this._openColorPopoverRowId === null) {
      return false;
    }

    return path.some((node) => node?.dataset?.colorPopoverRowId === this._openColorPopoverRowId);
  }

  /**
   * Checks whether max items limit was reached.
   * @returns {boolean}
   */
  _isMaxReached() {
    return this.maxItems > 0 && this._rows.length >= this.maxItems;
  }

  /**
   * Normalizes incoming label rows. Labels without an id get a new one and
   * are marked as new.
   * @param {Array<Object>} labels Labels payload
   * @returns {Array<Object>}
   */
  _normalizeRows(labels) {
    if (!Array.isArray(labels) || labels.length === 0) {
      return [];
    }

    const palette = new Set(this._paletteColors);
    const seen = new Set();
    const rows = [];
    for (const label of labels) {
      const name = String(label?.name || "").trim();
      if (!name) {
        continue;
      }

      const rawId = String(label?.event_label_id || "").trim();
      const eventLabelId = rawId && !seen.has(rawId) ? rawId : crypto.randomUUID();
      const rawColor = String(label?.color || "").trim();
      seen.add(eventLabelId);
      rows.push({
        color: palette.has(rawColor) ? rawColor : this._paletteColors[0] || rawColor,
        event_label_id: eventLabelId,
        is_new: eventLabelId !== rawId || label?.is_new === true,
        name,
      });
    }

    return rows.sort((left, right) => left.name.toLowerCase().localeCompare(right.name.toLowerCase()));
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
   * Removes the document listener used by the color popover.
   */
  _removeDocumentListener() {
    if (!this._documentClickHandler) {
      return;
    }

    document.removeEventListener("click", this._documentClickHandler);
    this._documentClickHandler = null;
  }

  /**
   * Removes a row by id. This is the only way to delete a saved label.
   * @param {string} rowId Row label id
   */
  _removeRow(rowId) {
    if (this.disabled) {
      return;
    }

    if (this._openColorPopoverRowId === rowId) {
      this._closeColorPopover();
    }
    this._setRows(this._rows.filter((row) => row.event_label_id !== rowId));
  }

  /**
   * Updates a row color.
   * @param {string} rowId Row label id
   * @param {string} color Selected color
   */
  _setRowColor(rowId, color) {
    if (this.disabled) {
      return;
    }

    this._setRows(this._rows.map((row) => (row.event_label_id === rowId ? { ...row, color } : row)));
    this._closeColorPopover();
  }

  /**
   * Updates a row name and its validity.
   * @param {string} rowId Row label id
   * @param {InputEvent} event Input event
   */
  _setRowName(rowId, event) {
    if (this.disabled) {
      return;
    }

    const value = event.target?.value || "";
    const row = this._rows.find((item) => item.event_label_id === rowId);
    if (row) {
      event.target.setCustomValidity?.(getNameValidityMessage({ ...row, name: value }));
    }
    this._setRows(
      this._rows.map((item) => (item.event_label_id === rowId ? { ...item, name: value } : item)),
    );
  }

  /**
   * Replaces the rows, keeps one starter row and notifies listeners.
   * @param {Array<Object>} rows Next rows
   */
  _setRows(rows) {
    this._rows = rows;
    if (this._rows.length === 0) {
      this._rows = [this._createEmptyRow()];
    }
    this._emitLabelsChanged();
  }

  /**
   * Keeps the custom validity of saved label name inputs in sync.
   */
  _syncNameValidity() {
    for (const row of this._rows) {
      const input = this.querySelector(`#${CSS.escape(nameInputId(row.event_label_id))}`);
      input?.setCustomValidity(getNameValidityMessage(row));
    }
  }

  /**
   * Toggles the color popover for a row.
   * @param {string} rowId Row label id
   */
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

  /**
   * Renders the hidden inputs submitted for one row.
   * @param {Object} row Label row
   * @param {number} index Row index
   * @returns {import("lit").TemplateResult|string}
   */
  _renderHiddenInputs(row, index) {
    const trimmedName = row.name.trim();
    if (row.is_new && !trimmedName) {
      return "";
    }

    const prefix = `${this.fieldName}[${index}]`;
    return html`
      <input type="hidden" name="${prefix}[color]" .value=${row.color} />
      <input type="hidden" name="${prefix}[event_label_id]" .value=${row.event_label_id} />
      ${row.is_new ? html`<input type="hidden" name="${prefix}[is_new]" value="true" />` : ""}
      <input type="hidden" name="${prefix}[name]" .value=${trimmedName} />
    `;
  }

  render() {
    const maxReached = this._isMaxReached();
    const paletteColors = this._paletteColors;
    const helperLegend = String(this.legend || "").trim();
    const hasCustomLegend = this._legendHtml.length > 0;

    return html`
      <div class="space-y-4">
        <input type="hidden" name="${this.fieldName}_present" value="true" />
        ${repeat(
          this._rows,
          (row) => row.event_label_id,
          (row, index) => {
            const rowId = row.event_label_id;
            const trimmedName = row.name.trim();
            const hasPaletteColors = paletteColors.length > 0;
            const isColorPopoverOpen = this._openColorPopoverRowId === rowId;
            const isDeleteDisabled =
              this.disabled || (this._rows.length === 1 && row.is_new && trimmedName.length === 0);
            const popoverId = `label-color-popover-${rowId}`;
            return html`
              <div class="w-full 2xl:w-1/2 py-1">
                <div class="flex items-center gap-2">
                  <div class="flex-1">
                    <label class="sr-only" for=${nameInputId(rowId)}>Label</label>
                    <input
                      id=${nameInputId(rowId)}
                      type="text"
                      class="input-primary w-full"
                      maxlength=${this.maxNameLength}
                      placeholder="track / ai + ml"
                      .value=${row.name}
                      ?required=${!this.disabled && !row.is_new}
                      ?disabled=${this.disabled}
                      data-managed-validity
                      @input=${(event) => this._setRowName(rowId, event)}
                    />
                  </div>

                  <div class="relative shrink-0">
                    <button
                      type="button"
                      data-color-popover-row-id=${rowId}
                      class="inline-flex size-[38px] items-center justify-center rounded-full border transition hover:ring-1 hover:ring-stone-200"
                      style=${labelColorStyle(row.color || "transparent")}
                      title="Pick label color"
                      aria-label="Pick label color. Selected color is ${row.color}"
                      aria-expanded=${isColorPopoverOpen}
                      aria-controls=${popoverId}
                      ?disabled=${this.disabled || !hasPaletteColors}
                      @click=${() => this._toggleColorPopover(rowId)}
                    >
                      <span
                        class="inline-flex size-[22px] rounded-full"
                        style="background-color:${row.color || "transparent"};"
                      ></span>
                    </button>
                    ${
                      isColorPopoverOpen && hasPaletteColors
                        ? html`
                            <div
                              id=${popoverId}
                              data-color-popover-row-id=${rowId}
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
                                        class="inline-flex h-8 w-8 items-center justify-center rounded-full border transition ${
                                          selected
                                            ? "ring-2 ring-stone-300"
                                            : "hover:ring-1 hover:ring-stone-200"
                                        }"
                                        style=${labelColorStyle(color)}
                                        title="${color}"
                                        role="option"
                                        aria-selected=${selected}
                                        aria-label="Select color ${color}"
                                        ?disabled=${this.disabled}
                                        @click=${() => this._setRowColor(rowId, color)}
                                      >
                                        ${
                                          selected
                                            ? html`<div class="svg-icon size-3 icon-check bg-black"></div>`
                                            : ""
                                        }
                                      </button>
                                    `;
                                  },
                                )}
                              </div>
                            </div>
                          `
                        : ""
                    }
                  </div>

                  <button
                    type="button"
                    class="inline-flex size-[38px] shrink-0 items-center justify-center rounded-full border border-stone-200 ${
                      isDeleteDisabled ? "" : "hover:bg-stone-100"
                    }"
                    title="Remove label"
                    aria-label="Remove label"
                    ?disabled=${isDeleteDisabled}
                    @click=${() => this._removeRow(rowId)}
                  >
                    <div class="svg-icon size-4 icon-trash bg-stone-600"></div>
                  </button>
                </div>

                ${this._renderHiddenInputs(row, index)}
              </div>
            `;
          },
        )}
        ${
          hasCustomLegend || helperLegend
            ? html`
                <div class="w-full">
                  <p class="form-legend" data-custom-legend=${hasCustomLegend ? "true" : "false"}>
                    ${hasCustomLegend ? renderTrustedHtml(this._legendHtml) : helperLegend}
                  </p>
                </div>
              `
            : ""
        }

        <div class="w-full 2xl:w-1/2">
          <button
            type="button"
            class="btn-primary-outline btn-mini"
            ?disabled=${this.disabled || maxReached}
            @click=${() => this._addRow()}
          >
            Add label
          </button>
        </div>

        ${
          maxReached
            ? html`<p class="form-legend w-full">Maximum number of labels reached (${this.maxItems}).</p>`
            : ""
        }
      </div>
    `;
  }
}

/**
 * Returns the validation message for a row name.
 * @param {{is_new: boolean, name: string}} row Label row
 * @returns {string} Validation message, or an empty string when valid
 */
const getNameValidityMessage = (row) =>
  !row.is_new && row.name.trim().length === 0 ? LABEL_NAME_REQUIRED_MESSAGE : "";

/**
 * Builds the DOM id of a row name input.
 * @param {string} rowId Row label id
 * @returns {string}
 */
const nameInputId = (rowId) => `label-name-${rowId}`;

if (!customElements.get("labels-editor")) {
  customElements.define("labels-editor", LabelsEditor);
}
