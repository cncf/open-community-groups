import { html, repeat } from "/static/vendor/js/lit-all.v3.3.1.min.js";
import { LitWrapper } from "/static/js/common/lit-wrapper.js";

const DEFAULT_CURRENCY_PLACEHOLDER = "USD";

/**
 * Safely parses a JSON attribute.
 * @param {*} value Raw attribute value
 * @param {*} fallback Fallback value
 * @returns {*}
 */
const parseJsonAttribute = (value, fallback) => {
  if (Array.isArray(value)) {
    return value;
  }

  if (typeof value !== "string" || value.trim().length === 0) {
    return fallback;
  }

  try {
    return JSON.parse(value);
  } catch (_) {
    return fallback;
  }
};

/**
 * Normalizes a boolean value.
 * @param {*} value Raw value
 * @param {boolean} fallback Fallback value
 * @returns {boolean}
 */
const toBoolean = (value, fallback = false) => {
  if (typeof value === "boolean") {
    return value;
  }

  if (typeof value === "string") {
    const normalized = value.trim().toLowerCase();
    if (normalized === "true") {
      return true;
    }
    if (normalized === "false") {
      return false;
    }
  }

  return fallback;
};

/**
 * Normalizes a trimmed string.
 * @param {*} value Raw value
 * @returns {string}
 */
const toTrimmedString = (value) => String(value || "").trim();

/**
 * Resolves the event currency from the shared event form.
 * @returns {string}
 */
const resolveEventCurrencyCode = () => {
  const currencyField = document.getElementById("payment_currency_code");
  const currencyCode = toTrimmedString(currencyField?.value).toUpperCase();

  return currencyCode || DEFAULT_CURRENCY_PLACEHOLDER;
};

/**
 * Resolves the number of fraction digits for a currency.
 * @param {string} currencyCode ISO currency code
 * @returns {number}
 */
const resolveCurrencyFractionDigits = (currencyCode) => {
  try {
    return new Intl.NumberFormat("en", {
      currency: currencyCode,
      style: "currency",
    }).resolvedOptions().maximumFractionDigits;
  } catch (_) {
    return 2;
  }
};

/**
 * Formats a minor-unit amount for a currency input.
 * @param {number} amountMinor Amount in minor units
 * @param {string} currencyCode ISO currency code
 * @returns {string}
 */
const formatMinorUnitsForInput = (amountMinor, currencyCode) => {
  if (!Number.isFinite(amountMinor)) {
    return "";
  }

  const fractionDigits = resolveCurrencyFractionDigits(currencyCode);
  if (fractionDigits === 0) {
    return String(amountMinor);
  }

  const divisor = 10 ** fractionDigits;
  const isNegative = amountMinor < 0;
  const normalizedAmount = Math.abs(amountMinor);
  const whole = Math.floor(normalizedAmount / divisor);
  const fraction = String(normalizedAmount % divisor).padStart(fractionDigits, "0");

  return `${isNegative ? "-" : ""}${whole}.${fraction}`;
};

/**
 * Parses a currency input string into minor units.
 * @param {string} value Currency input value
 * @param {string} currencyCode ISO currency code
 * @returns {number|null}
 */
const parseCurrencyInputToMinorUnits = (value, currencyCode) => {
  const trimmedValue = toTrimmedString(value);
  if (!trimmedValue) {
    return null;
  }

  const match = trimmedValue.match(/^(-)?(?:(\d+)(?:\.(\d+))?|\.(\d+))$/);
  if (!match) {
    return null;
  }

  const fractionDigits = resolveCurrencyFractionDigits(currencyCode);
  const sign = match[1] ? -1 : 1;
  const wholePart = match[2] || "0";
  const fractionPart = match[3] || match[4] || "";

  if (fractionPart.length > fractionDigits) {
    return null;
  }

  const paddedFraction = fractionPart.padEnd(fractionDigits, "0") || "0";
  const divisor = 10 ** fractionDigits;
  const wholeMinor = Number.parseInt(wholePart, 10) * divisor;
  const fractionMinor = fractionDigits === 0 ? 0 : Number.parseInt(paddedFraction, 10);

  return sign * (wholeMinor + fractionMinor);
};

/**
 * Returns a step value for currency amount inputs.
 * @param {string} currencyCode ISO currency code
 * @returns {string}
 */
const resolveCurrencyInputStep = (currencyCode) => {
  const fractionDigits = resolveCurrencyFractionDigits(currencyCode);
  if (fractionDigits === 0) {
    return "1";
  }

  return `0.${"0".repeat(fractionDigits - 1)}1`;
};

/**
 * Returns an example placeholder for currency amount inputs.
 * @param {string} currencyCode ISO currency code
 * @returns {string}
 */
const resolveCurrencyInputPlaceholder = (currencyCode) => {
  const fractionDigits = resolveCurrencyFractionDigits(currencyCode);
  return fractionDigits === 0 ? "5000" : `25.${"0".repeat(fractionDigits)}`;
};

/**
 * Resolves the event timezone from the shared event form.
 * @returns {string}
 */
const resolveEventTimezone = () => {
  const timezoneField = document.querySelector('[name="timezone"]');
  return typeof timezoneField?.value === "string" ? timezoneField.value.trim() : "";
};

/**
 * Builds a datetime-local string from an ISO timestamp in the selected timezone.
 * @param {string} value ISO timestamp
 * @param {string} timezone IANA timezone
 * @returns {string}
 */
const toDateTimeLocalInTimezone = (value, timezone) => {
  if (typeof value !== "string" || value.trim().length === 0) {
    return "";
  }

  const date = new Date(value);
  if (Number.isNaN(date.getTime())) {
    return "";
  }

  if (typeof timezone !== "string" || timezone.trim().length === 0) {
    return value.slice(0, 16);
  }

  try {
    const formatter = new Intl.DateTimeFormat("en-CA", {
      timeZone: timezone,
      year: "numeric",
      month: "2-digit",
      day: "2-digit",
      hour: "2-digit",
      minute: "2-digit",
      hourCycle: "h23",
    });
    const parts = formatter.formatToParts(date);
    const byType = Object.fromEntries(
      parts.filter((part) => part.type !== "literal").map((part) => [part.type, part.value]),
    );
    return `${byType.year}-${byType.month}-${byType.day}T${byType.hour}:${byType.minute}`;
  } catch (_) {
    return value.slice(0, 16);
  }
};

/**
 * Resolves the offset between UTC and a target timezone for a given date.
 * @param {Date} date Date instance
 * @param {string} timezone IANA timezone
 * @returns {number}
 */
const getTimeZoneOffsetMs = (date, timezone) => {
  const formatter = new Intl.DateTimeFormat("en-CA", {
    timeZone: timezone,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit",
    hourCycle: "h23",
  });
  const parts = formatter.formatToParts(date);
  const byType = Object.fromEntries(
    parts.filter((part) => part.type !== "literal").map((part) => [part.type, part.value]),
  );
  const utcMs = Date.UTC(
    Number.parseInt(byType.year, 10),
    Number.parseInt(byType.month, 10) - 1,
    Number.parseInt(byType.day, 10),
    Number.parseInt(byType.hour, 10),
    Number.parseInt(byType.minute, 10),
    Number.parseInt(byType.second, 10),
  );

  return utcMs - date.getTime();
};

/**
 * Converts a datetime-local value into UTC ISO using the selected timezone.
 * @param {string} value Datetime-local string
 * @param {string} timezone IANA timezone
 * @returns {string|null}
 */
const toUtcIsoInTimezone = (value, timezone) => {
  const trimmedValue = toTrimmedString(value);
  if (!trimmedValue) {
    return null;
  }

  if (typeof timezone !== "string" || timezone.trim().length === 0) {
    return trimmedValue;
  }

  const [datePart, timePart] = trimmedValue.split("T");
  if (!datePart || !timePart) {
    return trimmedValue;
  }

  const [year, month, day] = datePart.split("-").map((part) => Number.parseInt(part, 10));
  const [hour, minute] = timePart.split(":").map((part) => Number.parseInt(part, 10));
  if ([year, month, day, hour, minute].some((part) => Number.isNaN(part))) {
    return trimmedValue;
  }

  try {
    const guessMs = Date.UTC(year, month - 1, day, hour, minute, 0);
    const guessDate = new Date(guessMs);
    const offsetMs = getTimeZoneOffsetMs(guessDate, timezone);
    return new Date(guessMs - offsetMs).toISOString();
  } catch (_) {
    return trimmedValue;
  }
};

/**
 * Creates a stable row key.
 * @param {number} nextId Local counter
 * @returns {number}
 */
const nextLocalId = (nextId) => nextId;

/**
 * Shared base for ticketing editors.
 * @extends LitWrapper
 */
class TicketingEditorBase extends LitWrapper {
  static properties = {
    disabled: { type: Boolean, reflect: true },
  };

  constructor() {
    super();
    this.disabled = false;
    this.fieldNamePrefix = "";
    this._handleCurrencyFieldChange = this._handleCurrencyFieldChange.bind(this);
    this._nextId = 0;
    this.presenceFieldName = "";
  }

  connectedCallback() {
    super.connectedCallback();
    document
      .getElementById("payment_currency_code")
      ?.addEventListener("input", this._handleCurrencyFieldChange);
  }

  disconnectedCallback() {
    document
      .getElementById("payment_currency_code")
      ?.removeEventListener("input", this._handleCurrencyFieldChange);
    super.disconnectedCallback();
  }

  /**
   * Returns a new local row id.
   * @returns {number}
   */
  _nextRowId() {
    const rowId = nextLocalId(this._nextId);
    this._nextId += 1;
    return rowId;
  }

  /**
   * Emits a change event for dependent UI like waitlist controls.
   * @param {string} eventName Event name
   * @param {object} detail Event detail
   */
  _emitChange(eventName, detail) {
    this.dispatchEvent(
      new CustomEvent(eventName, {
        bubbles: true,
        composed: true,
        detail,
      }),
    );
  }

  /**
   * Returns the active event currency code.
   * @returns {string}
   */
  _currencyCode() {
    return resolveEventCurrencyCode();
  }

  /**
   * Returns the currency input placeholder for the event currency.
   * @returns {string}
   */
  _currencyInputPlaceholder() {
    return resolveCurrencyInputPlaceholder(this._currencyCode());
  }

  /**
   * Returns the currency input step for the event currency.
   * @returns {string}
   */
  _currencyInputStep() {
    return resolveCurrencyInputStep(this._currencyCode());
  }

  /**
   * Returns a label suffix for the event currency.
   * @returns {string}
   */
  _currencyLabelSuffix() {
    return `(${this._currencyCode()})`;
  }

  /**
   * Renders a hidden input field.
   * @param {string} name Input name
   * @param {string} value Input value
   * @returns {import("/static/vendor/js/lit-all.v3.3.1.min.js").TemplateResult}
   */
  _renderHiddenInput(name, value) {
    return html`<input type="hidden" name="${name}" .value=${value} />`;
  }

  /**
   * Renders the presence flag for the current editor.
   * @returns {import("/static/vendor/js/lit-all.v3.3.1.min.js").TemplateResult|string}
   */
  _renderPresenceField() {
    if (this.disabled || !this.presenceFieldName) {
      return "";
    }

    return this._renderHiddenInput(this.presenceFieldName, "true");
  }

  /**
   * Handles changes to the shared event currency input.
   */
  _handleCurrencyFieldChange() {
    this.requestUpdate();
  }
}

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
   * Replaces ticket types from external scripts.
   * @param {Array<object>} ticketTypes Ticket types payload
   */
  setTicketTypes(ticketTypes) {
    this.ticketTypes = ticketTypes;
    this._applyTicketTypes(ticketTypes);
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
   * Applies initial ticket types payload.
   * @param {*} ticketTypes Ticket types payload
   */
  _applyTicketTypes(ticketTypes) {
    const parsedTicketTypes = parseJsonAttribute(ticketTypes, []);
    this._rows = this._normalizeTicketTypes(parsedTicketTypes);
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
   * Normalizes incoming ticket types.
   * @param {*} ticketTypes Raw payload
   * @returns {Array<object>}
   */
  _normalizeTicketTypes(ticketTypes) {
    const timezone = resolveEventTimezone();
    if (!Array.isArray(ticketTypes) || ticketTypes.length === 0) {
      return [];
    }

    const normalized = ticketTypes.map((ticketType) => {
      const priceWindows = Array.isArray(ticketType?.price_windows)
        ? ticketType.price_windows.map((windowRow) => ({
            _row_id: this._nextRowId(),
            amount:
              windowRow?.amount_minor === null || windowRow?.amount_minor === undefined
                ? ""
                : formatMinorUnitsForInput(windowRow.amount_minor, this._currencyCode()),
            ends_at: toDateTimeLocalInTimezone(windowRow?.ends_at || "", timezone),
            event_ticket_price_window_id: toTrimmedString(windowRow?.event_ticket_price_window_id),
            starts_at: toDateTimeLocalInTimezone(windowRow?.starts_at || "", timezone),
          }))
        : [];

      return {
        _row_id: this._nextRowId(),
        active: toBoolean(ticketType?.active, true),
        description: String(ticketType?.description || ""),
        event_ticket_type_id: toTrimmedString(ticketType?.event_ticket_type_id),
        price_windows: priceWindows.length > 0 ? priceWindows : [this._createEmptyPriceWindow()],
        seats_total:
          ticketType?.seats_total === null || ticketType?.seats_total === undefined
            ? ""
            : String(ticketType.seats_total),
        title: String(ticketType?.title || ""),
      };
    });

    return normalized;
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
   * Renders hidden nested inputs for the current ticket types.
   * @returns {import("/static/vendor/js/lit-all.v3.3.1.min.js").TemplateResult|string}
   */
  _renderHiddenFields() {
    if (this.disabled) {
      return "";
    }

    const timezone = resolveEventTimezone();
    const currencyCode = this._currencyCode();
    return html`
      ${this._renderPresenceField()}
      ${this._rows.map((row, index) => {
        const rowPrefix = `${this.fieldNamePrefix}[${index}]`;
        const description = toTrimmedString(row.description);
        const seatsTotal = Number.parseInt(row.seats_total, 10);

        return html`
          ${this._renderHiddenInput(`${rowPrefix}[active]`, row.active ? "true" : "false")}
          ${this._renderHiddenInput(`${rowPrefix}[order]`, String(index + 1))}
          ${row.price_windows.map((windowRow, windowIndex) => {
            const windowPrefix = `${rowPrefix}[price_windows][${windowIndex}]`;
            const amountMinor = parseCurrencyInputToMinorUnits(windowRow.amount, currencyCode);
            const endsAt = toUtcIsoInTimezone(windowRow.ends_at, timezone);
            const startsAt = toUtcIsoInTimezone(windowRow.starts_at, timezone);
            const windowId = toTrimmedString(windowRow.event_ticket_price_window_id);

            return html`
              ${amountMinor === null
                ? ""
                : this._renderHiddenInput(`${windowPrefix}[amount_minor]`, String(amountMinor))}
              ${endsAt ? this._renderHiddenInput(`${windowPrefix}[ends_at]`, endsAt) : ""}
              ${windowId
                ? this._renderHiddenInput(`${windowPrefix}[event_ticket_price_window_id]`, windowId)
                : ""}
              ${startsAt ? this._renderHiddenInput(`${windowPrefix}[starts_at]`, startsAt) : ""}
            `;
          })}
          ${this._renderHiddenInput(`${rowPrefix}[title]`, row.title.trim())}
          ${description ? this._renderHiddenInput(`${rowPrefix}[description]`, description) : ""}
          ${toTrimmedString(row.event_ticket_type_id)
            ? this._renderHiddenInput(
                `${rowPrefix}[event_ticket_type_id]`,
                toTrimmedString(row.event_ticket_type_id),
              )
            : ""}
          ${Number.isFinite(seatsTotal)
            ? this._renderHiddenInput(`${rowPrefix}[seats_total]`, String(seatsTotal))
            : ""}
        `;
      })}
    `;
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
}

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
    this._rows = this._normalizeDiscountCodes(parsedDiscountCodes);
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
   * Normalizes incoming discount codes.
   * @param {*} discountCodes Raw payload
   * @returns {Array<object>}
   */
  _normalizeDiscountCodes(discountCodes) {
    const timezone = resolveEventTimezone();
    if (!Array.isArray(discountCodes) || discountCodes.length === 0) {
      return [];
    }

    return discountCodes
      .map((discountCode) => ({
        _row_id: this._nextRowId(),
        active: toBoolean(discountCode?.active, true),
        amount:
          discountCode?.amount_minor === null || discountCode?.amount_minor === undefined
            ? ""
            : formatMinorUnitsForInput(discountCode.amount_minor, this._currencyCode()),
        available:
          discountCode?.available === null || discountCode?.available === undefined
            ? ""
            : String(discountCode.available),
        available_dirty: false,
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

    const timezone = resolveEventTimezone();
    const currencyCode = this._currencyCode();
    return html`
      ${this._renderPresenceField()}
      ${this._rows.map((row, index) => {
        const rowPrefix = `${this.fieldNamePrefix}[${index}]`;
        const amountMinor = parseCurrencyInputToMinorUnits(row.amount, currencyCode);
        const available = Number.parseInt(row.available, 10);
        const discountCodeId = toTrimmedString(row.event_discount_code_id);
        const endsAt = toUtcIsoInTimezone(row.ends_at, timezone);
        const percentage = Number.parseInt(row.percentage, 10);
        const startsAt = toUtcIsoInTimezone(row.starts_at, timezone);
        const totalAvailable = Number.parseInt(row.total_available, 10);

        return html`
          ${this._renderHiddenInput(`${rowPrefix}[active]`, row.active ? "true" : "false")}
          ${this._renderHiddenInput(`${rowPrefix}[code]`, row.code.trim().toUpperCase())}
          ${this._renderHiddenInput(`${rowPrefix}[kind]`, row.kind)}
          ${this._renderHiddenInput(`${rowPrefix}[title]`, row.title.trim())}
          ${row.available_dirty && Number.isFinite(available)
            ? this._renderHiddenInput(`${rowPrefix}[available]`, String(available))
            : ""}
          ${row.kind === "fixed_amount" && amountMinor !== null
            ? this._renderHiddenInput(`${rowPrefix}[amount_minor]`, String(amountMinor))
            : ""}
          ${endsAt ? this._renderHiddenInput(`${rowPrefix}[ends_at]`, endsAt) : ""}
          ${discountCodeId
            ? this._renderHiddenInput(`${rowPrefix}[event_discount_code_id]`, discountCodeId)
            : ""}
          ${row.kind === "percentage" && Number.isFinite(percentage)
            ? this._renderHiddenInput(`${rowPrefix}[percentage]`, String(percentage))
            : ""}
          ${startsAt ? this._renderHiddenInput(`${rowPrefix}[starts_at]`, startsAt) : ""}
          ${Number.isFinite(totalAvailable)
            ? this._renderHiddenInput(`${rowPrefix}[total_available]`, String(totalAvailable))
            : ""}
        `;
      })}
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
}

if (!customElements.get("ticket-types-editor")) {
  customElements.define("ticket-types-editor", TicketTypesEditor);
}

if (!customElements.get("discount-codes-editor")) {
  customElements.define("discount-codes-editor", DiscountCodesEditor);
}
