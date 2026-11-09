import { expect, test } from "../../fixtures.js";

import {
  TEST_COMMUNITY_NAME,
  TEST_EVENT_SLUG,
  TEST_GROUP_SLUG,
  TEST_GROUP_SLUGS,
  TEST_SITE_TITLE,
} from "../../seed.js";
import {
  navigateToEvent,
  navigateToGroup,
  navigateToPath,
  navigateToSiteHome,
  routeEmptyBasemap,
  sendCloseRequest,
  waitForHtmxSettle,
} from "../../utils.js";

test.describe("site header", () => {
  test("desktop navigation links point to the expected public pages", async ({ page }) => {
    // Load the public home page before checking desktop navigation links.
    await navigateToSiteHome(page);

    // Find the Main navigation control.
    const navigation = page.getByRole("navigation", {
      name: "Main navigation",
    });

    // Verify desktop navigation links point to the expected public pages.
    await expect(navigation.getByRole("link", { name: "Home" })).toHaveAttribute("href", "/");
    await expect(navigation.getByRole("link", { name: "Explore" })).toHaveAttribute("href", /\/explore/);
    await expect(navigation.getByRole("link", { name: "Stats" })).toHaveAttribute("href", "/stats");
    await expect(navigation.getByRole("link", { name: "Docs" })).toHaveAttribute("href", "/docs");
  });

  test("guest user menu links point to authentication pages", async ({ page }) => {
    // Load a public page before opening the guest user menu.
    await navigateToPath(page, "/explore?entity=events");

    // Find the user menu button.
    const userMenuButton = page.locator('#user-dropdown-button[data-logged-in="false"]');

    // Verify guest user menu links point to authentication pages.
    await expect(userMenuButton).toBeVisible();
    await userMenuButton.click();

    // Find the user menu.
    const userMenu = page.locator("#user-dropdown");
    await expect(userMenu).toBeVisible();
    await expect(userMenu.getByRole("menuitem", { name: "Sign up" })).toHaveAttribute("href", "/sign-up");
    await expect(userMenu.getByRole("menuitem", { name: "Log in" })).toHaveAttribute("href", "/log-in");
  });

  test("user menu closes with Escape and restores trigger focus @smoke", async ({ page }) => {
    // Load a public page with the global user menu.
    await navigateToSiteHome(page);

    // Find the menu and the trigger used to restore focus.
    const userMenuButton = page.locator("#user-dropdown-button");
    const userMenu = page.locator("#user-dropdown");

    // Open the menu with the keyboard.
    await userMenuButton.focus();
    await userMenuButton.press("Enter");
    await expect(userMenu).toBeVisible();

    // Close the menu and verify focus returns to its trigger.
    await page.keyboard.press("Escape");
    await expect(userMenu).toBeHidden();
    await expect(userMenuButton).toBeFocused();
  });

  test("user menu closes after an outside click", async ({ page }) => {
    // Load the public shell before exercising pointer dismissal.
    await navigateToSiteHome(page);
    const userMenuButton = page.locator("#user-dropdown-button");
    const userMenu = page.locator("#user-dropdown");

    // Open the menu and dismiss it from outside the dropdown.
    await userMenuButton.click();
    await expect(userMenu).toBeVisible();
    await page.locator("main#main-content").click({ position: { x: 5, y: 5 } });
    await expect(userMenu).toBeHidden();
  });

  test("desktop navigation collapses into the user menu below the lg breakpoint", async ({ page }) => {
    // Load the public home page at the lg breakpoint.
    await page.setViewportSize({ width: 1024, height: 900 });
    await navigateToSiteHome(page);

    // Find the desktop navigation links and the guest user menu.
    const navigation = page.getByRole("navigation", { name: "Main navigation" });
    const desktopHomeLink = navigation.getByRole("link", { name: "Home" });
    const userMenuButton = page.locator('#user-dropdown-button[data-logged-in="false"]');
    const userMenu = page.locator("#user-dropdown");

    // Verify the menu omits the public destinations while the desktop links show.
    await expect(desktopHomeLink).toBeVisible();
    await userMenuButton.click();
    await expect(userMenu.getByRole("menuitem", { name: "Sign up" })).toBeVisible();
    await expect(userMenu.getByRole("menuitem", { name: "Home" })).toBeHidden();
    await expect(userMenu.getByRole("menuitem", { name: "Docs" })).toBeHidden();
    await page.keyboard.press("Escape");
    await expect(userMenu).toBeHidden();

    // Verify the desktop links collapse right below the lg breakpoint.
    await page.setViewportSize({ width: 1023, height: 900 });
    await expect(desktopHomeLink).toBeHidden();

    // Verify the user menu takes over every public destination.
    await userMenuButton.click();
    await expect(userMenu.getByRole("menuitem", { name: "Home" })).toBeVisible();
    await expect(userMenu.getByRole("menuitem", { name: "Explore" })).toBeVisible();
    await expect(userMenu.getByRole("menuitem", { name: "Stats" })).toBeVisible();
    await expect(userMenu.getByRole("menuitem", { name: "Docs" })).toBeVisible();
  });

  test("mobile guest menu exposes every public destination @mobile", async ({ page }) => {
    // Load the public shell using the configured mobile project.
    await navigateToSiteHome(page);
    await page.locator('#user-dropdown-button[data-logged-in="false"]').click();
    const userMenu = page.locator("#user-dropdown");

    // Verify mobile navigation and authentication destinations remain available.
    await expect(userMenu.getByRole("menuitem", { name: "Home" })).toHaveAttribute("href", "/");
    await expect(userMenu.getByRole("menuitem", { name: "Explore" })).toHaveAttribute("href", /\/explore/);
    await expect(userMenu.getByRole("menuitem", { name: "Stats" })).toHaveAttribute("href", "/stats");
    await expect(userMenu.getByRole("menuitem", { name: "Docs" })).toHaveAttribute("href", "/docs");
    await expect(userMenu.getByRole("menuitem", { name: "Sign up" })).toBeVisible();
    await expect(userMenu.getByRole("menuitem", { name: "Log in" })).toBeVisible();
  });

  test("explore links open every community", async ({ page }) => {
    // Load the public home page before checking both Explore links.
    await navigateToSiteHome(page);

    // Verify the desktop navigation link has no community.
    const navigation = page.getByRole("navigation", { name: "Main navigation" });
    await expect(navigation.getByRole("link", { name: "Explore" })).toHaveAttribute(
      "href",
      "/explore?entity=events",
    );

    // Verify the user menu link takes over below the lg breakpoint with the same target.
    await page.setViewportSize({ width: 1023, height: 900 });
    await page.locator('#user-dropdown-button[data-logged-in="false"]').click();
    await expect(page.locator("#user-dropdown").getByRole("menuitem", { name: "Explore" })).toHaveAttribute(
      "href",
      "/explore?entity=events",
    );
  });

  test("mobile explore link opens every community @mobile", async ({ page }) => {
    // Load the public shell and open the guest menu.
    await navigateToSiteHome(page);
    await page.locator('#user-dropdown-button[data-logged-in="false"]').click();

    // Verify the menu link has no community.
    await expect(page.locator("#user-dropdown").getByRole("menuitem", { name: "Explore" })).toHaveAttribute(
      "href",
      "/explore?entity=events",
    );
  });

  test("desktop version mode is toggled from the mobile user menu @mobile", async ({ page }) => {
    // Load a public page with a query string the reload must keep and a fragment it drops.
    await navigateToPath(page, "/explore?entity=events#main-content");
    const initialUrl = page.url();
    expect(initialUrl).toContain("?entity=events#main-content");
    const userMenuButton = page.locator('#user-dropdown-button[data-logged-in="false"]');
    const userMenu = page.locator("#user-dropdown");
    const desktopVersionItem = userMenu.getByRole("menuitem", { name: "Desktop version" });
    const mobileVersionItem = userMenu.getByRole("menuitem", { name: "Mobile version" });

    // Verify the responsive layout offers only the desktop version entry.
    await userMenuButton.click();
    await expect(desktopVersionItem).toBeVisible();
    await expect(mobileVersionItem).toBeHidden();

    // Verify a manually applied attribute hides the entry even before any reload.
    await page.evaluate(() => document.documentElement.setAttribute("data-viewport-mode", "desktop"));
    await expect(desktopVersionItem).toBeHidden();
    await expect(mobileVersionItem).toBeVisible();
    await page.evaluate(() => document.documentElement.removeAttribute("data-viewport-mode"));
    await expect(desktopVersionItem).toBeVisible();

    // Enable the desktop version and wait for the reload it triggers.
    await Promise.all([page.waitForEvent("load"), desktopVersionItem.click()]);

    // Verify the reloaded document is in desktop mode at the same URL without the fragment.
    expect(page.url()).toBe(initialUrl.replace("#main-content", ""));
    await expect
      .poll(() => page.evaluate(() => document.documentElement.dataset.viewportMode))
      .toBe("desktop");
    expect(await page.evaluate(() => window.innerWidth)).toBe(1280);
    expect(await page.evaluate(() => document.cookie)).toContain("ocg_viewport_mode=desktop");
    await expect(page.locator('meta[name="viewport"]')).toHaveAttribute("content", "width=1280");

    // Verify the menu now offers only the mobile version entry.
    await clickInDesktopMode(userMenuButton);
    await expect(mobileVersionItem).toBeVisible();
    await expect(desktopVersionItem).toBeHidden();
    await page.keyboard.press("Escape");
    await expect(userMenu).toBeHidden();

    // Verify a boosted navigation keeps the mode.
    const statsLink = page
      .getByRole("navigation", { name: "Main navigation" })
      .getByRole("link", { name: "Stats" });
    await expect(statsLink).toBeVisible();
    await clickInDesktopMode(statsLink);
    await expect(page).toHaveURL(/\/stats$/u);
    expect(await page.evaluate(() => document.documentElement.dataset.viewportMode)).toBe("desktop");
    expect(await page.evaluate(() => window.innerWidth)).toBe(1280);

    // Return to the mobile version and wait for the reload.
    await expect(userMenuButton).toBeVisible();
    await clickInDesktopMode(userMenuButton);
    await expect(mobileVersionItem).toBeVisible();
    await Promise.all([page.waitForEvent("load"), clickInDesktopMode(mobileVersionItem)]);

    // Verify the responsive layout is restored and the cookie is gone.
    await expect
      .poll(() => page.evaluate(() => document.documentElement.hasAttribute("data-viewport-mode")))
      .toBe(false);
    expect(await page.evaluate(() => window.innerWidth)).toBeLessThan(1024);
    expect(await page.evaluate(() => document.cookie)).not.toContain("ocg_viewport_mode");
    await userMenuButton.click();
    await expect(desktopVersionItem).toBeVisible();
    await expect(mobileVersionItem).toBeHidden();
  });

  test("desktop version entry follows the xl breakpoint on touch devices @mobile", async ({ page }) => {
    // Load the public shell and open the guest menu.
    await navigateToSiteHome(page);
    const userMenuButton = page.locator('#user-dropdown-button[data-logged-in="false"]');
    const userMenu = page.locator("#user-dropdown");
    const desktopVersionItem = userMenu.getByRole("menuitem", { name: "Desktop version" });

    // Verify the entry disappears once the layout viewport reaches xl.
    await page.setViewportSize({ width: 1280, height: 900 });
    await userMenuButton.click();
    await expect(desktopVersionItem).toBeHidden();
    await expect(userMenu.getByRole("menuitem", { name: "Mobile version" })).toBeHidden();

    // Verify the entry returns right below xl, including landscape tablet widths.
    await page.setViewportSize({ width: 1279, height: 900 });
    await expect(desktopVersionItem).toBeVisible();
  });

  test("viewport mode entries stay hidden for fine pointer devices", async ({ page }) => {
    // Load the public shell and open the guest menu on a mouse-driven browser.
    await navigateToSiteHome(page);
    const userMenuButton = page.locator("#user-dropdown-button");
    const userMenu = page.locator("#user-dropdown");

    // Verify neither entry shows at desktop or narrow widths.
    for (const width of [1280, 1279, 1023, 767]) {
      await page.setViewportSize({ width, height: 900 });
      await userMenuButton.click();
      await expect(userMenu).toBeVisible();
      await expect(userMenu.getByRole("menuitem", { name: "Desktop version" })).toBeHidden();
      await expect(userMenu.getByRole("menuitem", { name: "Mobile version" })).toBeHidden();
      await page.keyboard.press("Escape");
      await expect(userMenu).toBeHidden();
    }
  });

  test("logged-in attendee opens personal check-in from the mobile menu @mobile", async ({
    pending2Page,
  }) => {
    // Load the public shell with an attendee session.
    await navigateToSiteHome(pending2Page);
    await pending2Page.locator('#user-dropdown-button[data-logged-in="true"]').click();
    const userMenu = pending2Page.locator("#user-dropdown");

    // Follow the attendee shortcut while group check-in remains unavailable.
    const checkInLink = userMenu.getByRole("menuitem", { name: "Check in" });
    await expect(checkInLink).toBeVisible();
    await expect(checkInLink).toHaveAttribute("href", "/dashboard/user?tab=check-in");
    await expect(userMenu.getByRole("menuitem", { name: "Scan attendees" })).toHaveCount(0);
    await checkInLink.click();

    // Verify the shortcut opens the mobile attendee surface.
    await expect(pending2Page).toHaveURL(/\/dashboard\/user\?tab=check-in$/u);
    await expect(pending2Page.getByRole("heading", { name: "Check-In" })).toBeVisible();
  });

  test("group team member opens group check-in from the mobile menu @mobile", async ({
    checkInManagerGroupPage,
  }) => {
    // Load the public shell with a check-in manager session.
    await navigateToSiteHome(checkInManagerGroupPage);
    await checkInManagerGroupPage.locator('#user-dropdown-button[data-logged-in="true"]').click();
    const userMenu = checkInManagerGroupPage.locator("#user-dropdown");

    // Follow the permission-dependent group shortcut.
    const groupCheckInLink = userMenu.getByRole("menuitem", { name: "Scan attendees" });
    await expect(groupCheckInLink).toBeVisible();
    await expect(groupCheckInLink).toHaveAttribute("href", "/dashboard/group?tab=check-in");
    await groupCheckInLink.click();

    // Verify the shortcut opens the mobile group surface.
    await expect(checkInManagerGroupPage).toHaveURL(/\/dashboard\/group\?tab=check-in$/u);
    await expect(checkInManagerGroupPage.getByRole("heading", { name: "Check-In" })).toBeVisible();
  });

  test("logged-in member menu exposes only authorized dashboard destinations", async ({ member1Page }) => {
    // Load the public shell with a regular member session.
    await navigateToSiteHome(member1Page);
    await member1Page.locator('#user-dropdown-button[data-logged-in="true"]').click();
    const userMenu = member1Page.locator("#user-dropdown");
    const userShortcuts = userMenu.getByRole("group", { name: "User dashboard" });

    // Verify member destinations and permission-dependent links.
    await expect(userShortcuts.getByRole("menuitem", { name: "My Groups" })).toHaveAttribute(
      "href",
      "/dashboard/user?tab=groups",
    );
    await expect(userShortcuts.getByRole("menuitem", { name: "My Events" })).toHaveAttribute(
      "href",
      "/dashboard/user?tab=events",
    );
    await expect(userMenu.getByRole("menuitem", { name: "User dashboard" })).toHaveAttribute(
      "href",
      "/dashboard/user",
    );
    await expect(userMenu.getByRole("menuitem", { name: "Community dashboard" })).toHaveCount(0);
    await expect(userMenu.getByRole("menuitem", { name: "Group dashboard" })).toHaveCount(0);
    await expect(userMenu.getByRole("group", { name: "Group dashboard" })).toHaveCount(0);
    await expect(userMenu.getByRole("menuitem", { name: "Events", exact: true })).toHaveCount(0);
    await expect(userMenu.getByRole("menuitem", { name: "Log out" })).toBeVisible();
  });

  test("logged-in group team menu nests shortcuts under their dashboards", async ({
    checkInManagerGroupPage,
  }) => {
    // Load the public shell with a group team session.
    await navigateToSiteHome(checkInManagerGroupPage);
    await checkInManagerGroupPage.locator('#user-dropdown-button[data-logged-in="true"]').click();
    const userMenu = checkInManagerGroupPage.locator("#user-dropdown");
    const groupShortcuts = userMenu.getByRole("group", { name: "Group dashboard" });

    // Verify each dashboard link is followed by its own shortcuts.
    const menuItems = await userMenu.getByRole("menuitem").allInnerTexts();
    const labels = menuItems.map((label) => label.trim());
    const groupDashboardIndex = labels.indexOf("Group dashboard");
    expect(groupDashboardIndex).toBeGreaterThan(-1);
    expect(labels.indexOf("Events")).toBe(groupDashboardIndex + 1);
    expect(labels.indexOf("User dashboard")).toBe(groupDashboardIndex + 2);
    expect(labels.indexOf("My Groups")).toBe(groupDashboardIndex + 3);

    // Verify the group events shortcut is indented under its dashboard link.
    const groupDashboardLink = userMenu.getByRole("menuitem", { name: "Group dashboard" });
    const eventsLink = groupShortcuts.getByRole("menuitem", { name: "Events", exact: true });
    await expect(eventsLink).toBeVisible();
    await expect(eventsLink).toHaveAttribute("href", "/dashboard/group?tab=events");
    const labelOffset = async (link) =>
      link.evaluate((element) => element.querySelector(".svg-icon").getBoundingClientRect().left);
    expect(await labelOffset(eventsLink)).toBeGreaterThan(await labelOffset(groupDashboardLink));
    await eventsLink.click();

    // Verify the shortcut opens the group events tab.
    await expect(checkInManagerGroupPage).toHaveURL(/\/dashboard\/group\?tab=events$/u);
  });

  test("logged-in menu swaps check-in shortcuts for dashboard links at the md breakpoint on touch screens @mobile", async ({
    checkInManagerGroupPage,
  }) => {
    // Load the public shell with a group team session right below md.
    await checkInManagerGroupPage.setViewportSize({ width: 767, height: 900 });
    await navigateToSiteHome(checkInManagerGroupPage);
    const userMenu = checkInManagerGroupPage.locator("#user-dropdown");
    const checkInLink = userMenu
      .getByRole("group", { name: "User dashboard" })
      .getByRole("menuitem", { name: "Check in" });
    const scanAttendeesLink = userMenu
      .getByRole("group", { name: "Group dashboard" })
      .getByRole("menuitem", { name: "Scan attendees" });
    const groupDashboardLink = userMenu.getByRole("menuitem", { name: "Group dashboard" });
    const userDashboardLink = userMenu.getByRole("menuitem", { name: "User dashboard" });
    const groupEventsLink = userMenu.getByRole("menuitem", { name: "Events", exact: true });

    // Verify phones get the check-in shortcuts instead of the dashboard links.
    await checkInManagerGroupPage.locator('#user-dropdown-button[data-logged-in="true"]').click();
    await expect(checkInLink).toBeVisible();
    await expect(scanAttendeesLink).toBeVisible();
    await expect(groupDashboardLink).toBeHidden();
    await expect(userDashboardLink).toBeHidden();
    await expect(groupEventsLink).toBeHidden();

    // Verify md layouts get the dashboard links while public destinations stay in the menu.
    await checkInManagerGroupPage.setViewportSize({ width: 768, height: 900 });
    await expect(groupDashboardLink).toBeVisible();
    await expect(userDashboardLink).toBeVisible();
    await expect(userMenu.getByRole("menuitem", { name: "My Groups" })).toBeVisible();
    await expect(userMenu.getByRole("menuitem", { name: "My Events" })).toBeVisible();
    await expect(groupEventsLink).toBeVisible();
    await expect(checkInLink).toBeHidden();
    await expect(scanAttendeesLink).toBeHidden();
    await expect(userMenu.getByRole("menuitem", { name: "Home" })).toBeVisible();
  });

  test("logged-in menu shows dashboard links in narrow windows with a mouse", async ({
    checkInManagerGroupPage,
  }) => {
    // Load the public shell with a group team session in a narrow mouse-driven window.
    await checkInManagerGroupPage.setViewportSize({ width: 600, height: 900 });
    await navigateToSiteHome(checkInManagerGroupPage);
    await checkInManagerGroupPage.locator('#user-dropdown-button[data-logged-in="true"]').click();
    const userMenu = checkInManagerGroupPage.locator("#user-dropdown");

    // Verify the full dashboards stay reachable instead of the check-in shortcuts.
    await expect(userMenu.getByRole("menuitem", { name: "Group dashboard" })).toBeVisible();
    await expect(userMenu.getByRole("menuitem", { name: "User dashboard" })).toBeVisible();
    await expect(userMenu.getByRole("menuitem", { name: "Events", exact: true })).toBeVisible();
    await expect(userMenu.getByRole("menuitem", { name: "Check in" })).toBeHidden();
    await expect(userMenu.getByRole("menuitem", { name: "Scan attendees" })).toBeHidden();
  });

  test("public shell exposes its skip link, logo, and footer destinations", async ({ page }) => {
    // Load a non-home public page before checking its shared destinations.
    await navigateToPath(page, "/stats");

    // Verify keyboard users can skip directly to the main content.
    await expect(page.getByRole("link", { name: "Skip to main content" })).toHaveAttribute(
      "href",
      "#main-content",
    );
    await expect(page.locator("main#main-content")).toBeVisible();

    // Find the home logo and verify its destination.
    const homeLogo = page.getByRole("link", { name: "Go to homepage" });
    await expect(homeLogo).toHaveAttribute("href", "/");

    // Find the footer and verify its primary external destination.
    const footer = page.getByRole("contentinfo");
    await expect(footer).toBeVisible();
    await expect(footer.getByRole("link", { name: /GitHub/i })).toHaveAttribute("href", /github\.com/);
  });

  test("phone header stays pinned at 64px after scrolling @mobile", async ({ page }) => {
    // Load a long public page and scroll well past the header.
    await navigateToPath(page, "/stats");
    await page.evaluate(() => window.scrollTo(0, 900));
    await expect.poll(() => page.evaluate(() => window.scrollY)).toBeGreaterThan(0);

    // Verify the header holds the top edge on an opaque surface.
    const box = await page.locator("#header").boundingBox();
    expect(box.y).toBe(0);
    expect(box.height).toBe(64);
    await expect(page.locator("#header")).toHaveCSS("background-color", "rgb(255, 255, 255)");
  });

  test("phone section heading pins directly under the header @mobile", async ({ page }) => {
    // Load a page with section headings and scroll one past the header.
    await navigateToPath(page, "/stats");
    const strip = page.locator(".section-strip:visible").first();
    await strip.evaluate((element) => {
      window.scrollTo(0, element.getBoundingClientRect().top + window.scrollY + 120);
    });

    // Verify the heading rests on the header's hairline.
    await expect.poll(() => strip.evaluate((element) => element.getBoundingClientRect().top)).toBe(63);
  });

  test("phone in-main modal covers the header @mobile", async ({ page }) => {
    // Force the share modal, since phones otherwise prefer the system share.
    await page.addInitScript(() => {
      delete Navigator.prototype.share;
    });
    await navigateToGroup(page, TEST_COMMUNITY_NAME, TEST_GROUP_SLUGS.community1.alpha);

    // Open the modal rendered inside main.
    await page.locator("share-modal button").first().dispatchEvent("click");
    await expect(page.getByRole("dialog", { name: "Share" })).toBeVisible();

    // Verify nothing in the header paints above it.
    const headerOnTop = await page.evaluate(() => {
      const header = document.getElementById("header");
      const { height, width } = header.getBoundingClientRect();
      return header.contains(document.elementFromPoint(width / 2, height / 2));
    });
    expect(headerOnTop).toBe(false);
  });

  test("desktop menu and modals create no CloseWatcher", async ({ page }) => {
    // Count watchers from the first script of the event page.
    await countCloseWatchers(page);
    await routeEmptyBasemap(page);
    await navigateToEvent(page, TEST_COMMUNITY_NAME, TEST_GROUP_SLUG, TEST_EVENT_SLUG);

    // Open and close the user menu.
    const userButton = page.locator("#user-dropdown-button");
    await userButton.click();
    await expect(page.locator("#user-dropdown")).toBeVisible();
    await page.keyboard.press("Escape");
    await expect(page.locator("#user-dropdown")).toBeHidden();

    // Open and close a modal that runs through the shared lifecycle.
    const mapModal = page.locator("#event-map-modal");
    await page.getByRole("button", { name: "Open full map view" }).click();
    await expect(mapModal).toBeVisible();
    await page.locator("#close-event-map-modal").click();
    await expect(mapModal).toBeHidden();

    // Verify neither one reached the sheet gestures.
    expect(await getCloseWatcherCount(page)).toBe(0);
  });

  test("desktop version opens its menu without a CloseWatcher @mobile", async ({ page }) => {
    // Switch a phone to the desktop version.
    await countCloseWatchers(page);
    await navigateToPath(page, "/stats");
    const { userButton, userMenu } = getAccountSheet(page);
    await userButton.click();
    await Promise.all([
      page.waitForEvent("load"),
      userMenu.getByRole("menuitem", { name: "Desktop version" }).click(),
    ]);
    await expect
      .poll(() => page.evaluate(() => document.documentElement.dataset.viewportMode))
      .toBe("desktop");

    // Open the anchored menu in that mode.
    await clickInDesktopMode(userButton);
    await expect(userMenu.getByRole("menuitem", { name: "Mobile version" })).toBeVisible();

    // Verify the menu stayed out of the sheet gestures.
    expect(await getCloseWatcherCount(page)).toBe(0);
  });

  test("account sheet holds one CloseWatcher while open @mobile", async ({ page }) => {
    // Open the sheet with watchers counted, the control for the desktop cases.
    await countCloseWatchers(page);
    await navigateToPath(page, "/stats");
    const { userButton, userMenu } = getAccountSheet(page);
    await userButton.click();
    await expect(userMenu).toBeVisible();

    // Verify the sheet created exactly one.
    expect(await getCloseWatcherCount(page)).toBe(1);
  });

  test("tap progress bar shows while a boosted link loads @mobile", async ({ page }) => {
    // Hold the card's response so the bar outlasts its delay.
    await navigateToSiteHome(page);
    const card = page.locator("a.group[hx-boost]").first();
    const { pathname } = new URL(await card.evaluate((element) => element.href));
    let releaseResponse;
    const responseHeld = new Promise((resolve) => {
      releaseResponse = resolve;
    });
    await page.route(
      (url) => url.pathname === pathname,
      async (route) => {
        await responseHeld;
        await route.continue();
      },
    );

    // Verify the bar appears on the header's bottom edge.
    await card.tap();
    await expect.poll(() => getHeaderBar(page)).toEqual({ content: '""', height: "2px", opacity: "1" });

    // Verify it clears once the page arrives.
    releaseResponse();
    await expect(page).toHaveURL(new RegExp(`${pathname}$`, "u"));
    await expect.poll(async () => (await getHeaderBar(page)).content).toBe("none");
  });

  test("phone header shows the site title @mobile", async ({ page }) => {
    // Load a public page without a header logo.
    await navigateToPath(page, "/stats");
    const header = page.locator("#header");
    await expect(header.locator("nav span.truncate")).toBeVisible();

    // Verify the title links home under a name that includes its visible text.
    const titleLink = header.getByRole("link", { name: `Go to ${TEST_SITE_TITLE} homepage` });
    await expect(titleLink).toHaveAttribute("href", "/");
    await expect(titleLink).toHaveText(TEST_SITE_TITLE);
    expect((await titleLink.boundingBox()).height).toBe(44);
    await expect(header.getByRole("link", { name: "Go to homepage" })).toHaveCount(0);

    // Verify the user trigger fills a 44px target.
    const userButton = header.locator("#user-dropdown-button");
    await expect(userButton).toBeVisible();
    expect(await userButton.boundingBox()).toMatchObject({ height: 44, width: 44 });

    // Verify Home does not repeat the title that sits right below it.
    await navigateToSiteHome(page);
    await expect(userButton).toBeVisible();
    await expect(header.locator("nav span.truncate")).toHaveCount(0);
  });

  test("phone header leaves the desktop shell without the title", async ({ page }) => {
    // Load a public page at a desktop width.
    await navigateToPath(page, "/stats");
    const header = page.locator("#header");

    // Verify the phone title does not render.
    await expect(header.locator("nav span.truncate")).toBeHidden();
  });

  test("account sheet opens from the user button and returns focus to it @mobile", async ({ page }) => {
    // Load a public page with the menu mounted.
    await navigateToPath(page, "/stats");
    const { closeButton, userButton, userMenu } = getAccountSheet(page);

    // Open the sheet and verify focus enters it.
    await userButton.click();
    await expect(userMenu).toBeVisible();
    await expect(closeButton).toBeFocused();
    await expect(userButton).toHaveAttribute("aria-expanded", "true");
    await expect(page.locator("main#main-content")).toHaveJSProperty("inert", true);
    await expect(page.locator("body")).toHaveCSS("overflow", "hidden");

    // Close it and verify focus goes back to the trigger.
    await closeButton.click();
    await expect(userMenu).toBeHidden();
    await expect(userButton).toBeFocused();
    await expect(userButton).not.toHaveAttribute("aria-expanded", "true");
    await expectAccountSheetReleased(page);
  });

  test("account sheet closes from its scrim and marks the current page @mobile", async ({ page }) => {
    // Open the sheet on a page that has a row.
    await navigateToPath(page, "/stats");
    const { userButton, userMenu } = getAccountSheet(page);
    await userButton.click();

    // Verify only the current row is marked.
    await expect(userMenu.locator('[aria-current="page"]')).toHaveCount(1);
    await expect(userMenu.getByRole("menuitem", { name: "Stats" })).toHaveAttribute("aria-current", "page");

    // Tap the scrim above the sheet.
    await page.touchscreen.tap(100, 20);
    await expect(userMenu).toBeHidden();
    await expect(userMenu.locator('[aria-current="page"]')).toHaveCount(0);
    await expectAccountSheetReleased(page);
  });

  test("account sheet keeps Desktop version above the guest pills @mobile", async ({ page }) => {
    // Open the guest sheet.
    await navigateToPath(page, "/stats");
    const { userButton, userMenu } = getAccountSheet(page);
    await userButton.click();

    // Verify the row order and the pills' side-by-side layout.
    const desktopVersion = await userMenu.getByRole("menuitem", { name: "Desktop version" }).boundingBox();
    const logIn = await userMenu.getByRole("menuitem", { name: "Log in" }).boundingBox();
    const signUp = await userMenu.getByRole("menuitem", { name: "Sign up" }).boundingBox();
    expect(desktopVersion.y).toBeLessThan(logIn.y);
    expect(logIn.x).toBeLessThan(signUp.x);
    expect(logIn.y).toBe(signUp.y);
    expect(logIn.height).toBe(44);
    expect(signUp.height).toBe(44);
  });

  test("account sheet keeps Tab inside, including Desktop version @mobile", async ({ page }) => {
    // Open the guest sheet.
    await navigateToPath(page, "/stats");
    const { closeButton, userButton, userMenu } = getAccountSheet(page);
    await userButton.click();
    await expect(closeButton).toBeFocused();

    // Verify Shift+Tab wraps to the last rendered row.
    await page.keyboard.press("Shift+Tab");
    await expect(userMenu.getByRole("menuitem", { name: "Desktop version" })).toBeFocused();

    // Verify Tab wraps back to the close button.
    await page.keyboard.press("Tab");
    await expect(closeButton).toBeFocused();
  });

  test("account sheet does not return after Back then Forward @mobile", async ({ page }) => {
    // Reach a second page through a boosted row, so HTMX owns the history entry.
    await navigateToSiteHome(page);
    const { userButton, userMenu } = getAccountSheet(page);
    await userButton.click();
    await userMenu.getByRole("menuitem", { name: "Stats" }).click();
    await expect(page).toHaveURL(/\/stats$/u);
    await waitForHtmxSettle(page);
    await expectAccountSheetReleased(page);

    // Leave the page with the sheet open, then come back.
    await userButton.click();
    await expect(userMenu).toBeVisible();
    await page.goBack();
    await expect(page).not.toHaveURL(/\/stats$/u);
    await page.goForward();
    await expect(page).toHaveURL(/\/stats$/u);
    await waitForHtmxSettle(page);

    // Verify the sheet stayed closed and can open again.
    await expect(userMenu).toBeHidden();
    await expectAccountSheetReleased(page);
    await userButton.click();
    await expect(userMenu).toBeVisible();
    await expect(page.locator("body")).toHaveCSS("overflow", "hidden");
  });

  test("account sheet releases its state at 768 and stays open as the menu @mobile", async ({ page }) => {
    // Open the sheet on a phone width.
    await navigateToPath(page, "/stats");
    const { userButton, userMenu } = getAccountSheet(page);
    await userButton.click();
    await expect(userMenu).toHaveCSS("position", "fixed");

    // Rotate past md.
    await page.setViewportSize({ width: 768, height: 900 });

    // Verify the sheet state is gone and the anchored menu remains.
    await expect(userMenu).toBeVisible();
    await expect(userMenu).toHaveCSS("position", "absolute");
    await expectAccountSheetReleased(page);
  });

  test("a close request closes the account sheet without a history entry @mobile", async ({ page }) => {
    // Open the sheet and note the session history.
    await navigateToPath(page, "/stats");
    const { userButton, userMenu } = getAccountSheet(page);
    const historyLength = await page.evaluate(() => window.history.length);
    await userButton.click();
    await expect(userMenu).toBeVisible();

    // Reach the CloseWatcher past the sheet's own Escape handler.
    await sendCloseRequest(page);

    // Verify the sheet closed, focus returned, and history did not move.
    await expect(userMenu).toBeHidden();
    await expect(userButton).toBeFocused();
    await expectAccountSheetReleased(page);
    expect(await page.evaluate(() => window.history.length)).toBe(historyLength);
  });

  test("account sheet grabber closes past the threshold and snaps back short of it @mobile", async ({
    page,
  }) => {
    // Open the sheet and find its title row.
    await navigateToPath(page, "/stats");
    const { userButton, userMenu } = getAccountSheet(page);
    await userButton.click();
    const panel = userMenu.locator(".sheet-panel");
    const head = userMenu.locator(".sheet-grab");
    await expect(panel).toHaveAttribute("data-sheet-drag", "");

    // Verify a finger drags the row instead of scrolling the page.
    await expect(head).toHaveCSS("touch-action", "none");
    const box = await head.boundingBox();
    const startX = box.x + box.width / 2;
    const startY = box.y + box.height / 2;

    // A short, slow drag leaves the sheet where it was.
    await page.mouse.move(startX, startY);
    await page.mouse.down();
    await page.mouse.move(startX, startY + 20);
    await expect.poll(() => panel.evaluate((element) => element.style.translate)).toBe("0px 20px");
    await page.waitForTimeout(100);
    await page.mouse.up();
    await expect(userMenu).toBeVisible();
    await expect.poll(() => panel.evaluate((element) => element.style.translate)).toBe("");

    // A long drag closes it.
    await page.mouse.move(startX, startY);
    await page.mouse.down();
    await page.mouse.move(startX, startY + 200, { steps: 4 });
    await page.mouse.up();
    await expect(userMenu).toBeHidden();
    await expectAccountSheetReleased(page);
  });

  test("account sheet shows no grabber without drag support @mobile", async ({ page }) => {
    // Open the sheet.
    await navigateToPath(page, "/stats");
    const { userButton, userMenu } = getAccountSheet(page);
    await userButton.click();
    const head = userMenu.locator(".sheet-grab");
    const grabberContent = () =>
      head.evaluate((element) => window.getComputedStyle(element, "::before").content);

    // Verify the grabber follows the drag marker.
    await expect(userMenu.locator(".sheet-panel")).toHaveAttribute("data-sheet-drag", "");
    expect(await grabberContent()).not.toBe("none");
    await userMenu.locator(".sheet-panel").evaluate((element) => {
      delete element.dataset.sheetDrag;
    });
    expect(await grabberContent()).toBe("none");
  });

  test("account sheet offers Invitations to signed-in phones @mobile", async ({ member1Page }) => {
    // Open the sheet with a signed-in session.
    await navigateToPath(member1Page, "/stats");
    const { userButton, userMenu } = getAccountSheet(member1Page);
    await userButton.click();

    // Verify the row leads to the invitations tab.
    await expect(userMenu.getByRole("menuitem", { name: "Invitations" })).toHaveAttribute(
      "href",
      "/dashboard/user?tab=invitations",
    );
  });

  test("account sheet truncates a long username @mobile", async ({ member1Page }) => {
    // Open the sheet with a signed-in session.
    await navigateToPath(member1Page, "/stats");
    const { userButton, userMenu } = getAccountSheet(member1Page);
    await userButton.click();

    // Lengthen the username past the sheet width.
    await userMenu
      .locator(".truncate")
      .first()
      .evaluate((element) => {
        element.textContent = "a-very-long-username-".repeat(6);
      });

    // Verify the sheet keeps its width instead of scrolling sideways.
    const panel = userMenu.locator(".sheet-panel");
    expect(await panel.evaluate((element) => element.scrollWidth - element.clientWidth)).toBe(0);
  });

  test("account sheet opens over the dashboard header @mobile", async ({ member1Page }) => {
    // Load the phone dashboard and open the sheet from the user button.
    await navigateToPath(member1Page, "/dashboard/user?tab=check-in");
    const { closeButton, userButton, userMenu } = getAccountSheet(member1Page);
    await userButton.click();
    await expect(closeButton).toBeFocused();

    // Verify the shadow filter leaves the scrim covering the whole screen.
    const viewport = member1Page.viewportSize();
    expect(await userMenu.boundingBox()).toMatchObject({ height: viewport.height, y: 0 });
    await closeButton.click();
    await expect(userMenu).toBeHidden();
    await expectAccountSheetReleased(member1Page);
  });
});

/** Reads the tap progress bar drawn on the header's ::after. */
const getHeaderBar = (page) =>
  page.evaluate(() => {
    const { content, height, opacity } = getComputedStyle(document.getElementById("header"), "::after");
    return { content, height, opacity };
  });

/** Counts every CloseWatcher the page creates from its first script on. */
const countCloseWatchers = (page) =>
  page.addInitScript(() => {
    const NativeCloseWatcher = window.CloseWatcher;
    window.closeWatcherCount = 0;
    window.CloseWatcher = class extends NativeCloseWatcher {
      constructor(...args) {
        super(...args);
        window.closeWatcherCount += 1;
      }
    };
  });

/** Reads the count kept by countCloseWatchers. */
const getCloseWatcherCount = (page) => page.evaluate(() => window.closeWatcherCount);

/**
 * Finds the account sheet and its trigger.
 * @param {import("@playwright/test").Page} page - Page under test.
 * @returns {Record<string, import("@playwright/test").Locator>} Sheet locators.
 */
const getAccountSheet = (page) => {
  const userMenu = page.locator("#user-dropdown");
  return {
    closeButton: userMenu.getByRole("menuitem", { name: "Close menu" }),
    userButton: page.locator("#user-dropdown-button"),
    userMenu,
  };
};

/**
 * Verifies the account sheet holds nothing on the page.
 * @param {import("@playwright/test").Page} page - Page under test.
 * @returns {Promise<void>}
 */
const expectAccountSheetReleased = async (page) => {
  await expect(page.locator("body")).not.toHaveCSS("overflow", "hidden");
  await expect(page.locator("[inert]:not(#dashboard-menu-drawer)")).toHaveCount(0);
  await expect(page.locator("#user-dropdown [data-sheet-drag]")).toHaveCount(0);
};

/**
 * Clicks a control through a DOM event instead of emulated pointer input. In desktop version
 * mode the 1280px layout viewport exceeds the mobile visual viewport, and Chromium's emulated
 * pointer coordinates no longer map onto elements outside the visible area.
 */
const clickInDesktopMode = (locator) => locator.dispatchEvent("click");
