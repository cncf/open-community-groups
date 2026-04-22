import { html, repeat } from "/static/vendor/js/lit-all.v3.3.1.min.js";
import {
  lockBodyScroll,
  toDateTimeLocalInTimezone,
  toUtcIsoInTimezone,
  unlockBodyScroll,
} from "/static/js/common/common.js";
import { parseJsonAttribute, toBoolean, toTrimmedString } from "/static/js/common/utils.js";
import {
  formatMinorUnitsForInput,
  parseCurrencyInputToMinorUnits,
} from "/static/js/dashboard/event/ticketing/currency.js";
import { TicketingEditorBase } from "/static/js/dashboard/event/ticketing/editor-base.js";

/**
 * Normalizes incoming discount codes into editor rows.
 * @param {object} config Normalization config
 * @returns {Array<object>}
 */
const normalizeDiscountCodes = ({ currencyCode, discountCodes, nextRowId, timezone }) => {
  if (!Array.isArray(discountCodes) || discountCodes.length === 0) {
    return [];
  }

  return discountCodes
    .map((discountCode) => ({
      _row_id: nextRowId(),
      active: toBoolean(discountCode?.active, true),
      amount:
        discountCode?.amount_minor === null || discountCode?.amount_minor === undefined
          ? ""
          : formatMinorUnitsForInput(discountCode.amount_minor, currencyCode),
      available:
        discountCode?.available === null || discountCode?.available === undefined
          ? ""
          : String(discountCode.available),
      available_dirty: toBoolean(discountCode?.available_dirty, false),
      available_override_active: toBoolean(
        discountCode?.available_override_active,
        discountCode?.available !== null && discountCode?.available !== undefined,
      ),
      code: toTrimmedString(discountCode?.code).toUpperCase(),
      ends_at: toDateTimeLocalInTimezone(discountCode?.ends_at || "", timezone),
      event_discount_code_id: toTrimmedString(discountCode?.event_discount_code_id),
      kind: toTrimmedString(discountCode?.kind) || "percentage",
      percentage:
        discountCode?.percentage === null || discountCode?.percentage === undefined
          ? ""
          : String(discountCode.percentage),
      starts_at: toDateTimeLocalInTimezone(discountCode?.starts_at || "", timezone),
      title: String(discountCode?.title || ""),
      total_available:
        discountCode?.total_available === null || discountCode?.total_available === undefined
          ? ""
          : String(discountCode.total_available),
    }))
    .sort((left, right) => left.title.trim().toLowerCase().localeCompare(right.title.trim().toLowerCase()));
};

/**
 * Builds hidden input entries for discount codes.
 * @param {object} config Serialization config
 * @returns {Array<{name: string, value: string}>}
 */
const serializeDiscountCodes = ({ currencyCode, fieldNamePrefix, rows, timezone }) =>
  rows.flatMap((row, index) => {
    const rowPrefix = `${fieldNamePrefix}[${index}]`;
    const amountMinor = parseCurrencyInputToMinorUnits(row.amount, currencyCode);
    const available = Number.parseInt(row.available, 10);
    const availableOverrideActive = !!row.available_override_active;
    const discountCodeId = toTrimmedString(row.event_discount_code_id);
    const endsAt = toUtcIsoInTimezone(row.ends_at, timezone);
    const percentage = Number.parseInt(row.percentage, 10);
    const startsAt = toUtcIsoInTimezone(row.starts_at, timezone);
    const totalAvailable = Number.parseInt(row.total_available, 10);
    const fields = [
      { name: `${rowPrefix}[active]`, value: row.active ? "true" : "false" },
      {
        name: `${rowPrefix}[available_override_active]`,
        value: availableOverrideActive ? "true" : "false",
      },
      { name: `${rowPrefix}[code]`, value: row.code.trim().toUpperCase() },
      { name: `${rowPrefix}[kind]`, value: row.kind },
      { name: `${rowPrefix}[title]`, value: row.title.trim() },
    ];

    if (row.available_dirty && availableOverrideActive && Number.isFinite(available)) {
      fields.push({ name: `${rowPrefix}[available]`, value: String(available) });
    }

    if (row.kind === "fixed_amount" && amountMinor !== null) {
      fields.push({ name: `${rowPrefix}[amount_minor]`, value: String(amountMinor) });
    }

    if (endsAt) {
      fields.push({ name: `${rowPrefix}[ends_at]`, value: endsAt });
    }

    if (discountCodeId) {
      fields.push({ name: `${rowPrefix}[event_discount_code_id]`, value: discountCodeId });
    }

    if (row.kind === "percentage" && Number.isFinite(percentage)) {
      fields.push({ name: `${rowPrefix}[percentage]`, value: String(percentage) });
    }

    if (startsAt) {
      fields.push({ name: `${rowPrefix}[starts_at]`, value: startsAt });
    }

    if (Number.isFinite(totalAvailable)) {
      fields.push({
        name: `${rowPrefix}[total_available]`,
        value: String(totalAvailable),
      });
    }

    return fields;
  });

/**
 * Discount codes editor component.
 * @extends TicketingEditorBase
 */
class DiscountCodesEditor extends TicketingEditorBase {
  static properties = {
    discountCodes: {
      type: Array,
      attribute: "discount-codes",
      converter: {
        fromAttribute(value) {
          return parseJsonAttribute(value, []);
        },
      },
    },
  };

  constructor() {
    super();
    this.fieldNamePrefix = "discount_codes";
    this.presenceFieldName = "discount_codes_present";
    this.discountCodes = [];
  }

  /**
   * Resolves the reactive property that stores editor rows from attributes.
   * @returns {string}
   */
  get _editorDataProperty() {
    return "discountCodes";
  }

  /**
   * Resolves the shared add button id for this editor.
   * @returns {string}
   */
  get _addButtonId() {
    return "add-discount-code-button";
  }

  /**
   * Replaces serialized discount rows before normalization runs.
   * @param {Array<object>} discountCodes Serialized discount rows
   * @returns {void}
   */
  setDiscountCodes(discountCodes) {
    this.discountCodes = Array.isArray(discountCodes) ? discountCodes : [];
  }

  /**
   * Applies serialized editor data to the normalized row collection.
   * @param {Array<object>} discountCodes Serialized rows
   * @returns {void}
   */
  _applyEditorData(discountCodes) {
    this._applyDiscountCodes(discountCodes);
  }

  /**
   * Normalizes serialized rows into the reactive editor collection.
   * @param {Array<object>} discountCodes Serialized discount rows
   * @returns {void}
   */
  _applyDiscountCodes(discountCodes) {
    this._rows = normalizeDiscountCodes({
      currencyCode: this._currencyCode(),
      discountCodes,
      nextRowId: () => this._nextRowId(),
      timezone: this._timezone(),
    });
  }

  /**
   * Builds an empty discount code draft row.
   * @returns {object}
   */
  _createEmptyDiscountCode() {
    return {
      _row_id: this._nextRowId(),
      active: true,
      amount: "",
      available: "",
      available_dirty: false,
      available_override_active: false,
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
   * Clones a discount row so modal edits stay isolated.
   * @param {object} row Discount row to clone
   * @returns {object}
   */
  _cloneDiscountCode(row) {
    return { ...row };
  }

  /**
   * Opens the shared editor modal flow.
   * @returns {void}
   */
  _openEditorModal() {
    this._openDiscountModal();
  }

  /**
   * Closes the shared editor modal flow.
   * @returns {void}
   */
  _closeEditorModal() {
    this._closeDiscountModal();
  }

  /**
   * Opens the modal for a new or existing discount code.
   * @param {number|null} [rowId=null] Existing row id to edit
   * @returns {void}
   */
  _openDiscountModal(rowId = null) {
    if (this.disabled) {
      return;
    }

    const existingRow = rowId === null ? null : this._rows.find((row) => row._row_id === rowId);
    this._isNewRow = !existingRow;
    this._editingRowId = existingRow?._row_id ?? null;
    this._draftRow = existingRow ? this._cloneDiscountCode(existingRow) : this._createEmptyDiscountCode();
    this._isModalOpen = true;
    lockBodyScroll();
  }

  /**
   * Resets modal draft state and restores body scrolling.
   * @returns {void}
   */
  _closeDiscountModal() {
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
   * Removes a persisted discount row from the editor table.
   * @param {number} rowId Discount row id
   * @returns {void}
   */
  _removeDiscountCode(rowId) {
    if (this.disabled) {
      return;
    }

    this._rows = this._rows.filter((row) => row._row_id !== rowId);
  }

  /**
   * Validates and persists the current modal draft into the editor rows.
   * @returns {void}
   */
  _saveDiscountCode() {
    if (!this._draftRow) {
      return;
    }

    const invalidField = Array.from(this.querySelectorAll("[data-discount-modal-field]")).find(
      (field) => typeof field.checkValidity === "function" && !field.checkValidity(),
    );

    if (invalidField && typeof invalidField.reportValidity === "function") {
      invalidField.reportValidity();
      return;
    }

    const rowToSave = {
      ...this._draftRow,
      available: this._draftRow.available_override_active ? this._draftRow.available : "",
      code: String(this._draftRow.code || "")
        .trim()
        .toUpperCase(),
      title: String(this._draftRow.title || "").trim(),
    };

    if (!rowToSave.title || !rowToSave.code) {
      return;
    }

    if (this._isNewRow) {
      this._rows = [...this._rows, rowToSave];
    } else {
      this._rows = this._rows.map((row) => (row._row_id === this._editingRowId ? rowToSave : row));
    }

    this._closeDiscountModal();
  }

  /**
   * Updates a top-level field on the draft discount row.
   * @param {string} fieldName Draft field name
   * @param {*} value Next field value
   * @returns {void}
   */
  _updateDraftDiscountCode(fieldName, value) {
    if (this.disabled || !this._draftRow) {
      return;
    }

    const normalizedValue = fieldName === "code" ? String(value || "").toUpperCase() : value;
    this._draftRow = {
      ...this._draftRow,
      ...(fieldName === "available" ? { available_dirty: true } : {}),
      ...(fieldName === "available" ? { available_override_active: String(value || "").trim() !== "" } : {}),
      [fieldName]: normalizedValue,
    };
  }

  /**
   * Formats a numeric amount using the active event currency.
   * @param {number} amount Numeric amount
   * @returns {string}
   */
  _formatMoney(amount) {
    try {
      return new Intl.NumberFormat(undefined, {
        style: "currency",
        currency: this._currencyCode(),
      }).format(amount);
    } catch (_) {
      return `${this._currencyCode()} ${amount}`;
    }
  }

  /**
   * Renders split currency and value labels for compact table display.
   * @param {string} amountLabel Preformatted amount label
   * @param {{suffix?: string, strongColorClass?: string}} [options={}]
   * Render options
   * @returns {string|*}
   */
  _renderMoneyLabel(amountLabel, { suffix = "", strongColorClass = "text-stone-600" } = {}) {
    const trimmedAmountLabel = String(amountLabel || "").trim();
    const currencyCode = this._currencyCode();

    if (!trimmedAmountLabel) {
      return "";
    }

    const currencyPrefix = `${currencyCode} `;
    if (!trimmedAmountLabel.startsWith(currencyPrefix)) {
      return `${trimmedAmountLabel}${suffix ? ` ${suffix}` : ""}`;
    }

    const numericLabel = trimmedAmountLabel.slice(currencyPrefix.length).trim();
    return html`
      <span class="text-xs font-medium text-stone-500">${currencyCode}</span>
      <span class="text-sm font-medium ${strongColorClass}">${numericLabel}</span>
      ${suffix ? html`<span class="text-sm font-medium ${strongColorClass}">${suffix}</span>` : null}
    `;
  }

  /**
   * Returns the display title for a discount row.
   * @param {object} row Discount row
   * @returns {string}
   */
  _discountTitle(row) {
    return row.title?.trim() || "Untitled discount";
  }

  /**
   * Returns the display value summary for a discount row.
   * @param {object} row Discount row
   * @returns {string}
   */
  _discountValueSummary(row) {
    if (row.kind === "fixed_amount") {
      const amount = Number.parseFloat(row.amount);
      return Number.isFinite(amount) ? `${this._formatMoney(amount)} off` : "Fixed amount";
    }

    const percentage = Number.parseInt(row.percentage, 10);
    return Number.isFinite(percentage) ? `${percentage}% off` : "Percentage discount";
  }

  /**
   * Returns the display redemption limit summary for a discount row.
   * @param {object} row Discount row
   * @returns {string}
   */
  _discountSeatsSummary(row) {
    const totalAvailable = Number.parseInt(row.total_available, 10);
    return Number.isFinite(totalAvailable) ? String(totalAvailable) : "Unlimited";
  }

  /**
   * Returns the optional remaining-uses label for a discount row.
   * @param {object} row Discount row
   * @returns {string}
   */
  _discountSeatsDetail(row) {
    const available = Number.parseInt(row.available, 10);
    return row.available_override_active && Number.isFinite(available) ? `${available} remaining` : "";
  }

  /**
   * Formats a schedule boundary for compact availability labels.
   * @param {string} value Datetime-local string
   * @returns {string}
   */
  _formatScheduleDate(value) {
    if (!value) {
      return "";
    }

    const datePart = String(value).slice(0, 10);
    if (!datePart) {
      return "";
    }

    const date = new Date(`${datePart}T12:00:00`);
    if (Number.isNaN(date.getTime())) {
      return datePart;
    }

    return new Intl.DateTimeFormat("en", {
      day: "numeric",
      month: "short",
    }).format(date);
  }

  /**
   * Returns the display availability summary for a discount row.
   * @param {object} row Discount row
   * @returns {string}
   */
  _discountAvailabilitySummary(row) {
    const startsAt = this._formatScheduleDate(row.starts_at);
    const endsAt = this._formatScheduleDate(row.ends_at);

    if (startsAt && endsAt) {
      return `${startsAt} - ${endsAt}`;
    }

    if (startsAt) {
      return `From ${startsAt}`;
    }

    if (endsAt) {
      return `Until ${endsAt}`;
    }

    return "Always available";
  }

  /**
   * Serializes normalized rows into hidden form fields.
   * @returns {Array<{name: string, value: string}>}
   */
  _serializedFields() {
    const fields = serializeDiscountCodes({
      currencyCode: this._currencyCode(),
      fieldNamePrefix: this.fieldNamePrefix,
      rows: this._rows,
      timezone: this._timezone(),
    });

    return [{ name: this.presenceFieldName, value: "true" }, ...fields];
  }

  /**
   * Renders the discount code table body rows.
   * @returns {*}
   */
  _renderRows() {
    return repeat(
      this._rows,
      (row) => row._row_id,
      (row) => {
        const valueSummary =
          row.kind === "fixed_amount" && Number.isFinite(Number.parseFloat(row.amount))
            ? this._renderMoneyLabel(this._formatMoney(Number.parseFloat(row.amount)), { suffix: "off" })
            : this._discountValueSummary(row);

        return html`
          <tr class="odd:bg-white even:bg-stone-50/50 border-b border-stone-200 align-middle">
            <td class="px-3 xl:px-5 py-4 min-w-[180px] xl:min-w-[220px]">
              <div class="font-medium text-stone-900">${this._discountTitle(row)}</div>
              <div class="mt-2 text-xs font-medium text-stone-600 xl:hidden">
                ${row.code?.trim() || "CODE"}
              </div>
              <div class="mt-3 flex flex-wrap items-center gap-2 xl:hidden">
                <span
                  class="inline-flex items-center rounded-full bg-stone-100 px-2.5 py-1 text-[11px] font-medium text-stone-700"
                >
                  ${this._discountSeatsSummary(row)} seats
                </span>
                <span
                  class="inline-flex items-center rounded-full bg-stone-100 px-2.5 py-1 text-[11px] font-medium text-stone-700"
                >
                  ${this._discountValueSummary(row)}
                </span>
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
              </div>
            </td>
            <td class="hidden xl:table-cell px-3 xl:px-5 py-4 whitespace-nowrap text-stone-900">
              ${this._discountSeatsSummary(row)}
              ${this._discountSeatsDetail(row)
                ? html`<div class="mt-1 text-xs text-stone-500">${this._discountSeatsDetail(row)}</div>`
                : null}
            </td>
            <td class="hidden xl:table-cell px-3 xl:px-5 py-4 whitespace-nowrap">
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
              <div class="text-sm text-stone-700">${this._discountAvailabilitySummary(row)}</div>
            </td>
            <td class="hidden xl:table-cell px-3 xl:px-5 py-4 whitespace-nowrap text-stone-900">
              ${valueSummary}
            </td>
            <td class="hidden xl:table-cell px-3 xl:px-5 py-4 whitespace-nowrap font-medium text-stone-700">
              ${row.code?.trim() || "CODE"}
            </td>
            <td class="px-3 xl:px-5 py-4">
              <div class="flex items-center justify-start gap-1 xl:justify-end">
                <button
                  type="button"
                  class="rounded-full p-2 transition-colors ${this.disabled
                    ? "opacity-60 cursor-not-allowed"
                    : "hover:bg-stone-100"}"
                  data-ticketing-action="edit-discount"
                  data-row-id=${String(row._row_id)}
                  title="Edit"
                  ?disabled=${this.disabled}
                  @click=${() => this._openDiscountModal(row._row_id)}
                >
                  <div class="svg-icon size-4 icon-pencil bg-stone-600"></div>
                </button>
                <button
                  type="button"
                  class="rounded-full p-2 transition-colors ${this.disabled
                    ? "opacity-60 cursor-not-allowed"
                    : "hover:bg-stone-100"}"
                  data-ticketing-action="delete-discount"
                  data-row-id=${String(row._row_id)}
                  title="Delete"
                  ?disabled=${this.disabled}
                  @click=${() => this._removeDiscountCode(row._row_id)}
                >
                  <div class="svg-icon size-4 icon-trash bg-stone-600"></div>
                </button>
              </div>
            </td>
          </tr>
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

  /**
   * Renders the value editor that matches the selected discount kind.
   * @returns {*}
   */
  _renderDraftValueField() {
    if (!this._draftRow) {
      return null;
    }

    if (this._draftRow.kind === "fixed_amount") {
      return html`
        <div>
          <label class="form-label" for="discount-amount-draft">
            Amount ${this._currencyLabelSuffix()} <span class="asterisk">*</span>
          </label>
          <div class="mt-2">
            <input
              id="discount-amount-draft"
              data-discount-modal-field
              data-discount-field="amount"
              type="number"
              min="1"
              step=${this._currencyInputStep()}
              class="input-primary"
              placeholder=${this._currencyInputPlaceholder()}
              .value=${this._draftRow.amount}
              ?disabled=${!this._isModalOpen}
              required
              @input=${(event) => this._updateDraftDiscountCode("amount", event.target.value)}
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
        <label class="form-label" for="discount-percentage-draft">
          Percentage off <span class="asterisk">*</span>
        </label>
        <div class="mt-2">
          <input
            id="discount-percentage-draft"
            data-discount-modal-field
            data-discount-field="percentage"
            type="number"
            min="1"
            max="100"
            class="input-primary"
            placeholder="20"
            .value=${this._draftRow.percentage}
            ?disabled=${!this._isModalOpen}
            required
            @input=${(event) => this._updateDraftDiscountCode("percentage", event.target.value)}
          />
        </div>
      </div>
    `;
  }

  render() {
    return html`
      ${this._renderHiddenFields()}

      <div data-ticketing-role="table-wrapper" class="relative overflow-x-auto xl:overflow-visible">
        <table class="table-auto w-full text-xs lg:text-sm text-left text-stone-500">
          <thead class="text-xs text-stone-700 uppercase bg-stone-100 border-b border-stone-200">
            <tr>
              <th scope="col" class="px-3 xl:px-5 py-3">Name</th>
              <th scope="col" class="hidden xl:table-cell px-3 xl:px-5 py-3">Seats</th>
              <th scope="col" class="hidden xl:table-cell px-3 xl:px-5 py-3">Status</th>
              <th scope="col" class="px-3 xl:px-5 py-3">Availability</th>
              <th scope="col" class="hidden xl:table-cell px-3 xl:px-5 py-3">Value</th>
              <th scope="col" class="hidden xl:table-cell px-3 xl:px-5 py-3">Code</th>
              <th scope="col" class="px-3 xl:px-5 py-3 text-right">Actions</th>
            </tr>
          </thead>
          <tbody data-ticketing-role="empty-state" class=${this._rows.length > 0 ? "hidden" : ""}>
            <tr class="bg-white border-b border-stone-200">
              <td class="px-8 py-12 text-center text-stone-500" colspan="7">
                No discount codes yet. Configured discount codes will appear here.
              </td>
            </tr>
          </tbody>
          <tbody data-ticketing-role="table-body">
            ${this._renderRows()}
          </tbody>
        </table>
      </div>

      <div
        data-ticketing-role="discount-modal"
        class="fixed inset-0 z-[1000] ${this._isModalOpen
          ? "flex"
          : "hidden"} items-center justify-center overflow-y-auto overflow-x-hidden"
        role="dialog"
        aria-modal="true"
        aria-labelledby="discount-code-modal-title"
        data-pending-changes-ignore
      >
        <div
          class="absolute inset-0 bg-stone-950 opacity-35"
          data-ticketing-action="close-modal"
          @click=${() => this._closeDiscountModal()}
        ></div>
        <div class="modal-panel max-w-4xl p-4">
          <div class="modal-card rounded-2xl">
            <div class="flex items-center justify-between border-b border-stone-200 p-5 shrink-0">
              <h3
                id="discount-code-modal-title"
                data-ticketing-role="modal-title"
                class="text-xl font-semibold text-stone-900"
              >
                ${this._isNewRow ? "Add discount code" : "Edit discount code"}
              </h3>
              <button
                type="button"
                data-ticketing-action="close-modal"
                class="group inline-flex h-8 w-8 items-center justify-center rounded-lg bg-transparent text-sm text-stone-400 transition-colors hover:bg-stone-100"
                ?disabled=${!this._isModalOpen}
                @click=${() => this._closeDiscountModal()}
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
                  <label class="form-label" for="discount-title-draft">
                    Title <span class="asterisk">*</span>
                  </label>
                  <div class="mt-2">
                    <input
                      id="discount-title-draft"
                      data-discount-modal-field
                      data-discount-field="title"
                      type="text"
                      class="input-primary"
                      maxlength="120"
                      placeholder="Early supporter"
                      .value=${this._draftRow?.title || ""}
                      ?disabled=${!this._isModalOpen}
                      required
                      @input=${(event) => this._updateDraftDiscountCode("title", event.target.value)}
                    />
                  </div>
                </div>

                <div>
                  <label class="form-label" for="discount-code-draft">
                    Code <span class="asterisk">*</span>
                  </label>
                  <div class="mt-2">
                    <input
                      id="discount-code-draft"
                      data-discount-modal-field
                      data-discount-field="code"
                      type="text"
                      class="input-primary uppercase"
                      maxlength="40"
                      placeholder="EARLY20"
                      .value=${this._draftRow?.code || ""}
                      ?disabled=${!this._isModalOpen}
                      required
                      @input=${(event) => this._updateDraftDiscountCode("code", event.target.value)}
                    />
                  </div>
                </div>
              </div>

              <div>
                <label class="inline-flex cursor-pointer items-center">
                  <input
                    type="checkbox"
                    class="sr-only peer"
                    data-discount-field="active"
                    .checked=${this._draftRow?.active ?? true}
                    ?disabled=${!this._isModalOpen}
                    @change=${(event) => this._updateDraftDiscountCode("active", event.target.checked)}
                  />
                  <div
                    class="relative h-6 w-11 rounded-full bg-stone-200 transition peer-checked:bg-primary-500 peer-checked:after:translate-x-full after:absolute after:start-[2px] after:top-[2px] after:h-5 after:w-5 after:rounded-full after:border after:border-stone-200 after:bg-white after:transition-all after:content-['']"
                  ></div>
                  <span class="ms-3 text-sm font-medium text-stone-900">Active</span>
                </label>
              </div>

              <div class="grid gap-4 md:grid-cols-2">
                <div>
                  <label class="form-label" for="discount-kind-draft">Discount type</label>
                  <div class="mt-2">
                    <select
                      id="discount-kind-draft"
                      data-discount-field="kind"
                      class="input-primary"
                      .value=${this._draftRow?.kind || "percentage"}
                      ?disabled=${!this._isModalOpen}
                      @change=${(event) => this._updateDraftDiscountCode("kind", event.target.value)}
                    >
                      <option value="percentage">Percentage</option>
                      <option value="fixed_amount">Fixed amount</option>
                    </select>
                  </div>
                </div>

                <div data-ticketing-role="discount-value-field">${this._renderDraftValueField()}</div>

                <div>
                  <label class="form-label" for="discount-total-draft">Maximum redemptions</label>
                  <div class="mt-2">
                    <input
                      id="discount-total-draft"
                      data-discount-field="total_available"
                      type="number"
                      min="0"
                      class="input-primary"
                      placeholder="50"
                      .value=${this._draftRow?.total_available || ""}
                      ?disabled=${!this._isModalOpen}
                      @input=${(event) =>
                        this._updateDraftDiscountCode("total_available", event.target.value)}
                    />
                  </div>
                </div>

                <div>
                  <label class="form-label" for="discount-available-draft">Uses remaining</label>
                  <div class="mt-2">
                    <input
                      id="discount-available-draft"
                      data-discount-field="available"
                      type="number"
                      min="0"
                      class="input-primary"
                      placeholder="Leave blank unless you need a manual override"
                      .value=${this._draftRow?.available || ""}
                      ?disabled=${!this._isModalOpen}
                      @input=${(event) => this._updateDraftDiscountCode("available", event.target.value)}
                    />
                  </div>
                </div>

                <div>
                  <label class="form-label" for="discount-starts-draft">Starts at</label>
                  <div class="mt-2">
                    <input
                      id="discount-starts-draft"
                      data-discount-field="starts_at"
                      type="datetime-local"
                      class="input-primary"
                      .value=${this._draftRow?.starts_at || ""}
                      ?disabled=${!this._isModalOpen}
                      @input=${(event) => this._updateDraftDiscountCode("starts_at", event.target.value)}
                    />
                  </div>
                </div>

                <div>
                  <label class="form-label" for="discount-ends-draft">Ends at</label>
                  <div class="mt-2">
                    <input
                      id="discount-ends-draft"
                      data-discount-field="ends_at"
                      type="datetime-local"
                      class="input-primary"
                      .value=${this._draftRow?.ends_at || ""}
                      ?disabled=${!this._isModalOpen}
                      @input=${(event) => this._updateDraftDiscountCode("ends_at", event.target.value)}
                    />
                  </div>
                </div>
              </div>
            </div>

            <div class="flex items-center justify-end gap-3 border-t border-stone-200 p-5 shrink-0">
              <button
                type="button"
                data-ticketing-action="close-modal"
                class="btn-secondary"
                ?disabled=${!this._isModalOpen}
                @click=${() => this._closeDiscountModal()}
              >
                Cancel
              </button>
              <button
                type="button"
                data-ticketing-action="save-discount"
                class="btn-primary"
                ?disabled=${!this._isModalOpen}
                @click=${() => this._saveDiscountCode()}
              >
                <span data-ticketing-role="save-label">
                  ${this._isNewRow ? "Add discount code" : "Save changes"}
                </span>
              </button>
            </div>
          </div>
        </div>
      </div>
    `;
  }
}

if (!customElements.get("discount-codes-editor")) {
  customElements.define("discount-codes-editor", DiscountCodesEditor);
}
