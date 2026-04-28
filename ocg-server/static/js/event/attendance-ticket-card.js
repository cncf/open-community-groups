import { html, nothing } from "/static/vendor/js/lit-all.v3.3.1.min.js";
import { LitWrapper } from "/static/js/common/lit-wrapper.js";
import { toTrimmedString } from "/static/js/common/utils.js";

/**
 * Renders a ticket card from refreshed availability.
 */
class AttendanceTicketCard extends LitWrapper {
  static properties = {
    canceled: { type: Boolean },
    ticket: { type: Object },
    ticketPurchaseAvailable: { type: Boolean },
  };

  constructor() {
    super();
    this.canceled = false;
    this.ticket = null;
    this.ticketPurchaseAvailable = false;
  }

  get _eventTicketTypeId() {
    return toTrimmedString(this.ticket?.event_ticket_type_id);
  }

  get _priceLabel() {
    return toTrimmedString(this.ticket?.current_price_label);
  }

  get _title() {
    return toTrimmedString(this.ticket?.title) || "Ticket";
  }

  get _isSellableNow() {
    return this.ticket?.is_sellable_now === true && Boolean(this._priceLabel);
  }

  get _isDisabled() {
    return this.canceled || !this.ticketPurchaseAvailable || !this._isSellableNow;
  }

  get _cardStateClasses() {
    return this._isSellableNow
      ? "bg-white cursor-pointer hover:border-primary-300"
      : "bg-stone-50 cursor-not-allowed opacity-60";
  }

  get _statusLabel() {
    if (this.ticket?.sold_out === true) {
      return "Sold out";
    }

    return this._isSellableNow ? "Available now" : "Not on sale";
  }

  render() {
    return html`
      <label data-attendance-role="ticket-type-card" class="group block">
        <input
          data-attendance-role="ticket-type-option"
          data-ticket-purchasable=${String(this._isSellableNow)}
          type="radio"
          name="event_ticket_type_id"
          value=${this._eventTicketTypeId}
          class="sr-only"
          ?disabled=${this._isDisabled}
        />
        <div
          data-attendance-role="ticket-type-card-body"
          class="rounded-xl border border-stone-200 p-4 transition group-has-[input:checked]:border-primary-400 group-has-[input:checked]:ring-2 group-has-[input:checked]:ring-primary-200 ${this
            ._cardStateClasses}"
        >
          <div
            data-attendance-role="ticket-type-summary"
            class="flex min-w-0 items-center justify-between gap-2.5"
          >
            <div
              data-attendance-role="ticket-type-title"
              class="min-w-0 truncate text-left text-sm font-semibold text-stone-900"
            >
              ${this._title}
            </div>
            ${this._priceLabel
              ? html`
                  <div
                    data-attendance-role="ticket-type-price-badge"
                    class="inline-flex w-fit shrink-0 self-center rounded-full border border-green-800 bg-green-100 px-2 py-0.5 text-[11px] font-semibold text-green-800"
                  >
                    ${this._priceLabel}
                  </div>
                `
              : nothing}
          </div>
          <div class="mt-2 text-xs font-medium">
            <span data-attendance-role="ticket-type-status-label" class="text-stone-500">
              ${this._statusLabel}
            </span>
          </div>
        </div>
      </label>
    `;
  }
}

if (!customElements.get("attendance-ticket-card")) {
  customElements.define("attendance-ticket-card", AttendanceTicketCard);
}
