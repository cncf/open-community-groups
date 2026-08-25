import { expect } from "@open-wc/testing";

const loadTemplate = async () => {
  const response = await fetch("/ocg-server/templates/dashboard/dashboard_base.html");

  expect(response.ok).to.equal(true);

  return response.text();
};

const normalizeWhitespace = (value) => value.replace(/\s+/g, " ").trim();

describe("dashboard base template", () => {
  it("renders the menu as a closed drawer on mobile and a sticky sidebar on desktop", async () => {
    // Load the dashboard base before checking the responsive menu contract.
    const template = normalizeWhitespace(await loadTemplate());

    // Verify a single aside owns both the mobile drawer and the desktop menu.
    expect(template).to.include('<aside id="dashboard-menu-drawer"');
    expect(template).to.include("-translate-x-full");
    expect(template).to.include("bg-stone-100");
    expect(template).to.include("md:sticky");
    expect(template).to.include("md:translate-x-0");
    expect(template).to.include('tabindex="-1"');
  });

  it("wires the mobile drawer controls and backdrop", async () => {
    // Load the dashboard base before checking the drawer control contract.
    const template = normalizeWhitespace(await loadTemplate());

    // Verify the open button, close button, and backdrop keep their drawer wiring.
    expect(template).to.include('<button id="open-dashboard-menu"');
    expect(template).to.include('aria-controls="dashboard-menu-drawer"');
    expect(template).to.include('aria-expanded="false"');
    expect(template).to.include('<button id="close-dashboard-menu"');
    expect(template).to.include("focus-visible:ring-primary-500");
    expect(template).to.include('<div id="dashboard-menu-backdrop"');
    expect(template).to.include("z-[1050]");
  });

  it("renders the mobile drawer trigger in the dashboard header below md", async () => {
    // Load the dashboard base before checking trigger placement and visibility.
    const template = normalizeWhitespace(await loadTemplate());

    // Verify the trigger belongs to the header and follows the drawer breakpoint.
    const headerStart = template.indexOf('id="dashboard-header"');
    const trigger = template.indexOf('id="open-dashboard-menu"');
    const sharedHeader = template.indexOf('{% include "common/header.html" -%}');
    const mainStart = template.indexOf('id="dashboard-main-content"');
    expect(trigger).to.be.greaterThan(headerStart);
    expect(trigger).to.be.lessThan(sharedHeader);
    expect(trigger).to.be.lessThan(mainStart);
    const triggerMarkup = template.slice(trigger, sharedHeader);
    expect(triggerMarkup).to.include("focus-visible:ring-primary-500");
    expect(triggerMarkup).to.include("md:hidden");
  });

  it("keeps the drawer mounted while unsupported content is hidden on mobile", async () => {
    // Load the dashboard base before checking the shared responsive contract.
    const template = normalizeWhitespace(await loadTemplate());

    // Verify the shell stays mounted and only the unsupported main is hidden.
    expect(template).to.include(
      '<div id="dashboard-layout" class="flex max-md:grow max-md:px-4 max-md:pb-4">',
    );
    expect(template).to.include(
      "{% block dashboard_main_classes -%}hidden md:block{% endblock dashboard_main_classes -%}",
    );
  });
});
