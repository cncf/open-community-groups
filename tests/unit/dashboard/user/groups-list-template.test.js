import { expect } from "@open-wc/testing";

const loadTemplate = async () => {
  const response = await fetch("/ocg-server/templates/dashboard/user/groups_list.html");

  expect(response.ok).to.equal(true);

  return response.text();
};

const normalizeWhitespace = (value) => value.replace(/\s+/g, " ").trim();

describe("dashboard user groups list template", () => {
  it("renders the group link with its community name and membership date", async () => {
    // Load the template before checking visible row information
    const template = normalizeWhitespace(await loadTemplate());

    // Verify the public link and minimal group information
    expect(template).to.include(
      'href="/{{ item.group.community_name }}/group/{{ item.group.public_slug() }}"',
    );
    expect(template).to.include("{{ item.group.name }}");
    expect(template).to.include("{{ item.group.community_display_name }}");
    expect(template).to.include('{{ item.joined_at.format("%b %d, %Y") }}');
  });

  it("renders leave group as a confirmed delete action for members", async () => {
    // Load the template before checking the destructive action contract
    const template = normalizeWhitespace(await loadTemplate());

    // Verify member rows use the shared confirmation flow
    expect(template).to.include("<span>Leave group</span>");
    expect(template).to.include('id="leave-group-{{ item.group.group_id }}"');
    expect(template).to.include("{% if item.is_member -%}");
    expect(template).to.include(
      'hx-delete="/dashboard/user/groups/{{ item.group.community_name }}/{{ item.group.group_id }}/membership"',
    );
    expect(template).to.include('hx-trigger="confirmed"');
    expect(template).to.include('hx-disabled-elt="this"');
    expect(template).to.include("data-confirm-action");
    expect(template).to.include('data-confirm-message="Are you sure you want to leave this group?"');
    expect(template).to.include('data-success-message="You have successfully left the group."');
  });

  it("renders explicit member and team member roles", async () => {
    // Load the template before checking relationship role badges
    const template = normalizeWhitespace(await loadTemplate());

    // Verify each relationship flag controls its corresponding visible role
    expect(template).to.include("{% if item.is_member -%}");
    expect(template).to.include("{% if item.is_team_member -%}");
    expect(template).to.include(
      'badges::common_badge(content = "Member", extra_styles = Some("px-2.5 py-0.5") )',
    );
    expect(template).to.include(
      'badges::common_badge(content = "Team member", extra_styles = Some("px-2.5 py-0.5") )',
    );
  });

  it("keeps leave group visible but disabled for team-only rows", async () => {
    // Load the template before checking the disabled action state
    const template = normalizeWhitespace(await loadTemplate());

    // Verify the unavailable action remains explained and accessible
    expect(template).to.include("disabled");
    expect(template).to.include('title="Team memberships cannot be left from My Groups."');
    expect(template).to.include('<span class="sr-only">Actions</span>');
    expect(template).to.include('aria-label="Open group actions for {{ item.group.name }}"');
    expect(template).to.include("data-actions-menu");
    expect(template).not.to.include('role="menu"');
    expect(template).not.to.include('role="menuitem"');
  });
});
