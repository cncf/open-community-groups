import { html, repeat } from "/static/vendor/js/lit-all.v3.3.1.min.js";
import { resolveEventTimezone } from "/static/js/dashboard/event/ticketing/datetime.js";
import { normalizeTicketTypes, serializeTicketTypes } from "/static/js/dashboard/event/ticketing/contract.js";
import { TicketingEditorBase } from "/static/js/dashboard/event/ticketing/base.js";
import { parseJsonAttribute } from "/static/js/dashboard/event/ticketing/shared.js";

/**
 * Ticket types editor.
 * @extends TicketingEditorBase
 */
export class TicketTypesEditor extends TicketingEditorBase {
  static properties = {
    ...TicketingEditorBase.properties,
    ticketTypes: { type: Array, attribute: "ticket-types" },

    _rows: { state: true },
  };

  constructor() {
    super();
    this.fieldNamePrefix = "ticket_types";
    this.presenceFieldName = "ticket_types_present";
    this.ticketTypes = [];
    this._rows = [];
  }

  connectedCallback() {
    super.connectedCallback();
    this._applyTicketTypes(this.ticketTypes);
  }

  updated(changedProperties) {
    super.updated(changedProperties);

    if (changedProperties.has("ticketTypes")) {
      this._applyTicketTypes(this.ticketTypes);
    }
  }

  /**
   * Returns true when at least one ticket type is configured.
   * @returns {boolean}
   */
  hasConfiguredTicketTypes() {
    return this._rows.length > 0;
  }

  /**
   * Returns the configured total number of seats across ticket types.
   * @returns {number|null}
   */
  getConfiguredSeatTotal() {
    if (this._rows.length === 0) {
      return null;
    }

    return this._rows.reduce((total, row) => {
      const seatsTotal = Number.parseInt(row.seats_total, 10);
      return total + (Number.isFinite(seatsTotal) && seatsTotal > 0 ? seatsTotal : 0);
    }, 0);
  }

  /**
   * Replaces ticket types from external scripts.
   * @param {Array<object>} ticketTypes Ticket types payload
   */
  setTicketTypes(ticketTypes) {
    this.ticketTypes = ticketTypes;
    this._applyTicketTypes(ticketTypes);
  }

  /**
   * Adds a new price window to a ticket type.
   * @param {number} rowId Ticket type row id
   */
  _addPriceWindow(rowId) {
    if (this.disabled) {
      return;
    }

    this._rows = this._rows.map((row) => {
      if (row._row_id !== rowId) {
        return row;
      }

      return {
        ...row,
        price_windows: [...row.price_windows, this._createEmptyPriceWindow()],
      };
    });
  }

  /**
   * Adds a new ticket type row.
   */
  _addTicketType() {
    if (this.disabled) {
      return;
    }

    this._rows = [...this._rows, this._createEmptyTicketType()];
    this._notifyTicketTypesChanged();
  }

  /**
   * Applies initial ticket types payload.
   * @param {*} ticketTypes Ticket types payload
   */
  _applyTicketTypes(ticketTypes) {
    const parsedTicketTypes = parseJsonAttribute(ticketTypes, []);
    const rows = normalizeTicketTypes({
      currencyCode: this._currencyCode(),
      nextRowId: () => this._nextRowId(),
      ticketTypes: parsedTicketTypes,
      timezone: resolveEventTimezone(),
    });

    this._rows = rows.map((row) => ({
      ...row,
      price_windows: row.price_windows.length > 0 ? row.price_windows : [this._createEmptyPriceWindow()],
    }));
    this._notifyTicketTypesChanged();
  }

  /**
   * Creates an empty price window row.
   * @returns {object}
   */
  _createEmptyPriceWindow() {
    return {
      _row_id: this._nextRowId(),
      amount: "",
      ends_at: "",
      event_ticket_price_window_id: "",
      starts_at: "",
    };
  }

  /**
   * Creates an empty ticket type row.
   * @returns {object}
   */
  _createEmptyTicketType() {
    return {
      _row_id: this._nextRowId(),
      active: true,
      description: "",
      event_ticket_type_id: "",
      price_windows: [this._createEmptyPriceWindow()],
      seats_total: "",
      title: "",
    };
  }

  /**
   * Emits the current ticketing state for surrounding UI.
   */
  _notifyTicketTypesChanged() {
    this._emitChange("ticket-types-changed", {
      hasTicketTypes: this.hasConfiguredTicketTypes(),
    });
  }

  /**
   * Removes a price window row.
   * @param {number} rowId Ticket type row id
   * @param {number} windowRowId Price window row id
   */
  _removePriceWindow(rowId, windowRowId) {
    if (this.disabled) {
      return;
    }

    this._rows = this._rows.map((row) => {
      if (row._row_id !== rowId) {
        return row;
      }

      const remainingWindows = row.price_windows.filter((windowRow) => windowRow._row_id !== windowRowId);
      return {
        ...row,
        price_windows: remainingWindows.length > 0 ? remainingWindows : [this._createEmptyPriceWindow()],
      };
    });
  }

  /**
   * Removes a ticket type row.
   * @param {number} rowId Ticket type row id
   */
  _removeTicketType(rowId) {
    if (this.disabled) {
      return;
    }

    this._rows = this._rows.filter((row) => row._row_id !== rowId);
    this._notifyTicketTypesChanged();
  }

  /**
   * Renders hidden nested inputs for the current ticket types.
   * @returns {import("/static/vendor/js/lit-all.v3.3.1.min.js").TemplateResult|string}
   */
  _renderHiddenFields() {
    if (this.disabled) {
      return "";
    }

    const fields = serializeTicketTypes({
      currencyCode: this._currencyCode(),
      fieldNamePrefix: this.fieldNamePrefix,
      rows: this._rows,
      timezone: resolveEventTimezone(),
    });

    return html`
      ${this._renderPresenceField()}
      ${fields.map((field) => this._renderHiddenInput(field.name, field.value))}
    `;
  }

  /**
   * Renders a single price window row.
   * @param {object} row Ticket type row
   * @param {object} windowRow Price window row
   * @param {boolean} isOnlyWindow Whether this is the only price window
   * @returns {import("/static/vendor/js/lit-all.v3.3.1.min.js").TemplateResult}
   */
  _renderPriceWindow(row, windowRow, isOnlyWindow) {
    return html`
      <div class="rounded-xl border border-stone-200 bg-white p-4">
        <div class="flex items-start justify-between gap-3">
          <div>
            <div class="text-sm font-medium text-stone-900">Price window</div>
            <p class="mt-1 text-xs text-stone-500">
              Leave the dates blank to keep this price available for the whole event lifecycle.
            </p>
          </div>
          <button
            type="button"
            class="inline-flex size-9 items-center justify-center rounded-full border border-stone-200 ${this
              .disabled || isOnlyWindow
              ? ""
              : "hover:bg-stone-100"}"
            title="Remove price window"
            aria-label="Remove price window"
            ?disabled=${this.disabled || isOnlyWindow}
            @click=${() => this._removePriceWindow(row._row_id, windowRow._row_id)}
          >
            <div class="svg-icon size-4 icon-trash bg-stone-600"></div>
          </button>
        </div>

        <div class="mt-4 grid gap-4 md:grid-cols-3">
          <div>
            <label class="form-label" for="ticket-price-${windowRow._row_id}"
              >Price ${this._currencyLabelSuffix()}</label
            >
            <div class="mt-2">
              <input
                id="ticket-price-${windowRow._row_id}"
                type="number"
                min="0"
                step=${this._currencyInputStep()}
                class="input-primary"
                placeholder=${this._currencyInputPlaceholder()}
                .value=${windowRow.amount}
                ?required=${!this.disabled}
                ?disabled=${this.disabled}
                @input=${(event) =>
                  this._updatePriceWindow(row._row_id, windowRow._row_id, "amount", event.target.value)}
              />
            </div>
            <p class="form-legend">Use <span class="font-semibold">0</span> for free tickets.</p>
          </div>

          <div>
            <label class="form-label" for="ticket-starts-${windowRow._row_id}">Starts at</label>
            <div class="mt-2">
              <input
                id="ticket-starts-${windowRow._row_id}"
                type="datetime-local"
                class="input-primary"
                .value=${windowRow.starts_at}
                ?disabled=${this.disabled}
                @input=${(event) =>
                  this._updatePriceWindow(row._row_id, windowRow._row_id, "starts_at", event.target.value)}
              />
            </div>
          </div>

          <div>
            <label class="form-label" for="ticket-ends-${windowRow._row_id}">Ends at</label>
            <div class="mt-2">
              <input
                id="ticket-ends-${windowRow._row_id}"
                type="datetime-local"
                class="input-primary"
                .value=${windowRow.ends_at}
                ?disabled=${this.disabled}
                @input=${(event) =>
                  this._updatePriceWindow(row._row_id, windowRow._row_id, "ends_at", event.target.value)}
              />
            </div>
          </div>
        </div>
      </div>
    `;
  }

  render() {
    return html`
      <div class="space-y-4">
        ${this._renderHiddenFields()}
        ${this._rows.length === 0
          ? html`
              <div
                class="rounded-xl border border-dashed border-stone-300 bg-white/80 p-5 text-sm text-stone-600"
              >
                Add each ticket tier here. You can mix paid and free options, set seat limits, and add more
                than one price window for early-bird or late pricing.
              </div>
            `
          : repeat(
              this._rows,
              (row) => row._row_id,
              (row) => html`
                <div class="rounded-2xl border border-stone-200 bg-white p-5 shadow-sm">
                  <div class="flex flex-col gap-4 md:flex-row md:items-start md:justify-between">
                    <div class="flex-1">
                      <div class="grid gap-4 md:grid-cols-2">
                        <div>
                          <label class="form-label" for="ticket-title-${row._row_id}">Ticket name</label>
                          <div class="mt-2">
                            <input
                              id="ticket-title-${row._row_id}"
                              type="text"
                              class="input-primary"
                              maxlength="120"
                              placeholder="General admission"
                              .value=${row.title}
                              ?required=${!this.disabled}
                              ?disabled=${this.disabled}
                              @input=${(event) =>
                                this._updateTicketType(row._row_id, "title", event.target.value)}
                            />
                          </div>
                        </div>

                        <div>
                          <label class="form-label" for="ticket-seats-${row._row_id}">Seats available</label>
                          <div class="mt-2">
                            <input
                              id="ticket-seats-${row._row_id}"
                              type="number"
                              min="0"
                              class="input-primary"
                              placeholder="100"
                              .value=${row.seats_total}
                              ?required=${!this.disabled}
                              ?disabled=${this.disabled}
                              @input=${(event) =>
                                this._updateTicketType(row._row_id, "seats_total", event.target.value)}
                            />
                          </div>
                        </div>
                      </div>

                      <div class="mt-4">
                        <label class="form-label" for="ticket-description-${row._row_id}">Description</label>
                        <div class="mt-2">
                          <textarea
                            id="ticket-description-${row._row_id}"
                            rows="3"
                            class="input-primary"
                            maxlength="300"
                            placeholder="Who this ticket is for, what it includes, or when it should be used."
                            .value=${row.description}
                            ?disabled=${this.disabled}
                            @input=${(event) =>
                              this._updateTicketType(row._row_id, "description", event.target.value)}
                          ></textarea>
                        </div>
                      </div>
                    </div>

                    <div class="flex items-center gap-3 md:ps-4">
                      <label class="inline-flex items-center cursor-pointer">
                        <input
                          type="checkbox"
                          class="sr-only peer"
                          .checked=${row.active}
                          ?disabled=${this.disabled}
                          @change=${(event) =>
                            this._updateTicketType(row._row_id, "active", event.target.checked)}
                        />
                        <div
                          class="relative h-6 w-11 rounded-full bg-stone-200 transition peer-checked:bg-primary-500 peer-checked:after:translate-x-full after:absolute after:start-[2px] after:top-[2px] after:h-5 after:w-5 after:rounded-full after:border after:border-stone-200 after:bg-white after:transition-all after:content-['']"
                        ></div>
                        <span class="ms-3 text-sm font-medium text-stone-900">Active</span>
                      </label>

                      <button
                        type="button"
                        class="inline-flex size-10 items-center justify-center rounded-full border border-stone-200 ${this
                          .disabled
                          ? ""
                          : "hover:bg-stone-100"}"
                        title="Remove ticket type"
                        aria-label="Remove ticket type"
                        ?disabled=${this.disabled}
                        @click=${() => this._removeTicketType(row._row_id)}
                      >
                        <div class="svg-icon size-4 icon-trash bg-stone-600"></div>
                      </button>
                    </div>
                  </div>

                  <div class="mt-6 space-y-4">
                    <div class="flex items-center justify-between gap-3">
                      <div>
                        <div class="text-sm font-semibold text-stone-900">Price windows</div>
                        <p class="mt-1 text-sm text-stone-600">
                          Add one window for a single flat price, or several windows for early-bird and
                          last-minute pricing.
                        </p>
                      </div>
                      <button
                        type="button"
                        class="btn-primary-outline btn-mini"
                        ?disabled=${this.disabled}
                        @click=${() => this._addPriceWindow(row._row_id)}
                      >
                        Add price window
                      </button>
                    </div>

                    ${repeat(
                      row.price_windows,
                      (windowRow) => windowRow._row_id,
                      (windowRow) => this._renderPriceWindow(row, windowRow, row.price_windows.length === 1),
                    )}
                  </div>
                </div>
              `,
            )}

        <div>
          <button
            type="button"
            class="btn-primary-outline btn-mini"
            ?disabled=${this.disabled}
            @click=${() => this._addTicketType()}
          >
            Add ticket type
          </button>
        </div>
      </div>
    `;
  }

  /**
   * Updates a price window field.
   * @param {number} rowId Ticket type row id
   * @param {number} windowRowId Price window row id
   * @param {string} fieldName Field name
   * @param {*} value Field value
   */
  _updatePriceWindow(rowId, windowRowId, fieldName, value) {
    if (this.disabled) {
      return;
    }

    this._rows = this._rows.map((row) => {
      if (row._row_id !== rowId) {
        return row;
      }

      return {
        ...row,
        price_windows: row.price_windows.map((windowRow) => {
          if (windowRow._row_id !== windowRowId) {
            return windowRow;
          }

          return {
            ...windowRow,
            [fieldName]: value,
          };
        }),
      };
    });
  }

  /**
   * Updates a ticket type row field.
   * @param {number} rowId Row id
   * @param {string} fieldName Field name
   * @param {*} value Field value
   */
  _updateTicketType(rowId, fieldName, value) {
    if (this.disabled) {
      return;
    }

    this._rows = this._rows.map((row) => {
      if (row._row_id !== rowId) {
        return row;
      }

      return {
        ...row,
        [fieldName]: value,
      };
    });
    this._notifyTicketTypesChanged();
  }
}

if (!customElements.get("ticket-types-editor")) {
  customElements.define("ticket-types-editor", TicketTypesEditor);
}
