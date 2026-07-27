import { expect, waitUntil } from "@open-wc/testing";

import { initializeAttendeeBadgeAwards } from "/static/js/dashboard/group/attendees/badge-awards.js";

describe("attendee badge awards", () => {
  let originalFetch;

  beforeEach(() => {
    originalFetch = window.fetch;
  });

  afterEach(() => {
    document.querySelector("[data-test-attendee-badges]")?.remove();
    document.querySelector("badge-award-modal")?.remove();
    window.fetch = originalFetch;
  });

  it("resolves a bypass scope before opening the shared modal", async () => {
    // Mock the recipient resolver for one seeded event attendee.
    const recipientId = "00000000-0000-0000-0000-000000000001";
    const eventId = "00000000-0000-0000-0000-000000000002";
    const requests = [];
    window.fetch = async (url) => {
      requests.push(String(url));
      return new Response(JSON.stringify({ user_ids: [recipientId] }), {
        headers: { "Content-Type": "application/json" },
      });
    };

    // Render and initialize the scoped attendee award trigger.
    const modal = document.createElement("badge-award-modal");
    let openInput;
    modal.open = (input) => {
      openInput = input;
    };
    const root = document.createElement("section");
    root.dataset.testAttendeeBadges = "";
    root.innerHTML = `<button
      type="button"
      data-attendee-badge-recipients-open
      data-event-id="${eventId}"
      data-recipient-scope="checked-in-attendees"
    >Checked-in attendees</button>`;
    document.body.append(modal, root);
    initializeAttendeeBadgeAwards(root);

    // Open the trigger and wait for the shared award modal.
    const trigger = root.querySelector("button");
    trigger.click();
    await waitUntil(() => Boolean(openInput), "the shared award modal should open");

    // Verify the resolved recipient and event context reach the modal.
    expect(requests).to.deep.equal([
      `/dashboard/group/events/${eventId}/badges/recipients?scope=checked-in-attendees`,
    ]);
    expect(openInput.eventId).to.equal(eventId);
    expect(openInput.trigger).to.equal(trigger);
    expect(openInput.userIds).to.deep.equal([recipientId]);
    expect(trigger.disabled).to.equal(false);
  });
});
