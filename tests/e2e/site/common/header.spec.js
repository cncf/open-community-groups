import { expect, test } from "@playwright/test";

import { navigateToPath, navigateToSiteHome } from "../../utils.js";

test.describe("site header", () => {
  test("desktop navigation links point to the expected public pages", async ({
    page,
  }) => {
    // Load the public home page before checking desktop navigation links.
    await navigateToSiteHome(page);

    // Find the Main navigation control.
    const navigation = page.getByRole("navigation", {
      name: "Main navigation",
    });

    // Verify desktop navigation links point to the expected public pages.
    await expect(
      navigation.getByRole("link", { name: "Home" }),
    ).toHaveAttribute("href", "/");
    await expect(
      navigation.getByRole("link", { name: "Events & Groups" }),
    ).toHaveAttribute("href", /\/explore/);
    await expect(
      navigation.getByRole("link", { name: "Stats" }),
    ).toHaveAttribute("href", "/stats");
    await expect(
      navigation.getByRole("link", { name: "Jobs" }),
    ).toHaveAttribute("href", "/jobs");
    await navigation.getByRole("link", { name: "Jobs" }).hover();
    await expect(
      navigation.getByRole("link", { name: /Browse roles/ }),
    ).toHaveAttribute("href", "/jobs");
    await expect(
      navigation.getByRole("link", { name: /Remote roles/ }),
    ).toHaveAttribute("href", "/jobs?remote=true");
    await expect(
      navigation.getByRole("link", { name: /Post a role/ }),
    ).toHaveAttribute("href", "/log-in?next_url=/dashboard/jobs");
    await expect(
      navigation.getByRole("link", { name: "Ecosystem" }),
    ).toHaveAttribute("href", "/landscape");
    await expect(
      navigation.getByRole("link", { name: "Resources" }),
    ).toHaveAttribute("href", "/wiki");
    await expect(
      navigation.getByRole("link", { name: "Join GOUP" }),
    ).toHaveAttribute("href", "/log-in/oidc/linkedin");
    await expect(navigation.getByRole("link", { name: "About" })).toHaveCount(
      0,
    );
    await expect(navigation.getByRole("link", { name: "Docs" })).toHaveCount(0);
  });

  test("guest user menu links point to authentication pages", async ({
    page,
  }) => {
    // Load a public page before opening the guest user menu.
    await navigateToPath(page, "/explore?entity=events");

    // Find the user menu button.
    const userMenuButton = page.locator(
      '#user-dropdown-button[data-logged-in="false"]',
    );

    // Verify guest user menu links point to authentication pages.
    await expect(userMenuButton).toBeVisible();
    await userMenuButton.click();

    // Find the user menu.
    const userMenu = page.locator("#user-dropdown");
    await expect(userMenu).toBeVisible();
    await expect(
      userMenu.getByRole("menuitem", { name: "Join GOUP" }),
    ).toHaveAttribute("href", "/log-in/oidc/linkedin");
    await expect(
      userMenu.getByRole("menuitem", { name: "Sign up" }),
    ).toHaveAttribute("href", "/sign-up");
    await expect(
      userMenu.getByRole("menuitem", { name: "Log in" }),
    ).toHaveAttribute("href", "/log-in");
    await expect(userMenu.getByRole("menuitem", { name: "Jobs" })).toHaveCount(
      0,
    );
    await expect(
      userMenu.getByRole("menuitem", { name: "Ecosystem" }),
    ).toHaveCount(0);
    await expect(
      userMenu.getByRole("menuitem", { name: "Resources" }),
    ).toHaveCount(0);
  });
});
