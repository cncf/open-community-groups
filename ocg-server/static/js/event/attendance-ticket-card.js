import { html, nothing } from "/static/vendor/js/lit-all.v3.3.3.min.js";
import { LitWrapper } from "/static/js/common/lit-wrapper.js";
import { toTrimmedString } from "/static/js/common/utils.js";
import {
  deriveTicketCardState,
  TICKET_CARD_AVAILABLE_CLASSES,
  TICKET_CARD_UNAVAILABLE_CLASSES,
  TICKET_PRICE_BADGE_CLASSES,
} from "/static/js/event/attendance-ticket-state.js";

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

  render() {
    const state = deriveTicketCardState(this.ticket, {
      attendeeApprovalRequired: this.attendeeApprovalRequired,
      canceled: this.canceled,
      registrationWindowOpen: this.registrationWindowOpen,
      ticketPurchaseAvailable: this.ticketPurchaseAvailable,
      waitlistEnabled: this.waitlistEnabled,
    });
    const cardStateClasses = state.selectable
      ? TICKET_CARD_AVAILABLE_CLASSES.join(" ")
      : TICKET_CARD_UNAVAILABLE_CLASSES.join(" ");

    return html`
      <label data-attendance-role="ticket-type-card" class="group block">
        <input
          data-attendance-role="ticket-type-option"
          data-ticket-purchasable=${String(state.purchasable)}
          data-ticket-price-minor=${String(this.ticket?.current_price_minor ?? "")}
          data-ticket-selectable=${String(state.selectable)}
          data-ticket-sold-out=${String(state.soldOut)}
          type="radio"
          name="event_ticket_type_id"
          value=${this._eventTicketTypeId}
          class="sr-only"
          ?disabled=${!state.selectable}
        />
        <div
          data-attendance-role="ticket-type-card-body"
          class="rounded-xl border border-stone-200 p-4 transition group-has-[input:checked]:border-primary-400 group-has-[input:checked]:ring-2 group-has-[input:checked]:ring-primary-200 group-has-[input:focus-visible]:border-primary-500 group-has-[input:focus-visible]:ring-2 group-has-[input:focus-visible]:ring-primary-200 ${cardStateClasses}"
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
                        class=${TICKET_PRICE_BADGE_CLASSES.join(" ")}
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
                class="inline-flex h-2 w-2 rounded-full ${state.statusClass}"
              ></span>
              <span data-attendance-role="ticket-type-status-label" class="text-stone-500">
                ${state.statusLabel}
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
