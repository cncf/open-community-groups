import { expect, test } from "../../fixtures.js";

import { navigateToPath, navigateToSiteHome } from "../../utils.js";

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

  test("user menu closes with Escape and restores trigger focus", async ({ page }) => {
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

  test("desktop navigation collapses into the user menu below the lg breakpoint", async ({
    page,
  }) => {
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
    await expect(userMenu.getByRole("menuitem", { name: "Home" })).toHaveAttribute(
      "href",
      "/",
    );
    await expect(userMenu.getByRole("menuitem", { name: "Explore" })).toHaveAttribute(
      "href",
      /\/explore/,
    );
    await expect(userMenu.getByRole("menuitem", { name: "Stats" })).toHaveAttribute(
      "href",
      "/stats",
    );
    await expect(userMenu.getByRole("menuitem", { name: "Docs" })).toHaveAttribute(
      "href",
      "/docs",
    );
    await expect(userMenu.getByRole("menuitem", { name: "Sign up" })).toBeVisible();
    await expect(userMenu.getByRole("menuitem", { name: "Log in" })).toBeVisible();
  });

  test("logged-in member menu exposes only authorized dashboard destinations", async ({
    member1Page,
  }) => {
    // Load the public shell with a regular member session.
    await navigateToSiteHome(member1Page);
    await member1Page.locator('#user-dropdown-button[data-logged-in="true"]').click();
    const userMenu = member1Page.locator("#user-dropdown");

    // Verify member destinations and permission-dependent links.
    await expect(userMenu.getByRole("menuitem", { name: "My Groups" })).toHaveAttribute(
      "href",
      "/dashboard/user?tab=groups",
    );
    await expect(userMenu.getByRole("menuitem", { name: "My Events" })).toHaveAttribute(
      "href",
      "/dashboard/user?tab=events",
    );
    await expect(userMenu.getByRole("menuitem", { name: "User Dashboard" })).toHaveAttribute(
      "href",
      "/dashboard/user",
    );
    await expect(userMenu.getByRole("menuitem", { name: "Community Dashboard" })).toHaveCount(0);
    await expect(userMenu.getByRole("menuitem", { name: "Group Dashboard" })).toHaveCount(0);
    await expect(userMenu.getByRole("menuitem", { name: "Log out" })).toBeVisible();
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
});
