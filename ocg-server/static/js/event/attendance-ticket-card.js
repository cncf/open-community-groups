import { html, nothing } from "/static/vendor/js/lit-all.v3.3.3.min.js";
import { LitWrapper } from "/static/js/common/lit-wrapper.js";
import { toTrimmedString } from "/static/js/common/utils.js";

/**
 * Renders a ticket card from refreshed availability.
 */
class AttendanceTicketCard extends LitWrapper {
  static properties = {
    attendeeApprovalRequired: { type: Boolean },
    canceled: { type: Boolean },
    registrationWindowOpen: { type: Boolean },
    ticket: { type: Object },
    ticketPurchaseAvailable: { type: Boolean },
    waitlistEnabled: { type: Boolean },
  };

  constructor() {
    super();
    this.attendeeApprovalRequired = false;
    this.canceled = false;
    this.registrationWindowOpen = true;
    this.ticket = null;
    this.ticketPurchaseAvailable = false;
    this.waitlistEnabled = false;
  }

  get _eventTicketTypeId() {
    return toTrimmedString(this.ticket?.event_ticket_type_id);
  }

  get _description() {
    return toTrimmedString(this.ticket?.description);
  }

  get _priceLabel() {
    return toTrimmedString(this.ticket?.current_price_label);
  }

  get _title() {
    return toTrimmedString(this.ticket?.title) || "Ticket";
  }

  get _isSellableNow() {
    return (
      this.ticket?.active !== false && this.ticket?.is_sellable_now === true && Boolean(this._priceLabel)
    );
  }

  get _isDisabled() {
    return (
      this.canceled ||
      !this.registrationWindowOpen ||
      this.ticket?.active === false ||
      !this._priceLabel ||
      (!this.attendeeApprovalRequired &&
        !(this.ticketPurchaseAvailable && this._isSellableNow) &&
        !(this.waitlistEnabled && this.ticket?.sold_out === true))
    );
  }

  get _cardStateClasses() {
    return !this._isDisabled
      ? "bg-white cursor-pointer hover:border-primary-300 hover:shadow-sm"
      : "bg-stone-50 cursor-not-allowed opacity-60";
  }

  get _statusLabel() {
    if (this.ticket?.sold_out === true) {
      return "Sold out";
    }

    if (!this.registrationWindowOpen) {
      return "Registration not open";
    }

    return this._isSellableNow ? "Available now" : "Not on sale";
  }

  get _statusDotClass() {
    if (this.ticket?.sold_out === true) {
      return "bg-red-500";
    }

    return this._isDisabled ? "bg-stone-300" : "bg-green-500";
  }

  render() {
    return html`
      <label data-attendance-role="ticket-type-card" class="group block">
        <input
          data-attendance-role="ticket-type-option"
          data-ticket-purchasable=${String(this._isSellableNow)}
          data-ticket-price-minor=${String(this.ticket?.current_price_minor ?? "")}
          data-ticket-sold-out=${String(this.ticket?.sold_out === true)}
          type="radio"
          name="event_ticket_type_id"
          value=${this._eventTicketTypeId}
          class="sr-only"
          ?disabled=${this._isDisabled}
        />
        <div
          data-attendance-role="ticket-type-card-body"
          class="rounded-xl border border-stone-200 p-4 transition group-has-[input:checked]:border-primary-400 group-has-[input:checked]:ring-2 group-has-[input:checked]:ring-primary-200 group-has-[input:focus-visible]:border-primary-500 group-has-[input:focus-visible]:ring-2 group-has-[input:focus-visible]:ring-primary-200 ${
            this._cardStateClasses
          }"
        >
          <div class="grid grid-cols-[1.25rem] items-start gap-x-2.5 gap-y-2">
            <span
              data-attendance-role="ticket-type-indicator"
              aria-hidden="true"
              class="row-start-1 inline-flex h-5 w-5 shrink-0 items-center self-center"
            >
              <span
                class="relative flex h-5 w-5 items-center justify-center rounded-full border border-stone-300 transition-colors group-has-[input:checked]:border-primary-500"
              >
                <span
                  class="hidden h-2.5 w-2.5 rounded-full bg-primary-500 group-has-[input:checked]:block"
                ></span>
              </span>
            </span>
            <div
              data-attendance-role="ticket-type-summary"
              class="row-start-1 flex w-full min-w-0 items-center justify-between gap-2.5"
            >
              <div
                data-attendance-role="ticket-type-title"
                class="min-w-0 truncate text-left text-sm font-semibold text-stone-900"
              >
                ${this._title}
              </div>
              ${
                this._priceLabel
                  ? html`
                      <div
                        data-attendance-role="ticket-type-price-badge"
                        class="inline-flex w-fit shrink-0 self-center rounded-full border border-green-800 bg-green-100 px-2 py-0.5 text-[11px] font-semibold text-green-800"
                      >
                        ${this._priceLabel}
                      </div>
                    `
                  : nothing
              }
            </div>
            ${
              this._description
                ? html`<p
                    data-attendance-role="ticket-type-description"
                    class="col-start-2 form-legend min-w-0"
                  >
                    ${this._description}
                  </p>`
                : nothing
            }
            <div class="col-start-2 flex items-center gap-2 text-xs font-medium">
              <span
                data-attendance-role="ticket-type-status-dot"
                class="inline-flex h-2 w-2 rounded-full ${this._statusDotClass}"
              ></span>
              <span data-attendance-role="ticket-type-status-label" class="text-stone-500">
                ${this._statusLabel}
              </span>
            </div>
          </div>
        </div>
      </label>
    `;
  }
}

if (!customElements.get("attendance-ticket-card")) {
  customElements.define("attendance-ticket-card", AttendanceTicketCard);
}
