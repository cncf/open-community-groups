import { expect } from "@open-wc/testing";

const loadTemplate = async () => {
  const response = await fetch("/ocg-server/templates/dashboard/group/waitlist_list.html");

  expect(response.ok).to.equal(true);

  return response.text();
};

const normalizeWhitespace = (value) => value.replace(/\s+/g, " ").trim();

describe("dashboard group waitlist list template", () => {
  it("renders row actions to invite waitlisted users", async () => {
    // Load the waitlist list template before checking invite action markup.
    const template = normalizeWhitespace(await loadTemplate());

    // Verify waitlisted users get an action menu with an invitation action.
    expect(template).to.include("data-events-list-page");
    expect(template).to.include("<span class=\"sr-only\">Actions</span>");
    expect(template).to.include(
      "can_manage_events && !event.canceled && !event.is_past() && !event.is_ticketed()",
    );
    expect(template).to.include(
      "Open waitlist actions for {{ entry.name|assigned_or(entry.username) }}",
    );
    expect(template).to.include('data-event-id="waitlist-{{ entry.user_id }}"');
    expect(template).to.include('id="dropdown-actions-waitlist-{{ entry.user_id }}"');
    expect(template).to.include("data-event-actions-dropdown");
    expect(template).to.include(
      'hx-post="/dashboard/group/events/{{ event.event_id }}/attendees/invite"',
    );
    expect(template).to.include('name="user_id" value="{{ entry.user_id }}"');
    expect(template).to.include("Invite user");
    expect(template).to.include('data-success-message="Invitation sent."');
    expect(template).to.include(
      'data-error-message="Something went wrong sending this invitation. Please try again later."',
    );
  });

  it("keeps waitlist actions disabled for unsupported invite states", async () => {
    // Load the waitlist list template before checking disabled invite states.
    const template = normalizeWhitespace(await loadTemplate());

    // Verify unsupported invite states keep the waitlist action unavailable.
    expect(template).to.include('title="Your role cannot invite attendees."');
    expect(template).to.include('title="Canceled events cannot invite attendees."');
    expect(template).to.include('title="Past events cannot invite attendees."');
    expect(template).to.include(
      'title="Manual invitations are not available for ticketed events."',
    );
    expect(template).to.include(
      "Waitlist actions unavailable for {{ entry.name|assigned_or(entry.username) }}",
    );
  });
});
