import { expect, test } from "@playwright/test";
import type { Page } from "@playwright/test";

import {
  buildAuthUser,
  logInWithSeededUser,
  navigateToPath,
  TEST_USER_CREDENTIALS,
  type AuthUser,
} from "../utils";

const userDashboardEventsPath = "/dashboard/user?tab=events";
type EmailCredentials = Pick<AuthUser, "username" | "password">;

/**
 * Completes the sign-up form using email and password credentials.
 */
const signUpWithEmail = async (page: Page, user: AuthUser) => {
  await navigateToPath(page, "/sign-up");

  await expect(page.getByRole("heading", { name: "Sign Up" })).toBeVisible();
  await page.getByLabel("Full Name").fill(user.name);
  await page.getByLabel("Email Address").fill(user.email);
  await page.getByLabel("Username").fill(user.username);
  await page
    .getByRole("textbox", { name: "Password required", exact: true })
    .fill(user.password);
  await page
    .getByRole("textbox", { name: "Confirm Password required" })
    .fill(user.password);

  await page.getByRole("button", { name: "Create Account" }).click();
  await expect(page.getByRole("heading", { name: "Log In" })).toBeVisible();
};

/**
 * Logs in using email username and password credentials.
 */
const logInWithEmail = async (page: Page, user: EmailCredentials) => {
  await expect(page.getByRole("heading", { name: "Log In" })).toBeVisible();
  await page.getByLabel("Username").fill(user.username);
  await page
    .getByRole("textbox", { name: "Password required" })
    .fill(user.password);
  await page.getByRole("button", { name: "Sign In" }).click();
};

/**
 * Authentication flow tests for email sign-up and subsequent login attempts.
 */
test.describe("authentication", () => {
  /**
   * Ensures email sign-up requires verification before log in is allowed.
   */
  test("email sign up requires verification before log in", async ({ page }) => {
    const user = buildAuthUser();

    await signUpWithEmail(page, user);
    await logInWithEmail(page, user);

    await expect(page).toHaveURL(/\/log-in/);
    await expect(page.getByRole("button", { name: "Sign In" })).toBeVisible();
  });

  test("seeded user can log in and is redirected to the requested page", async ({
    page,
  }) => {
    await navigateToPath(page, userDashboardEventsPath);

    await expect(page).toHaveURL(/\/log-in\?next_url=/);
    expect(page.url()).toContain(encodeURIComponent(userDashboardEventsPath));

    await Promise.all([
      page.waitForURL((url) => url.pathname === "/dashboard/user"),
      logInWithEmail(page, TEST_USER_CREDENTIALS.member1),
    ]);

    await expect(page).toHaveURL(
      (url) =>
        url.pathname === "/dashboard/user" && url.searchParams.get("tab") === "events",
    );
    await expect(
      page.locator("#dashboard-content").getByText("My Events", { exact: true }),
    ).toBeVisible();
  });

  test("logged in user can log out from the header menu", async ({ page }) => {
    await logInWithSeededUser(page, TEST_USER_CREDENTIALS.member1);

    const userMenuButton = page.locator('#user-dropdown-button[data-logged-in="true"]');
    await expect(userMenuButton).toBeVisible();
    await userMenuButton.click();

    const logOutLink = page.getByRole("menuitem", { name: "Log out" });
    await expect(logOutLink).toBeVisible();

    await Promise.all([
      page.waitForURL(/\/log-in/),
      logOutLink.click(),
    ]);

    await expect(page.getByRole("heading", { name: "Log In" })).toBeVisible();
  });
});
