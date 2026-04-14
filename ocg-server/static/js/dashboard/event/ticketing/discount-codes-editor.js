import { html, repeat } from "/static/vendor/js/lit-all.v3.3.1.min.js";
import { resolveEventTimezone } from "/static/js/dashboard/event/ticketing/datetime.js";
import {
  normalizeDiscountCodes,
  serializeDiscountCodes,
} from "/static/js/dashboard/event/ticketing/contract.js";
import { TicketingEditorBase } from "/static/js/dashboard/event/ticketing/base.js";
import { parseJsonAttribute } from "/static/js/dashboard/event/ticketing/shared.js";

/**
 * Discount codes editor.
 * @extends TicketingEditorBase
 */
export class DiscountCodesEditor extends TicketingEditorBase {
  static properties = {
    ...TicketingEditorBase.properties,
    discountCodes: { type: Array, attribute: "discount-codes" },

    _rows: { state: true },
  };

  constructor() {
    super();
    this.fieldNamePrefix = "discount_codes";
    this.presenceFieldName = "discount_codes_present";
    this.discountCodes = [];
    this._rows = [];
  }

  connectedCallback() {
    super.connectedCallback();
    this._applyDiscountCodes(this.discountCodes);
  }

  updated(changedProperties) {
    super.updated(changedProperties);

    if (changedProperties.has("discountCodes")) {
      this._applyDiscountCodes(this.discountCodes);
    }
  }

  /**
   * Replaces discount codes from external scripts.
   * @param {Array<object>} discountCodes Discount codes payload
   */
  setDiscountCodes(discountCodes) {
    this.discountCodes = discountCodes;
    this._applyDiscountCodes(discountCodes);
  }

  /**
   * Adds a discount code row.
   */
  _addDiscountCode() {
    if (this.disabled) {
      return;
    }

    this._rows = [...this._rows, this._createEmptyDiscountCode()];
  }

  /**
   * Applies initial discount code payload.
   * @param {*} discountCodes Raw payload
   */
  _applyDiscountCodes(discountCodes) {
    const parsedDiscountCodes = parseJsonAttribute(discountCodes, []);
    this._rows = normalizeDiscountCodes({
      currencyCode: this._currencyCode(),
      discountCodes: parsedDiscountCodes,
      nextRowId: () => this._nextRowId(),
      timezone: resolveEventTimezone(),
    });
  }

  /**
   * Creates an empty discount code row.
   * @returns {object}
   */
  _createEmptyDiscountCode() {
    return {
      _row_id: this._nextRowId(),
      active: true,
      amount: "",
      available: "",
      available_dirty: false,
      code: "",
      ends_at: "",
      event_discount_code_id: "",
      kind: "percentage",
      percentage: "",
      starts_at: "",
      title: "",
      total_available: "",
    };
  }

  /**
   * Removes a discount code row.
   * @param {number} rowId Discount code row id
   */
  _removeDiscountCode(rowId) {
    if (this.disabled) {
      return;
    }

    this._rows = this._rows.filter((row) => row._row_id !== rowId);
  }

  /**
   * Renders hidden nested inputs for the current discount codes.
   * @returns {import("/static/vendor/js/lit-all.v3.3.1.min.js").TemplateResult|string}
   */
  _renderHiddenFields() {
    if (this.disabled) {
      return "";
    }

    const fields = serializeDiscountCodes({
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
   * Renders the value fields for a discount kind.
   * @param {object} row Discount row
   * @returns {import("/static/vendor/js/lit-all.v3.3.1.min.js").TemplateResult}
   */
  _renderDiscountValueFields(row) {
    if (row.kind === "fixed_amount") {
      return html`
        <div>
          <label class="form-label" for="discount-amount-${row._row_id}"
            >Amount ${this._currencyLabelSuffix()}</label
          >
          <div class="mt-2">
            <input
              id="discount-amount-${row._row_id}"
              type="number"
              min="0"
              step=${this._currencyInputStep()}
              class="input-primary"
              placeholder=${this._currencyInputPlaceholder()}
              .value=${row.amount}
              ?required=${!this.disabled}
              ?disabled=${this.disabled}
              @input=${(event) => this._updateDiscountCode(row._row_id, "amount", event.target.value)}
            />
          </div>
          <p class="form-legend">
            Use the same currency as the event, for example
            <span class="font-semibold">${this._currencyInputPlaceholder()}</span>.
          </p>
        </div>
      `;
    }

    return html`
      <div>
        <label class="form-label" for="discount-percentage-${row._row_id}">Percentage off</label>
        <div class="mt-2">
          <input
            id="discount-percentage-${row._row_id}"
            type="number"
            min="1"
            max="100"
            class="input-primary"
            placeholder="20"
            .value=${row.percentage}
            ?required=${!this.disabled}
            ?disabled=${this.disabled}
            @input=${(event) => this._updateDiscountCode(row._row_id, "percentage", event.target.value)}
          />
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
                Add optional discount codes for campaigns like early supporters, member perks, or sponsor
                invites.
              </div>
            `
          : repeat(
              this._rows,
              (row) => row._row_id,
              (row) => html`
                <div class="rounded-2xl border border-stone-200 bg-white p-5 shadow-sm">
                  <div class="flex flex-col gap-4 md:flex-row md:items-start md:justify-between">
                    <div class="grid flex-1 gap-4 md:grid-cols-2">
                      <div>
                        <label class="form-label" for="discount-title-${row._row_id}">Internal title</label>
                        <div class="mt-2">
                          <input
                            id="discount-title-${row._row_id}"
                            type="text"
                            class="input-primary"
                            maxlength="120"
                            placeholder="Early supporter"
                            .value=${row.title}
                            ?required=${!this.disabled}
                            ?disabled=${this.disabled}
                            @input=${(event) =>
                              this._updateDiscountCode(row._row_id, "title", event.target.value)}
                          />
                        </div>
                      </div>

                      <div>
                        <label class="form-label" for="discount-code-${row._row_id}">Code</label>
                        <div class="mt-2">
                          <input
                            id="discount-code-${row._row_id}"
                            type="text"
                            class="input-primary uppercase"
                            maxlength="40"
                            placeholder="EARLY20"
                            .value=${row.code}
                            ?required=${!this.disabled}
                            ?disabled=${this.disabled}
                            @input=${(event) =>
                              this._updateDiscountCode(row._row_id, "code", event.target.value)}
                          />
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
                            this._updateDiscountCode(row._row_id, "active", event.target.checked)}
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
                        title="Remove discount code"
                        aria-label="Remove discount code"
                        ?disabled=${this.disabled}
                        @click=${() => this._removeDiscountCode(row._row_id)}
                      >
                        <div class="svg-icon size-4 icon-trash bg-stone-600"></div>
                      </button>
                    </div>
                  </div>

                  <div class="mt-6 grid gap-4 md:grid-cols-2">
                    <div>
                      <label class="form-label" for="discount-kind-${row._row_id}">Discount type</label>
                      <div class="mt-2">
                        <select
                          id="discount-kind-${row._row_id}"
                          class="input-primary"
                          .value=${row.kind}
                          ?disabled=${this.disabled}
                          @change=${(event) =>
                            this._updateDiscountCode(row._row_id, "kind", event.target.value)}
                        >
                          <option value="percentage">Percentage</option>
                          <option value="fixed_amount">Fixed amount</option>
                        </select>
                      </div>
                    </div>

                    ${this._renderDiscountValueFields(row)}

                    <div>
                      <label class="form-label" for="discount-total-${row._row_id}"
                        >Maximum redemptions</label
                      >
                      <div class="mt-2">
                        <input
                          id="discount-total-${row._row_id}"
                          type="number"
                          min="0"
                          class="input-primary"
                          placeholder="50"
                          .value=${row.total_available}
                          ?disabled=${this.disabled}
                          @input=${(event) =>
                            this._updateDiscountCode(row._row_id, "total_available", event.target.value)}
                        />
                      </div>
                    </div>

                    <div>
                      <label class="form-label" for="discount-available-${row._row_id}">Uses remaining</label>
                      <div class="mt-2">
                        <input
                          id="discount-available-${row._row_id}"
                          type="number"
                          min="0"
                          class="input-primary"
                          placeholder="Leave blank unless you need a manual override"
                          .value=${row.available}
                          ?disabled=${this.disabled}
                          @input=${(event) =>
                            this._updateDiscountCode(row._row_id, "available", event.target.value)}
                        />
                      </div>
                    </div>

                    <div>
                      <label class="form-label" for="discount-starts-${row._row_id}">Starts at</label>
                      <div class="mt-2">
                        <input
                          id="discount-starts-${row._row_id}"
                          type="datetime-local"
                          class="input-primary"
                          .value=${row.starts_at}
                          ?disabled=${this.disabled}
                          @input=${(event) =>
                            this._updateDiscountCode(row._row_id, "starts_at", event.target.value)}
                        />
                      </div>
                    </div>

                    <div>
                      <label class="form-label" for="discount-ends-${row._row_id}">Ends at</label>
                      <div class="mt-2">
                        <input
                          id="discount-ends-${row._row_id}"
                          type="datetime-local"
                          class="input-primary"
                          .value=${row.ends_at}
                          ?disabled=${this.disabled}
                          @input=${(event) =>
                            this._updateDiscountCode(row._row_id, "ends_at", event.target.value)}
                        />
                      </div>
                    </div>
                  </div>
                </div>
              `,
            )}

        <div>
          <button
            type="button"
            class="btn-primary-outline btn-mini"
            ?disabled=${this.disabled}
            @click=${() => this._addDiscountCode()}
          >
            Add discount code
          </button>
        </div>
      </div>
    `;
  }

  /**
   * Updates a discount code row field.
   * @param {number} rowId Row id
   * @param {string} fieldName Field name
   * @param {*} value Field value
   */
  _updateDiscountCode(rowId, fieldName, value) {
    if (this.disabled) {
      return;
    }

    const normalizedValue = fieldName === "code" ? String(value || "").toUpperCase() : value;
    this._rows = this._rows.map((row) => {
      if (row._row_id !== rowId) {
        return row;
      }

      return {
        ...row,
        ...(fieldName === "available" ? { available_dirty: true } : {}),
        [fieldName]: normalizedValue,
      };
    });
  }
}

if (!customElements.get("discount-codes-editor")) {
  customElements.define("discount-codes-editor", DiscountCodesEditor);
}
