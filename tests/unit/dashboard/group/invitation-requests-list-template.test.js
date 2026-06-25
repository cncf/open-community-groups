import { expect } from "@open-wc/testing";

const loadTemplate = async () => {
  const response = await fetch("/ocg-server/templates/dashboard/group/invitation_requests_list.html");

  expect(response.ok).to.equal(true);

  return response.text();
};

const normalizeWhitespace = (value) => value.replace(/\s+/g, " ").trim();

describe("dashboard group invitation requests list template", () => {
  it("uses the shared search convention for table filtering", async () => {
    // Load the invitation requests list template before checking search markup.
    const template = normalizeWhitespace(await loadTemplate());

    // Verify invitation request search follows the existing dashboard HTMX pattern.
    expect(template).to.include('id="invitation-requests-search-form"');
    expect(template).to.include('hx-get="/dashboard/group/events/{{ event.event_id }}/invitation-requests"');
    expect(template).to.include('hx-trigger="change, submit"');
    expect(template).to.include('hx-target="#invitation-requests-content"');
    expect(template).to.include(
      '<label for="search_invitation_requests" class="sr-only">Search invitation requests</label>',
    );
    expect(template).to.include('name="ts_query"');
    expect(template).to.include('value="{{ ts_query|assigned_or("") }}"');
    expect(template).to.include('placeholder="Search requests"');
    expect(template).to.include('aria-label="Clear invitation request search"');
    expect(template).to.include("dashboard/placeholders/group_invitation_requests_no_results.html");
  });

  it("preserves current filters for invitation request refreshes", async () => {
    // Load the invitation requests list template before checking refresh markup.
    const template = normalizeWhitespace(await loadTemplate());

    // Verify action-triggered refreshes reuse the handler-built filtered URL.
    expect(template).to.include('id="invitation-requests-refresh"');
    expect(template).to.include('hx-get="{{ refresh_url }}"');
    expect(template).to.include('hx-trigger="refresh-event-invitation-requests from:body"');
    expect(template).not.to.include("refresh_limit");
  });
});
