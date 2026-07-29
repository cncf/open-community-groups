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
            <div data-attendance-role="ticket-type-summary">
              <div data-attendance-role="ticket-type-title">Old admission</div>
            </div>
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
      is_simple_rsvp: false,
      remaining_capacity: 4,
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
      waitlist_enabled: true,
    });

    // Availability updates metadata, public counters, and ticket controls.
    expect(container.dataset.capacity).to.equal("10");
    expect(container.dataset.remainingCapacity).to.equal("4");
    expect(document.querySelector("[data-availability-capacity]")?.textContent).to.equal("10");
    expect(document.querySelector("[data-availability-remaining]")?.textContent).to.equal("4");
    expect(document.querySelector('[data-attendance-role="ticket-type-option"]')?.disabled).to.equal(false);
    const ticketCardBody = document.querySelector('[data-attendance-role="ticket-type-card-body"]');
    expect(ticketCardBody.classList.contains("hover:border-primary-300")).to.equal(true);
    expect(ticketCardBody.classList.contains("hover:shadow-sm")).to.equal(true);
    expect(document.querySelector('[data-attendance-role="ticket-type-status-label"]')?.textContent).to.equal(
      "Available now",
    );
    expect(document.querySelector('[data-attendance-role="ticket-type-price-badge"]')?.textContent).to.equal(
      "EUR 20.00",
    );
    expect(document.querySelector('[data-attendance-role="ticket-type-title"]')?.textContent).to.equal(
      "General admission",
    );
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
    const ticketStatusLabel = container.querySelector('[data-attendance-role="ticket-type-status-label"]');
    const ticketCardBody = container.querySelector('[data-attendance-role="ticket-type-card-body"]');
    renderAttendanceAvailability(container, {
      attendee_approval_required: false,
      capacity: null,
      canceled: false,
      has_sellable_ticket_types: true,
      is_live: false,
      is_past: false,
      is_simple_rsvp: false,
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
    expect(container.dataset.registrationWindowUnavailableTitle).to.equal("Registration closed May 1, 2099.");
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
      is_simple_rsvp: false,
      registration_window_message: "Registration closed May 1, 2099.",
      registration_window_open: false,
      registration_window_unavailable_title: "Registration closed May 1, 2099.",
      remaining_capacity: null,
      ticket_types: [
        {
          active: true,
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
    const ticketStatusLabel = card.querySelector('[data-attendance-role="ticket-type-status-label"]');
    const ticketTitle = card.querySelector('[data-attendance-role="ticket-type-title"]');
    expect(ticketOption.disabled).to.equal(true);
    expect(ticketCardBody.classList.contains("cursor-not-allowed")).to.equal(true);
    expect(ticketStatusLabel.textContent.trim()).to.equal("Registration not open");
    expect(ticketTitle.textContent.trim()).to.equal("General admission");
  });

  it("renders appended ticket details with visible selection and focus affordances", async () => {
    document.body.innerHTML = `
      <div data-attendance-container>
        <div data-attendance-role="ticket-type-list"></div>
      </div>
    `;
    const container = document.querySelector("[data-attendance-container]");

    renderAttendanceAvailability(container, {
      attendee_approval_required: false,
      canceled: false,
      has_sellable_ticket_types: true,
      is_simple_rsvp: false,
      registration_window_open: true,
      ticket_types: [
        {
          active: true,
          current_price_label: "EUR 20.00",
          description: "Includes lunch and workshop materials.",
          event_ticket_type_id: "ticket-1",
          is_sellable_now: true,
          sold_out: false,
          title: "General admission",
        },
      ],
      waitlist_enabled: false,
    });

    const card = container.querySelector("attendance-ticket-card");
    await card.updateComplete;
    const ticketOption = card.querySelector('[data-attendance-role="ticket-type-option"]');
    const ticketCardBody = card.querySelector('[data-attendance-role="ticket-type-card-body"]');

    ticketOption.focus();

    expect(card.querySelector('[data-attendance-role="ticket-type-indicator"]')).to.not.equal(null);
    expect(card.querySelector('[data-attendance-role="ticket-type-status-dot"]')).to.not.equal(null);
    expect(card.textContent).to.include("Includes lunch and workshop materials.");
    expect(ticketCardBody.classList.contains("group-has-[input:focus-visible]:ring-2")).to.equal(true);
    expect(document.activeElement).to.equal(ticketOption);
  });

  it("keeps price-ineligible approval tickets unavailable", () => {
    // Build cached markup containing a ticket that has since become inactive.
    document.body.innerHTML = `
      <div data-attendance-container>
        <div data-attendance-role="ticket-type-list">
          <label data-attendance-role="ticket-type-card">
            <input
              data-attendance-role="ticket-type-option"
              type="radio"
              name="event_ticket_type_id"
              value="ticket-inactive"
              checked
            />
            <div data-attendance-role="ticket-type-card-body" class="bg-white cursor-pointer"></div>
            <div data-attendance-role="ticket-type-summary"></div>
            <span data-attendance-role="ticket-type-status-dot" class="bg-green-500"></span>
            <span data-attendance-role="ticket-type-status-label">Available now</span>
          </label>
        </div>
      </div>
    `;

    // Refresh with an inactive cached tier and a future tier without a current price.
    const container = document.querySelector("[data-attendance-container]");
    renderAttendanceAvailability(container, {
      attendee_approval_required: true,
      canceled: false,
      has_sellable_ticket_types: false,
      is_simple_rsvp: false,
      registration_window_open: true,
      ticket_types: [
        {
          active: false,
          current_price_label: "EUR 20.00",
          event_ticket_type_id: "ticket-inactive",
          is_sellable_now: false,
          sold_out: false,
        },
        {
          active: true,
          current_price_label: null,
          event_ticket_type_id: "ticket-future",
          is_sellable_now: false,
          sold_out: false,
          title: "Future admission",
        },
      ],
      waitlist_enabled: false,
    });

    // Neither tier can be selected or submitted for organizer approval.
    const inactiveOption = container.querySelector('[value="ticket-inactive"]');
    expect(inactiveOption.disabled).to.equal(true);
    expect(inactiveOption.checked).to.equal(false);
    expect(container.querySelector('[value="ticket-future"]')).to.equal(null);
  });

  it("updates and clears cached ticket descriptions from fresh availability", () => {
    // Build cached ticket markup with an existing description.
    document.body.innerHTML = `
      <div data-attendance-container>
        <div data-attendance-role="ticket-type-list">
          <label data-attendance-role="ticket-type-card">
            <input data-attendance-role="ticket-type-option" value="ticket-1" />
            <div data-attendance-role="ticket-type-card-body"></div>
            <div data-attendance-role="ticket-type-summary">
              <span data-attendance-role="ticket-type-title">General admission</span>
            </div>
            <p data-attendance-role="ticket-type-description">Old description</p>
            <div><span data-attendance-role="ticket-type-status-label"></span></div>
          </label>
        </div>
      </div>
    `;
    const container = document.querySelector("[data-attendance-container]");
    const availability = {
      attendee_approval_required: false,
      canceled: false,
      has_sellable_ticket_types: true,
      is_simple_rsvp: false,
      registration_window_open: true,
      ticket_types: [
        {
          active: true,
          current_price_label: "EUR 20.00",
          description: "Updated description",
          event_ticket_type_id: "ticket-1",
          is_sellable_now: true,
          sold_out: false,
          title: "General admission",
        },
      ],
      waitlist_enabled: false,
    };

    // Fresh copy replaces the cached description.
    renderAttendanceAvailability(container, availability);
    expect(container.querySelector('[data-attendance-role="ticket-type-description"]').textContent).to.equal(
      "Updated description",
    );

    // Removing the description from availability also removes stale cached copy.
    availability.ticket_types[0].description = null;
    renderAttendanceAvailability(container, availability);
    expect(container.querySelector('[data-attendance-role="ticket-type-description"]')).to.equal(null);
  });

  it("removes cached tickets missing from public availability", () => {
    // Build cached markup with one public tier and one tier that became private.
    document.body.innerHTML = `
      <div data-attendance-container>
        <div data-attendance-role="ticket-type-list">
          <label data-attendance-role="ticket-type-card">
            <input data-attendance-role="ticket-type-option" value="ticket-public" />
            <div data-attendance-role="ticket-type-card-body"></div>
            <div data-attendance-role="ticket-type-summary"></div>
            <span data-attendance-role="ticket-type-status-label"></span>
          </label>
          <label data-attendance-role="ticket-type-card">
            <input data-attendance-role="ticket-type-option" value="ticket-private" />
            <div data-attendance-role="ticket-type-card-body"></div>
            <div data-attendance-role="ticket-type-summary"></div>
            <p>Invitation-only details</p>
            <span data-attendance-role="ticket-type-status-label"></span>
          </label>
        </div>
      </div>
    `;

    // Refresh with only the tier that remains publicly visible.
    const container = document.querySelector("[data-attendance-container]");
    renderAttendanceAvailability(container, {
      attendee_approval_required: false,
      canceled: false,
      has_sellable_ticket_types: true,
      is_simple_rsvp: false,
      registration_window_open: true,
      ticket_types: [
        {
          active: true,
          current_price_label: "EUR 20.00",
          event_ticket_type_id: "ticket-public",
          is_sellable_now: true,
          sold_out: false,
          title: "Public admission",
        },
      ],
      waitlist_enabled: false,
    });

    // The private tier and its cached attendee-facing details are removed together.
    expect(container.querySelector('[value="ticket-public"]')).to.not.equal(null);
    expect(container.querySelector('[value="ticket-private"]')).to.equal(null);
    expect(container.textContent).to.not.include("Invitation-only details");
  });
});
