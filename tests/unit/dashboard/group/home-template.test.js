import { expect } from "@open-wc/testing";

const loadTemplate = async () => {
  const response = await fetch("/ocg-server/templates/dashboard/group/home.html");

  expect(response.ok).to.equal(true);

  return response.text();
};

const normalizeWhitespace = (value) => value.replace(/\s+/g, " ").trim();

describe("dashboard group home template", () => {
  it("groups badge tabs below events in the main dashboard menu", async () => {
    // Load the group dashboard shell before checking the navigation hierarchy.
    const template = normalizeWhitespace(await loadTemplate());

    // Verify the permission-gated section uses concise peer tab labels and routes.
    const eventsSection = template.indexOf('dashboard::menu_title(text = "Events"');
    const badgesSection = template.indexOf('dashboard::menu_title(text = "Badges"');
    const membersSection = template.indexOf('dashboard::menu_title(text = "Members and sponsors"');
    expect(eventsSection).to.be.greaterThan(-1);
    expect(badgesSection).to.be.greaterThan(eventsSection);
    expect(membersSection).to.be.greaterThan(badgesSection);
    expect(template).to.include(
      'dashboard::menu_item(name = "Badges", icon = "certificate", is_active = content.is_badges() , href = "/dashboard/group?tab=badges")',
    );
    expect(template).to.include(
      'dashboard::menu_item(name = "Artwork", icon = "image", is_active = content.is_artwork() , href = "/dashboard/group?tab=artwork")',
    );
    expect(template).to.include(
      'dashboard::menu_item(name = "Awards", icon = "star", is_active = content.is_awards() , href = "/dashboard/group?tab=awards")',
    );
  });

  it("uses the shared dashboard menu shell", async () => {
    // Load the group dashboard shell template before checking menu layout.
    const template = normalizeWhitespace(await loadTemplate());

    // Verify the group shell delegates shared title, spinner, and wrapper markup.
    expect(template).to.include(
      'dashboard::dashboard_menu_shell("Group Dashboard", spinner_classes = "hx-spinner -mt-0.5 relative")',
    );
    expect(template).not.to.include('id="dashboard-spinner" class="hx-spinner -mt-0.5 relative"');
    expect(template).not.to.include("max-h-full w-full flex flex-col flex-1");
  });

  it("keeps dashboard content at full minimum height", async () => {
    // Load the group dashboard shell template before checking content layout.
    const template = normalizeWhitespace(await loadTemplate());

    // Verify swapped dashboard content can fill the dashboard card.
    expect(template).to.include('id="dashboard-content"');
    expect(template).to.include(
      'class="flex min-h-full min-h-[calc(100dvh-7.5rem)] flex-col p-4 sm:p-6 lg:p-12"',
    );
  });

  it("gates the refunds tab without globally refreshing its partial", async () => {
    // Load the group dashboard shell template before checking refund navigation.
    const template = normalizeWhitespace(await loadTemplate());

    // Verify payment readiness controls the menu without intercepting refund action events globally.
    expect(template).to.include(
      '{% if payments_ready -%} {{ dashboard::menu_item(name = "Refunds", icon = "refund", is_active = content.is_refunds() , href = "/dashboard/group?tab=refunds") -}} {% endif -%}',
    );
    expect(template).to.include(
      'dashboard::menu_item(name = "Refunds", icon = "refund", is_active = content.is_refunds() , href = "/dashboard/group?tab=refunds")',
    );
    expect(template).to.include("else if content.is_refunds() -%}refunds");
    expect(template).not.to.include("refresh-group-refunds");
  });

  it("loads the shared user profile modal wiring", async () => {
    // Load the group dashboard shell template before checking profile modal wiring.
    const template = normalizeWhitespace(await loadTemplate());

    // Verify the dashboard shell loads one trigger module and one modal component.
    expect(template).to.include('src="/static/js/common/users/user-profile-modal-triggers.js"');
    expect(template).to.include(
      '<script type="module" src="/static/js/common/modals/user-info-modal.js"></script>',
    );
    expect(template).to.include("<user-info-modal></user-info-modal>");
  });
});
