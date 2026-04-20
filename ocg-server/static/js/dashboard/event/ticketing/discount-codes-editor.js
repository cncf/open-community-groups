import { lockBodyScroll, unlockBodyScroll } from "/static/js/common/common.js";
import {
  normalizeDiscountCodes,
  serializeDiscountCodes,
} from "/static/js/dashboard/event/ticketing/contract.js";
import { resolveEventTimezone } from "/static/js/dashboard/event/ticketing/datetime.js";
import {
  resolveCurrencyInputPlaceholder,
  resolveCurrencyInputStep,
  resolveEventCurrencyCode,
} from "/static/js/dashboard/event/ticketing/money.js";
import {
  escapeHtml,
  parseJsonAttribute,
  parseJsonSeed,
} from "/static/js/dashboard/event/ticketing/shared.js";

class DiscountCodesController {
  constructor({ addButton = null, currencyInput = null, root, timezoneInput = null }) {
    this.addButton = addButton;
    this.currencyInput = currencyInput;
    this.root = root;
    this.timezoneInput = timezoneInput;
    this.disabled = root.dataset.disabled === "true";
    this.fieldNamePrefix = "discount_codes";
    this.presenceFieldName = "discount_codes_present";
    this._rows = [];
    this._draftRow = null;
    this._editingRowId = null;
    this._isModalOpen = false;
    this._isNewRow = false;
    this._nextId = 0;

    this._handleCurrencyFieldChange = this._handleCurrencyFieldChange.bind(this);
    this._handleExternalAddClick = this._handleExternalAddClick.bind(this);
    this._handleKeydown = this._handleKeydown.bind(this);
    this._handleRootClick = this._handleRootClick.bind(this);
    this._handleRootInput = this._handleRootInput.bind(this);
    this._handleRootChange = this._handleRootChange.bind(this);

    this._applyDiscountCodes(
      parseJsonSeed(root, "discount-codes", parseJsonAttribute(root.dataset.discountCodes, [])),
    );
    this._bind();
    this.render();
  }

  destroy() {
    if (this._isModalOpen) {
      unlockBodyScroll();
    }

    this._draftRow = null;
    this._editingRowId = null;
    this._isModalOpen = false;
    this._isNewRow = false;
    this._toggleExternalAddButtonListener(false);
    this.root.removeEventListener("click", this._handleRootClick);
    this.root.removeEventListener("input", this._handleRootInput);
    this.root.removeEventListener("change", this._handleRootChange);
    document.removeEventListener("keydown", this._handleKeydown);
    this.currencyInput?.removeEventListener("input", this._handleCurrencyFieldChange);
  }

  setDiscountCodes(discountCodes) {
    this._applyDiscountCodes(discountCodes);
    this.render();
  }

  _bind() {
    this._toggleExternalAddButtonListener(true);
    this.root.addEventListener("click", this._handleRootClick);
    this.root.addEventListener("input", this._handleRootInput);
    this.root.addEventListener("change", this._handleRootChange);
    document.addEventListener("keydown", this._handleKeydown);
    this.currencyInput?.addEventListener("input", this._handleCurrencyFieldChange);
  }

  _toggleExternalAddButtonListener(shouldAdd) {
    if (!this.addButton) {
      return;
    }

    this.addButton[shouldAdd ? "addEventListener" : "removeEventListener"](
      "click",
      this._handleExternalAddClick,
    );
  }

  _handleCurrencyFieldChange() {
    this.render();
  }

  _handleExternalAddClick() {
    this._openDiscountModal();
  }

  _handleKeydown(event) {
    if (event.key === "Escape" && this._isModalOpen) {
      this._closeDiscountModal();
    }
  }

  _handleRootClick(event) {
    const target = event.target instanceof Element ? event.target.closest("[data-ticketing-action]") : null;
    const action = target?.dataset.ticketingAction;
    if (!action) {
      return;
    }

    if (action === "close-modal") {
      this._closeDiscountModal();
      return;
    }

    if (this.disabled) {
      return;
    }

    switch (action) {
      case "edit-discount":
        this._openDiscountModal(this._resolveRowId(target));
        break;
      case "delete-discount":
        this._removeDiscountCode(this._resolveRowId(target));
        break;
      case "save-discount":
        this._saveDiscountCode();
        break;
      default:
        break;
    }
  }

  _handleRootInput(event) {
    const target = event.target;
    if (!(target instanceof HTMLElement) || !this._draftRow) {
      return;
    }

    if (!target.dataset.discountField) {
      return;
    }

    this._updateDraftDiscountCode(target.dataset.discountField, target.value);
    if (target.dataset.discountField === "kind") {
      this.render();
    }
  }

  _handleRootChange(event) {
    const target = event.target;
    if (!(target instanceof HTMLElement) || !this._draftRow) {
      return;
    }

    if (!target.dataset.discountField) {
      return;
    }

    if (target instanceof HTMLInputElement && target.type === "checkbox") {
      this._updateDraftDiscountCode(target.dataset.discountField, target.checked);
      return;
    }

    this._updateDraftDiscountCode(target.dataset.discountField, target.value);
    if (target.dataset.discountField === "kind") {
      this.render();
    }
  }

  _currencyCode() {
    return resolveEventCurrencyCode(this.currencyInput);
  }

  _timezone() {
    return resolveEventTimezone(this.timezoneInput);
  }

  _currencyInputPlaceholder() {
    return resolveCurrencyInputPlaceholder(this._currencyCode());
  }

  _currencyInputStep() {
    return resolveCurrencyInputStep(this._currencyCode());
  }

  _currencyLabelSuffix() {
    return `(${this._currencyCode()})`;
  }

  _nextRowId() {
    const rowId = this._nextId;
    this._nextId += 1;
    return rowId;
  }

  _applyDiscountCodes(discountCodes) {
    this._rows = normalizeDiscountCodes({
      currencyCode: this._currencyCode(),
      discountCodes,
      nextRowId: () => this._nextRowId(),
      timezone: this._timezone(),
    });
  }

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

  _cloneDiscountCode(row) {
    return { ...row };
  }

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
    this.render();
  }

  _closeDiscountModal() {
    if (!this._isModalOpen) {
      return;
    }

    this._draftRow = null;
    this._editingRowId = null;
    this._isModalOpen = false;
    this._isNewRow = false;
    unlockBodyScroll();
    this.render();
  }

  _removeDiscountCode(rowId) {
    if (this.disabled) {
      return;
    }

    this._rows = this._rows.filter((row) => row._row_id !== rowId);
    this.render();
  }

  _saveDiscountCode() {
    if (!this._draftRow) {
      return;
    }

    const invalidField = Array.from(this.root.querySelectorAll("[data-discount-modal-field]")).find(
      (field) => typeof field.checkValidity === "function" && !field.checkValidity(),
    );

    if (invalidField && typeof invalidField.reportValidity === "function") {
      invalidField.reportValidity();
      return;
    }

    const rowToSave = {
      ...this._draftRow,
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
    this.render();
  }

  _resolveRowId(target) {
    const rowId = Number.parseInt(target.dataset.rowId || "", 10);
    return Number.isFinite(rowId) ? rowId : Number.NaN;
  }

  _updateDraftDiscountCode(fieldName, value) {
    if (this.disabled || !this._draftRow) {
      return;
    }

    const normalizedValue = fieldName === "code" ? String(value || "").toUpperCase() : value;
    this._draftRow = {
      ...this._draftRow,
      ...(fieldName === "available" ? { available_dirty: true } : {}),
      [fieldName]: normalizedValue,
    };
  }

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

  _renderMoneyLabel(amountLabel, { suffix = "", strongColorClass = "text-stone-600" } = {}) {
    const trimmedAmountLabel = String(amountLabel || "").trim();
    const currencyCode = this._currencyCode();

    if (!trimmedAmountLabel) {
      return "";
    }

    const currencyPrefix = `${currencyCode} `;
    if (!trimmedAmountLabel.startsWith(currencyPrefix)) {
      return `<span class="text-sm font-medium ${strongColorClass}">${escapeHtml(trimmedAmountLabel)}</span>${suffix ? ` <span class="text-sm font-medium ${strongColorClass}">${escapeHtml(suffix)}</span>` : ""}`;
    }

    const numericLabel = trimmedAmountLabel.slice(currencyPrefix.length).trim();
    return `
      <span class="text-xs font-medium text-stone-500">${escapeHtml(currencyCode)}</span>
      <span class="text-sm font-medium ${strongColorClass}">${escapeHtml(numericLabel)}</span>
      ${suffix ? `<span class="text-sm font-medium ${strongColorClass}">${escapeHtml(suffix)}</span>` : ""}
    `;
  }

  _discountTitle(row) {
    return row.title?.trim() || "Untitled discount";
  }

  _discountValueSummary(row) {
    if (row.kind === "fixed_amount") {
      const amount = Number.parseFloat(row.amount);
      return Number.isFinite(amount) ? `${this._formatMoney(amount)} off` : "Fixed amount";
    }

    const percentage = Number.parseInt(row.percentage, 10);
    return Number.isFinite(percentage) ? `${percentage}% off` : "Percentage discount";
  }

  _discountSeatsSummary(row) {
    const totalAvailable = Number.parseInt(row.total_available, 10);
    return Number.isFinite(totalAvailable) ? String(totalAvailable) : "Unlimited";
  }

  _discountSeatsDetail(row) {
    const available = Number.parseInt(row.available, 10);
    return Number.isFinite(available) ? `${available} remaining` : "";
  }

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

  _renderHiddenFields() {
    const container = this.root.querySelector('[data-ticketing-role="hidden-fields"]');
    if (!container) {
      return;
    }

    if (this.disabled) {
      container.innerHTML = "";
      return;
    }

    const fields = serializeDiscountCodes({
      currencyCode: this._currencyCode(),
      fieldNamePrefix: this.fieldNamePrefix,
      rows: this._rows,
      timezone: this._timezone(),
    });

    const allFields = [{ name: this.presenceFieldName, value: "true" }, ...fields];
    container.innerHTML = allFields
      .map(
        (field) =>
          `<input type="hidden" name="${escapeHtml(field.name)}" value="${escapeHtml(field.value)}">`,
      )
      .join("");
  }

  _renderRows() {
    const body = this.root.querySelector('[data-ticketing-role="table-body"]');
    if (!body) {
      return;
    }

    body.innerHTML = this._rows
      .map((row) => {
        const status = row.active
          ? '<span class="custom-badge shrink-0 border-green-800 bg-green-100 px-2.5 py-0.5 text-green-800">Active</span>'
          : '<span class="custom-badge shrink-0 border-stone-500 bg-stone-100 px-2.5 py-0.5 text-stone-700">Inactive</span>';
        const mobileValueSummary = escapeHtml(this._discountValueSummary(row));
        const valueSummary =
          row.kind === "fixed_amount" && Number.isFinite(Number.parseFloat(row.amount))
            ? this._renderMoneyLabel(this._formatMoney(Number.parseFloat(row.amount)), { suffix: "off" })
            : escapeHtml(this._discountValueSummary(row));

        return `
          <tr class="odd:bg-white even:bg-stone-50/50 border-b border-stone-200 align-middle">
            <td class="px-3 xl:px-5 py-4 min-w-[180px] xl:min-w-[220px]">
              <div class="font-medium text-stone-900">${escapeHtml(this._discountTitle(row))}</div>
              <div class="mt-2 text-xs font-medium text-stone-600 xl:hidden">${escapeHtml(row.code?.trim() || "CODE")}</div>
              <div class="mt-3 flex flex-wrap items-center gap-2 xl:hidden">
                <span class="inline-flex items-center rounded-full bg-stone-100 px-2.5 py-1 text-[11px] font-medium text-stone-700">${escapeHtml(this._discountSeatsSummary(row))} seats</span>
                <span class="inline-flex items-center rounded-full bg-stone-100 px-2.5 py-1 text-[11px] font-medium text-stone-700">${mobileValueSummary}</span>
                ${status}
              </div>
            </td>
            <td class="hidden xl:table-cell px-3 xl:px-5 py-4 whitespace-nowrap text-stone-900">
              ${escapeHtml(this._discountSeatsSummary(row))}
              ${
                this._discountSeatsDetail(row)
                  ? `<div class="mt-1 text-xs text-stone-500">${escapeHtml(this._discountSeatsDetail(row))}</div>`
                  : ""
              }
            </td>
            <td class="hidden xl:table-cell px-3 xl:px-5 py-4 whitespace-nowrap">${status}</td>
            <td class="px-3 xl:px-5 py-4">
              <div class="text-sm text-stone-700">${escapeHtml(this._discountAvailabilitySummary(row))}</div>
            </td>
            <td class="hidden xl:table-cell px-3 xl:px-5 py-4 whitespace-nowrap text-stone-900">${valueSummary}</td>
            <td class="hidden xl:table-cell px-3 xl:px-5 py-4 whitespace-nowrap font-medium text-stone-700">${escapeHtml(row.code?.trim() || "CODE")}</td>
            <td class="px-3 xl:px-5 py-4">
              <div class="flex items-center justify-start gap-1 xl:justify-end">
                <button
                  type="button"
                  class="rounded-full p-2 transition-colors ${this.disabled ? "opacity-60 cursor-not-allowed" : "hover:bg-stone-100"}"
                  data-ticketing-action="edit-discount"
                  data-row-id="${row._row_id}"
                  title="Edit"
                  ${this.disabled ? "disabled" : ""}
                >
                  <div class="svg-icon size-4 icon-pencil bg-stone-600"></div>
                </button>
                <button
                  type="button"
                  class="rounded-full p-2 transition-colors ${this.disabled ? "opacity-60 cursor-not-allowed" : "hover:bg-stone-100"}"
                  data-ticketing-action="delete-discount"
                  data-row-id="${row._row_id}"
                  title="Delete"
                  ${this.disabled ? "disabled" : ""}
                >
                  <div class="svg-icon size-4 icon-trash bg-stone-600"></div>
                </button>
              </div>
            </td>
          </tr>
        `;
      })
      .join("");
  }

  _renderDraftValueField() {
    const container = this.root.querySelector('[data-ticketing-role="discount-value-field"]');
    if (!container) {
      return;
    }

    if (!this._draftRow) {
      container.innerHTML = "";
      return;
    }

    if (this._draftRow.kind === "fixed_amount") {
      container.innerHTML = `
        <div>
          <label class="form-label" for="discount-amount-draft">
            Amount ${escapeHtml(this._currencyLabelSuffix())} <span class="asterisk">*</span>
          </label>
          <div class="mt-2">
            <input
              id="discount-amount-draft"
              data-discount-modal-field
              data-discount-field="amount"
              type="number"
              min="1"
              step="${escapeHtml(this._currencyInputStep())}"
              class="input-primary"
              placeholder="${escapeHtml(this._currencyInputPlaceholder())}"
              value="${escapeHtml(this._draftRow.amount)}"
              required
            >
          </div>
          <p class="form-legend">
            Use the same currency as the event, for example
            <span class="font-semibold">${escapeHtml(this._currencyInputPlaceholder())}</span>.
          </p>
        </div>
      `;
      return;
    }

    container.innerHTML = `
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
            value="${escapeHtml(this._draftRow.percentage)}"
            required
          >
        </div>
      </div>
    `;
  }

  _renderModal() {
    const modal = this.root.querySelector('[data-ticketing-role="discount-modal"]');
    if (!modal) {
      return;
    }

    const isModalVisible = this._isModalOpen && !!this._draftRow;

    modal.classList.toggle("hidden", !isModalVisible);
    modal.classList.toggle("flex", isModalVisible);
    modal.querySelectorAll("input, textarea, select, button").forEach((field) => {
      field.disabled = !isModalVisible;
    });

    if (!this._draftRow) {
      return;
    }

    const modalTitle = this.root.querySelector('[data-ticketing-role="modal-title"]');
    const saveLabel = this.root.querySelector('[data-ticketing-role="save-label"]');
    const titleField = this.root.querySelector("#discount-title-draft");
    const codeField = this.root.querySelector("#discount-code-draft");
    const activeField = this.root.querySelector('[data-discount-field="active"]');
    const kindField = this.root.querySelector("#discount-kind-draft");
    const totalField = this.root.querySelector("#discount-total-draft");
    const availableField = this.root.querySelector("#discount-available-draft");
    const startsField = this.root.querySelector("#discount-starts-draft");
    const endsField = this.root.querySelector("#discount-ends-draft");

    if (modalTitle) {
      modalTitle.textContent = this._isNewRow ? "Add discount code" : "Edit discount code";
    }

    if (saveLabel) {
      saveLabel.textContent = this._isNewRow ? "Add discount code" : "Save changes";
    }

    if (titleField) {
      titleField.value = this._draftRow.title;
    }

    if (codeField) {
      codeField.value = this._draftRow.code;
    }

    if (activeField) {
      activeField.checked = this._draftRow.active;
    }

    if (kindField) {
      kindField.value = this._draftRow.kind;
    }

    if (totalField) {
      totalField.value = this._draftRow.total_available;
    }

    if (availableField) {
      availableField.value = this._draftRow.available;
    }

    if (startsField) {
      startsField.value = this._draftRow.starts_at;
    }

    if (endsField) {
      endsField.value = this._draftRow.ends_at;
    }

    this._renderDraftValueField();
  }

  render() {
    const emptyState = this.root.querySelector('[data-ticketing-role="empty-state"]');
    if (emptyState) {
      emptyState.classList.toggle("hidden", this._rows.length > 0);
    }

    this._renderRows();
    this._renderHiddenFields();
    this._renderModal();
  }
}

export const initializeDiscountCodesController = ({
  addButton = null,
  addButtonId = "",
  currencyInput = null,
  currencyInputId = "payment_currency_code",
  root = null,
  rootId = "",
  timezoneInput = null,
  timezoneSelector = '[name="timezone"]',
}) => {
  const resolvedRoot = root || document.getElementById(rootId);
  if (!resolvedRoot) {
    return null;
  }

  const resolvedAddButton = addButton || (addButtonId ? document.getElementById(addButtonId) : null);
  const resolvedCurrencyInput =
    currencyInput || (currencyInputId ? document.getElementById(currencyInputId) : null);
  const resolvedTimezoneInput =
    timezoneInput || (timezoneSelector ? document.querySelector(timezoneSelector) : null);

  if (resolvedRoot._discountCodesController) {
    return resolvedRoot._discountCodesController;
  }

  const controller = new DiscountCodesController({
    addButton: resolvedAddButton,
    currencyInput: resolvedCurrencyInput,
    root: resolvedRoot,
    timezoneInput: resolvedTimezoneInput,
  });
  resolvedRoot._discountCodesController = controller;
  return controller;
};
