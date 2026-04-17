import { expect } from "@open-wc/testing";

import { initializeEventAddPage } from "/static/js/dashboard/group/event-add-page.js";
import { initializeEventUpdatePage } from "/static/js/dashboard/group/event-update-page.js";
import { resetDom } from "/tests/unit/test-utils/dom.js";
import { mockSwal } from "/tests/unit/test-utils/globals.js";

const mountSharedEventForms = () => {
  document.body.innerHTML = `
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
};

describe("event page modules", () => {
  let swal;

  beforeEach(() => {
    resetDom();
    delete document.body.dataset.approvedSubmissionsSyncBound;
    swal = mockSwal();
  });

  afterEach(() => {
    resetDom();
    delete document.body.dataset.approvedSubmissionsSyncBound;
    swal.restore();
  });

  it("initializes the add page and syncs boolean hidden fields", () => {
    mountSharedEventForms();
    document.body.insertAdjacentHTML(
      "beforeend",
      `
        <button id="add-event-button" type="button"></button>
        <button id="cancel-button" type="button"></button>
        <button data-section="details" data-active="true" class="active">Details</button>
        <button data-section="sessions" data-active="false">Sessions</button>
        <section data-content="details"></section>
        <section data-content="sessions" class="hidden"></section>
      `,
    );

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
    mountSharedEventForms();
    document.body.insertAdjacentHTML(
      "beforeend",
      `
        <button id="add-event-button" type="button"></button>
        <button id="cancel-button" type="button"></button>
        <button data-section="details" data-active="true" class="active">Details</button>
        <button data-section="sessions" data-active="false">Sessions</button>
        <section data-content="details"></section>
        <section data-content="sessions" class="hidden"></section>
      `,
    );

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

  it("initializes the update page and respects the page data contract", () => {
    mountSharedEventForms();
    document.body.insertAdjacentHTML(
      "afterbegin",
      `
        <div data-event-past="false" data-can-manage-events="false">
          <button data-section="details" data-active="true" class="active">Details</button>
          <button data-section="submissions" data-active="false">Submissions</button>
          <section data-content="details"></section>
          <section data-content="submissions" class="hidden"></section>
          <div class="inert-form" inert></div>
        </div>
      `,
    );
    document.body.insertAdjacentHTML(
      "beforeend",
      `
        <button id="update-event-button" type="button" data-waitlist-count="2"></button>
        <button id="cancel-button" type="button"></button>
      `,
    );

    initializeEventUpdatePage();

    document
      .querySelector('[data-section="submissions"]')
      .dispatchEvent(new Event("click", { bubbles: true }));

    expect(document.querySelector(".inert-form").hasAttribute("inert")).to.equal(false);
  });

  it("warns before clearing capacity with a populated waitlist on the update page", () => {
    mountSharedEventForms();
    document.body.insertAdjacentHTML(
      "afterbegin",
      `
        <div data-event-past="false" data-can-manage-events="true">
          <button data-section="details" data-active="true" class="active">Details</button>
          <section data-content="details"></section>
          <div class="inert-form"></div>
        </div>
      `,
    );
    document.body.insertAdjacentHTML(
      "beforeend",
      `
        <input id="capacity" value="" />
        <button id="update-event-button" type="button" data-waitlist-count="2"></button>
        <button id="cancel-button" type="button"></button>
      `,
    );

    initializeEventUpdatePage();

    document
      .getElementById("update-event-button")
      .dispatchEvent(new MouseEvent("click", { bubbles: true, cancelable: true }));

    expect(swal.calls).to.have.length(1);
    expect(swal.calls[0].text).to.contain("currently on the waitlist");
  });
});
