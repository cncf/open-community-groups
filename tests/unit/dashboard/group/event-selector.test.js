import { expect } from "@open-wc/testing";

import "/static/js/dashboard/group/event-selector.js";
import { resetDom, mockScrollTo } from "/tests/unit/test-utils/dom.js";
import { mountLitComponent, useMountedElementsCleanup } from "/tests/unit/test-utils/lit.js";
import { mockSwal } from "/tests/unit/test-utils/globals.js";

describe("event-selector", () => {
  const EventSelector = customElements.get("event-selector");

  let swal;
  let scrollToMock;

  useMountedElementsCleanup("event-selector");

  beforeEach(() => {
    resetDom();
    swal = mockSwal();
    scrollToMock = mockScrollTo();
  });

  afterEach(() => {
    swal.restore();
    scrollToMock.restore();
  });

  const renderSelector = async (properties = {}) => {
    return mountLitComponent("event-selector", {
      groupId: "group-1",
      community: "cncf",
      groupSlug: "platform-engineering",
      buttonId: "copy-event-trigger",
      ...properties,
    });
  };

  it("loads primary events from upcoming and past results", async () => {
    const element = await renderSelector();

    const requestCalls = [];
    element._requestEvents = async (config) => {
      requestCalls.push(config);
      if (config.sortDirection === "asc") {
        return [
          { event_id: "future-1", name: "Future 1" },
          { event_id: "future-2", name: "Future 2" },
          { event_id: "future-3", name: "Future 3" },
        ];
      }
      return [
        { event_id: "past-1", name: "Past 1" },
        { event_id: "past-2", name: "Past 2" },
      ];
    };

    await element._fetchPrimaryEvents();

    expect(requestCalls).to.have.length(2);
    expect(requestCalls[0]).to.include({ sortDirection: "asc", query: "" });
    expect(requestCalls[1]).to.include({ sortDirection: "desc", query: "" });
    expect(element._primaryResults.map((event) => event.event_id)).to.deep.equal([
      "future-3",
      "future-2",
      "future-1",
      "past-1",
      "past-2",
    ]);
    expect(element._results).to.deep.equal(element._primaryResults);
    expect(element._hasFetched).to.equal(true);
  });

  it("updates active navigation and closes the dropdown on escape", async () => {
    const element = await renderSelector();
    let selectedActiveResult = 0;

    element._isOpen = true;
    element._results = [{ event_id: "1" }, { event_id: "2" }];
    element._selectActiveResult = () => {
      selectedActiveResult += 1;
    };

    const event = {
      key: "",
      preventDefaultCalls: 0,
      preventDefault() {
        this.preventDefaultCalls += 1;
      },
    };

    event.key = "ArrowDown";
    element._handleInputKeydown(event);
    expect(element._activeIndex).to.equal(0);

    event.key = "ArrowUp";
    element._handleInputKeydown(event);
    expect(element._activeIndex).to.equal(1);

    event.key = "Enter";
    element._handleInputKeydown(event);
    expect(selectedActiveResult).to.equal(1);

    event.key = "Escape";
    element._handleInputKeydown(event);
    expect(element._isOpen).to.equal(false);
    expect(element._activeIndex).to.equal(-1);
    expect(event.preventDefaultCalls).to.equal(4);
  });

  it("copies event details, updates selection state, and shows success feedback", async () => {
    const element = await renderSelector();
    const appliedDetails = [];

    element._isOpen = true;
    element._applyEventDetails = (details) => {
      appliedDetails.push(details);
    };
    element._fetchEventDetails = async () => ({
      event_id: "event-9",
      name: "Cloud Native Málaga",
      starts_at: 1744466400,
      timezone: "Europe/Madrid",
    });

    await element._handleCopyMode({ event_id: "event-9" });

    expect(appliedDetails).to.deep.equal([
      {
        event_id: "event-9",
        name: "Cloud Native Málaga",
        starts_at: 1744466400,
        timezone: "Europe/Madrid",
      },
    ]);
    expect(element.selectedEventId).to.equal("event-9");
    expect(element.selectedEvent).to.deep.equal({
      event_id: "event-9",
      name: "Cloud Native Málaga",
      starts_at: 1744466400,
      timezone: "Europe/Madrid",
    });
    expect(element._isOpen).to.equal(false);
    expect(element._copyLoading).to.equal(false);
    expect(scrollToMock.calls).to.deep.equal([{ top: 0, behavior: "smooth" }]);
    expect(swal.calls.at(-1)).to.include({
      text: "Event details copied. Update the schedule before publishing.",
      icon: "info",
    });
  });

  it("applies copied event details into the form and resets meeting state", async () => {
    document.body.innerHTML = `
      <input id="name" />
      <select id="category_id">
        <option value="">Select</option>
        <option value="10">Conference</option>
      </select>
      <select id="kind_id">
        <option value="">Select</option>
        <option value="workshop">Workshop</option>
      </select>
      <input id="description_short" />
      <textarea id="description-textarea"></textarea>
      <input id="capacity" />
      <input id="toggle_event_reminder_enabled" type="checkbox" />
      <input id="event_reminder_enabled" type="hidden" />
      <input id="toggle_registration_required" type="checkbox" />
      <input id="registration_required" type="hidden" />
      <input id="meetup_url" />
      <select id="payment_currency_code">
        <option value="">Select currency</option>
        <option value="EUR">EUR</option>
      </select>
      <input id="venue_name" />
      <input id="venue_address" />
      <input id="venue_city" />
      <input id="venue_zip_code" />
      <input id="meeting_join_url" value="filled" />
      <input id="meeting_recording_url" value="filled" />
      <div id="ticket-types-ui"></div>
      <div id="discount-codes-ui"></div>
      <gallery-field field-name="photos_urls"></gallery-field>
      <multiple-inputs field-name="tags"></multiple-inputs>
      <user-search-selector field-name="hosts"></user-search-selector>
      <sponsors-section></sponsors-section>
      <sessions-section></sessions-section>
      <timezone-selector name="timezone"></timezone-selector>
      <online-event-details></online-event-details>
      <markdown-editor id="description">
        <textarea></textarea>
      </markdown-editor>
    `;

    const gallery = document.querySelector('gallery-field[field-name="photos_urls"]');
    gallery._setImages = (images) => {
      gallery.images = images;
    };

    const tags = document.querySelector('multiple-inputs[field-name="tags"]');
    tags.requestUpdate = () => {};

    const hosts = document.querySelector('user-search-selector[field-name="hosts"]');
    hosts.requestUpdate = () => {};

    const sponsors = document.querySelector("sponsors-section");
    sponsors.requestUpdate = () => {};

    const sessionsSection = document.querySelector("sessions-section");
    sessionsSection.requestUpdate = () => {};

    const ticketTypesCalls = [];
    const ticketTypesRoot = document.getElementById("ticket-types-ui");
    ticketTypesRoot._ticketTypesController = {
      setTicketTypes(ticketTypes) {
        ticketTypesCalls.push(ticketTypes);
      },
    };

    const discountCodesCalls = [];
    const discountCodesRoot = document.getElementById("discount-codes-ui");
    discountCodesRoot._discountCodesController = {
      setDiscountCodes(discountCodes) {
        discountCodesCalls.push(discountCodes);
      },
    };

    const timezoneSelector = document.querySelector("timezone-selector[name='timezone']");
    timezoneSelector.dispatchEvent = () => true;

    const meetingDetails = document.querySelector("online-event-details");
    let resetCalls = 0;
    meetingDetails.reset = () => {
      resetCalls += 1;
    };

    const editor = document.querySelector("markdown-editor#description");
    const editorTextarea = editor.querySelector("textarea");

    const element = await renderSelector();

    element._applyEventDetails({
      name: "Cloud Native Málaga",
      category_name: "Conference",
      kind: "workshop",
      logo_url: "https://example.com/logo.png",
      description_short: "Short description",
      description: "Long description",
      capacity: 300,
      event_reminder_enabled: true,
      registration_required: true,
      meetup_url: "https://meetup.com/cloud-native-malaga",
      payment_currency_code: "EUR",
      photos_urls: [" one.png ", "two.png"],
      tags: ["cloud", " malaga "],
      ticket_types: [
        {
          title: "General admission",
          price_windows: [{ amount_minor: 2500 }],
        },
      ],
      discount_codes: [
        {
          code: "EARLY20",
          kind: "percentage",
          percentage: 20,
          title: "Early supporter",
        },
      ],
      timezone: "Europe/Madrid",
      venue_name: "FYCMA",
      venue_address: "Av. de José Ortega y Gasset, 201",
      venue_city: "Málaga",
      venue_zip_code: "29006",
      hosts: [{ user: { user_id: "1", username: "alice" } }],
      sponsors: [{ name: "ACME", level: 2 }],
    });

    expect(document.getElementById("name")?.value).to.equal("Cloud Native Málaga (copy)");
    expect(document.getElementById("category_id")?.value).to.equal("10");
    expect(document.getElementById("kind_id")?.value).to.equal("workshop");
    expect(document.getElementById("description_short")?.value).to.equal("Short description");
    expect(editorTextarea.value).to.equal("Long description");
    expect(document.getElementById("capacity")?.value).to.equal("300");
    expect(document.getElementById("toggle_event_reminder_enabled")?.checked).to.equal(true);
    expect(document.getElementById("event_reminder_enabled")?.value).to.equal("true");
    expect(document.getElementById("toggle_registration_required")?.checked).to.equal(true);
    expect(document.getElementById("registration_required")?.value).to.equal("true");
    expect(document.getElementById("meetup_url")?.value).to.equal("https://meetup.com/cloud-native-malaga");
    expect(document.getElementById("payment_currency_code")?.value).to.equal("EUR");
    expect(document.getElementById("venue_city")?.value).to.equal("Málaga");
    expect(document.getElementById("meeting_join_url")?.value).to.equal("");
    expect(document.getElementById("meeting_recording_url")?.value).to.equal("");
    expect(ticketTypesCalls).to.deep.equal([
      [
        {
          title: "General admission",
          price_windows: [{ amount_minor: 2500 }],
        },
      ],
    ]);
    expect(discountCodesCalls).to.deep.equal([
      [
        {
          code: "EARLY20",
          kind: "percentage",
          percentage: 20,
          title: "Early supporter",
        },
      ],
    ]);
    expect(gallery.images).to.deep.equal(["one.png", "two.png"]);
    expect(tags.items).to.deep.equal([
      { id: 0, value: "cloud" },
      { id: 1, value: "malaga" },
    ]);
    expect(hosts.selectedUsers).to.deep.equal([{ user_id: "1", username: "alice" }]);
    expect(sponsors.selectedSponsors).to.deep.equal([{ name: "ACME", level: "2" }]);
    expect(sessionsSection.sessions).to.deep.equal([]);
    expect(timezoneSelector.value).to.equal("Europe/Madrid");
    expect(resetCalls).to.equal(1);
  });
});
