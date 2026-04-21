import { html, repeat } from "/static/vendor/js/lit-all.v3.3.1.min.js";
import { lockBodyScroll, unlockBodyScroll } from "/static/js/common/common.js";
import { TicketingEditorBase } from "/static/js/dashboard/event/ticketing/editor-base.js";
import { normalizeTicketTypes, serializeTicketTypes } from "/static/js/dashboard/event/ticketing/contract.js";
import { parseJsonAttribute } from "/static/js/dashboard/event/ticketing/shared.js";

/**
 * Ticket types editor component.
 * @extends TicketingEditorBase
 */
class TicketTypesEditor extends TicketingEditorBase {
  static properties = {
    ticketTypes: {
      type: Array,
      attribute: "ticket-types",
      converter: {
        fromAttribute(value) {
          return parseJsonAttribute(value, []);
        },
      },
    },
  };

  constructor() {
    super();
    this.fieldNamePrefix = "ticket_types";
    this.presenceFieldName = "ticket_types_present";
    this.ticketTypes = [];
  }

  /**
   * Resolves the reactive property that stores editor rows from attributes.
   * @returns {string}
   */
  get _editorDataProperty() {
    return "ticketTypes";
  }

  /**
   * Resolves the shared add button id for this editor.
   * @returns {string}
   */
  get _addButtonId() {
    return "add-ticket-type-button";
  }

  /**
   * Returns whether the editor currently has any configured ticket rows.
   * @returns {boolean}
   */
  hasConfiguredTicketTypes() {
    return this._rows.length > 0;
  }

  /**
   * Replaces serialized ticket rows before normalization runs.
   * @param {Array<object>} ticketTypes Serialized ticket rows
   * @returns {void}
   */
  setTicketTypes(ticketTypes) {
    this.ticketTypes = Array.isArray(ticketTypes) ? ticketTypes : [];
  }

  /**
   * Sums configured seats across all normalized ticket rows.
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
   * Applies serialized editor data to the normalized row collection.
   * @param {Array<object>} ticketTypes Serialized rows
   * @returns {void}
   */
  _applyEditorData(ticketTypes) {
    this._applyTicketTypes(ticketTypes);
  }

  /**
   * Broadcasts editor state changes to parent page listeners.
   * @param {object} detail Event payload
   * @returns {void}
   */
  _emitChange(detail) {
    this.dispatchEvent(
      new CustomEvent("ticket-types-changed", {
        bubbles: true,
        composed: true,
        detail,
      }),
    );
  }

  /**
   * Emits whether the editor currently contains ticket rows.
   * @returns {void}
   */
  _notifyTicketTypesChanged() {
    this._emitChange({ hasTicketTypes: this.hasConfiguredTicketTypes() });
  }

  /**
   * Normalizes serialized rows and guarantees at least one draft price window.
   * @param {Array<object>} ticketTypes Serialized ticket rows
   * @returns {void}
   */
  _applyTicketTypes(ticketTypes) {
    const rows = normalizeTicketTypes({
      currencyCode: this._currencyCode(),
      nextRowId: () => this._nextRowId(),
      ticketTypes,
      timezone: this._timezone(),
    });

    this._rows = rows.map((row) => ({
      ...row,
      price_windows: row.price_windows.length > 0 ? row.price_windows : [this._createEmptyPriceWindow()],
    }));
    this._notifyTicketTypesChanged();
  }

  /**
   * Builds an empty draft price window row.
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
   * Builds an empty draft ticket type with one price window.
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
   * Clones a ticket row so modal edits do not mutate the table state directly.
   * @param {object} row Ticket row to clone
   * @returns {object}
   */
  _cloneTicketType(row) {
    return {
      ...row,
      price_windows: row.price_windows.map((windowRow) => ({ ...windowRow })),
    };
  }

  /**
   * Opens the shared editor modal flow.
   * @returns {void}
   */
  _openEditorModal() {
    this._openTicketModal();
  }

  /**
   * Closes the shared editor modal flow.
   * @returns {void}
   */
  _closeEditorModal() {
    this._closeTicketModal();
  }

  /**
   * Opens the modal for a new or existing ticket type.
   * @param {number|null} [rowId=null] Existing row id to edit
   * @returns {void}
   */
  _openTicketModal(rowId = null) {
    if (this.disabled) {
      return;
    }

    const existingRow = rowId === null ? null : this._rows.find((row) => row._row_id === rowId);
    this._isNewRow = !existingRow;
    this._editingRowId = existingRow?._row_id ?? null;
    this._draftRow = existingRow ? this._cloneTicketType(existingRow) : this._createEmptyTicketType();
    this._isModalOpen = true;
    lockBodyScroll();
  }

  /**
   * Resets modal draft state and restores body scrolling.
   * @returns {void}
   */
  _closeTicketModal() {
    if (!this._isModalOpen) {
      return;
    }

    this._draftRow = null;
    this._editingRowId = null;
    this._isModalOpen = false;
    this._isNewRow = false;
    unlockBodyScroll();
  }

  /**
   * Appends a new empty price window to the draft ticket.
   * @returns {void}
   */
  _addDraftPriceWindow() {
    if (this.disabled || !this._draftRow) {
      return;
    }

    this._draftRow = {
      ...this._draftRow,
      price_windows: [...this._draftRow.price_windows, this._createEmptyPriceWindow()],
    };
  }

  /**
   * Removes a draft price window while keeping one row available.
   * @param {number} windowRowId Draft window row id
   * @returns {void}
   */
  _removeDraftPriceWindow(windowRowId) {
    if (this.disabled || !this._draftRow) {
      return;
    }

    const remainingWindows = this._draftRow.price_windows.filter(
      (windowRow) => windowRow._row_id !== windowRowId,
    );
    this._draftRow = {
      ...this._draftRow,
      price_windows: remainingWindows.length > 0 ? remainingWindows : [this._createEmptyPriceWindow()],
    };
  }

  /**
   * Removes a persisted ticket row from the editor table.
   * @param {number} rowId Ticket row id
   * @returns {void}
   */
  _removeTicketType(rowId) {
    if (this.disabled) {
      return;
    }

    this._rows = this._rows.filter((row) => row._row_id !== rowId);
    this._notifyTicketTypesChanged();
  }

  /**
   * Validates and persists the current modal draft into the editor rows.
   * @returns {void}
   */
  _saveTicketType() {
    if (!this._draftRow) {
      return;
    }

    const invalidField = Array.from(this.querySelectorAll("[data-ticket-modal-field]")).find(
      (field) => typeof field.checkValidity === "function" && !field.checkValidity(),
    );

    if (invalidField && typeof invalidField.reportValidity === "function") {
      invalidField.reportValidity();
      return;
    }

    const rowToSave = {
      ...this._draftRow,
      description: String(this._draftRow.description || ""),
      seats_total: String(this._draftRow.seats_total || ""),
      title: String(this._draftRow.title || "").trim(),
    };

    if (!rowToSave.title) {
      return;
    }

    if (this._isNewRow) {
      this._rows = [...this._rows, rowToSave];
    } else {
      this._rows = this._rows.map((row) => (row._row_id === this._editingRowId ? rowToSave : row));
    }

    this._notifyTicketTypesChanged();
    this._closeTicketModal();
  }

  /**
   * Updates a top-level field on the draft ticket row.
   * @param {string} fieldName Draft field name
   * @param {*} value Next field value
   * @returns {void}
   */
  _updateDraftTicketType(fieldName, value) {
    if (this.disabled || !this._draftRow) {
      return;
    }

    this._draftRow = {
      ...this._draftRow,
      [fieldName]: value,
    };
  }

  /**
   * Updates a nested draft price window field by row id.
   * @param {number} windowRowId Draft window row id
   * @param {string} fieldName Draft field name
   * @param {*} value Next field value
   * @returns {void}
   */
  _updateDraftPriceWindow(windowRowId, fieldName, value) {
    if (this.disabled || !this._draftRow) {
      return;
    }

    this._draftRow = {
      ...this._draftRow,
      price_windows: this._draftRow.price_windows.map((windowRow) =>
        windowRow._row_id === windowRowId
          ? {
              ...windowRow,
              [fieldName]: value,
            }
          : windowRow,
      ),
    };
  }

  /**
   * Returns the display title for a ticket row.
   * @param {object} row Ticket row
   * @returns {string}
   */
  _ticketTitle(row) {
    return row.title?.trim() || "Untitled ticket";
  }

  /**
   * Serializes normalized rows into hidden form fields.
   * @returns {Array<{name: string, value: string}>}
   */
  _serializedFields() {
    const fields = serializeTicketTypes({
      currencyCode: this._currencyCode(),
      fieldNamePrefix: this.fieldNamePrefix,
      rows: this._rows,
      timezone: this._timezone(),
    });

    return [{ name: this.presenceFieldName, value: "true" }, ...fields];
  }

  /**
   * Renders the ticket type table body rows.
   * @returns {*}
   */
  _renderRows() {
    return repeat(
      this._rows,
      (row) => row._row_id,
      (row) => html`
        <tr class="odd:bg-white even:bg-stone-50/50 border-b border-stone-200 align-middle">
          <td class="px-3 xl:px-5 py-4 min-w-[180px] xl:min-w-[220px]">
            <div class="font-medium text-stone-900">${this._ticketTitle(row)}</div>
          </td>
          <td class="px-3 xl:px-5 py-4 whitespace-nowrap text-stone-900">${row.seats_total || "—"}</td>
          <td class="px-3 xl:px-5 py-4 whitespace-nowrap">
            ${row.active
              ? html`<span
                  class="custom-badge shrink-0 border-green-800 bg-green-100 px-2.5 py-0.5 text-green-800"
                >
                  Active
                </span>`
              : html`<span
                  class="custom-badge shrink-0 border-stone-500 bg-stone-100 px-2.5 py-0.5 text-stone-700"
                >
                  Inactive
                </span>`}
          </td>
          <td class="px-3 xl:px-5 py-4">
            <div class="flex items-center justify-start gap-1 xl:justify-end">
              <button
                type="button"
                class="rounded-full p-2 transition-colors ${this.disabled
                  ? "opacity-60 cursor-not-allowed"
                  : "hover:bg-stone-100"}"
                data-ticketing-action="edit-ticket"
                data-row-id=${String(row._row_id)}
                title="Edit"
                ?disabled=${this.disabled}
                @click=${() => this._openTicketModal(row._row_id)}
              >
                <div class="svg-icon size-4 icon-pencil bg-stone-600"></div>
              </button>
              <button
                type="button"
                class="rounded-full p-2 transition-colors ${this.disabled
                  ? "opacity-60 cursor-not-allowed"
                  : "hover:bg-stone-100"}"
                data-ticketing-action="delete-ticket"
                data-row-id=${String(row._row_id)}
                title="Delete"
                ?disabled=${this.disabled}
                @click=${() => this._removeTicketType(row._row_id)}
              >
                <div class="svg-icon size-4 icon-trash bg-stone-600"></div>
              </button>
            </div>
          </td>
        </tr>
      `,
    );
  }

  /**
   * Renders the draft price window editor rows inside the modal.
   * @returns {*}
   */
  _renderDraftPriceWindows() {
    if (!this._draftRow) {
      return null;
    }

    return repeat(
      this._draftRow.price_windows,
      (windowRow) => windowRow._row_id,
      (windowRow) => {
        const isOnlyWindow = this._draftRow.price_windows.length === 1;
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
                data-ticketing-action="remove-price-window"
                data-window-row-id=${String(windowRow._row_id)}
                ?disabled=${this.disabled || isOnlyWindow}
                @click=${() => this._removeDraftPriceWindow(windowRow._row_id)}
              >
                <div class="svg-icon size-4 icon-trash bg-stone-600"></div>
              </button>
            </div>

            <div class="mt-4 grid gap-4 md:grid-cols-3">
              <div>
                <label class="form-label" for=${`ticket-price-${windowRow._row_id}`}>
                  Price ${this._currencyLabelSuffix()} <span class="asterisk">*</span>
                </label>
                <div class="mt-2">
                  <input
                    id=${`ticket-price-${windowRow._row_id}`}
                    data-ticket-modal-field
                    data-ticket-window-field="amount"
                    data-window-row-id=${String(windowRow._row_id)}
                    type="number"
                    min="0"
                    step=${this._currencyInputStep()}
                    class="input-primary"
                    placeholder=${this._currencyInputPlaceholder()}
                    .value=${windowRow.amount}
                    ?disabled=${!this._isModalOpen}
                    required
                    @input=${(event) =>
                      this._updateDraftPriceWindow(windowRow._row_id, "amount", event.target.value)}
                  />
                </div>
                <p class="form-legend">Use <span class="font-semibold">0</span> for free tickets.</p>
              </div>

              <div>
                <label class="form-label" for=${`ticket-starts-${windowRow._row_id}`}>Starts at</label>
                <div class="mt-2">
                  <input
                    id=${`ticket-starts-${windowRow._row_id}`}
                    data-ticket-window-field="starts_at"
                    data-window-row-id=${String(windowRow._row_id)}
                    type="datetime-local"
                    class="input-primary"
                    .value=${windowRow.starts_at}
                    ?disabled=${!this._isModalOpen}
                    @input=${(event) =>
                      this._updateDraftPriceWindow(windowRow._row_id, "starts_at", event.target.value)}
                  />
                </div>
              </div>

              <div>
                <label class="form-label" for=${`ticket-ends-${windowRow._row_id}`}>Ends at</label>
                <div class="mt-2">
                  <input
                    id=${`ticket-ends-${windowRow._row_id}`}
                    data-ticket-window-field="ends_at"
                    data-window-row-id=${String(windowRow._row_id)}
                    type="datetime-local"
                    class="input-primary"
                    .value=${windowRow.ends_at}
                    ?disabled=${!this._isModalOpen}
                    @input=${(event) =>
                      this._updateDraftPriceWindow(windowRow._row_id, "ends_at", event.target.value)}
                  />
                </div>
              </div>
            </div>
          </div>
        `;
      },
    );
  }

  /**
   * Renders hidden fields that keep the outer form payload in sync.
   * @returns {*}
   */
  _renderHiddenFields() {
    if (this.disabled) {
      return null;
    }

    return repeat(
      this._serializedFields(),
      (field) => `${field.name}:${field.value}`,
      (field) => html`<input type="hidden" name=${field.name} value=${field.value} />`,
    );
  }

  render() {
    return html`
      ${this._renderHiddenFields()}

      <div data-ticketing-role="table-wrapper" class="relative overflow-x-auto xl:overflow-visible">
        <table class="table-auto w-full text-xs lg:text-sm text-left text-stone-500">
          <thead class="text-xs text-stone-700 uppercase bg-stone-100 border-b border-stone-200">
            <tr>
              <th scope="col" class="px-3 xl:px-5 py-3">Name</th>
              <th scope="col" class="px-3 xl:px-5 py-3">Seats</th>
              <th scope="col" class="px-3 xl:px-5 py-3">Status</th>
              <th scope="col" class="px-3 xl:px-5 py-3 text-right">Actions</th>
            </tr>
          </thead>
          <tbody data-ticketing-role="empty-state" class=${this._rows.length > 0 ? "hidden" : ""}>
            <tr class="bg-white border-b border-stone-200">
              <td class="px-8 py-12 text-center text-stone-500" colspan="4">
                No ticket tiers yet. Configured ticket tiers will appear here.
              </td>
            </tr>
          </tbody>
          <tbody data-ticketing-role="table-body">
            ${this._renderRows()}
          </tbody>
        </table>
      </div>

      <div
        data-ticketing-role="ticket-modal"
        class="fixed inset-0 z-[1000] ${this._isModalOpen
          ? "flex"
          : "hidden"} items-center justify-center overflow-y-auto overflow-x-hidden"
        role="dialog"
        aria-modal="true"
        aria-labelledby="ticket-type-modal-title"
        data-pending-changes-ignore
      >
        <div
          class="absolute inset-0 bg-stone-950 opacity-35"
          data-ticketing-action="close-modal"
          @click=${() => this._closeTicketModal()}
        ></div>
        <div class="modal-panel max-w-5xl p-4">
          <div class="modal-card rounded-2xl">
            <div class="flex items-center justify-between border-b border-stone-200 p-5 shrink-0">
              <h3
                id="ticket-type-modal-title"
                data-ticketing-role="modal-title"
                class="text-xl font-semibold text-stone-900"
              >
                ${this._isNewRow ? "Add ticket type" : "Edit ticket type"}
              </h3>
              <button
                type="button"
                data-ticketing-action="close-modal"
                class="group inline-flex h-8 w-8 items-center justify-center rounded-lg bg-transparent text-sm text-stone-400 transition-colors hover:bg-stone-100"
                ?disabled=${!this._isModalOpen}
                @click=${() => this._closeTicketModal()}
              >
                <div
                  class="svg-icon h-4 w-4 bg-stone-400 transition-colors group-hover:bg-stone-600 icon-close"
                ></div>
                <span class="sr-only">Close modal</span>
              </button>
            </div>

            <div class="modal-body flex-1 space-y-6 p-6">
              <div class="grid gap-4 md:grid-cols-2">
                <div>
                  <label class="form-label" for="ticket-title-draft">
                    Ticket name <span class="asterisk">*</span>
                  </label>
                  <div class="mt-2">
                    <input
                      id="ticket-title-draft"
                      data-ticket-modal-field
                      data-ticket-field="title"
                      type="text"
                      class="input-primary"
                      maxlength="120"
                      placeholder="General admission"
                      .value=${this._draftRow?.title || ""}
                      ?disabled=${!this._isModalOpen}
                      required
                      @input=${(event) => this._updateDraftTicketType("title", event.target.value)}
                    />
                  </div>
                </div>

                <div>
                  <label class="form-label" for="ticket-seats-draft">
                    Seats available <span class="asterisk">*</span>
                  </label>
                  <div class="mt-2">
                    <input
                      id="ticket-seats-draft"
                      data-ticket-modal-field
                      data-ticket-field="seats_total"
                      type="number"
                      min="0"
                      class="input-primary"
                      placeholder="100"
                      .value=${this._draftRow?.seats_total || ""}
                      ?disabled=${!this._isModalOpen}
                      required
                      @input=${(event) => this._updateDraftTicketType("seats_total", event.target.value)}
                    />
                  </div>
                </div>
              </div>

              <div>
                <label class="form-label" for="ticket-description-draft">Description</label>
                <div class="mt-2">
                  <textarea
                    id="ticket-description-draft"
                    data-ticket-field="description"
                    rows="3"
                    class="input-primary"
                    maxlength="300"
                    placeholder="Who this ticket is for, what it includes, or when it should be used."
                    .value=${this._draftRow?.description || ""}
                    ?disabled=${!this._isModalOpen}
                    @input=${(event) => this._updateDraftTicketType("description", event.target.value)}
                  ></textarea>
                </div>
              </div>

              <div>
                <label class="inline-flex cursor-pointer items-center">
                  <input
                    type="checkbox"
                    class="sr-only peer"
                    data-ticket-field="active"
                    .checked=${this._draftRow?.active ?? true}
                    ?disabled=${!this._isModalOpen}
                    @change=${(event) => this._updateDraftTicketType("active", event.target.checked)}
                  />
                  <div
                    class="relative h-6 w-11 rounded-full bg-stone-200 transition peer-checked:bg-primary-500 peer-checked:after:translate-x-full after:absolute after:start-[2px] after:top-[2px] after:h-5 after:w-5 after:rounded-full after:border after:border-stone-200 after:bg-white after:transition-all after:content-['']"
                  ></div>
                  <span class="ms-3 text-sm font-medium text-stone-900">Active</span>
                </label>
              </div>

              <div class="space-y-4">
                <div class="flex items-center justify-between gap-3">
                  <div>
                    <div class="text-sm font-semibold text-stone-900">Price windows</div>
                    <p class="mt-1 text-sm text-stone-600">
                      Add one window for a single flat price, or several windows for early-bird and late
                      pricing.
                    </p>
                  </div>
                  <button
                    type="button"
                    data-ticketing-action="add-price-window"
                    class="btn-primary-outline btn-mini"
                    ?disabled=${!this._isModalOpen}
                    @click=${() => this._addDraftPriceWindow()}
                  >
                    Add price window
                  </button>
                </div>

                <div data-ticketing-role="price-windows-list" class="space-y-4">
                  ${this._renderDraftPriceWindows()}
                </div>
              </div>
            </div>

            <div class="flex items-center justify-end gap-3 border-t border-stone-200 p-5 shrink-0">
              <button
                type="button"
                data-ticketing-action="close-modal"
                class="btn-secondary"
                ?disabled=${!this._isModalOpen}
                @click=${() => this._closeTicketModal()}
              >
                Cancel
              </button>
              <button
                type="button"
                data-ticketing-action="save-ticket"
                class="btn-primary"
                ?disabled=${!this._isModalOpen}
                @click=${() => this._saveTicketType()}
              >
                <span data-ticketing-role="save-label">
                  ${this._isNewRow ? "Add ticket type" : "Save changes"}
                </span>
              </button>
            </div>
          </div>
        </div>
      </div>
    `;
  }
}

if (!customElements.get("ticket-types-editor")) {
  customElements.define("ticket-types-editor", TicketTypesEditor);
}
