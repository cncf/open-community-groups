import { expect } from "@open-wc/testing";

import "/static/js/dashboard/event/ticketing/discount-codes-editor.js";
import "/static/js/dashboard/event/ticketing/ticket-types-editor.js";
import { initializeEventAddPage } from "/static/js/dashboard/group/event-add-page.js";
import { initializeEventUpdatePage } from "/static/js/dashboard/group/event-update-page.js";
import { waitForMicrotask } from "/tests/unit/test-utils/async.js";
import { resetDom } from "/tests/unit/test-utils/dom.js";
import { mockHtmx, mockSwal } from "/tests/unit/test-utils/globals.js";

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

const mountUpdatePageShell = ({ canManageEvents = false, waitlistCount = "2" } = {}) => {
  document.body.innerHTML = `
    <div id="event-update-page"
         data-event-page="update"
         data-event-past="false"
         data-can-manage-events="${String(canManageEvents)}">
      ${sharedEventFormsMarkup()}
      <button data-section="details" data-active="true" class="active">Details</button>
      <button data-section="submissions" data-active="false">Submissions</button>
      <section data-content="details"></section>
      <section data-content="submissions" class="hidden"></section>
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
    mountAddPageShell();

    initializeEventAddPage();

    const registrationToggle = document.getElementById("toggle_registration_required");
    const reminderToggle = document.getElementById("toggle_event_reminder_enabled");

    registrationToggle.checked = true;
    registrationToggle.dispatchEvent(new Event("change", { bubbles: true }));
    reminderToggle.checked = true;
    reminderToggle.dispatchEvent(new Event("change", { bubbles: true }));

    expect(document.getElementById("registration_required").value).to.equal("true");
    expect(document.getElementById("event_reminder_enabled").value).to.equal("true");
  });

  it("converts event and session dates during add page HTMX config requests", () => {
    mountAddPageShell();

    initializeEventAddPage();

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

    document.getElementById("add-event-button").dispatchEvent(requestEvent);

    expect(requestEvent.detail.parameters.starts_at).to.equal("2026-05-10T09:30:00");
    expect(requestEvent.detail.parameters.ends_at).to.equal("2026-05-10T11:00:00");
    expect(requestEvent.detail.parameters["sessions[0][starts_at]"]).to.equal(
      "2026-05-10T10:00:00",
    );
  });

  it("re-syncs session bounds after rejecting an add page start date change", async () => {
    mountAddPageShell();
    document
      .querySelector('[data-event-page="add"]')
      .insertAdjacentHTML(
        "beforeend",
        '<sessions-section></sessions-section><online-event-details id="online-event-details"></online-event-details>',
      );

    const sessionsSection = document.querySelector("sessions-section");
    const onlineEventDetails = document.querySelector("online-event-details");
    const startsAtInput = document.getElementById("starts_at");
    const endsAtInput = document.getElementById("ends_at");

    startsAtInput.value = "2026-05-10T09:00";
    endsAtInput.value = "2026-05-10T11:00";
    onlineEventDetails.trySetStartsAt = async () => false;

    initializeEventAddPage();

    startsAtInput.value = "2026-05-11T09:00";
    startsAtInput.dispatchEvent(new Event("change", { bubbles: true }));

    await waitForMicrotask();

    expect(startsAtInput.value).to.equal("2026-05-10T09:00");
    expect(sessionsSection.eventStartsAt).to.equal("2026-05-10T09:00");
    expect(sessionsSection.eventEndsAt).to.equal("2026-05-10T11:00");
  });

  it("re-syncs session bounds after rejecting an update page end date change", async () => {
    mountUpdatePageShell();
    document
      .querySelector('[data-event-page="update"]')
      .insertAdjacentHTML(
        "beforeend",
        '<sessions-section></sessions-section><online-event-details id="online-event-details"></online-event-details>',
      );

    const sessionsSection = document.querySelector("sessions-section");
    const onlineEventDetails = document.querySelector("online-event-details");
    const startsAtInput = document.getElementById("starts_at");
    const endsAtInput = document.getElementById("ends_at");

    startsAtInput.value = "2026-05-10T09:00";
    endsAtInput.value = "2026-05-10T11:00";
    onlineEventDetails.trySetEndsAt = async () => false;

    initializeEventUpdatePage();

    endsAtInput.value = "2026-05-10T12:30";
    endsAtInput.dispatchEvent(new Event("change", { bubbles: true }));

    await waitForMicrotask();

    expect(endsAtInput.value).to.equal("2026-05-10T11:00");
    expect(sessionsSection.eventStartsAt).to.equal("2026-05-10T09:00");
    expect(sessionsSection.eventEndsAt).to.equal("2026-05-10T11:00");
  });

  it("initializes the update page and respects the page data contract", () => {
    mountUpdatePageShell();

    initializeEventUpdatePage();

    document
      .querySelector('[data-section="submissions"]')
      .dispatchEvent(new Event("click", { bubbles: true }));

    expect(document.querySelector(".inert-form").hasAttribute("inert")).to.equal(false);
  });

  it("warns before clearing capacity with a populated waitlist on the update page", async () => {
    mountUpdatePageShell({ canManageEvents: true });

    initializeEventUpdatePage();

    document
      .getElementById("update-event-button")
      .dispatchEvent(new MouseEvent("click", { bubbles: true, cancelable: true }));
    await waitForMicrotask();
    await waitForMicrotask();

    expect(swal.calls).to.have.length(1);
    expect(swal.calls[0].text).to.contain("currently on the waitlist");
    expect(htmx.triggerCalls).to.deep.equal([["#update-event-button", "confirmed"]]);
  });

  it("scopes add page initialization to the provided root", () => {
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

    const pageRoot = document.getElementById("page-root");
    initializeEventAddPage(pageRoot);

    const scopedToggle = pageRoot.querySelector('#toggle_registration_required');
    scopedToggle.checked = true;
    scopedToggle.dispatchEvent(new Event("change", { bubbles: true }));

    expect(pageRoot.querySelector("#registration_required").value).to.equal("true");
    expect(document.querySelector("#outside #registration_required").value).to.equal("outside");
  });

  it("reconfigures ticketing editors to use scoped page dependencies", async () => {
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

    const pageRoot = document.getElementById("page-root");
    initializeEventAddPage(pageRoot);

    const ticketTypesEditor = pageRoot.querySelector("#ticket-types-ui");
    const discountCodesEditor = pageRoot.querySelector("#discount-codes-ui");
    const scopedTicketButton = pageRoot.querySelector("#add-ticket-type-button");
    const scopedDiscountButton = pageRoot.querySelector("#add-discount-code-button");
    const scopedCurrency = pageRoot.querySelector("#payment_currency_code");
    const scopedTimezone = pageRoot.querySelector('[name="timezone"]');

    expect(ticketTypesEditor.addButton).to.equal(scopedTicketButton);
    expect(ticketTypesEditor.currencyInput).to.equal(scopedCurrency);
    expect(ticketTypesEditor.timezoneInput).to.equal(scopedTimezone);
    expect(discountCodesEditor.addButton).to.equal(scopedDiscountButton);
    expect(discountCodesEditor.currencyInput).to.equal(scopedCurrency);
    expect(discountCodesEditor.timezoneInput).to.equal(scopedTimezone);

    scopedTicketButton.click();
    scopedDiscountButton.click();
    await ticketTypesEditor.updateComplete;
    await discountCodesEditor.updateComplete;

    expect(ticketTypesEditor.textContent).to.contain("Price (EUR)");
    expect(ticketTypesEditor.querySelector('[data-ticketing-role="ticket-modal"]')?.classList.contains("hidden")).to
      .equal(false);
    expect(
      discountCodesEditor.querySelector('[data-ticketing-role="discount-modal"]')?.classList.contains("hidden"),
    ).to.equal(false);
  });

  it("keeps venue changes scoped when switching the event kind", async () => {
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

    const pageRoot = document.getElementById("page-root");
    const kindSelect = pageRoot.querySelector("#kind_id");
    swal.setNextResult({ isConfirmed: true });

    initializeEventAddPage(pageRoot);

    kindSelect.value = "virtual";
    kindSelect.dispatchEvent(new Event("change", { bubbles: true }));
    await waitForMicrotask();

    expect(pageRoot.querySelector("#venue_name")?.value).to.equal("");
    expect(pageRoot.querySelector("#venue_address")?.value).to.equal("");
    expect(pageRoot.querySelector("#venue-information-section")?.classList.contains("hidden")).to.equal(true);
    expect(pageRoot.querySelector("#online-event-details-section")?.classList.contains("hidden")).to.equal(false);

    expect(document.querySelector("#outside-root #venue_name")?.value).to.equal("Outside hall");
    expect(document.querySelector("#outside-root #venue_address")?.value).to.equal("Outside street");
    expect(
      document.querySelector("#outside-root #venue-information-section")?.classList.contains("hidden"),
    ).to.equal(true);
  });

  it("does not bind duplicate update page handlers when initialized twice", () => {
    mountUpdatePageShell({ canManageEvents: true });

    initializeEventUpdatePage();
    initializeEventUpdatePage();

    document
      .getElementById("update-event-button")
      .dispatchEvent(new MouseEvent("click", { bubbles: true, cancelable: true }));

    expect(swal.calls).to.have.length(1);
  });

  it("syncs approved submissions only within the initialized update page root", () => {
    mountUpdatePageShell({ canManageEvents: true });
    document.body.insertAdjacentHTML(
      "beforeend",
      '<sessions-section id="outside-sessions" approved-submissions=\'[{"cfs_submission_id":"outside"}]\'></sessions-section>',
    );

    const pageRoot = document.querySelector('[data-event-page="update"]');
    const scopedSessions = document.createElement("sessions-section");
    scopedSessions.id = "scoped-sessions";
    scopedSessions.setAttribute(
      "approved-submissions",
      JSON.stringify([{ cfs_submission_id: "12", title: "Old title", speaker_name: "Ada" }]),
    );
    scopedSessions.requestUpdate = () => {
      scopedSessions.dataset.updated = "true";
    };
    pageRoot.append(scopedSessions);

    initializeEventUpdatePage(pageRoot);

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
    expect(document.getElementById("outside-sessions").getAttribute("approved-submissions")).to.equal(
      '[{"cfs_submission_id":"outside"}]',
    );
  });

  it("dispatches submissions refresh from the update page root after a successful save", () => {
    mountUpdatePageShell({ canManageEvents: true, waitlistCount: "0" });

    const pageRoot = document.getElementById("event-update-page");
    const refreshEvents = [];
    const bodyEvents = [];

    pageRoot.addEventListener("refresh-event-submissions", () => {
      refreshEvents.push("page");
    });
    document.body.addEventListener("refresh-event-submissions", () => {
      bodyEvents.push("body");
    });

    initializeEventUpdatePage();

    document.getElementById("update-event-button").dispatchEvent(
      new CustomEvent("htmx:afterRequest", {
        bubbles: true,
        detail: {
          elt: document.getElementById("update-event-button"),
          xhr: { status: 204 },
        },
      }),
    );

    expect(refreshEvents).to.deep.equal(["page"]);
    expect(bodyEvents).to.deep.equal([]);
  });
});
