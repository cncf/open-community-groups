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

  it("swaps check-in shortcuts for dashboard links at md or with a fine pointer", async () => {
    // Load the header template and isolate the logged-in menu.
    const template = normalizeWhitespace(await loadTemplate());
    const loggedInMenu = template.slice(
      0,
      template.indexOf("{# User dropdown menu for non-logged users -#}"),
    );

    // Verify the check-in shortcuts only show on narrow touch screens.
    expect(loggedInMenu).to.include(
      '<li class="md:hidden pointer-fine:hidden" role="none"> <a href="/dashboard/user?tab=check-in"',
    );
    expect(loggedInMenu).to.include(
      '<li class="md:hidden pointer-fine:hidden" role="none"> <a href="/dashboard/group?tab=check-in"',
    );

    // Verify every dashboard entry point shows from md or with a fine pointer.
    [
      "/dashboard/community",
      "/dashboard/user?tab=groups",
      "/dashboard/user?tab=events",
      "/dashboard/group?tab=events",
    ].forEach((href) => {
      expect(loggedInMenu, href).to.include(
        `<li class="hidden md:block pointer-fine:block" role="none"> <a href="${href}"`,
      );
    });
    ["group", "user"].forEach((dashboard) => {
      expect(loggedInMenu, dashboard).to.include(
        `<a id="user-menu-${dashboard}-dashboard-link" href="/dashboard/${dashboard}" hx-boost="true" hx-target="body" class="hidden md:inline-block pointer-fine:inline-block w-full text-start px-4 py-2 hover:bg-stone-100" role="menuitem">`,
      );
    });
    expect(loggedInMenu).not.to.include('class="hidden md:block border-t');

    // Verify the public destination copies still follow the lg desktop navigation.
    expect(loggedInMenu).to.include('<li class="lg:hidden" role="none"> <a href="/"');
    expect(loggedInMenu).not.to.include("hidden lg:block");
  });

  it("nests the dashboard shortcuts under their dashboard links", async () => {
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

    // Verify each shortcut group follows and is named by its dashboard link.
    const groupLinkIndex = indexOf('<a id="user-menu-group-dashboard-link"');
    const groupShortcutsIndex = indexOf(
      '</a> <ul role="group" aria-labelledby="user-menu-group-dashboard-link">',
    );
    const userLinkIndex = indexOf('<a id="user-menu-user-dashboard-link"');
    const userShortcutsIndex = indexOf(
      '</a> <ul role="group" aria-labelledby="user-menu-user-dashboard-link">',
    );
    expect(indexOf('<a href="/dashboard/community"')).to.be.lessThan(groupLinkIndex);
    expect(groupLinkIndex).to.be.lessThan(groupShortcutsIndex);
    expect(groupShortcutsIndex).to.be.lessThan(userLinkIndex);
    expect(userLinkIndex).to.be.lessThan(userShortcutsIndex);

    // Verify the shortcuts sit in their dashboard group.
    ["/dashboard/group?tab=check-in", "/dashboard/group?tab=events"].forEach((href) => {
      const index = indexOf(`<a href="${href}"`);
      expect(index, href).to.be.greaterThan(groupShortcutsIndex);
      expect(index, href).to.be.lessThan(userLinkIndex);
    });
    ["/dashboard/user?tab=check-in", "/dashboard/user?tab=groups", "/dashboard/user?tab=events"].forEach(
      (href) => {
        expect(indexOf(`<a href="${href}"`), href).to.be.greaterThan(userShortcutsIndex);
      },
    );

    // Verify the md shortcuts are indented under their parents while mobile ones are not.
    ["/dashboard/user?tab=groups", "/dashboard/user?tab=events", "/dashboard/group?tab=events"].forEach(
      (href) => {
        expect(loggedInMenu, href).to.include(
          `<a href="${href}" hx-boost="true" hx-target="body" class="inline-block w-full text-start ps-10 pe-4 py-2 hover:bg-stone-100" role="menuitem">`,
        );
      },
    );
    ["/dashboard/user?tab=check-in", "/dashboard/group?tab=check-in"].forEach((href) => {
      expect(loggedInMenu, href).to.include(
        `<a href="${href}" hx-boost="true" hx-target="body" class="inline-block w-full text-start px-4 py-2 hover:bg-stone-100" role="menuitem">`,
      );
    });

    // Verify the group links are gated by group team membership.
    expect(loggedInMenu).to.include(
      '{% if user.belongs_to_any_group_team.unwrap_or(false) -%} <li role="none"> <a id="user-menu-group-dashboard-link"',
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

  it("adds the phone Invitations row after Check in", async () => {
    // Load the header template and isolate the logged-in menu.
    const template = normalizeWhitespace(await loadTemplate());
    const loggedInMenu = template.slice(
      0,
      template.indexOf("{# User dropdown menu for non-logged users -#}"),
    );

    // Verify the row has the check-in shape and only renders on phones.
    expect(loggedInMenu).to.include(
      '<li class="not-phone:hidden" role="none"> <a href="/dashboard/user?tab=invitations" hx-boost="true" hx-target="body" class="inline-block w-full text-start px-4 py-2 hover:bg-stone-100" role="menuitem"> <div class="flex items-center"> <div class="svg-icon size-4 icon-pending-invitation bg-stone-600"></div> <div class="ms-2 text-xs/6">Invitations</div>',
    );

    // Verify it sits between Check in and the desktop shortcuts.
    const invitationsIndex = loggedInMenu.indexOf('href="/dashboard/user?tab=invitations"');
    expect(invitationsIndex).to.be.greaterThan(loggedInMenu.indexOf('href="/dashboard/user?tab=check-in"'));
    expect(invitationsIndex).to.be.lessThan(loggedInMenu.indexOf('href="/dashboard/user?tab=groups"'));
  });

  it("renders the phone menu button only where the user menu section loads", async () => {
    // Load the header template before checking the button.
    const template = normalizeWhitespace(await loadTemplate());
    const button = template.slice(
      template.indexOf('<button id="open-site-menu"'),
      template.indexOf("{# End open menu button (phone only) -#}"),
    );

    // Verify it shares the condition of the section placeholder.
    expect(template).to.include('{% if loads_user_menu -%} <button id="open-site-menu"');
    expect(template).to.include('{% if loads_user_menu -%} <div hx-get="/section/user-menu"');

    // Verify it stays out of desktop and waits for the sheet to mount.
    expect(button).to.include("not-phone:hidden");
    expect(button).to.include("phone:size-11");
    expect(button).to.include("icon-lines");
    expect(button).to.include('aria-label="Open menu"');
    expect(button).to.include(" disabled>");
  });

  it("shows the site title on phones when there is no logo, except where it repeats", async () => {
    // Load the header template before checking the logo fallback.
    const template = normalizeWhitespace(await loadTemplate());

    // Verify the fallback is guarded on logos, dashboards and Home.
    expect(template).to.include(
      '{% let shows_phone_title = site_settings.header_logo_url.is_none() && !path.starts_with("/dashboard") && path != "/" -%}',
    );

    // Verify it swaps the desktop link for a phone-only one named after the visible title.
    expect(template).to.include(
      'class="inline-flex phone:min-w-0 {% if shows_phone_title %}phone:hidden{% endif %}">',
    );
    expect(template).to.include(
      '{% if shows_phone_title -%} <a href="/" aria-label="Go to {{ site_settings.title }} homepage" class="not-phone:hidden flex items-center min-w-0 h-11 me-3"> <span class="truncate text-lg font-semibold text-stone-900">{{ site_settings.title }}</span> </a> {% endif -%}',
    );
  });

  it("marks both user menus as the account sheet", async () => {
    // Load the header template before checking the sheet hooks.
    const template = normalizeWhitespace(await loadTemplate());

    // Verify the single dropdown stays a menu in both variants.
    expect([...template.matchAll(/<div id="user-dropdown"/g)]).to.have.lengthOf(2);
    expect(
      [...template.matchAll(/rounded-lg shadow border border-stone-200 account-sheet" role="menu">/g)],
    ).to.have.lengthOf(2);
    expect(
      [
        ...template.matchAll(
          /<ul class="text-stone-700 my-2 sheet-panel sheet-body" role="none"> \{\{ header::account_sheet_head\(\) -\}\}/g,
        ),
      ],
    ).to.have.lengthOf(2);

    // Verify the guest actions become pills with DOM order unchanged.
    const signUpIndex = template.indexOf(
      '<li class="account-sheet-cta account-sheet-cta-fill" role="none"> <a href="/sign-up"',
    );
    const logInIndex = template.indexOf('<li class="account-sheet-cta" role="none"> <a href="/log-in"');
    expect(signUpIndex).to.be.greaterThan(-1);
    expect(logInIndex).to.be.greaterThan(signUpIndex);
  });

  it("gives the sheet head a phone-only title and a close control", async () => {
    // Load the header macros before checking the sheet head.
    const template = normalizeWhitespace(await loadTemplate("macros/header.html"));

    // Verify the head keeps the menu roles and offers a direct close icon.
    expect(template).to.include(
      '<li class="sheet-head sheet-grab not-phone:hidden" role="none"> <span aria-hidden="true">Menu</span>',
    );
    expect(template).to.include('role="menuitem" aria-label="Close menu"> <div class="svg-icon size-4 icon-close"></div>');
  });

  it("adds only phone tokens to the identity row and trigger", async () => {
    // Load the header template before checking the phone tokens.
    const template = normalizeWhitespace(await loadTemplate());

    // Verify the header and its triggers reach their phone sizes.
    expect(template).to.include("h-20 min-h-20 phone:h-[63px] phone:min-h-[63px]");
    expect([...template.matchAll(/size-\[38px\] p-0\.5 overflow-hidden phone:block phone:size-11/g)]).to.have.lengthOf(3);

    // Verify the initials are phone-only and hidden from assistive technology.
    expect(template).to.match(/<div class="not-phone:hidden [^"]*" aria-hidden="true"> \{\{ self::user_initials/);

    // Verify the openprofile.dev link reaches a tap target on phones only.
    expect(template).to.include('<a class="text-xs/6 text-stone-500 flex items-center mt-3 phone:min-h-11" href="https://openprofile.dev"');

    // Verify an empty name line takes its gap with it, on phones only.
    expect(template).to.include('text-stone-700 mb-3 phone:has-[+:empty]:mb-0">{{ user.username|assigned_or("") }}');
    expect(template).to.include('text-xs/4 truncate phone:empty:hidden">{{ user.name|assigned_or("") }}');
  });

  it("lets the dashboard header host the fixed sheet on phones", async () => {
    // Load the dashboard base before checking its header.
    const template = normalizeWhitespace(await loadTemplate("dashboard/dashboard_base.html"));

    // Verify the shadow filter no longer traps the sheet and the sheet clears the page.
    expect(template).to.include(
      "drop-shadow-sm flex items-center justify-between gap-3 px-3 xl:px-5 phone:filter-none phone:has-[#user-dropdown:not(.hidden)]:z-[1100]",
    );
  });
});
