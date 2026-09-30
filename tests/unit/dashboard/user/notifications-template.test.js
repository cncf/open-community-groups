import { expect } from "@open-wc/testing";

const loadTemplate = async (path) => {
  const response = await fetch(path);

  expect(response.ok).to.equal(true);

  return response.text();
};

describe("dashboard user notifications template", () => {
  it("keeps notification preference field contracts and section guards", async () => {
    // Load the notifications template before checking form and conditional section contracts.
    const template = await loadTemplate("/ocg-server/templates/dashboard/user/notifications.html");

    // Verify the preference form and toggle macro submit the server-owned field names.
    expect(template).to.include('id="notification-preferences-form"');
    expect(template).to.include('hx-put="/dashboard/user/notifications/preferences"');
    expect(template).to.include('name="preferences[{{ category }}]"');
    expect(template).to.include('id="preference-{{ category }}"');
    expect(template).to.include('data-preference-input="preference-{{ category }}"');

    // Verify organizer-only sections remain guarded.
    expect(template).to.include("{% if show_group_team_section -%}");
    expect(template).to.include("{% if show_community_team_section -%}");
  });

  it("keeps muted groups wrapper permanent around the inner partial", async () => {
    // Load the notifications template before checking HTMX refresh ownership.
    const template = await loadTemplate("/ocg-server/templates/dashboard/user/notifications.html");

    // Verify HTMX refreshes only replace inner content and keep the wrapper trigger alive.
    expect(template).to.include('id="muted-groups"');
    expect(template).to.include('hx-get="/dashboard/user/notifications/muted-groups"');
    expect(template).to.include('hx-trigger="refresh-muted-groups from:body"');
    expect(template).to.include('hx-swap="innerHTML"');
    expect(template).to.include('{% include "dashboard/user/notifications_muted_groups.html" -%}');
  });

  it("keeps muted group unmute rows on the partial contract", async () => {
    // Load the muted groups partial before checking row action contracts.
    const template = await loadTemplate("/ocg-server/templates/dashboard/user/notifications_muted_groups.html");

    // Verify each row uses the shared logo component and HTMX unmute action.
    expect(template).to.include("<logo-image");
    expect(template).to.include('hx-delete="/dashboard/user/notifications/muted-groups/{{ group.group_id }}"');
    expect(template).to.include('hx-swap="none"');
    expect(template).to.include("data-htmx-response");
    expect(template).to.include('aria-label="Unmute {{ group.name }}"');
    expect(template).to.include("You haven't muted any groups.");
  });
});
