import { expect } from "@open-wc/testing";

import {
  applyTicketCardState,
  deriveTicketCardState,
  readTicketCardState,
} from "/static/js/event/attendance-ticket-state.js";
import { resetDom } from "/tests/unit/test-utils/dom.js";

const defaultMeta = {
  attendeeApprovalRequired: false,
  canceled: false,
  registrationWindowOpen: true,
  ticketPurchaseAvailable: true,
  waitlistEnabled: false,
};

const defaultTicket = {
  active: true,
  current_price_label: "EUR 20.00",
  current_price_minor: 2000,
  is_sellable_now: true,
  sold_out: false,
};

describe("attendance ticket state", () => {
  afterEach(() => {
    resetDom();
  });

  it("derives purchasable ticket state", () => {
    const state = deriveTicketCardState(defaultTicket, defaultMeta);

    expect(state).to.deep.equal({
      priceMinor: 2000,
      purchasable: true,
      selectable: true,
      soldOut: false,
      statusClass: "bg-green-500",
      statusLabel: "Available now",
    });
  });

  it("keeps sold-out waitlist tickets selectable", () => {
    const state = deriveTicketCardState(
      { ...defaultTicket, is_sellable_now: false, sold_out: true },
      { ...defaultMeta, ticketPurchaseAvailable: false, waitlistEnabled: true },
    );

    expect(state.selectable).to.equal(true);
    expect(state.purchasable).to.equal(false);
    expect(state.soldOut).to.equal(true);
    expect(state.statusClass).to.equal("bg-red-500");
    expect(state.statusLabel).to.equal("Sold out");
  });

  it("keeps approval selection separate from ticket sales", () => {
    const state = deriveTicketCardState(
      { ...defaultTicket, is_sellable_now: false },
      {
        ...defaultMeta,
        attendeeApprovalRequired: true,
        ticketPurchaseAvailable: false,
      },
    );

    expect(state.selectable).to.equal(true);
    expect(state.purchasable).to.equal(false);
    expect(state.statusClass).to.equal("bg-green-500");
    expect(state.statusLabel).to.equal("Not on sale");
  });

  it("applies disabled, visual, dataset, and status state together", () => {
    document.body.innerHTML = `
      <label data-attendance-role="ticket-type-card">
        <input
          data-attendance-role="ticket-type-option"
          type="radio"
          checked
        />
        <div
          data-attendance-role="ticket-type-card-body"
          class="bg-white cursor-pointer hover:border-primary-300 hover:shadow-sm"
        ></div>
        <span data-attendance-role="ticket-type-status-dot" class="bg-green-500"></span>
        <span data-attendance-role="ticket-type-status-label">Available now</span>
      </label>
    `;
    const option = document.querySelector('[data-attendance-role="ticket-type-option"]');
    const state = deriveTicketCardState(
      { ...defaultTicket, is_sellable_now: false, sold_out: true },
      { ...defaultMeta, ticketPurchaseAvailable: false },
    );

    applyTicketCardState(option, state);

    const card = option.closest('[data-attendance-role="ticket-type-card"]');
    const cardBody = card.querySelector('[data-attendance-role="ticket-type-card-body"]');
    expect(option.disabled).to.equal(true);
    expect(option.checked).to.equal(false);
    expect(option.dataset.ticketSelectable).to.equal("false");
    expect(option.dataset.ticketSoldOut).to.equal("true");
    expect(cardBody.classList.contains("cursor-not-allowed")).to.equal(true);
    expect(cardBody.classList.contains("hover:shadow-sm")).to.equal(false);
    expect(card.querySelector('[data-attendance-role="ticket-type-status-dot"]')).to.have.class(
      "bg-red-500",
    );
    expect(card.querySelector('[data-attendance-role="ticket-type-status-label"]')).to.have.text(
      "Sold out",
    );
  });

  it("reads cached eligibility without re-deriving it", () => {
    const option = document.createElement("input");
    option.dataset.ticketPurchasable = "false";
    option.dataset.ticketPriceMinor = "2500";
    option.dataset.ticketSelectable = "true";
    option.dataset.ticketSoldOut = "true";
    option.disabled = true;

    expect(readTicketCardState(option)).to.deep.equal({
      priceMinor: "2500",
      purchasable: false,
      selectable: true,
      soldOut: true,
    });
  });
});
