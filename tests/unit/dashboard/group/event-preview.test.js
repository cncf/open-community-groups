import { expect } from "@open-wc/testing";

import {
  buildEventPreviewPayload,
  initializeEventPreview,
} from "/static/js/dashboard/group/event-preview.js";
import { waitForMicrotask } from "/tests/unit/test-utils/async.js";
import { useDashboardTestEnv } from "/tests/unit/test-utils/env.js";
import { mockFetch } from "/tests/unit/test-utils/network.js";

const mountPreviewPage = () => {
  document.body.innerHTML = `
    <div id="dashboard-content"
         data-community="test-community"
         data-community-display-name="Test Community"
         data-community-logo-url="/community.svg"
         data-community-banner-url="/community-banner.png"
         data-group-name="Test Group"
         data-group-slug="test-group">
      <div data-event-page="add">
        <form id="details-form">
          <input name="name" value="Draft Event" />
          <input name="capacity" value="" />
          <input name="toggle_registration_required" value="on" />
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
        <form id="payments-form"></form>
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
  sessionsSection.sessionKinds = [{ display_name: "Talk", session_kind_id: "talk" }];
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
    const pageRoot = mountPreviewPage();

    const payload = buildEventPreviewPayload(pageRoot);
    const context = JSON.parse(payload.get("preview_context"));

    expect(payload.get("name")).to.equal("Draft Event");
    expect(payload.get("capacity")).to.equal(null);
    expect(payload.get("toggle_registration_required")).to.equal(null);
    expect(payload.get("starts_at")).to.equal("2026-06-01T18:30:00");
    expect(payload.get("timezone")).to.equal("PDT");
    expect(payload.get("sessions[0][starts_at]")).to.equal("2026-06-01T19:00:00");
    expect(context.kind_label).to.equal("Hybrid");
    expect(context.category_label).to.equal("Meetup");
    expect(context.community.display_name).to.equal("Test Community");
    expect(context.group.name).to.equal("Test Group");
    expect(context.hosts[0].name).to.equal("Host User");
    expect(context.speakers[0].featured).to.equal(true);
    expect(context.sponsors[0].name).to.equal("Sponsor Co");
    expect(context.sessions[0].kind_label).to.equal("Talk");
    expect(context.sessions[0].speakers[0].name).to.equal("Session Speaker");
  });

  it("posts the preview payload and opens the returned modal", async () => {
    const pageRoot = mountPreviewPage();
    const fetchMock = mockFetch({
      impl: async () =>
        new Response(
          '<div id="event-preview-modal"><button type="button" data-event-preview-close>Close</button></div>',
          {
            headers: { "Content-Type": "text/html" },
            status: 200,
          },
        ),
    });

    try {
      expect(pageRoot.querySelector("#event-preview-modal-root")).to.equal(null);

      initializeEventPreview({
        pageRoot,
      });
      pageRoot.querySelector("#event-preview-button").click();
      await waitForMicrotask();
      await waitForMicrotask();

      expect(fetchMock.calls).to.have.length(1);
      expect(fetchMock.calls[0][0]).to.equal("/dashboard/group/events/preview");
      expect(fetchMock.calls[0][1].method).to.equal("POST");
      expect(fetchMock.calls[0][1].body.get("name")).to.equal("Draft Event");
      expect(document.querySelector("#event-preview-modal")).to.not.equal(null);
      expect(document.body.dataset.modalOpenCount).to.equal("1");

      document.querySelector("[data-event-preview-close]").click();

      expect(document.querySelector("#event-preview-modal")).to.equal(null);
      expect(document.body.dataset.modalOpenCount).to.equal("0");
    } finally {
      fetchMock.restore();
    }
  });
});
