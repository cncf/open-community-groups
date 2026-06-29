import { expect } from "@open-wc/testing";

const loadTemplate = async () => {
  const response = await fetch("/ocg-server/templates/dashboard/group/waitlist_list.html");

  expect(response.ok).to.equal(true);

  return response.text();
};

const normalizeWhitespace = (value) => value.replace(/\s+/g, " ").trim();

describe("dashboard group waitlist list template", () => {
  it("renders waitlist identity cells as profile modal triggers", async () => {
    // Load the waitlist list template before checking profile trigger markup.
    const template = normalizeWhitespace(await loadTemplate());

    // Verify the waitlist identity area opens the shared user profile modal.
    expect(template).to.include('<button type="button"');
    expect(template).to.include("data-user-profile-modal");
    expect(template).to.include("data-user-profile='{{ entry.user|json }}'");
    expect(template).to.include(
      'aria-label="View profile for {{ entry.user.name.as_deref() |assigned_or(entry.user.username) }}"',
    );
  });

  it("uses the shared search convention for table filtering", async () => {
    // Load the waitlist list template before checking search markup.
    const template = normalizeWhitespace(await loadTemplate());

    // Verify waitlist search follows the existing dashboard HTMX pattern.
    expect(template).to.include('id="waitlist-search-form"');
    expect(template).to.include('hx-get="/dashboard/group/events/{{ event.event_id }}/waitlist"');
    expect(template).to.include('hx-trigger="change, submit"');
    expect(template).to.include('hx-target="#waitlist-content"');
    expect(template).to.include('<label for="search_waitlist" class="sr-only">Search waitlist</label>');
    expect(template).to.include('name="ts_query"');
    expect(template).to.include('value="{{ ts_query|assigned_or("") }}"');
    expect(template).to.include('placeholder="Search waitlist"');
    expect(template).to.include('aria-label="Clear waitlist search"');
    expect(template).to.include("dashboard/placeholders/group_waitlist_no_results.html");
    expect(template).to.include("{{ entry.waitlist_position }}");
    expect(template).not.to.include("{{ refresh_offset + loop.index }}");
  });

  it("preserves current filters for waitlist refreshes", async () => {
    // Load the waitlist list template before checking refresh markup.
    const template = normalizeWhitespace(await loadTemplate());

    // Verify action-triggered refreshes reuse the handler-built filtered URL.
    expect(template).to.include('id="waitlist-refresh"');
    expect(template).to.include('hx-get="{{ refresh_url }}"');
    expect(template).to.include('hx-trigger="refresh-event-waitlist from:body"');
    expect(template).not.to.include("refresh_limit");
  });

  it("renders row actions to invite waitlisted users", async () => {
    // Load the waitlist list template before checking invite action markup.
    const template = normalizeWhitespace(await loadTemplate());

    // Verify waitlisted users get an action menu with an invitation action.
    expect(template).to.include("data-events-list-page");
    expect(template).to.include('<span class="sr-only">Actions</span>');
    expect(template).to.include(
      "can_manage_events && !event.canceled && !event.is_past() && !event.is_ticketed()",
    );
    expect(template).to.include(
      "Open waitlist actions for {{ entry.user.name.as_deref() |assigned_or(entry.user.username) }}",
    );
    expect(template).to.include('data-event-id="waitlist-{{ entry.user.user_id }}"');
    expect(template).to.include('id="dropdown-actions-waitlist-{{ entry.user.user_id }}"');
    expect(template).to.include("data-event-actions-dropdown");
    expect(template).to.include('hx-post="/dashboard/group/events/{{ event.event_id }}/attendees/invite"');
    expect(template).to.include('name="user_id" value="{{ entry.user.user_id }}"');
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
    expect(template).to.include('title="Manual invitations are not available for ticketed events."');
    expect(template).to.include(
      "Waitlist actions unavailable for {{ entry.user.name.as_deref() |assigned_or(entry.user.username) }}",
    );
  });
});
