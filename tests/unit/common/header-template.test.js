import { expect } from "@open-wc/testing";

const loadTemplate = async (path = "common/header.html") => {
  const response = await fetch(`/ocg-server/templates/${path}`);

  expect(response.ok).to.equal(true);

  return response.text();
};

const normalizeWhitespace = (value) => value.replace(/\s+/g, " ").trim();

describe("common header template", () => {
  it("exposes logged-in profile completion state on the user menu button", async () => {
    // Load the header template before checking user menu data markers.
    const template = normalizeWhitespace(await loadTemplate());

    // Verify public pages can read the backend profile completion flag.
    expect(template).to.include('id="user-dropdown-button"');
    expect(template).to.include('data-logged-in="true"');
    expect(template).to.include('data-profile-complete="{{ user.profile_complete }}"');
  });

  it("labels the mobile check-in links by their actions", async () => {
    // Load the header template before checking mobile check-in navigation.
    const template = normalizeWhitespace(await loadTemplate());

    // Verify each mobile link describes its attendee action.
    expect(template).to.include(
      'href="/dashboard/user?tab=check-in" hx-boost="true" hx-target="body" class="inline-block w-full text-start px-4 py-2 hover:bg-stone-100" role="menuitem"> <div class="flex items-center"> <div class="svg-icon size-4 icon-events bg-stone-600"></div> <div class="ms-2 text-xs/6">Check in</div>',
    );
    expect(template).to.include(
      'href="/dashboard/group?tab=check-in" hx-boost="true" hx-target="body" class="inline-block w-full text-start px-4 py-2 hover:bg-stone-100" role="menuitem"> <div class="flex items-center"> <div class="svg-icon size-4 icon-qr-code bg-stone-600"></div> <div class="ms-2 text-xs/6">Scan attendees</div>',
    );
  });

  it("swaps check-in shortcuts for dashboard links at the md breakpoint", async () => {
    // Load the header template and isolate the logged-in menu.
    const template = normalizeWhitespace(await loadTemplate());
    const loggedInMenu = template.slice(
      0,
      template.indexOf("{# User dropdown menu for non-logged users -#}"),
    );

    // Verify the check-in shortcuts only show below md.
    expect(loggedInMenu).to.include(
      '<li class="md:hidden" role="none"> <a href="/dashboard/user?tab=check-in"',
    );
    expect(loggedInMenu).to.include(
      '<li class="md:hidden" role="none"> <a href="/dashboard/group?tab=check-in"',
    );

    // Verify every dashboard entry point and its divider show from md.
    [
      "/dashboard/community",
      "/dashboard/group",
      "/dashboard/user",
      "/dashboard/user?tab=groups",
      "/dashboard/user?tab=events",
      "/dashboard/group?tab=events",
    ].forEach((href) => {
      expect(loggedInMenu, href).to.include(`<li class="hidden md:block" role="none"> <a href="${href}"`);
    });
    expect(loggedInMenu).to.include(
      '{# End dashboard links -#} <li class="hidden md:block border-t border-stone-200 mt-2 pt-2" role="separator" aria-hidden="true"></li> {# Quick access links -#}',
    );

    // Verify the public destination copies still follow the lg desktop navigation.
    expect(loggedInMenu).to.include('<li class="lg:hidden" role="none"> <a href="/"');
    expect(loggedInMenu).not.to.include("hidden lg:block");
  });

  it("renders the dashboard links above the labeled quick access shortcuts", async () => {
    // Load the header template and isolate the logged-in menu.
    const template = normalizeWhitespace(await loadTemplate());
    const loggedInMenu = template.slice(
      0,
      template.indexOf("{# User dropdown menu for non-logged users -#}"),
    );
    const indexOf = (value) => {
      const index = loggedInMenu.indexOf(value);
      expect(index, value).to.be.greaterThan(-1);
      return index;
    };

    // Verify the dashboard links use sentence case labels.
    ["Community dashboard", "Group dashboard", "User dashboard"].forEach((label) => {
      expect(loggedInMenu).to.include(`<div class="ms-2 text-xs/6">${label}</div>`);
    });

    // Verify the dashboards section comes before the quick access section.
    expect(indexOf('<a href="/dashboard/user" ')).to.be.lessThan(indexOf("{# Quick access links -#}"));

    // Verify the quick access title and subtitles use distinct heading styles.
    expect(loggedInMenu).to.include(
      '<li id="user-menu-quick-access-title" class="px-4 pt-1 text-[11px]/6 font-semibold uppercase tracking-wide text-stone-600" role="none">Quick access</li>',
    );
    expect(loggedInMenu).to.include(
      '<div id="user-menu-quick-access-user-title" class="px-4 pt-1 text-xs/6 font-medium text-stone-500">User dashboard</div>',
    );
    expect(loggedInMenu).to.include(
      '<div id="user-menu-quick-access-group-title" class="px-4 pt-1 text-xs/6 font-medium text-stone-500">Group dashboard</div>',
    );

    // Verify each shortcut group is named by the title and its subtitle.
    const userGroupIndex = indexOf(
      '<ul role="group" aria-labelledby="user-menu-quick-access-title user-menu-quick-access-user-title">',
    );
    const groupGroupIndex = indexOf(
      '<ul role="group" aria-labelledby="user-menu-quick-access-title user-menu-quick-access-group-title">',
    );

    // Verify user shortcuts sit in the user group and group shortcuts in the group group.
    ["/dashboard/user?tab=check-in", "/dashboard/user?tab=groups", "/dashboard/user?tab=events"].forEach(
      (href) => {
        const index = indexOf(`<a href="${href}"`);
        expect(index, href).to.be.greaterThan(userGroupIndex);
        expect(index, href).to.be.lessThan(groupGroupIndex);
      },
    );
    ["/dashboard/group?tab=check-in", "/dashboard/group?tab=events"].forEach((href) => {
      expect(indexOf(`<a href="${href}"`), href).to.be.greaterThan(groupGroupIndex);
    });

    // Verify the group shortcuts are gated by group team membership.
    expect(loggedInMenu).to.include(
      '{# Group dashboard shortcuts -#} {% if user.belongs_to_any_group_team.unwrap_or(false) -%} <li role="none"> <div id="user-menu-quick-access-group-title"',
    );
    expect(loggedInMenu).to.include('<div class="ms-2 text-xs/6">Events</div>');
  });

  it("renders mutually exclusive desktop and mobile version menu items", async () => {
    // Load the header macros before checking the viewport mode toggle markup.
    const template = normalizeWhitespace(await loadTemplate("macros/header.html"));
    const macro = template.slice(template.indexOf("{% macro viewport_mode_items() -%}"));

    // Verify no standalone separator item is rendered; each entry carries its own divider.
    expect(macro).not.to.include('role="separator"');

    // Verify the desktop entry targets narrow touch devices still in the default mode.
    expect(macro).to.include(
      '<li class="hidden max-xl:pointer-coarse:not-viewport-desktop:block border-t border-stone-200 mt-2 pt-2" role="none"> <button type="button" data-viewport-mode="desktop" class="block w-full text-start px-4 py-2 hover:bg-stone-100" role="menuitem"> <span class="flex items-center"> <span class="svg-icon size-4 icon-desktop bg-stone-600"></span> <span class="ms-2 text-xs/6">Desktop version</span>',
    );

    // Verify the mobile entry only depends on the desktop mode attribute.
    expect(macro).to.include(
      '<li class="hidden viewport-desktop:block border-t border-stone-200 mt-2 pt-2" role="none"> <button type="button" data-viewport-mode="default" class="block w-full text-start px-4 py-2 hover:bg-stone-100" role="menuitem"> <span class="flex items-center"> <span class="svg-icon size-4 icon-mobile bg-stone-600"></span> <span class="ms-2 text-xs/6">Mobile version</span>',
    );
  });

  it("offers the viewport mode toggle in both user menu variants", async () => {
    // Load the header template before checking where the toggle is rendered.
    const template = normalizeWhitespace(await loadTemplate());

    // Verify both the logged-in and guest menus render the shared macro once.
    const calls = [...template.matchAll(/\{\{ header::viewport_mode_items\(\) -\}\}/g)];
    expect(calls).to.have.lengthOf(2);

    // Verify the logged-in toggle sits before the log-out form.
    const logoutIndex = template.indexOf('<form action="/log-out"');
    const guestMenuIndex = template.indexOf("{# User dropdown menu for non-logged users -#}");
    expect(calls[0].index).to.be.lessThan(logoutIndex);
    expect(logoutIndex).to.be.lessThan(guestMenuIndex);
    expect(calls[1].index).to.be.greaterThan(guestMenuIndex);
  });
});
