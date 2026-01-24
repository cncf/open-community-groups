import { expect, test } from "@playwright/test";
import type { Page } from "@playwright/test";

import { buildAuthUser, navigateToPath, type AuthUser } from "../utils";

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
const logInWithEmail = async (page: Page, user: AuthUser) => {
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
});
