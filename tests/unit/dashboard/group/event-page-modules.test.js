import { expect } from "@open-wc/testing";

import "/static/js/dashboard/event/ticketing/discount-codes-editor.js";
import "/static/js/dashboard/event/ticketing/ticket-types-editor.js";
import "/static/js/dashboard/event/sessions/section.js";
import {
  initializeEventAddPage,
  initializeEventAddPageRoots,
} from "/static/js/dashboard/group/event-add.js";
import {
  initializeEventUpdatePage,
  initializeEventUpdatePageRoots,
} from "/static/js/dashboard/group/event-update.js";
import {
  waitForAnimationFrames,
  waitForMicrotask,
} from "/tests/unit/test-utils/async.js";
import { resetDom } from "/tests/unit/test-utils/dom.js";
import { mockHtmx, mockSwal } from "/tests/unit/test-utils/globals.js";
import { dispatchHtmxLoad } from "/tests/unit/test-utils/htmx.js";

// Prepare the module under test.
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
  eventPast = false,
  waitlistCount = "2",
} = {}) => {
  document.body.innerHTML = `
    <div id="event-update-page"
         data-event-page="update"
         data-event-canceled="${String(eventCanceled)}"
         data-event-past="${String(eventPast)}"
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
    globalThis.htmx.on = () => {};
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
    // Mount the add page shell.
    mountAddPageShell();

    // Initialize the add page behavior.
    initializeEventAddPage();

    // Read the add page toggles and hidden fields.
    const registrationToggle = document.getElementById(
      "toggle_registration_required",
    );
    const testEventToggle = document.getElementById("toggle_test_event");
    const reminderToggle = document.getElementById(
      "toggle_event_reminder_enabled",
    );

    // Update the checkbox state before asserting the new state.
    registrationToggle.checked = true;
    registrationToggle.dispatchEvent(new Event("change", { bubbles: true }));
    testEventToggle.checked = true;
    testEventToggle.dispatchEvent(new Event("change", { bubbles: true }));
    reminderToggle.checked = true;
    reminderToggle.dispatchEvent(new Event("change", { bubbles: true }));

    // Verify initializes the add page and syncs boolean hidden fields.
    expect(document.getElementById("registration_required").value).to.equal(
      "true",
    );
    expect(document.getElementById("test_event").value).to.equal("true");
    expect(document.getElementById("event_reminder_enabled").value).to.equal(
      "true",
    );
  });

  it("clears add page venue fields from the location clear button", () => {
    // Location clear events empty the add page venue fields.
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

    // Read the add page venue fields before clearing them.
    const locationSearchField = pageRoot.querySelector("location-search-field");
    let locationFieldsCleared = false;
    locationSearchField.clearLocationFields = () => {
      locationFieldsCleared = true;
    };

    // Clearing location data removes add page venue values.
    initializeEventAddPage();

    // Add page venue fields are empty after clearing.
    document.getElementById("clear-location-fields").click();

    // The add page clear button empties venue fields.
    expect(document.getElementById("venue_name").value).to.equal("");
    expect(document.getElementById("venue_address").value).to.equal("");
    expect(locationFieldsCleared).to.equal(true);
  });

  it("initializes add page fragments from the fragment root", () => {
    // Mount the add page shell.
    mountAddPageShell();
    const pageRoot = document.querySelector('[data-event-page="add"]');

    // Initialize the add page from the swapped fragment root.
    initializeEventAddPageRoots(pageRoot);

    // Verify the add page fragment is marked as initialized.
    expect(pageRoot.dataset.eventPageReady).to.equal("true");
  });

  it("initializes swapped add page fragments on htmx load", () => {
    // Mount the add page shell as swapped dashboard content.
    mountAddPageShell();

    // Dispatch the lifecycle event used by swapped dashboard content.
    dispatchHtmxLoad(document.querySelector('[data-event-page="add"]'));

    // Verify the add page fragment is initialized from the lifecycle event.
    expect(
      document.querySelector('[data-event-page="add"]').dataset.eventPageReady,
    ).to.equal("true");
  });

  it("converts event and session dates during add page HTMX config requests", () => {
    // Mount the add page shell.
    mountAddPageShell();

    // Initialize the add page behavior.
    initializeEventAddPage();

    // Prepare request event for converting event and session dates during add page.
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

    // Dispatch the add-page HTMX config request.
    document.getElementById("add-event-button").dispatchEvent(requestEvent);

    // Verify converts event and session dates during add page HTMX config requests.
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

  it("reports the first invalid add page select when saving", async () => {
    mountAddPageShell();

    document.getElementById("details-form").innerHTML = `
      <select id="kind_id" name="kind_id" required>
        <option value="">Select</option>
        <option value="virtual">Virtual</option>
      </select>
      <select id="category_id" name="category_id" required>
        <option value="">Select</option>
        <option value="general">General</option>
      </select>
    `;

    const reportCalls = [];
    const kindSelect = document.querySelector("#details-form #kind_id");
    const categorySelect = document.querySelector("#details-form #category_id");
    kindSelect.setCustomValidity("Please select an item in the list.");
    categorySelect.setCustomValidity("Please select an item in the list.");
    kindSelect.reportValidity = () => {
      reportCalls.push("kind_id");
      return false;
    };
    categorySelect.reportValidity = () => {
      reportCalls.push("category_id");
      return false;
    };

    initializeEventAddPage();

    const requestEvent = new CustomEvent("htmx:beforeRequest", {
      bubbles: true,
      cancelable: true,
      detail: {
        elt: document.getElementById("add-event-button"),
      },
    });

    document.getElementById("add-event-button").dispatchEvent(requestEvent);
    await waitForAnimationFrames(1);
    await waitForMicrotask();

    expect(requestEvent.defaultPrevented).to.equal(true);
    expect(reportCalls).to.deep.equal(["kind_id"]);
    expect(document.activeElement).to.equal(kindSelect);
  });

  it("updates add page recurrence labels and additional-occurrence controls", () => {
    // Verify updates add page recurrence labels.
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

    // Keep a reference to the starts at element.
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

    // Update the input before asserting it updates add page recurrence labels.
    startsAtInput.value = "2026-05-13T09:30";

    // Verify updates add page recurrence labels.
    initializeEventAddPage();

    // Verify updates add page recurrence labels and additional-occurrence controls.
    expect(optionText("weekly")).to.equal("Weekly on Wednesday");
    expect(optionText("biweekly")).to.equal("Every two weeks on Wednesday");
    expect(optionText("monthly")).to.equal("Monthly on the second Wednesday");
    expect(
      additionalOccurrencesContainer.classList.contains("hidden"),
    ).to.equal(true);
    expect(additionalOccurrencesInput.disabled).to.equal(true);
    expect(additionalOccurrencesInput.required).to.equal(false);
    expect(additionalOccurrencesInput.value).to.equal("");

    // Update the input before asserting it updates add page recurrence labels.
    additionalOccurrencesInput.value = "2";
    recurrencePatternSelect.value = "weekly";
    recurrencePatternSelect.dispatchEvent(
      new Event("change", { bubbles: true }),
    );

    // Verify updates add page recurrence labels and additional-occurrence controls.
    expect(
      additionalOccurrencesContainer.classList.contains("hidden"),
    ).to.equal(false);
    expect(additionalOccurrencesInput.disabled).to.equal(false);
    expect(additionalOccurrencesInput.required).to.equal(true);
    expect(additionalOccurrencesInput.value).to.equal("2");

    // Set the event start date used by recurrence labels.
    startsAtInput.value = "2026-05-20T09:30";
    startsAtInput.dispatchEvent(new Event("change", { bubbles: true }));

    // Verify updates add page recurrence labels and additional-occurrence controls.
    expect(optionText("monthly")).to.equal("Monthly on the third Wednesday");

    // Switch recurrence back to a single occurrence.
    recurrencePatternSelect.value = "just-once";
    recurrencePatternSelect.dispatchEvent(
      new Event("change", { bubbles: true }),
    );

    // Verify updates add page recurrence labels and additional-occurrence controls.
    expect(
      additionalOccurrencesContainer.classList.contains("hidden"),
    ).to.equal(true);
    expect(additionalOccurrencesInput.disabled).to.equal(true);
    expect(additionalOccurrencesInput.required).to.equal(false);
    expect(additionalOccurrencesInput.value).to.equal("");
  });

  it("re-syncs session bounds after rejecting an add page start date change", async () => {
    // Rejected add-page changes keep session bounds unchanged.
    mountAddPageShell();
    document
      .querySelector('[data-event-page="add"]')
      .insertAdjacentHTML(
        "beforeend",
        '<sessions-section></sessions-section><online-event-details id="online-event-details"></online-event-details>',
      );

    // Read the add page event and session date fields.
    const sessionsSection = document.querySelector("sessions-section");
    const onlineEventDetails = document.querySelector("online-event-details");
    const startsAtInput = document.getElementById("starts_at");
    const endsAtInput = document.getElementById("ends_at");

    // Set the event start date.
    startsAtInput.value = "2026-05-10T09:00";
    endsAtInput.value = "2026-05-10T11:00";
    onlineEventDetails.trySetStartsAt = async () => false;

    // Session bounds are restored after rejecting add-page changes.
    initializeEventAddPage();

    // Try moving the session outside the event date.
    startsAtInput.value = "2026-05-11T09:00";
    startsAtInput.dispatchEvent(new Event("change", { bubbles: true }));

    // Wait for queued event handlers to finish.
    await waitForMicrotask();

    // Rejected add-page start changes restore session bounds.
    expect(startsAtInput.value).to.equal("2026-05-10T09:00");
    expect(sessionsSection.eventStartsAt).to.equal("2026-05-10T09:00");
    expect(sessionsSection.eventEndsAt).to.equal("2026-05-10T11:00");
  });

  it("re-syncs session bounds after rejecting an update page end date change", async () => {
    // Rejected update-page changes keep session bounds unchanged.
    mountUpdatePageShell();
    document
      .querySelector('[data-event-page="update"]')
      .insertAdjacentHTML(
        "beforeend",
        '<sessions-section></sessions-section><online-event-details id="online-event-details"></online-event-details>',
      );

    // Read the update page event and session date fields.
    const sessionsSection = document.querySelector("sessions-section");
    const onlineEventDetails = document.querySelector("online-event-details");
    const startsAtInput = document.getElementById("starts_at");
    const endsAtInput = document.getElementById("ends_at");

    // Set the event start date.
    startsAtInput.value = "2026-05-10T09:00";
    endsAtInput.value = "2026-05-10T11:00";
    onlineEventDetails.trySetEndsAt = async () => false;

    // Session bounds are restored after rejecting update-page changes.
    initializeEventUpdatePage();

    // Try moving the session outside the updated end time.
    endsAtInput.value = "2026-05-10T12:30";
    endsAtInput.dispatchEvent(new Event("change", { bubbles: true }));

    // Wait for queued event handlers to finish.
    await waitForMicrotask();

    // Rejected update-page end changes restore session bounds.
    expect(endsAtInput.value).to.equal("2026-05-10T11:00");
    expect(sessionsSection.eventStartsAt).to.equal("2026-05-10T09:00");
    expect(sessionsSection.eventEndsAt).to.equal("2026-05-10T11:00");
  });

  it("initializes the update page and respects the page data contract", () => {
    // Mount the update page shell.
    mountUpdatePageShell();

    // Initialize the update page behavior.
    initializeEventUpdatePage();

    // Dispatch the click event.
    document
      .querySelector('[data-section="submissions"]')
      .dispatchEvent(new Event("click", { bubbles: true }));

    // Verify initializes the update page and respects the page data contract.
    expect(
      document.querySelector(".inert-form").hasAttribute("inert"),
    ).to.equal(false);
  });

  it("syncs past-event state into update page online details", () => {
    // Mount the update page shell for a past event.
    mountUpdatePageShell({ eventPast: true });
    document
      .querySelector('[data-event-page="update"]')
      .insertAdjacentHTML(
        "beforeend",
        '<online-event-details id="online-event-details"></online-event-details>',
      );

    // Initialize the update page behavior.
    initializeEventUpdatePage();

    // The online details component receives the past-event state.
    const onlineEventDetails = document.querySelector("online-event-details");
    expect(onlineEventDetails.eventPast).to.equal(true);
    expect(onlineEventDetails.hasAttribute("event-past")).to.equal(true);
  });

  it("syncs past-event state into update page session details", () => {
    // Mount the update page shell for a past event.
    mountUpdatePageShell({ eventPast: true });
    document
      .querySelector('[data-event-page="update"]')
      .insertAdjacentHTML("beforeend", "<sessions-section></sessions-section>");

    // Initialize the update page behavior.
    initializeEventUpdatePage();

    // The sessions component receives the past-event state for child meeting editors.
    const sessionsSection = document.querySelector("sessions-section");
    expect(sessionsSection.eventPast).to.equal(true);
    expect(sessionsSection.hasAttribute("event-past")).to.equal(true);
  });

  it("clears update page venue fields from the location clear button", () => {
    // Location clear events empty the update page venue fields.
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

    // Read the update page venue fields before clearing them.
    const locationSearchField = pageRoot.querySelector("location-search-field");
    let locationFieldsCleared = false;
    locationSearchField.clearLocationFields = () => {
      locationFieldsCleared = true;
    };

    // Clearing location data removes update page venue values.
    initializeEventUpdatePage();

    // Update page venue fields are empty after clearing.
    document.getElementById("clear-location-fields").click();

    // The update page clear button empties venue fields.
    expect(document.getElementById("venue_name").value).to.equal("");
    expect(document.getElementById("venue_address").value).to.equal("");
    expect(locationFieldsCleared).to.equal(true);
  });

  it("initializes update page fragments from the fragment root", () => {
    // Mount the update page shell.
    mountUpdatePageShell();
    const pageRoot = document.querySelector('[data-event-page="update"]');

    // Initialize the update page from the swapped fragment root.
    initializeEventUpdatePageRoots(pageRoot);

    // Verify the update page fragment is marked as initialized.
    expect(pageRoot.dataset.eventPageReady).to.equal("true");
  });

  it("initializes swapped update page fragments on htmx load", () => {
    // Mount the update page shell as swapped dashboard content.
    mountUpdatePageShell();

    // Dispatch the lifecycle event used by swapped dashboard content.
    dispatchHtmxLoad(document.querySelector('[data-event-page="update"]'));

    // Verify the update page fragment is initialized from the lifecycle event.
    expect(
      document.querySelector('[data-event-page="update"]').dataset.eventPageReady,
    ).to.equal("true");
  });

  it("keeps canceled event review tabs interactive for event managers", () => {
    // Mount the update page shell.
    mountUpdatePageShell({ canManageEvents: true, eventCanceled: true });

    // Initialize the update page behavior.
    initializeEventUpdatePage();

    // Dispatch the click event.
    document
      .querySelector('[data-section="attendees"]')
      .dispatchEvent(new Event("click", { bubbles: true }));

    // Verify keeps canceled event review tabs interactive for event managers.
    expect(
      document.querySelector(".inert-form").hasAttribute("inert"),
    ).to.equal(false);

    // Verify keeps canceled event review tabs interactive.
    document
      .querySelector('[data-section="details"]')
      .dispatchEvent(new Event("click", { bubbles: true }));

    // Verify keeps canceled event review tabs interactive for event managers.
    expect(
      document.querySelector(".inert-form").hasAttribute("inert"),
    ).to.equal(true);
  });

  it("warns before clearing capacity with a populated waitlist on the update page", async () => {
    // Mount the update page shell.
    mountUpdatePageShell({ canManageEvents: true });

    // Initialize the update page behavior.
    initializeEventUpdatePage();

    // Click the update button with a populated waitlist.
    document
      .getElementById("update-event-button")
      .dispatchEvent(
        new MouseEvent("click", { bubbles: true, cancelable: true }),
      );
    await waitForMicrotask();
    await waitForMicrotask();

    // Clearing capacity with a populated waitlist shows a warning.
    expect(swal.calls).to.have.length(1);
    expect(swal.calls[0].text).to.contain("currently on the waitlist");
    expect(htmx.triggerCalls).to.deep.equal([
      ["#update-event-button", "confirmed"],
    ]);
  });

  it("scopes add page initialization to the provided root", () => {
    // Render the DOM fixture for scoping add page initialization to the provided.
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

    // Keep a reference to the page root element.
    const pageRoot = document.getElementById("page-root");
    initializeEventAddPage(pageRoot);

    // Read controls from the scoped add page root.
    const scopedToggle = pageRoot.querySelector(
      "#toggle_registration_required",
    );
    scopedToggle.checked = true;
    scopedToggle.dispatchEvent(new Event("change", { bubbles: true }));

    // Verify scopes add page initialization to the provided root.
    expect(pageRoot.querySelector("#registration_required").value).to.equal(
      "true",
    );
    expect(
      document.querySelector("#outside #registration_required").value,
    ).to.equal("outside");
  });

  it("reconfigures ticketing editors to use scoped page dependencies", async () => {
    // Render the DOM fixture for reconfiguring ticketing editors to use scoped.
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

    // Keep a reference to the page root element.
    const pageRoot = document.getElementById("page-root");
    initializeEventAddPage(pageRoot);

    // Read the rendered DOM state for reconfiguring ticketing editors to use scoped page.
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

    // Ticketing editors use dependencies from the scoped page.
    expect(ticketTypesEditor.addButton).to.equal(scopedTicketButton);
    expect(ticketTypesEditor.currencyInput).to.equal(scopedCurrency);
    expect(ticketTypesEditor.timezoneInput).to.equal(scopedTimezone);
    expect(discountCodesEditor.addButton).to.equal(scopedDiscountButton);
    expect(discountCodesEditor.currencyInput).to.equal(scopedCurrency);
    expect(discountCodesEditor.timezoneInput).to.equal(scopedTimezone);

    // Ticketing editors use the scoped dependencies.
    scopedTicketButton.click();
    scopedDiscountButton.click();
    await ticketTypesEditor.updateComplete;
    await discountCodesEditor.updateComplete;

    // Reconfigured ticketing editors keep using scoped dependencies.
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
    // Render the DOM fixture for keeping venue changes scoped when switching.
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

    // Keep a reference to the page root element.
    const pageRoot = document.getElementById("page-root");
    const kindSelect = pageRoot.querySelector("#kind_id");
    swal.setNextResult({ isConfirmed: true });

    // Verify keeps venue changes scoped when switching the event.
    initializeEventAddPage(pageRoot);

    // Update the input before asserting it keeps venue changes scoped when switching.
    kindSelect.value = "virtual";
    kindSelect.dispatchEvent(new Event("change", { bubbles: true }));
    await waitForMicrotask();

    // Verify keeps venue changes scoped when switching the event kind.
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

    // Verify keeps venue changes scoped when switching the event kind.
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
    // Mount the update page shell.
    mountUpdatePageShell({ canManageEvents: true });

    // Initialize the update page behavior.
    initializeEventUpdatePage();
    initializeEventUpdatePage();

    // Click the update button after initializing twice.
    document
      .getElementById("update-event-button")
      .dispatchEvent(
        new MouseEvent("click", { bubbles: true, cancelable: true }),
      );

    // Initializing twice does not bind duplicate update handlers.
    expect(swal.calls).to.have.length(1);
  });

  it("syncs approved submissions only within the initialized update page root", () => {
    // Mount the managed update page and add an unrelated sessions section.
    mountUpdatePageShell({ canManageEvents: true });
    document.body.insertAdjacentHTML(
      "beforeend",
      '<sessions-section id="outside-sessions" approved-submissions=\'[{"cfs_submission_id":"outside"}]\'></sessions-section>',
    );

    // Keep a reference to the event page= element.
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

    // Initialize only the update page root.
    initializeEventUpdatePage(pageRoot);

    // Dispatch the approved submissions update.
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

    // Only sessions inside the initialized root receive the update.
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
    // Mount the update page shell.
    mountUpdatePageShell({ canManageEvents: true, waitlistCount: "0" });

    // Keep a reference to the event update page element.
    const pageRoot = document.getElementById("event-update-page");
    const refreshEvents = [];
    const bodyEvents = [];

    // Listen for refresh events on the page root and body.
    pageRoot.addEventListener("refresh-event-submissions", () => {
      refreshEvents.push("page");
    });
    document.body.addEventListener("refresh-event-submissions", () => {
      bodyEvents.push("body");
    });

    // Initialize the update page behavior.
    initializeEventUpdatePage();

    // Dispatch the successful update response.
    document.getElementById("update-event-button").dispatchEvent(
      new CustomEvent("htmx:afterRequest", {
        bubbles: true,
        detail: {
          elt: document.getElementById("update-event-button"),
          xhr: { status: 204 },
        },
      }),
    );

    // Submissions refresh is emitted from the update page root.
    expect(refreshEvents).to.deep.equal(["page"]);
    expect(bodyEvents).to.deep.equal([]);
  });
});
