import { expect } from "@open-wc/testing";

const loadTemplate = async () => {
  const response = await fetch("/ocg-server/templates/dashboard/group/home.html");

  expect(response.ok).to.equal(true);

  return response.text();
};

const normalizeWhitespace = (value) => value.replace(/\s+/g, " ").trim();

describe("dashboard group home template", () => {
  it("inherits the shared dashboard base with the mobile Check-In layout", async () => {
    // Load the group dashboard shell before checking responsive layout ownership.
    const template = await loadTemplate();

    // Verify the page opts into the mobile Check-In layout over the shared base.
    expect(template).to.include('{% extends "dashboard/dashboard_base.html" -%}');
    expect(template).to.include(
      "{% if content.is_check_in() || is_check_in_fallback %}flex max-md:px-4 max-md:pb-4{% else %}hidden md:flex{% endif %}",
    );
  });

  it("shows the header menu trigger only on mobile Check-In", async () => {
    // Load the group dashboard shell before checking trigger visibility.
    const template = await loadTemplate();

    // Verify Check-In and its fallback display the trigger only below medium.
    expect(template).to.include(
      "{% if content.is_check_in() || is_check_in_fallback %}inline-flex md:hidden{% else %}hidden{% endif %}",
    );
  });

  it("keeps the check-in fallback warning inside the main content wrapper", async () => {
    // Load the group dashboard shell before checking the fallback surface.
    const template = normalizeWhitespace(await loadTemplate());

    // Verify the fallback keeps the standard wrapper with only the warning on mobile.
    expect(template).to.include(
      'dashboard::permission_warning(message = "You cannot manage check-ins for the selected group.", extra_classes = "mb-6 md:hidden")',
    );
    expect(template).to.include('<div class="max-md:hidden">{{ content|safe }}</div>');
    expect(template).to.include("{% if !content.is_check_in() && !is_check_in_fallback -%}");
    expect(template).not.to.include("mobile_selectors");
    expect(template).not.to.include("data-check-in-fallback-overlay");
  });

  it("keeps only Check-In and the selectors in the mobile drawer menu", async () => {
    // Load the group dashboard shell before checking responsive navigation.
    const template = normalizeWhitespace(await loadTemplate());

    // Verify non Check-In navigation stays hidden below the medium breakpoint.
    expect(template).to.include('<div class="mt-6 grid gap-y-0.5 max-md:hidden">');
    expect(template).to.include(
      'dashboard::menu_item(name = "Events", icon = "calendar", is_active = content.is_events() , href = "/dashboard/group?tab=events", extra_styles = "max-md:hidden")',
    );
    expect(template).to.include(
      'dashboard::menu_item(name = "Check-In", icon = "qr-code", is_active = content.is_check_in() , href = "/dashboard/group?tab=check-in")',
    );

    // Verify the drawer keeps a mobile-only Check-In entry for read-only groups.
    expect(template).to.include(
      'dashboard::menu_item(name = "Check-In", icon = "qr-code", is_active = is_check_in_fallback , href = "/dashboard/group?tab=check-in", extra_styles = "md:hidden")',
    );
  });

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
      'dashboard::dashboard_menu_shell( "Group Dashboard", spinner_classes = "hx-spinner -mt-0.5 relative", navigation_target = "#dashboard-layout", navigation_select = "#dashboard-layout", navigation_select_oob = "#mobile-dashboard-view:outerHTML,#open-dashboard-menu:outerHTML", navigation_swap = "outerHTML show:window:top" )',
    );
    expect(template).to.include('id="mobile-dashboard-view" class="contents"');
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

  it("keeps refund history accessible without globally refreshing its partial", async () => {
    // Load the group dashboard shell template before checking refund navigation.
    const template = normalizeWhitespace(await loadTemplate());

    // Verify the history tab remains available while unavailable provider actions receive a warning.
    expect(template).to.include(
      'dashboard::menu_item(name = "Refunds", icon = "refund", is_active = content.is_refunds() , href = "/dashboard/group?tab=refunds", extra_styles = "max-md:hidden")',
    );
    expect(template).to.include("{% if content.is_refunds() && !payments_ready -%}");
    expect(template).to.include("Historical refunds and recovery records remain accessible");
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

  it("loads group settings form validation", async () => {
    const template = normalizeWhitespace(await loadTemplate());

    expect(template).to.include(
      '<script type="module" src="/static/js/dashboard/group/settings-form.js"></script>',
    );
  });
});
