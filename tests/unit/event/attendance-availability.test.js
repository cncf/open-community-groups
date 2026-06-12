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
    expect(
      document.querySelector('[data-attendance-role="ticket-type-status-label"]')?.textContent,
    ).to.equal("Available now");
    expect(
      document.querySelector('[data-attendance-role="ticket-type-price-badge"]')?.textContent,
    ).to.equal("EUR 20.00");
  });
});
