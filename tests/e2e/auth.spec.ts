import { test, expect } from "@playwright/test";
import { navigateWithRetry, openLoginPage, openSignUpPage } from "./utils";

test.describe("Login Page", () => {
  test("should display login form with all required fields", async ({
    page,
  }) => {
    await openLoginPage(page);
    const usernameInput = page.locator("#username");
    const passwordInput = page.locator("#password");
    const submitButton = page.locator('button[type="submit"]');

    await expect(usernameInput).toBeVisible();
    await expect(passwordInput).toBeVisible();
    await expect(submitButton).toBeVisible();
  });

  test("should have link to sign up page", async ({ page }) => {
    await openLoginPage(page);
    const signUpLink = page.getByRole('link', { name: 'Sign up' });

    await expect(signUpLink).toBeVisible();
  });

  test("should navigate to sign up page when link is clicked", async ({
    page,
  }) => {
    await openLoginPage(page);
    const signUpLink = page.getByRole('link', { name: 'Sign up' })

    await signUpLink.click();
    await expect(page).toHaveURL(/\/sign-up/);
  });

  test("should show validation error for empty username", async ({ page }) => {
    await openLoginPage(page);
    const passwordInput = page.locator("#password");
    const submitButton = page.locator('button[type="submit"]');

    await passwordInput.fill("somepassword");
    await submitButton.click();

    await expect(page).toHaveURL(/\/log-in/);
  });

  test("should show validation error for empty password", async ({ page }) => {
    await openLoginPage(page);
    const usernameInput = page.locator("#username");
    const submitButton = page.locator('button[type="submit"]');

    await usernameInput.fill("someuser");
    await submitButton.click();

    await expect(page).toHaveURL(/\/log-in/);
  });

  test("should preserve next_url parameter for redirect", async ({ page }) => {
    const redirectUrl = "/group/test-group";

    await navigateWithRetry(
      page,
      `/log-in?next_url=${encodeURIComponent(redirectUrl)}`,
    );

    await expect(page.url()).toContain("next_url");
  });
});

test.describe("Sign Up Page", () => {
  test("should display registration form with all required fields", async ({
    page,
  }) => {
    await openSignUpPage(page);
    const nameInput = page.locator("#name");
    const emailInput = page.locator("#email");
    const usernameInput = page.locator("#username");
    const passwordInput = page.locator("#password");
    const passwordConfirmationInput = page.locator("#password_confirmation");
    const submitButton = page.locator('button[type="submit"]');

    await expect(nameInput).toBeVisible();
    await expect(emailInput).toBeVisible();
    await expect(usernameInput).toBeVisible();
    await expect(passwordInput).toBeVisible();
    await expect(passwordConfirmationInput).toBeVisible();
    await expect(submitButton).toBeVisible();
  });

  test("should have link to login page", async ({ page }) => {
    await openSignUpPage(page);
    const loginLink = page.getByRole('link', { name: 'Sign in' });

    await expect(loginLink).toBeVisible();
  });

  test("should navigate to login page when link is clicked", async ({
    page,
  }) => {
    await openSignUpPage(page);
    const loginLink = page.getByRole('link', { name: 'Sign in' });

    await loginLink.click();
    await expect(page).toHaveURL(/\/log-in/);
  });

  test("should show validation for empty required fields", async ({ page }) => {
    await openSignUpPage(page);
    const submitButton = page.locator('button[type="submit"]');

    await submitButton.click();

    await expect(page).toHaveURL(/\/sign-up/);
  });

  test("should validate email format", async ({ page }) => {
    await openSignUpPage(page);
    const nameInput = page.locator("#name");
    const emailInput = page.locator("#email");
    const usernameInput = page.locator("#username");
    const passwordInput = page.locator("#password");
    const passwordConfirmationInput = page.locator("#password_confirmation");
    const submitButton = page.locator('button[type="submit"]');

    await nameInput.fill("Test User");
    await emailInput.fill("invalid-email");
    await usernameInput.fill("testuser");
    await passwordInput.fill("password123");
    await passwordConfirmationInput.fill("password123");

    await submitButton.click();

    await expect(page).toHaveURL(/\/sign-up/);
  });

  test("should validate password confirmation matches", async ({ page }) => {
    await openSignUpPage(page);
    const nameInput = page.locator("#name");
    const emailInput = page.locator("#email");
    const usernameInput = page.locator("#username");
    const passwordInput = page.locator("#password");
    const passwordConfirmationInput = page.locator("#password_confirmation");
    const submitButton = page.locator('button[type="submit"]');

    await nameInput.fill("Test User");
    await emailInput.fill("test@example.com");
    await usernameInput.fill("testuser");
    await passwordInput.fill("password123");
    await passwordConfirmationInput.fill("different-password");
    await submitButton.click();

    await expect(page).toHaveURL(/\/sign-up/);
  });
});
