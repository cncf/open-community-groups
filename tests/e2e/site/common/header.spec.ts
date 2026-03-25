import { expect, test } from "@playwright/test";

import { navigateToPath, navigateToSiteHome } from "../../utils";

test.describe("site header", () => {
  test("desktop navigation links point to the expected public pages", async ({
    page,
  }) => {
    await navigateToSiteHome(page);

    const navigation = page.getByRole("navigation", { name: "Main navigation" });

    await expect(navigation.getByRole("link", { name: "Home" })).toHaveAttribute(
      "href",
      "/",
    );
    await expect(navigation.getByRole("link", { name: "Explore" })).toHaveAttribute(
      "href",
      /\/explore/,
    );
    await expect(navigation.getByRole("link", { name: "Stats" })).toHaveAttribute(
      "href",
      "/stats",
    );
    await expect(navigation.getByRole("link", { name: "Docs" })).toHaveAttribute(
      "href",
      "/docs",
    );
  });

  test("guest user menu links point to authentication pages", async ({ page }) => {
    await navigateToPath(page, "/explore?entity=events");

    const userMenuButton = page.locator('#user-dropdown-button[data-logged-in="false"]');
    await expect(userMenuButton).toBeVisible();
    await userMenuButton.click();

    const userMenu = page.locator("#user-dropdown");
    await expect(userMenu).toBeVisible();
    await expect(userMenu.getByRole("menuitem", { name: "Sign up" })).toHaveAttribute(
      "href",
      "/sign-up",
    );
    await expect(userMenu.getByRole("menuitem", { name: "Log in" })).toHaveAttribute(
      "href",
      "/log-in",
    );
  });
});
