import { lockBodyScroll, unlockBodyScroll } from "/static/js/common/common.js";
import { normalizeTicketTypes, serializeTicketTypes } from "/static/js/dashboard/event/ticketing/contract.js";
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

class TicketTypesController {
  constructor({ addButton = null, currencyInput = null, root, timezoneInput = null }) {
    this.addButton = addButton;
    this.currencyInput = currencyInput;
    this.root = root;
    this.timezoneInput = timezoneInput;
    this.disabled = root.dataset.disabled === "true";
    this.fieldNamePrefix = "ticket_types";
    this.presenceFieldName = "ticket_types_present";
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

    this._applyTicketTypes(
      parseJsonSeed(root, "ticket-types", parseJsonAttribute(root.dataset.ticketTypes, [])),
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

  hasConfiguredTicketTypes() {
    return this._rows.length > 0;
  }

  setTicketTypes(ticketTypes) {
    this._applyTicketTypes(ticketTypes);
    this.render();
  }

  getConfiguredSeatTotal() {
    if (this._rows.length === 0) {
      return null;
    }

    return this._rows.reduce((total, row) => {
      const seatsTotal = Number.parseInt(row.seats_total, 10);
      return total + (Number.isFinite(seatsTotal) && seatsTotal > 0 ? seatsTotal : 0);
    }, 0);
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
    this._openTicketModal();
  }

  _handleKeydown(event) {
    if (event.key === "Escape" && this._isModalOpen) {
      this._closeTicketModal();
    }
  }

  _handleRootClick(event) {
    const target = event.target instanceof Element ? event.target.closest("[data-ticketing-action]") : null;
    const action = target?.dataset.ticketingAction;
    if (!action) {
      return;
    }

    if (action === "close-modal") {
      this._closeTicketModal();
      return;
    }

    if (this.disabled) {
      return;
    }

    switch (action) {
      case "edit-ticket":
        this._openTicketModal(this._resolveRowId(target));
        break;
      case "delete-ticket":
        this._removeTicketType(this._resolveRowId(target));
        break;
      case "add-price-window":
        this._addDraftPriceWindow();
        break;
      case "remove-price-window":
        this._removeDraftPriceWindow(Number.parseInt(target.dataset.windowRowId || "", 10));
        break;
      case "save-ticket":
        this._saveTicketType();
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

    if (target.dataset.ticketField) {
      this._updateDraftTicketType(target.dataset.ticketField, target.value);
      return;
    }

    if (target.dataset.ticketWindowField) {
      this._updateDraftPriceWindow(
        Number.parseInt(target.dataset.windowRowId || "", 10),
        target.dataset.ticketWindowField,
        target.value,
      );
    }
  }

  _handleRootChange(event) {
    const target = event.target;
    if (!(target instanceof HTMLElement) || !this._draftRow) {
      return;
    }

    if (target.dataset.ticketField && target instanceof HTMLInputElement && target.type === "checkbox") {
      this._updateDraftTicketType(target.dataset.ticketField, target.checked);
    }
  }

  _emitChange(detail) {
    this.root.dispatchEvent(
      new CustomEvent("ticket-types-changed", {
        bubbles: true,
        composed: true,
        detail,
      }),
    );
  }

  _notifyTicketTypesChanged() {
    this._emitChange({ hasTicketTypes: this.hasConfiguredTicketTypes() });
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

  _createEmptyPriceWindow() {
    return {
      _row_id: this._nextRowId(),
      amount: "",
      ends_at: "",
      event_ticket_price_window_id: "",
      starts_at: "",
    };
  }

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

  _cloneTicketType(row) {
    return {
      ...row,
      price_windows: row.price_windows.map((windowRow) => ({ ...windowRow })),
    };
  }

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
    this.render();
  }

  _closeTicketModal() {
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

  _addDraftPriceWindow() {
    if (this.disabled || !this._draftRow) {
      return;
    }

    this._draftRow = {
      ...this._draftRow,
      price_windows: [...this._draftRow.price_windows, this._createEmptyPriceWindow()],
    };
    this.render();
  }

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
    this.render();
  }

  _removeTicketType(rowId) {
    if (this.disabled) {
      return;
    }

    this._rows = this._rows.filter((row) => row._row_id !== rowId);
    this._notifyTicketTypesChanged();
    this.render();
  }

  _saveTicketType() {
    if (!this._draftRow) {
      return;
    }

    const invalidField = Array.from(this.root.querySelectorAll("[data-ticket-modal-field]")).find(
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
    this.render();
  }

  _resolveRowId(target) {
    const rowId = Number.parseInt(target.dataset.rowId || "", 10);
    return Number.isFinite(rowId) ? rowId : Number.NaN;
  }

  _updateDraftTicketType(fieldName, value) {
    if (this.disabled || !this._draftRow) {
      return;
    }

    this._draftRow = {
      ...this._draftRow,
      [fieldName]: value,
    };
  }

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

  _formatMoney(amount) {
    if (amount === 0) {
      return "Free";
    }

    try {
      return new Intl.NumberFormat(undefined, {
        style: "currency",
        currency: this._currencyCode(),
      }).format(amount);
    } catch (_) {
      return `${this._currencyCode()} ${amount}`;
    }
  }

  _renderMoneyLabel(amountLabel, { strongColorClass = "text-stone-700" } = {}) {
    const trimmedAmountLabel = String(amountLabel || "").trim();
    const currencyCode = this._currencyCode();

    if (!trimmedAmountLabel || trimmedAmountLabel === "Free") {
      return `<span class="text-sm font-medium ${strongColorClass}">${escapeHtml(trimmedAmountLabel || "Free")}</span>`;
    }

    const currencyPrefix = `${currencyCode} `;
    if (!trimmedAmountLabel.startsWith(currencyPrefix)) {
      return `<span class="text-sm font-medium ${strongColorClass}">${escapeHtml(trimmedAmountLabel)}</span>`;
    }

    const numericLabel = trimmedAmountLabel.slice(currencyPrefix.length).trim();
    return `
      <span class="text-xs font-medium text-stone-500">${escapeHtml(currencyCode)}</span>
      <span class="text-sm font-medium ${strongColorClass}">${escapeHtml(numericLabel)}</span>
    `;
  }

  _ticketTitle(row) {
    return row.title?.trim() || "Untitled ticket";
  }

  _formatTicketWindowDate(value) {
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

  _ticketWindowItems(row) {
    return row.price_windows
      .map((windowRow) => {
        const amount = Number.parseFloat(windowRow.amount);
        const priceLabel = Number.isFinite(amount) ? this._formatMoney(amount) : "Price TBD";
        const startsAt = this._formatTicketWindowDate(windowRow.starts_at);
        const endsAt = this._formatTicketWindowDate(windowRow.ends_at);
        let timingLabel = "Always available";

        if (startsAt && endsAt) {
          timingLabel = `${startsAt} - ${endsAt}`;
        } else if (startsAt) {
          timingLabel = `from ${startsAt}`;
        } else if (endsAt) {
          timingLabel = `until ${endsAt}`;
        }

        return {
          rowId: windowRow._row_id,
          priceLabel,
          timingLabel,
        };
      })
      .filter((windowRow) => windowRow.priceLabel || windowRow.timingLabel);
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

    const fields = serializeTicketTypes({
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
        const windows = this._ticketWindowItems(row)
          .map(
            (windowRow) => `
              <div class="flex flex-col gap-1 rounded-md bg-stone-50 px-3 py-2 text-sm sm:flex-row sm:items-center sm:justify-between sm:gap-3">
                <span>${this._renderMoneyLabel(windowRow.priceLabel)}</span>
                <span class="text-left text-stone-500 sm:text-right">${escapeHtml(windowRow.timingLabel)}</span>
              </div>
            `,
          )
          .join("");

        return `
          <tr class="odd:bg-white even:bg-stone-50/50 border-b border-stone-200 align-middle">
            <td class="px-3 xl:px-5 py-4 min-w-[180px] xl:min-w-[220px]">
              <div class="font-medium text-stone-900">${escapeHtml(this._ticketTitle(row))}</div>
              <div class="mt-3 flex flex-wrap items-center gap-2 xl:hidden">
                <span class="inline-flex items-center rounded-full bg-stone-100 px-2.5 py-1 text-[11px] font-medium text-stone-700">${escapeHtml(row.seats_total || "—")} seats</span>
                ${status}
              </div>
            </td>
            <td class="hidden xl:table-cell px-3 xl:px-5 py-4 whitespace-nowrap text-stone-900">${escapeHtml(row.seats_total || "—")}</td>
            <td class="hidden xl:table-cell px-3 xl:px-5 py-4 whitespace-nowrap">${status}</td>
            <td class="px-3 xl:px-5 py-4 min-w-[220px] xl:min-w-[280px]">
              <div class="space-y-2">${windows || '<div class="text-sm text-stone-500">No price windows configured.</div>'}</div>
            </td>
            <td class="px-3 xl:px-5 py-4">
              <div class="flex items-center justify-start gap-1 xl:justify-end">
                <button
                  type="button"
                  class="rounded-full p-2 transition-colors ${this.disabled ? "opacity-60 cursor-not-allowed" : "hover:bg-stone-100"}"
                  data-ticketing-action="edit-ticket"
                  data-row-id="${row._row_id}"
                  title="Edit"
                  ${this.disabled ? "disabled" : ""}
                >
                  <div class="svg-icon size-4 icon-pencil bg-stone-600"></div>
                </button>
                <button
                  type="button"
                  class="rounded-full p-2 transition-colors ${this.disabled ? "opacity-60 cursor-not-allowed" : "hover:bg-stone-100"}"
                  data-ticketing-action="delete-ticket"
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

  _renderDraftPriceWindows() {
    const list = this.root.querySelector('[data-ticketing-role="price-windows-list"]');
    if (!list) {
      return;
    }

    if (!this._draftRow) {
      list.innerHTML = "";
      return;
    }

    list.innerHTML = this._draftRow.price_windows
      .map((windowRow) => {
        const isOnlyWindow = this._draftRow.price_windows.length === 1;

        return `
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
                class="inline-flex size-9 items-center justify-center rounded-full border border-stone-200 ${this.disabled || isOnlyWindow ? "" : "hover:bg-stone-100"}"
                title="Remove price window"
                aria-label="Remove price window"
                data-ticketing-action="remove-price-window"
                data-window-row-id="${windowRow._row_id}"
                ${this.disabled || isOnlyWindow ? "disabled" : ""}
              >
                <div class="svg-icon size-4 icon-trash bg-stone-600"></div>
              </button>
            </div>

            <div class="mt-4 grid gap-4 md:grid-cols-3">
              <div>
                <label class="form-label" for="ticket-price-${windowRow._row_id}">
                  Price ${escapeHtml(this._currencyLabelSuffix())} <span class="asterisk">*</span>
                </label>
                <div class="mt-2">
                  <input
                    id="ticket-price-${windowRow._row_id}"
                    data-ticket-modal-field
                    data-ticket-window-field="amount"
                    data-window-row-id="${windowRow._row_id}"
                    type="number"
                    min="0"
                    step="${escapeHtml(this._currencyInputStep())}"
                    class="input-primary"
                    placeholder="${escapeHtml(this._currencyInputPlaceholder())}"
                    value="${escapeHtml(windowRow.amount)}"
                    required
                  >
                </div>
                <p class="form-legend">Use <span class="font-semibold">0</span> for free tickets.</p>
              </div>

              <div>
                <label class="form-label" for="ticket-starts-${windowRow._row_id}">Starts at</label>
                <div class="mt-2">
                  <input
                    id="ticket-starts-${windowRow._row_id}"
                    data-ticket-window-field="starts_at"
                    data-window-row-id="${windowRow._row_id}"
                    type="datetime-local"
                    class="input-primary"
                    value="${escapeHtml(windowRow.starts_at)}"
                  >
                </div>
              </div>

              <div>
                <label class="form-label" for="ticket-ends-${windowRow._row_id}">Ends at</label>
                <div class="mt-2">
                  <input
                    id="ticket-ends-${windowRow._row_id}"
                    data-ticket-window-field="ends_at"
                    data-window-row-id="${windowRow._row_id}"
                    type="datetime-local"
                    class="input-primary"
                    value="${escapeHtml(windowRow.ends_at)}"
                  >
                </div>
              </div>
            </div>
          </div>
        `;
      })
      .join("");
  }

  _renderModal() {
    const modal = this.root.querySelector('[data-ticketing-role="ticket-modal"]');
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
    const titleField = this.root.querySelector("#ticket-title-draft");
    const seatsField = this.root.querySelector("#ticket-seats-draft");
    const descriptionField = this.root.querySelector("#ticket-description-draft");
    const activeField = this.root.querySelector('[data-ticket-field="active"]');

    if (modalTitle) {
      modalTitle.textContent = this._isNewRow ? "Add ticket type" : "Edit ticket type";
    }

    if (saveLabel) {
      saveLabel.textContent = this._isNewRow ? "Add ticket type" : "Save changes";
    }

    if (titleField) {
      titleField.value = this._draftRow.title;
    }

    if (seatsField) {
      seatsField.value = this._draftRow.seats_total;
    }

    if (descriptionField) {
      descriptionField.value = this._draftRow.description;
    }

    if (activeField) {
      activeField.checked = this._draftRow.active;
    }

    this._renderDraftPriceWindows();
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

export const initializeTicketTypesController = ({
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

  if (resolvedRoot._ticketTypesController) {
    return resolvedRoot._ticketTypesController;
  }

  const controller = new TicketTypesController({
    addButton: resolvedAddButton,
    currencyInput: resolvedCurrencyInput,
    root: resolvedRoot,
    timezoneInput: resolvedTimezoneInput,
  });
  resolvedRoot._ticketTypesController = controller;
  return controller;
};
