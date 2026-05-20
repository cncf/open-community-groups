import { expect } from "@open-wc/testing";

import "/static/js/dashboard/event/ticketing/discount-codes-editor.js";
import "/static/js/dashboard/event/ticketing/ticket-types-editor.js";
import { initializeEventAddPage } from "/static/js/dashboard/group/event-add-page.js";
import { initializeEventUpdatePage } from "/static/js/dashboard/group/event-update-page.js";
import { waitForMicrotask } from "/tests/unit/test-utils/async.js";
import { resetDom } from "/tests/unit/test-utils/dom.js";
import { mockHtmx, mockSwal } from "/tests/unit/test-utils/globals.js";

// Prepare shared event forms markup to check it covers the current behavior.
const sharedEventFormsMarkup = () => `
  <div id="pending-changes-alert"></div>
  <form id="details-form"></form>
  <form id="date-venue-form"></form>
  <form id="hosts-sponsors-form"></form>
  <form id="sessions-form"></form>
  <form id="cfs-form"></form>
  <input id="starts_at" />
  <input id="ends_at" />
  <input id="toggle_registration_required" type="checkbox" />
  <input id="registration_required" type="hidden" value="false" />
  <input id="toggle_test_event" type="checkbox" />
  <input id="test_event" type="hidden" value="false" />
  <input id="toggle_event_reminder_enabled" type="checkbox" />
  <input id="event_reminder_enabled" type="hidden" value="false" />
  <input id="toggle_cfs_enabled" type="checkbox" />
  <input id="cfs_enabled" type="hidden" value="false" />
  <input id="cfs_starts_at" />
  <input id="cfs_ends_at" />
  <textarea id="cfs_description"></textarea>
  <div id="cfs-labels-editor"></div>
  <select id="kind_id">
    <option value="">Select</option>
    <option value="virtual">Virtual</option>
  </select>
  <input name="timezone" value="UTC" />
`;

// Mount add page shell for the test.
const mountAddPageShell = () => {
  document.body.innerHTML = `
    <div data-event-page="add">
      ${sharedEventFormsMarkup()}
      <button id="add-event-button" type="button"></button>
      <button id="cancel-button" type="button"></button>
      <button data-section="details" data-active="true" class="active">Details</button>
      <button data-section="sessions" data-active="false">Sessions</button>
      <section data-content="details"></section>
      <section data-content="sessions" class="hidden"></section>
    </div>
  `;
};

const mountUpdatePageShell = ({
  canManageEvents = false,
  eventCanceled = false,
  waitlistCount = "2",
} = {}) => {
  document.body.innerHTML = `
    <div id="event-update-page"
         data-event-page="update"
         data-event-canceled="${String(eventCanceled)}"
         data-event-past="false"
         data-can-manage-events="${String(canManageEvents)}">
      ${sharedEventFormsMarkup()}
      <button data-section="details" data-active="true" class="active">Details</button>
      <button data-section="submissions" data-active="false">Submissions</button>
      <button data-section="attendees" data-active="false">Attendees</button>
      <section data-content="details"></section>
      <section data-content="submissions" class="hidden"></section>
      <section data-content="attendees" class="hidden"></section>
      <div class="inert-form" inert></div>
      <input id="capacity" value="" />
      <button id="update-event-button" type="button" data-waitlist-count="${waitlistCount}"></button>
      <button id="cancel-button" type="button"></button>
    </div>
  `;
};

describe("event page modules", () => {
  let htmx;
  let swal;

  beforeEach(() => {
    resetDom();
    htmx = mockHtmx();
    swal = mockSwal();
  });

  afterEach(async () => {
    await waitForMicrotask();
    await waitForMicrotask();
    resetDom();
    htmx.restore();
    swal.restore();
  });

  it("initializes the add page and syncs boolean hidden fields", () => {
    // Exercise the flow to check it initializes the add page and syncs boolean hidden.
    mountAddPageShell();

    // Exercise the flow to check it initializes the add page and syncs boolean hidden.
    initializeEventAddPage();

    // Read the DOM to check it initializes the add page and syncs boolean hidden fields.
    const registrationToggle = document.getElementById(
      "toggle_registration_required",
    );
    const testEventToggle = document.getElementById("toggle_test_event");
    const reminderToggle = document.getElementById(
      "toggle_event_reminder_enabled",
    );

    // Update the checkbox state to check it initializes the add page and syncs boolean.
    registrationToggle.checked = true;
    registrationToggle.dispatchEvent(new Event("change", { bubbles: true }));
    testEventToggle.checked = true;
    testEventToggle.dispatchEvent(new Event("change", { bubbles: true }));
    reminderToggle.checked = true;
    reminderToggle.dispatchEvent(new Event("change", { bubbles: true }));

    // Confirm it initializes the add page and syncs boolean hidden fields.
    expect(document.getElementById("registration_required").value).to.equal(
      "true",
    );
    expect(document.getElementById("test_event").value).to.equal("true");
    expect(document.getElementById("event_reminder_enabled").value).to.equal(
      "true",
    );
  });

  it("clears add page venue fields from the location clear button", () => {
    // Exercise the flow to check it clears add page venue fields from the location clear.
    mountAddPageShell();
    const pageRoot = document.querySelector('[data-event-page="add"]');
    pageRoot.insertAdjacentHTML(
      "beforeend",
      `
        <button id="clear-location-fields" type="button"></button>
        <input id="venue_name" value="Main hall" />
        <input id="venue_address" value="123 Street" />
        <location-search-field></location-search-field>
      `,
    );

    // Read the DOM to check it clears add page venue fields from the location clear.
    const locationSearchField = pageRoot.querySelector("location-search-field");
    let locationFieldsCleared = false;
    locationSearchField.clearLocationFields = () => {
      locationFieldsCleared = true;
    };

    // Exercise the flow to check it clears add page venue fields from the location clear.
    initializeEventAddPage();

    // Trigger the user interaction to check it clears add page venue fields.
    document.getElementById("clear-location-fields").click();

    // Confirm it clears add page venue fields from the location clear button.
    expect(document.getElementById("venue_name").value).to.equal("");
    expect(document.getElementById("venue_address").value).to.equal("");
    expect(locationFieldsCleared).to.equal(true);
  });

  it("converts event and session dates during add page HTMX config requests", () => {
    // Exercise the flow to check it converts event and session dates during add page.
    mountAddPageShell();

    // Exercise the flow to check it converts event and session dates during add page.
    initializeEventAddPage();

    // Prepare request event to check it converts event and session dates during add page.
    const requestEvent = new CustomEvent("htmx:configRequest", {
      bubbles: true,
      cancelable: true,
      detail: {
        elt: document.getElementById("add-event-button"),
        parameters: {
          starts_at: "2026-05-10T09:30",
          ends_at: "2026-05-10T11:00",
          "sessions[0][starts_at]": "2026-05-10T10:00",
        },
      },
    });

    // Dispatch the event event to check it converts event and session dates during add.
    document.getElementById("add-event-button").dispatchEvent(requestEvent);

    // Confirm it converts event and session dates during add page HTMX config requests.
    expect(requestEvent.detail.parameters.starts_at).to.equal(
      "2026-05-10T09:30:00",
    );
    expect(requestEvent.detail.parameters.ends_at).to.equal(
      "2026-05-10T11:00:00",
    );
    expect(requestEvent.detail.parameters["sessions[0][starts_at]"]).to.equal(
      "2026-05-10T10:00:00",
    );
  });

  it("updates add page recurrence labels and additional-occurrence controls", () => {
    // Exercise the flow to check it updates add page recurrence labels.
    mountAddPageShell();
    document.querySelector('[data-event-page="add"]').insertAdjacentHTML(
      "beforeend",
      `
        <select id="recurrence_pattern">
          <option value="just-once">Just once</option>
          <option value="weekly" data-recurrence-label="weekly">Weekly</option>
          <option value="biweekly" data-recurrence-label="biweekly">Every two weeks</option>
          <option value="monthly" data-recurrence-label="monthly">Monthly</option>
        </select>
        <div id="recurrence-additional-occurrences-container" class="hidden">
          <input id="recurrence_additional_occurrences" value="3" />
        </div>
      `,
    );

    // Read the starts at element to check it updates add page recurrence labels.
    const startsAtInput = document.getElementById("starts_at");
    const recurrencePatternSelect =
      document.getElementById("recurrence_pattern");
    const additionalOccurrencesContainer = document.getElementById(
      "recurrence-additional-occurrences-container",
    );
    const additionalOccurrencesInput = document.getElementById(
      "recurrence_additional_occurrences",
    );
    // Return option text for assertions.
    const optionText = (value) =>
      recurrencePatternSelect.querySelector(`option[value="${value}"]`)
        .textContent;

    // Update the input value to check it updates add page recurrence labels.
    startsAtInput.value = "2026-05-13T09:30";

    // Exercise the flow to check it updates add page recurrence labels.
    initializeEventAddPage();

    // Confirm it updates add page recurrence labels and additional-occurrence controls.
    expect(optionText("weekly")).to.equal("Weekly on Wednesday");
    expect(optionText("biweekly")).to.equal("Every two weeks on Wednesday");
    expect(optionText("monthly")).to.equal("Monthly on the second Wednesday");
    expect(
      additionalOccurrencesContainer.classList.contains("hidden"),
    ).to.equal(true);
    expect(additionalOccurrencesInput.disabled).to.equal(true);
    expect(additionalOccurrencesInput.required).to.equal(false);
    expect(additionalOccurrencesInput.value).to.equal("");

    // Update the input value to check it updates add page recurrence labels.
    additionalOccurrencesInput.value = "2";
    recurrencePatternSelect.value = "weekly";
    recurrencePatternSelect.dispatchEvent(
      new Event("change", { bubbles: true }),
    );

    // Confirm it updates add page recurrence labels and additional-occurrence controls.
    expect(
      additionalOccurrencesContainer.classList.contains("hidden"),
    ).to.equal(false);
    expect(additionalOccurrencesInput.disabled).to.equal(false);
    expect(additionalOccurrencesInput.required).to.equal(true);
    expect(additionalOccurrencesInput.value).to.equal("2");

    // Update the input value to check it updates add page recurrence labels.
    startsAtInput.value = "2026-05-20T09:30";
    startsAtInput.dispatchEvent(new Event("change", { bubbles: true }));

    // Confirm it updates add page recurrence labels and additional-occurrence controls.
    expect(optionText("monthly")).to.equal("Monthly on the third Wednesday");

    // Update the input value to check it updates add page recurrence labels.
    recurrencePatternSelect.value = "just-once";
    recurrencePatternSelect.dispatchEvent(
      new Event("change", { bubbles: true }),
    );

    // Confirm it updates add page recurrence labels and additional-occurrence controls.
    expect(
      additionalOccurrencesContainer.classList.contains("hidden"),
    ).to.equal(true);
    expect(additionalOccurrencesInput.disabled).to.equal(true);
    expect(additionalOccurrencesInput.required).to.equal(false);
    expect(additionalOccurrencesInput.value).to.equal("");
  });

  it("re-syncs session bounds after rejecting an add page start date change", async () => {
    // Exercise the flow to check it re-syncs session bounds after rejecting an add page.
    mountAddPageShell();
    document
      .querySelector('[data-event-page="add"]')
      .insertAdjacentHTML(
        "beforeend",
        '<sessions-section></sessions-section><online-event-details id="online-event-details"></online-event-details>',
      );

    // Read the DOM to check it re-syncs session bounds after rejecting an add page start.
    const sessionsSection = document.querySelector("sessions-section");
    const onlineEventDetails = document.querySelector("online-event-details");
    const startsAtInput = document.getElementById("starts_at");
    const endsAtInput = document.getElementById("ends_at");

    // Update the input value to check it re-syncs session bounds after rejecting an add.
    startsAtInput.value = "2026-05-10T09:00";
    endsAtInput.value = "2026-05-10T11:00";
    onlineEventDetails.trySetStartsAt = async () => false;

    // Exercise the flow to check it re-syncs session bounds after rejecting an add page.
    initializeEventAddPage();

    // Update the input value to check it re-syncs session bounds after rejecting an add.
    startsAtInput.value = "2026-05-11T09:00";
    startsAtInput.dispatchEvent(new Event("change", { bubbles: true }));

    // Wait for queued event handlers to finish.
    await waitForMicrotask();

    // Confirm it re-syncs session bounds after rejecting an add page start date change.
    expect(startsAtInput.value).to.equal("2026-05-10T09:00");
    expect(sessionsSection.eventStartsAt).to.equal("2026-05-10T09:00");
    expect(sessionsSection.eventEndsAt).to.equal("2026-05-10T11:00");
  });

  it("re-syncs session bounds after rejecting an update page end date change", async () => {
    // Exercise the flow to check it re-syncs session bounds after rejecting an update.
    mountUpdatePageShell();
    document
      .querySelector('[data-event-page="update"]')
      .insertAdjacentHTML(
        "beforeend",
        '<sessions-section></sessions-section><online-event-details id="online-event-details"></online-event-details>',
      );

    // Read the DOM to check it re-syncs session bounds after rejecting an update page.
    const sessionsSection = document.querySelector("sessions-section");
    const onlineEventDetails = document.querySelector("online-event-details");
    const startsAtInput = document.getElementById("starts_at");
    const endsAtInput = document.getElementById("ends_at");

    // Update the input value to check it re-syncs session bounds after rejecting.
    startsAtInput.value = "2026-05-10T09:00";
    endsAtInput.value = "2026-05-10T11:00";
    onlineEventDetails.trySetEndsAt = async () => false;

    // Exercise the flow to check it re-syncs session bounds after rejecting an update.
    initializeEventUpdatePage();

    // Update the input value to check it re-syncs session bounds after rejecting.
    endsAtInput.value = "2026-05-10T12:30";
    endsAtInput.dispatchEvent(new Event("change", { bubbles: true }));

    // Wait for queued event handlers to finish.
    await waitForMicrotask();

    // Confirm it re-syncs session bounds after rejecting an update page end date change.
    expect(endsAtInput.value).to.equal("2026-05-10T11:00");
    expect(sessionsSection.eventStartsAt).to.equal("2026-05-10T09:00");
    expect(sessionsSection.eventEndsAt).to.equal("2026-05-10T11:00");
  });

  it("initializes the update page and respects the page data contract", () => {
    // Exercise the flow to check it initializes the update page and respects the page.
    mountUpdatePageShell();

    // Exercise the flow to check it initializes the update page and respects the page.
    initializeEventUpdatePage();

    // Exercise the flow to check it initializes the update page and respects the page.
    document
      .querySelector('[data-section="submissions"]')
      .dispatchEvent(new Event("click", { bubbles: true }));

    // Confirm it initializes the update page and respects the page data contract.
    expect(
      document.querySelector(".inert-form").hasAttribute("inert"),
    ).to.equal(false);
  });

  it("clears update page venue fields from the location clear button", () => {
    // Exercise the flow to check it clears update page venue fields from the location.
    mountUpdatePageShell();
    const pageRoot = document.querySelector('[data-event-page="update"]');
    pageRoot.insertAdjacentHTML(
      "beforeend",
      `
        <button id="clear-location-fields" type="button"></button>
        <input id="venue_name" value="Main hall" />
        <input id="venue_address" value="123 Street" />
        <location-search-field></location-search-field>
      `,
    );

    // Read the DOM to check it clears update page venue fields from the location clear.
    const locationSearchField = pageRoot.querySelector("location-search-field");
    let locationFieldsCleared = false;
    locationSearchField.clearLocationFields = () => {
      locationFieldsCleared = true;
    };

    // Exercise the flow to check it clears update page venue fields from the location.
    initializeEventUpdatePage();

    // Trigger the user interaction to check it clears update page venue fields.
    document.getElementById("clear-location-fields").click();

    // Confirm it clears update page venue fields from the location clear button.
    expect(document.getElementById("venue_name").value).to.equal("");
    expect(document.getElementById("venue_address").value).to.equal("");
    expect(locationFieldsCleared).to.equal(true);
  });

  it("keeps canceled event review tabs interactive for event managers", () => {
    // Exercise the flow to check it keeps canceled event review tabs interactive.
    mountUpdatePageShell({ canManageEvents: true, eventCanceled: true });

    // Exercise the flow to check it keeps canceled event review tabs interactive.
    initializeEventUpdatePage();

    // Exercise the flow to check it keeps canceled event review tabs interactive.
    document
      .querySelector('[data-section="attendees"]')
      .dispatchEvent(new Event("click", { bubbles: true }));

    // Confirm it keeps canceled event review tabs interactive for event managers.
    expect(
      document.querySelector(".inert-form").hasAttribute("inert"),
    ).to.equal(false);

    // Exercise the flow to check it keeps canceled event review tabs interactive.
    document
      .querySelector('[data-section="details"]')
      .dispatchEvent(new Event("click", { bubbles: true }));

    // Confirm it keeps canceled event review tabs interactive for event managers.
    expect(
      document.querySelector(".inert-form").hasAttribute("inert"),
    ).to.equal(true);
  });

  it("warns before clearing capacity with a populated waitlist on the update page", async () => {
    // Exercise the flow to check it warns before clearing capacity with a populated.
    mountUpdatePageShell({ canManageEvents: true });

    // Exercise the flow to check it warns before clearing capacity with a populated.
    initializeEventUpdatePage();

    // Exercise the flow to check it warns before clearing capacity with a populated.
    document
      .getElementById("update-event-button")
      .dispatchEvent(
        new MouseEvent("click", { bubbles: true, cancelable: true }),
      );
    await waitForMicrotask();
    await waitForMicrotask();

    // Confirm it warns before clearing capacity with a populated waitlist on the update.
    expect(swal.calls).to.have.length(1);
    expect(swal.calls[0].text).to.contain("currently on the waitlist");
    expect(htmx.triggerCalls).to.deep.equal([
      ["#update-event-button", "confirmed"],
    ]);
  });

  it("scopes add page initialization to the provided root", () => {
    // Build the DOM fixture to check it scopes add page initialization to the provided.
    document.body.innerHTML = `
      <div id="outside">
        <input id="toggle_registration_required" type="checkbox" checked />
        <input id="registration_required" type="hidden" value="outside" />
      </div>
      <div id="page-root">
        <div data-event-page="add">
          ${sharedEventFormsMarkup()}
          <button id="add-event-button" type="button"></button>
          <button id="cancel-button" type="button"></button>
          <button data-section="details" data-active="true" class="active">Details</button>
          <section data-content="details"></section>
        </div>
      </div>
    `;

    // Read the page root element to check it scopes add page initialization.
    const pageRoot = document.getElementById("page-root");
    initializeEventAddPage(pageRoot);

    // Read the DOM to check it scopes add page initialization to the provided root.
    const scopedToggle = pageRoot.querySelector(
      "#toggle_registration_required",
    );
    scopedToggle.checked = true;
    scopedToggle.dispatchEvent(new Event("change", { bubbles: true }));

    // Confirm it scopes add page initialization to the provided root.
    expect(pageRoot.querySelector("#registration_required").value).to.equal(
      "true",
    );
    expect(
      document.querySelector("#outside #registration_required").value,
    ).to.equal("outside");
  });

  it("reconfigures ticketing editors to use scoped page dependencies", async () => {
    // Build the DOM fixture to check it reconfigures ticketing editors to use scoped.
    document.body.innerHTML = `
      <div id="outside-root">
        <button id="add-ticket-type-button" type="button">Outside ticket</button>
        <button id="add-discount-code-button" type="button">Outside discount</button>
        <select id="payment_currency_code">
          <option value="USD" selected>USD</option>
        </select>
        <input name="timezone" value="UTC" />
      </div>
      <div id="page-root">
        <div data-event-page="add">
          ${sharedEventFormsMarkup()}
          <button id="add-event-button" type="button"></button>
          <button id="cancel-button" type="button"></button>
          <button id="add-ticket-type-button" type="button">Scoped ticket</button>
          <button id="add-discount-code-button" type="button">Scoped discount</button>
          <select id="payment_currency_code">
            <option value="EUR" selected>EUR</option>
          </select>
          <ticket-types-editor
            id="ticket-types-ui"
            ticket-types="[]"
            data-disabled="false"></ticket-types-editor>
          <discount-codes-editor
            id="discount-codes-ui"
            discount-codes="[]"
            data-disabled="false"></discount-codes-editor>
          <button data-section="details" data-active="true" class="active">Details</button>
          <section data-content="details"></section>
        </div>
      </div>
    `;

    // Read the page root element to check it reconfigures ticketing editors to use.
    const pageRoot = document.getElementById("page-root");
    initializeEventAddPage(pageRoot);

    // Read the DOM to check it reconfigures ticketing editors to use scoped page.
    const ticketTypesEditor = pageRoot.querySelector("#ticket-types-ui");
    const discountCodesEditor = pageRoot.querySelector("#discount-codes-ui");
    const scopedTicketButton = pageRoot.querySelector(
      "#add-ticket-type-button",
    );
    const scopedDiscountButton = pageRoot.querySelector(
      "#add-discount-code-button",
    );
    const scopedCurrency = pageRoot.querySelector("#payment_currency_code");
    const scopedTimezone = pageRoot.querySelector('[name="timezone"]');

    // Confirm it reconfigures ticketing editors to use scoped page dependencies.
    expect(ticketTypesEditor.addButton).to.equal(scopedTicketButton);
    expect(ticketTypesEditor.currencyInput).to.equal(scopedCurrency);
    expect(ticketTypesEditor.timezoneInput).to.equal(scopedTimezone);
    expect(discountCodesEditor.addButton).to.equal(scopedDiscountButton);
    expect(discountCodesEditor.currencyInput).to.equal(scopedCurrency);
    expect(discountCodesEditor.timezoneInput).to.equal(scopedTimezone);

    // Trigger the user interaction to check it reconfigures ticketing editors to use.
    scopedTicketButton.click();
    scopedDiscountButton.click();
    await ticketTypesEditor.updateComplete;
    await discountCodesEditor.updateComplete;

    // Confirm it reconfigures ticketing editors to use scoped page dependencies.
    expect(ticketTypesEditor.textContent).to.contain("Price (EUR)");
    expect(
      ticketTypesEditor
        .querySelector('[data-ticketing-role="ticket-modal"]')
        ?.classList.contains("hidden"),
    ).to.equal(false);
    expect(
      discountCodesEditor
        .querySelector('[data-ticketing-role="discount-modal"]')
        ?.classList.contains("hidden"),
    ).to.equal(false);
  });

  it("keeps venue changes scoped when switching the event kind", async () => {
    // Build the DOM fixture to check it keeps venue changes scoped when switching.
    document.body.innerHTML = `
      <div id="outside-root">
        <section id="venue-information-section" class="hidden"></section>
        <section id="online-event-details-section" class="hidden"></section>
        <input id="venue_name" value="Outside hall" />
        <input id="venue_address" value="Outside street" />
      </div>
      <div id="page-root">
        <div data-event-page="add">
          ${sharedEventFormsMarkup()}
          <section id="venue-information-section"></section>
          <section id="online-event-details-section" class="hidden"></section>
          <input id="venue_name" value="Main hall" />
          <input id="venue_address" value="123 Street" />
          <button id="add-event-button" type="button"></button>
          <button id="cancel-button" type="button"></button>
          <button data-section="details" data-active="true" class="active">Details</button>
          <section data-content="details"></section>
        </div>
      </div>
    `;

    // Read the page root element to check it keeps venue changes scoped when switching.
    const pageRoot = document.getElementById("page-root");
    const kindSelect = pageRoot.querySelector("#kind_id");
    swal.setNextResult({ isConfirmed: true });

    // Exercise the flow to check it keeps venue changes scoped when switching the event.
    initializeEventAddPage(pageRoot);

    // Update the input value to check it keeps venue changes scoped when switching.
    kindSelect.value = "virtual";
    kindSelect.dispatchEvent(new Event("change", { bubbles: true }));
    await waitForMicrotask();

    // Confirm it keeps venue changes scoped when switching the event kind.
    expect(pageRoot.querySelector("#venue_name")?.value).to.equal("");
    expect(pageRoot.querySelector("#venue_address")?.value).to.equal("");
    expect(
      pageRoot
        .querySelector("#venue-information-section")
        ?.classList.contains("hidden"),
    ).to.equal(true);
    expect(
      pageRoot
        .querySelector("#online-event-details-section")
        ?.classList.contains("hidden"),
    ).to.equal(false);

    // Confirm it keeps venue changes scoped when switching the event kind.
    expect(document.querySelector("#outside-root #venue_name")?.value).to.equal(
      "Outside hall",
    );
    expect(
      document.querySelector("#outside-root #venue_address")?.value,
    ).to.equal("Outside street");
    expect(
      document
        .querySelector("#outside-root #venue-information-section")
        ?.classList.contains("hidden"),
    ).to.equal(true);
  });

  it("does not bind duplicate update page handlers when initialized twice", () => {
    // Exercise the flow to check it does not bind duplicate update page handlers.
    mountUpdatePageShell({ canManageEvents: true });

    // Exercise the flow to check it does not bind duplicate update page handlers.
    initializeEventUpdatePage();
    initializeEventUpdatePage();

    // Exercise the flow to check it does not bind duplicate update page handlers.
    document
      .getElementById("update-event-button")
      .dispatchEvent(
        new MouseEvent("click", { bubbles: true, cancelable: true }),
      );

    // Confirm it does not bind duplicate update page handlers when initialized twice.
    expect(swal.calls).to.have.length(1);
  });

  it("syncs approved submissions only within the initialized update page root", () => {
    // Exercise the flow to check it syncs approved submissions only within.
    mountUpdatePageShell({ canManageEvents: true });
    document.body.insertAdjacentHTML(
      "beforeend",
      '<sessions-section id="outside-sessions" approved-submissions=\'[{"cfs_submission_id":"outside"}]\'></sessions-section>',
    );

    // Read the event page= element to check it syncs approved submissions only within.
    const pageRoot = document.querySelector('[data-event-page="update"]');
    const scopedSessions = document.createElement("sessions-section");
    scopedSessions.id = "scoped-sessions";
    scopedSessions.setAttribute(
      "approved-submissions",
      JSON.stringify([
        { cfs_submission_id: "12", title: "Old title", speaker_name: "Ada" },
      ]),
    );
    scopedSessions.requestUpdate = () => {
      scopedSessions.dataset.updated = "true";
    };
    pageRoot.append(scopedSessions);

    // Exercise the flow to check it syncs approved submissions only within.
    initializeEventUpdatePage(pageRoot);

    // Dispatch the event event to check it syncs approved submissions only within.
    pageRoot.dispatchEvent(
      new CustomEvent("event-approved-submissions-updated", {
        bubbles: true,
        detail: {
          approved: true,
          cfsSubmissionId: "12",
          submission: {
            cfs_submission_id: "12",
            session_proposal_id: "99",
            title: "Platform Engineering at Scale",
            speaker_name: "Ada Lovelace",
          },
        },
      }),
    );

    // Confirm it syncs approved submissions only within the initialized update page root.
    expect(scopedSessions.getAttribute("approved-submissions")).to.equal(
      JSON.stringify([
        {
          cfs_submission_id: "12",
          session_proposal_id: "99",
          title: "Platform Engineering at Scale",
          speaker_name: "Ada Lovelace",
        },
      ]),
    );
    expect(scopedSessions.dataset.updated).to.equal("true");
    expect(
      document
        .getElementById("outside-sessions")
        .getAttribute("approved-submissions"),
    ).to.equal('[{"cfs_submission_id":"outside"}]');
  });

  it("dispatches submissions refresh from the update page root after a successful save", () => {
    // Exercise the flow to check it dispatches submissions refresh from the update page.
    mountUpdatePageShell({ canManageEvents: true, waitlistCount: "0" });

    // Read the event update page element to check it dispatches submissions refresh.
    const pageRoot = document.getElementById("event-update-page");
    const refreshEvents = [];
    const bodyEvents = [];

    // Exercise the flow to check it dispatches submissions refresh from the update page.
    pageRoot.addEventListener("refresh-event-submissions", () => {
      refreshEvents.push("page");
    });
    document.body.addEventListener("refresh-event-submissions", () => {
      bodyEvents.push("body");
    });

    // Exercise the flow to check it dispatches submissions refresh from the update page.
    initializeEventUpdatePage();

    // Dispatch the event event to check it dispatches submissions refresh.
    document.getElementById("update-event-button").dispatchEvent(
      new CustomEvent("htmx:afterRequest", {
        bubbles: true,
        detail: {
          elt: document.getElementById("update-event-button"),
          xhr: { status: 204 },
        },
      }),
    );

    // Confirm it dispatches submissions refresh from the update page root.
    expect(refreshEvents).to.deep.equal(["page"]);
    expect(bodyEvents).to.deep.equal([]);
  });
});
