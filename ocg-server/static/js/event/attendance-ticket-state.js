import { toTrimmedString } from "/static/js/common/utils.js";

export const TICKET_CARD_AVAILABLE_CLASSES = [
  "bg-white",
  "cursor-pointer",
  "hover:border-primary-300",
  "hover:shadow-sm",
];
export const TICKET_CARD_UNAVAILABLE_CLASSES = ["bg-stone-50", "cursor-not-allowed", "opacity-60"];
export const TICKET_PRICE_BADGE_CLASSES = [
  "inline-flex",
  "w-fit",
  "shrink-0",
  "self-center",
  "rounded-full",
  "border",
  "border-green-800",
  "bg-green-100",
  "px-2",
  "py-0.5",
  "text-[11px]",
  "font-semibold",
  "uppercase",
  "text-green-800",
];
export const TICKET_STATUS_CLASSES = ["bg-green-500", "bg-red-500", "bg-stone-300"];

/**
 * Applies canonical availability state to a ticket option and its card.
 * @param {HTMLInputElement} option Ticket option input.
 * @param {object} state Canonical ticket state.
 * @returns {void}
 */
export const applyTicketCardState = (option, state) => {
  const card = option.closest('[data-attendance-role="ticket-type-card"]');
  const cardBody = card?.querySelector('[data-attendance-role="ticket-type-card-body"]');
  const statusDot = card?.querySelector('[data-attendance-role="ticket-type-status-dot"]');
  const statusLabel = card?.querySelector('[data-attendance-role="ticket-type-status-label"]');

  option.dataset.ticketPurchasable = String(state.purchasable);
  option.dataset.ticketSelectable = String(state.selectable);
  option.dataset.ticketSoldOut = String(state.soldOut);
  if (state.priceMinor !== undefined) {
    option.dataset.ticketPriceMinor = String(state.priceMinor ?? "");
  }
  option.disabled = !state.selectable;
  if (!state.selectable && option.checked) {
    option.checked = false;
  }

  if (cardBody instanceof HTMLElement) {
    TICKET_CARD_AVAILABLE_CLASSES.forEach((className) => {
      cardBody.classList.toggle(className, state.selectable);
    });
    TICKET_CARD_UNAVAILABLE_CLASSES.forEach((className) => {
      cardBody.classList.toggle(className, !state.selectable);
    });
  }

  if (statusDot instanceof HTMLElement && state.statusClass) {
    statusDot.classList.remove(...TICKET_STATUS_CLASSES);
    statusDot.classList.add(state.statusClass);
  }
  if (statusLabel instanceof HTMLElement && state.statusLabel) {
    statusLabel.textContent = state.statusLabel;
  }
};

/**
 * Derives canonical ticket-card state from availability and event metadata.
 * @param {object} ticket Ticket availability payload.
 * @param {object} meta Event attendance metadata.
 * @returns {object} Canonical ticket-card state.
 */
export const deriveTicketCardState = (ticket, meta) => {
  const hasCurrentPrice = Boolean(toTrimmedString(ticket?.current_price_label));
  const isActive = ticket?.active !== false;
  const purchasable = isActive && ticket?.is_sellable_now === true && hasCurrentPrice;
  const soldOut = ticket?.sold_out === true;
  const approvalSelectable = meta.attendeeApprovalRequired && isActive && hasCurrentPrice;
  const waitlistSelectable = meta.waitlistEnabled && isActive && hasCurrentPrice && soldOut;
  const selectable =
    !meta.canceled &&
    meta.registrationWindowOpen &&
    (approvalSelectable || (meta.ticketPurchaseAvailable && purchasable) || waitlistSelectable);

  let statusClass = selectable ? "bg-green-500" : "bg-stone-300";
  let statusLabel = purchasable ? "Available now" : "Not on sale";
  if (soldOut) {
    statusClass = "bg-red-500";
    statusLabel = "Sold out";
  } else if (!meta.registrationWindowOpen) {
    statusLabel = "Registration not open";
  }

  return {
    priceMinor: ticket?.current_price_minor,
    purchasable,
    selectable,
    soldOut,
    statusClass,
    statusLabel,
  };
};

/**
 * Reads canonical ticket state from server-rendered or refreshed option data.
 * @param {HTMLInputElement} option Ticket option input.
 * @returns {object} Canonical state available in the option dataset.
 */
export const readTicketCardState = (option) => ({
  priceMinor: option.dataset.ticketPriceMinor,
  purchasable: option.dataset.ticketPurchasable === "true",
  selectable:
    option.dataset.ticketSelectable === undefined
      ? !option.disabled
      : option.dataset.ticketSelectable === "true",
  soldOut: option.dataset.ticketSoldOut === "true",
});
