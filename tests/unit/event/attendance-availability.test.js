import { expect } from "@open-wc/testing";

import {
  fetchAttendanceAvailability,
  getAvailabilityStringValue,
  isFiniteNumberValue,
  renderAttendanceAvailability,
} from "/static/js/event/attendance-availability.js";
import { resetDom } from "/tests/unit/test-utils/dom.js";
import { mockFetch } from "/tests/unit/test-utils/network.js";

describe("attendance availability", () => {
  afterEach(() => {
    resetDom();
  });

  it("normalizes availability payload values", () => {
    // Availability helpers normalize primitive payload values.
    expect(getAvailabilityStringValue("  EUR 20.00  ")).to.equal("EUR 20.00");
    expect(getAvailabilityStringValue(null)).to.equal("");
    expect(isFiniteNumberValue("10")).to.equal(true);
    expect(isFiniteNumberValue("not-a-number")).to.equal(false);
  });

  it("fetches public attendance availability", async () => {
    // Mock a public availability endpoint response.
    const fetchMock = mockFetch({
      response: {
        ok: true,
        async json() {
          return { capacity: 10 };
        },
      },
    });
    const container = document.createElement("div");
    container.dataset.availabilityUrl = "/events/test/availability";

    try {
      // Fetch availability from the container endpoint.
      const availability = await fetchAttendanceAvailability(container);

      expect(availability).to.deep.equal({ capacity: 10 });
      expect(fetchMock.calls[0][0]).to.equal("/events/test/availability");
      expect(fetchMock.calls[0][1]).to.deep.include({
        cache: "no-store",
        credentials: "same-origin",
      });
    } finally {
      fetchMock.restore();
    }
  });

  it("renders availability metadata, captions, and ticket state", () => {
    // Build a minimal attendance fixture with public counters and one ticket.
    document.body.innerHTML = `
      <span data-availability-capacity></span>
      <span data-availability-remaining></span>
      <span data-availability-waitlist></span>
      <span data-availability-caption="capacity" class="hidden"></span>
      <span data-availability-caption="remaining" class="hidden"></span>
      <span data-availability-caption="waitlist" class="hidden"></span>
      <span data-availability-sold-out-ribbon class="hidden"></span>
      <div data-attendance-container>
        <div data-attendance-role="ticket-type-list">
          <label data-attendance-role="ticket-type-card">
            <input data-attendance-role="ticket-type-option" value="ticket-1" />
            <div data-attendance-role="ticket-type-card-body" class="bg-stone-50"></div>
            <div data-attendance-role="ticket-type-summary"></div>
            <span data-attendance-role="ticket-type-status-dot" class="bg-stone-300"></span>
            <span data-attendance-role="ticket-type-status-label">Not on sale</span>
          </label>
        </div>
      </div>
    `;

    // Render fresh availability into the server-rendered attendance shell.
    const container = document.querySelector("[data-attendance-container]");
    renderAttendanceAvailability(container, {
      attendee_approval_required: false,
      capacity: 10,
      canceled: false,
      has_sellable_ticket_types: true,
      is_live: false,
      is_past: false,
      is_ticketed: true,
      remaining_capacity: 4,
      ticket_types: [
        {
          current_price_label: "EUR 20.00",
          event_ticket_type_id: "ticket-1",
          is_sellable_now: true,
          sold_out: false,
        },
      ],
      waitlist_count: 0,
      waitlist_enabled: true,
    });

    // Availability updates metadata, public counters, and ticket controls.
    expect(container.dataset.capacity).to.equal("10");
    expect(container.dataset.remainingCapacity).to.equal("4");
    expect(document.querySelector("[data-availability-capacity]")?.textContent).to.equal("10");
    expect(document.querySelector("[data-availability-remaining]")?.textContent).to.equal("4");
    expect(
      document.querySelector('[data-attendance-role="ticket-type-option"]')?.disabled,
    ).to.equal(false);
    const ticketCardBody = document.querySelector(
      '[data-attendance-role="ticket-type-card-body"]',
    );
    expect(ticketCardBody.classList.contains("hover:border-primary-300")).to.equal(true);
    expect(ticketCardBody.classList.contains("hover:shadow-sm")).to.equal(true);
    expect(
      document.querySelector('[data-attendance-role="ticket-type-status-label"]')?.textContent,
    ).to.equal("Available now");
    expect(
      document.querySelector('[data-attendance-role="ticket-type-price-badge"]')?.textContent,
    ).to.equal("EUR 20.00");
  });

  it("renders closed registration windows into messages and disabled tickets", () => {
    // Build a minimal attendance fixture with a registration-window message.
    document.body.innerHTML = `
      <div data-registration-window-message-display class="hidden"></div>
      <span data-availability-caption="capacity" class="hidden"></span>
      <div data-attendance-container>
        <div data-attendance-role="ticket-type-list">
          <label data-attendance-role="ticket-type-card">
            <input
              data-attendance-role="ticket-type-option"
              type="radio"
              name="event_ticket_type_id"
              value="ticket-1"
              class="sr-only"
              checked
            />
            <div data-attendance-role="ticket-type-card-body" class="bg-white cursor-pointer hover:border-primary-300 hover:shadow-sm"></div>
            <div data-attendance-role="ticket-type-summary"></div>
            <span data-attendance-role="ticket-type-status-dot" class="bg-green-500"></span>
            <span data-attendance-role="ticket-type-status-label">Available now</span>
          </label>
        </div>
      </div>
    `;

    // Render a closed registration window over otherwise sellable tickets.
    const container = document.querySelector("[data-attendance-container]");
    const ticketOption = container.querySelector('[data-attendance-role="ticket-type-option"]');
    const ticketStatusLabel = container.querySelector(
      '[data-attendance-role="ticket-type-status-label"]',
    );
    const ticketCardBody = container.querySelector(
      '[data-attendance-role="ticket-type-card-body"]',
    );
    renderAttendanceAvailability(container, {
      attendee_approval_required: false,
      capacity: null,
      canceled: false,
      has_sellable_ticket_types: true,
      is_live: false,
      is_past: false,
      is_ticketed: true,
      registration_window_message: "Registration closed May 1, 2099.",
      registration_window_open: false,
      registration_window_unavailable_title: "Registration closed May 1, 2099.",
      remaining_capacity: null,
      ticket_types: [
        {
          current_price_label: "EUR 20.00",
          event_ticket_type_id: "ticket-1",
          is_sellable_now: true,
          sold_out: false,
        },
      ],
      waitlist_count: 0,
      waitlist_enabled: false,
    });

    // Closed windows update metadata, show the message and disable ticket selection.
    const message = document.querySelector("[data-registration-window-message-display]");
    expect(container.dataset.registrationWindowOpen).to.equal("false");
    expect(container.dataset.registrationWindowUnavailableTitle).to.equal(
      "Registration closed May 1, 2099.",
    );
    expect(message.textContent).to.equal("Registration closed May 1, 2099.");
    expect(message.classList.contains("hidden")).to.equal(false);
    expect(ticketOption.disabled).to.equal(true);
    expect(ticketOption.checked).to.equal(false);
    expect(ticketCardBody.classList.contains("hover:border-primary-300")).to.equal(false);
    expect(ticketCardBody.classList.contains("hover:shadow-sm")).to.equal(false);
    expect(ticketStatusLabel.textContent).to.equal("Registration not open");
  });

  it("renders appended ticket cards as disabled when registration is closed", async () => {
    // Build a minimal attendance fixture where cached markup has no ticket cards.
    document.body.innerHTML = `
      <div data-registration-window-message-display class="hidden"></div>
      <span data-availability-caption="capacity" class="hidden"></span>
      <div data-attendance-container>
        <div data-attendance-role="ticket-type-list"></div>
      </div>
    `;

    // Render a newly available ticket after the registration window has closed.
    const container = document.querySelector("[data-attendance-container]");
    renderAttendanceAvailability(container, {
      attendee_approval_required: false,
      capacity: null,
      canceled: false,
      has_sellable_ticket_types: true,
      is_live: false,
      is_past: false,
      is_ticketed: true,
      registration_window_message: "Registration closed May 1, 2099.",
      registration_window_open: false,
      registration_window_unavailable_title: "Registration closed May 1, 2099.",
      remaining_capacity: null,
      ticket_types: [
        {
          current_price_label: "EUR 20.00",
          event_ticket_type_id: "ticket-1",
          is_sellable_now: true,
          sold_out: false,
          title: "General admission",
        },
      ],
      waitlist_count: 0,
      waitlist_enabled: false,
    });

    const card = container.querySelector("attendance-ticket-card");
    await card.updateComplete;

    // Appended cards should use the same closed-registration state as cached cards.
    const ticketOption = card.querySelector('[data-attendance-role="ticket-type-option"]');
    const ticketCardBody = card.querySelector('[data-attendance-role="ticket-type-card-body"]');
    const ticketStatusLabel = card.querySelector(
      '[data-attendance-role="ticket-type-status-label"]',
    );
    expect(ticketOption.disabled).to.equal(true);
    expect(ticketCardBody.classList.contains("cursor-not-allowed")).to.equal(true);
    expect(ticketStatusLabel.textContent.trim()).to.equal("Registration not open");
  });
});
