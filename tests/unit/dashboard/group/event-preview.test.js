import { expect } from "@open-wc/testing";

import {
  buildEventPreviewPayload,
  initializeEventPreview,
  openEventPreviewModal,
} from "/static/js/dashboard/group/event-preview.js";
import { waitForMicrotask } from "/tests/unit/test-utils/async.js";
import { useDashboardTestEnv } from "/tests/unit/test-utils/env.js";
import { mockFetch } from "/tests/unit/test-utils/network.js";

// Mount preview page for the test.
const mountPreviewPage = ({ testEvent = false } = {}) => {
  document.body.innerHTML = `
    <div id="dashboard-content"
         data-alliance="test-alliance"
         data-alliance-display-name="Test Alliance"
         data-alliance-logo-url="/alliance.svg"
         data-alliance-banner-url="/alliance-banner.png"
         data-group-name="Test Group"
         data-group-slug="test-group">
      <div data-event-page="add">
        <form id="details-form">
          <input name="name" value="Draft Event" />
          <input name="capacity" value="" />
          <input name="meetup_url" value="https://meetup.example/events/draft" />
          <input name="luma_url" value="https://luma.example/draft" />
          <input name="toggle_registration_required" value="on" />
          <input id="test_event"
                 name="test_event"
                 type="hidden"
                 value="${testEvent ? "true" : "false"}" />
          <select id="kind_id" name="kind_id">
            <option value="">Select</option>
            <option value="hybrid" selected>Hybrid</option>
          </select>
          <select id="category_id" name="category_id">
            <option value="">Select</option>
            <option value="cat-1" selected>Meetup</option>
          </select>
          <textarea name="description">Draft description</textarea>
        </form>
        <form id="date-venue-form">
          <input name="starts_at" value="2026-06-01T18:30" />
          <input name="timezone" value="America/Los_Angeles" />
        </form>
        <form id="sessions-form">
          <input name="sessions[0][name]" value="Opening session" />
          <input name="sessions[0][starts_at]" value="2026-06-01T19:00" />
        </form>
        <form id="hosts-sponsors-form">
          <user-search-selector field-name="hosts"></user-search-selector>
          <speakers-selector field-name-prefix="speakers"></speakers-selector>
          <sponsors-section></sponsors-section>
        </form>
        <form id="payments-form">
          <input name="payment_currency_code" value="USD" />
          <input name="ticket_types[0][title]" value="General admission" />
          <input name="ticket_types[0][price_windows][0][price]" value="25.00" />
        </form>
        <form id="cfs-form"></form>
        <sessions-section></sessions-section>
        <button id="event-preview-button" type="button">Preview</button>
      </div>
      <div id="event-preview-modal-root"></div>
    </div>
  `;

  const pageRoot = document.querySelector('[data-event-page="add"]');
  pageRoot.querySelector("user-search-selector").selectedUsers = [
    {
      company: "Example",
      name: "Host User",
      photo_url: "/host.png",
      title: "Organizer",
      username: "host-user",
    },
  ];
  pageRoot.querySelector("speakers-selector").selectedSpeakers = [
    {
      featured: true,
      name: "Speaker User",
      username: "speaker-user",
    },
  ];
  pageRoot.querySelector("sponsors-section").selectedSponsors = [
    {
      level: "Gold",
      logo_url: "/sponsor.png",
      name: "Sponsor Co",
      website_url: "https://example.test",
    },
  ];
  const sessionsSection = pageRoot.querySelector("sessions-section");
  sessionsSection.sessionKinds = [
    { display_name: "Talk", session_kind_id: "talk" },
  ];
  sessionsSection.sessions = [
    {
      kind: "talk",
      name: "Opening session",
      speakers: [{ name: "Session Speaker", username: "session-speaker" }],
    },
  ];

  return pageRoot;
};

describe("event preview", () => {
  useDashboardTestEnv({
    path: "/dashboard/group?tab=events",
    withSwal: true,
  });

  it("builds a preview payload from current form state and display context", () => {
    // Prepare page root for building a preview payload from current form state.
    const pageRoot = mountPreviewPage();

    // Prepare payload for building a preview payload from current form state.
    const payload = buildEventPreviewPayload(pageRoot);
    const context = JSON.parse(payload.get("preview_context"));

    // Verify builds a preview payload from current form state and display context.
    expect(payload.get("name")).to.equal("Draft Event");
    expect(payload.get("capacity")).to.equal(null);
    expect(payload.get("meetup_url")).to.equal(null);
    expect(payload.get("luma_url")).to.equal(null);
    expect(payload.get("payment_currency_code")).to.equal(null);
    expect(payload.get("ticket_types[0][title]")).to.equal(null);
    expect(payload.get("ticket_types[0][price_windows][0][price]")).to.equal(
      null,
    );
    expect(payload.get("toggle_registration_required")).to.equal(null);
    expect(payload.get("starts_at")).to.equal("2026-06-01T18:30:00");
    expect(payload.get("timezone")).to.equal("PDT");
    expect(payload.get("sessions[0][starts_at]")).to.equal(
      "2026-06-01T19:00:00",
    );
    expect(context.kind_label).to.equal("Hybrid");
    expect(context.category_label).to.equal("Meetup");
    expect(context.alliance.display_name).to.equal("Test Alliance");
    expect(context.group.name).to.equal("Test Group");
    expect(context.hosts[0].name).to.equal("Host User");
    expect(context.speakers[0].featured).to.equal(true);
    expect(context.sponsors[0].name).to.equal("Sponsor Co");
    expect(context.sessions[0].kind_label).to.equal("Talk");
    expect(context.sessions[0].speakers[0].name).to.equal("Session Speaker");
  });

  it("posts the preview payload and opens the returned modal", async () => {
    // Prepare page root for posting the preview payload and opens the returned.
    const pageRoot = mountPreviewPage();
    const fetchMock = mockFetch({
      impl: async () =>
        new Response(
          `<div id="event-preview-modal" data-event-preview-modal>
            <div data-event-preview-social-links class="hidden md:flex">
              <div data-event-preview-social-links-list></div>
            </div>
            <div data-event-preview-social-links class="hidden mt-4 md:hidden">
              <div data-event-preview-social-links-list></div>
            </div>
            <button type="button" data-event-preview-close>Close</button>
          </div>`,
          {
            headers: { "Content-Type": "text/html" },
            status: 200,
          },
        ),
    });

    // Assert the page root.
    try {
      expect(pageRoot.querySelector("#event-preview-modal-root")).to.equal(
        null,
      );

      // Initialize event preview behavior.
      initializeEventPreview({
        pageRoot,
      });
      pageRoot.querySelector("#event-preview-button").click();
      await waitForMicrotask();
      await waitForMicrotask();

      // Posting the preview payload opens the returned modal.
      expect(fetchMock.calls).to.have.length(1);
      expect(fetchMock.calls[0][0]).to.equal("/dashboard/group/events/preview");
      expect(fetchMock.calls[0][1].method).to.equal("POST");
      expect(fetchMock.calls[0][1].body.get("name")).to.equal("Draft Event");
      expect(document.querySelector("#event-preview-modal")).to.not.equal(null);
      expect(
        document.querySelector('[title="Meetup"]')?.getAttribute("href"),
      ).to.equal("https://meetup.example/events/draft");
      expect(
        document.querySelector('[title="Luma"]')?.getAttribute("href"),
      ).to.equal("https://luma.example/draft");
      const socialContainers = [
        ...document.querySelectorAll("[data-event-preview-social-links]"),
      ];
      expect(socialContainers[0].classList.contains("hidden")).to.equal(true);
      expect(socialContainers[1].classList.contains("hidden")).to.equal(false);
      expect(document.body.dataset.modalOpenCount).to.equal("1");

      // The preview modal receives the returned markup.
      document.querySelector("[data-event-preview-close]").click();

      // The returned modal is marked as open.
      expect(document.querySelector("#event-preview-modal")).to.equal(null);
      expect(document.body.dataset.modalOpenCount).to.equal("0");
    } finally {
      fetchMock.restore();
    }
  });

  it("does not render a login page response inside the preview modal", async () => {
    // Prepare page root for a preview response that returned the login page.
    const pageRoot = mountPreviewPage();
    const loginResponse = new Response(`<main><h1>Log In</h1></main>`, {
      headers: { "Content-Type": "text/html" },
      status: 200,
    });
    Object.defineProperty(loginResponse, "url", {
      value: "http://localhost/log-in?next_url=%2Fdashboard%2Fgroup%3Ftab%3Devents",
    });
    const fetchMock = mockFetch({ response: loginResponse });

    try {
      // Initialize event preview behavior.
      initializeEventPreview({ pageRoot });
      pageRoot.querySelector("#event-preview-button").click();
      await waitForMicrotask();
      await waitForMicrotask();

      // Verify the login page was not rendered inside the preview modal.
      expect(fetchMock.calls).to.have.length(1);
      expect(document.querySelector("#event-preview-modal")).to.equal(null);
      expect(document.querySelector("#event-preview-modal-root").innerHTML).to.equal("");
    } finally {
      fetchMock.restore();
    }
  });

  it("shows the test badge in the preview modal when test event is enabled", () => {
    // Prepare page root for showing the test badge in the preview modal when test.
    const pageRoot = mountPreviewPage({ testEvent: true });
    const modalRoot = document.getElementById("event-preview-modal-root");

    // Verify shows the test badge in the preview modal when test.
    openEventPreviewModal(
      modalRoot,
      `<div id="event-preview-modal">
        <div class="flex flex-wrap items-center gap-1.5">
          <span class="custom-badge">Hybrid</span>
          <span class="custom-badge hidden bg-amber-100 border-amber-800 text-amber-800"
                data-event-preview-test-badge>Test</span>
        </div>
        <button type="button" data-event-preview-close>Close</button>
      </div>`,
      pageRoot,
    );

    // Read the preview modal after rendering a test event.
    const testBadge = modalRoot.querySelector(
      "[data-event-preview-test-badge]",
    );
    expect(testBadge.classList.contains("hidden")).to.equal(false);
    expect(testBadge.textContent.trim()).to.equal("Test");

    // Verify shows the test badge in the preview modal.
    modalRoot.querySelector("[data-event-preview-close]").click();
  });
});
