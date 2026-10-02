import { expect } from "@open-wc/testing";

const loadTemplate = async () => {
  const response = await fetch(
    "/ocg-server/templates/dashboard/user/home.html",
  );

  expect(response.ok).to.equal(true);

  return response.text();
};

describe("dashboard user home template", () => {
  it("keeps only Check-In content visible below md", async () => {
    // Load the user dashboard shell before checking responsive content ownership.
    const template = await loadTemplate();

    // Verify Check-In stays visible while unsupported content, including Inbox, yields to the placeholder.
    expect(template).to.include('{% extends "dashboard/dashboard_base.html" -%}');
    expect(template).to.include("{% if content.is_check_in() %}block{% else %}hidden md:block{% endif %}");
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
    expect(
      template.split(
        'menu_item(name = "Inbox", icon = "email", is_active = content.is_inbox() , href = "/dashboard/user?tab=inbox")',
      ).length,
    ).to.equal(2);
    const mobileMenu = template.slice(
      template.indexOf("{# Events check-in (mobile only) -#}"),
      template.indexOf("{# End events check-in (mobile only) -#}"),
    );
    expect(mobileMenu).not.to.include('name = "Inbox"');
    expect(template).to.include('hx-get="/dashboard/user/{{ content.refresh_path() }}"');
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

  it("loads notification scripts and links the notifications menu item", async () => {
    // Load the user dashboard shell before checking the notifications contracts.
    const template = await loadTemplate();

    // Verify the account settings script was replaced by the notification modules.
    expect(template).to.include('src="/static/js/dashboard/user/notification-group-mutes.js"');
    expect(template).to.include('src="/static/js/dashboard/user/notification-preferences.js"');

    // Verify the dashboard exposes the Notifications menu item.
    expect(template).to.include(
      'menu_item(name = "Notifications", icon = "bell", is_active = content.is_notifications() , href = "/dashboard/user?tab=notifications")',
    );
  });
});
