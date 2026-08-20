import { expect } from "@open-wc/testing";

const loadTemplate = async () => {
  const response = await fetch(
    "/ocg-server/templates/dashboard/user/home.html",
  );

  expect(response.ok).to.equal(true);

  return response.text();
};

describe("dashboard user home template", () => {
  it("inherits the shared dashboard base with the mobile Check-In layout", async () => {
    // Load the user dashboard shell before checking responsive layout ownership.
    const template = await loadTemplate();

    // Verify the page opts into the mobile Check-In layout over the shared base.
    expect(template).to.include('{% extends "dashboard/dashboard_base.html" -%}');
    expect(template).to.include(
      "{% if content.is_check_in() %}flex max-md:px-4 max-md:pb-4{% else %}hidden md:flex{% endif %}",
    );
  });

  it("shows the header menu trigger only on mobile Check-In", async () => {
    // Load the user dashboard shell before checking trigger visibility.
    const template = await loadTemplate();

    // Verify only the supported mobile dashboard surface displays the trigger.
    expect(template).to.include(
      "{% if content.is_check_in() %}inline-flex md:hidden{% else %}hidden{% endif %}",
    );
  });

  it("keeps only Check-In navigation in the mobile drawer menu", async () => {
    // Load the user dashboard shell before checking responsive navigation.
    const template = await loadTemplate();

    // Verify the notice stays conditional while the drawer offers Check-In only.
    expect(template).to.include("{% block mobile_dashboard_view -%}");
    expect(template).to.include("{% if !content.is_check_in() -%}");
    expect(template).to.include(
      'menu_item(name = "Check-In", icon = "qr-code", is_active = content.is_check_in() , href = "/dashboard/user?tab=check-in")',
    );
    expect(template).to.include('class="leading-10 grid gap-y-0.5 md:hidden"');
    expect(template).to.include('class="leading-10 grid gap-y-0.5 max-md:hidden"');
  });

  it("uses a compact purchases label through the large breakpoint", async () => {
    // Load the user dashboard shell before checking responsive navigation copy.
    const template = await loadTemplate();

    // Verify the item keeps its full label, compact fallback, and invoice icon.
    expect(template).to.include(
      'menu_item(name = "Purchases & documents", compact_name = "Purchases", icon = "invoice"',
    );
  });
});
