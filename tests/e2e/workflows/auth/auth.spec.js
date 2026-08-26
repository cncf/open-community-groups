import { expect, test } from "@playwright/test";

import { queryE2eDatabase } from "../../database.js";
import { buildAuthUser, logInWithSeededUser, navigateToPath, TEST_USER_CREDENTIALS } from "../../utils.js";

const USER_DASHBOARD_EVENTS_PATH = "/dashboard/user?tab=events";

// Read the email verification code for a newly created user from the E2E DB.
const readEmailVerificationCode = (email) => {
  const escapedEmail = email.replace(/'/g, "''");
  const sql = `
    select evc.email_verification_code_id
    from email_verification_code evc
    join "user" u on u.user_id = evc.user_id
    where u.email = '${escapedEmail}'
  `;

  const output = queryE2eDatabase(sql);

  return output || null;
};

// Wait until sign-up persistence creates an email verification code.
const waitForEmailVerificationCode = async (email) => {
  const timeoutAt = Date.now() + 10_000;

  while (Date.now() < timeoutAt) {
    const code = readEmailVerificationCode(email);

    if (code) {
      return code;
    }

    await new Promise((resolve) => setTimeout(resolve, 250));
  }

  throw new Error(`Timed out waiting for verification code for ${email}`);
};

// Fill the email sign-up form using the provided account details.
const fillSignUpForm = async (page, user) => {
  await page.getByLabel("Full Name").fill(user.name);
  await page.getByLabel("Email Address").fill(user.email);
  await page.getByLabel("Username").fill(user.username);
  await page.getByRole("textbox", { name: "Password required", exact: true }).fill(user.password);
  await page.getByRole("textbox", { name: "Confirm Password required" }).fill(user.password);
};

// Complete the sign-up form using email and password credentials.
const signUpWithEmail = async (page, user) => {
  await navigateToPath(page, "/sign-up");

  await expect(page.getByRole("heading", { name: "Sign Up" })).toBeVisible();
  await fillSignUpForm(page, user);

  await page.getByRole("button", { name: "Create Account" }).click();
  await expect(page.getByRole("heading", { name: "Log In" })).toBeVisible();
};

// Log in using email username and password credentials.
const logInWithEmail = async (page, user) => {
  await expect(page.getByRole("heading", { name: "Log In" })).toBeVisible();
  await page.getByLabel("Username").fill(user.username);
  await page.getByRole("textbox", { name: "Password required" }).fill(user.password);
  await page.getByRole("button", { name: "Sign In" }).click();
};

test.describe("authentication", () => {
  test("login and sign-up preserve the requested destination and form contracts", async ({ page }) => {
    // Define the protected destination carried between authentication pages.
    const nextUrl = "/dashboard/user?tab=events";

    // Load login with a return destination.
    await navigateToPath(page, `/log-in?next_url=${encodeURIComponent(nextUrl)}`);

    // Find the login form and verify its browser-facing contract. The server
    // stores the sanitized next url percent-encoded, so expect that form.
    const encodedNextUrl = encodeURIComponent(nextUrl);
    const loginForm = page.getByRole("form", { name: "Log In" });
    await expect(loginForm).toHaveAttribute("action", `/log-in?next_url=${encodedNextUrl}`);
    await expect(loginForm.getByLabel("Username")).toHaveAttribute("autocomplete", "username");
    await expect(loginForm.getByLabel("Username")).toHaveAttribute("required", "");
    await expect(loginForm.getByRole("textbox", { name: "Password required" })).toHaveAttribute(
      "autocomplete",
      "current-password",
    );
    await expect(page.getByRole("link", { name: "Sign up" })).toHaveAttribute(
      "href",
      `/sign-up?next_url=${encodeURIComponent(nextUrl)}`,
    );

    // Verify enabled external providers preserve the same destination.
    for (const providerName of ["GitHub", "Linux Foundation SSO"]) {
      const providerLink = page.getByRole("link", { name: providerName });

      if ((await providerLink.count()) > 0) {
        await expect(providerLink).toHaveAttribute(
          "href",
          new RegExp(`next_url=${encodeURIComponent(nextUrl)}`),
        );
      }
    }

    // Move to sign-up and verify its form contract and return link.
    await page.getByRole("link", { name: "Sign up" }).click();
    await expect(page).toHaveURL(new RegExp(`/sign-up\\?next_url=${encodeURIComponent(nextUrl)}`));
    await expect(page.getByRole("heading", { name: "Sign Up" })).toBeVisible();
    await expect(page.getByLabel("Full Name")).toHaveAttribute("autocomplete", "name");
    await expect(page.getByLabel("Email Address")).toHaveAttribute("type", "email");
    await expect(page.getByRole("textbox", { name: "Password required", exact: true })).toHaveAttribute(
      "autocomplete",
      "new-password",
    );
    await expect(page.getByRole("link", { name: "Sign in" })).toHaveAttribute(
      "href",
      `/log-in?next_url=${encodedNextUrl}`,
    );
  });

  test("browser validation blocks empty and mismatched sign-up forms", async ({ page }) => {
    // Build a unique user so client-side validation can be exercised safely.
    const user = buildAuthUser();

    // Load sign-up and submit the untouched form.
    await navigateToPath(page, "/sign-up");
    await page.getByRole("button", { name: "Create Account" }).click();
    await expect(page.getByLabel("Full Name")).toBeFocused();
    await expect(page).toHaveURL(/\/sign-up$/);

    // Fill the required fields with mismatched passwords and submit again.
    await page.getByLabel("Full Name").fill(user.name);
    await page.getByLabel("Email Address").fill(user.email);
    await page.getByLabel("Username").fill(user.username);
    await page.getByRole("textbox", { name: "Password required", exact: true }).fill(user.password);
    const confirmation = page.getByRole("textbox", {
      name: "Confirm Password required",
    });
    await confirmation.fill("Different123!");
    await page.getByRole("button", { name: "Create Account" }).click();

    // Verify the invalid form focuses and explains the mismatched field.
    await expect(confirmation).toBeFocused();
    await expect(confirmation).toHaveJSProperty("validationMessage", "Passwords do not match");
    await expect(page).toHaveURL(/\/sign-up$/);
  });

  test("duplicate email sign-ups show a safe recovery error", async ({ page }) => {
    // Reuse a seeded email; duplicate usernames are auto-suffixed by the
    // server, so only the email uniqueness conflict fails the sign-up.
    const user = {
      ...buildAuthUser(),
      email: "e2e-member-1@example.com",
    };

    // Submit the duplicate account through the public sign-up form.
    await navigateToPath(page, "/sign-up");
    await fillSignUpForm(page, user);
    await page.getByRole("button", { name: "Create Account" }).click();

    // Verify uniqueness failures stay on sign-up and avoid exposing account details.
    await expect(page).toHaveURL(/\/sign-up$/);
    await expect(
      page.getByText("Something went wrong while signing up. Please try again later.", {
        exact: true,
      }),
    ).toBeVisible();
    await expect(page.getByRole("heading", { name: "Sign Up" })).toBeVisible();
    await expect(page.locator("body")).not.toContainText("e2e-member-1@example.com");
  });

  test("invalid credentials preserve the login page and show recovery copy", async ({ page }) => {
    // Load login and submit credentials that cannot authenticate.
    await navigateToPath(page, "/log-in");
    await page.getByLabel("Username").fill("missing-e2e-user");
    await page.getByRole("textbox", { name: "Password required" }).fill("Password123!");
    await page.getByRole("button", { name: "Sign In" }).click();

    // Verify the user remains on login and receives recovery guidance. The
    // server renders a fresh form, so the username field is not preserved.
    await expect(page).toHaveURL(/\/log-in$/);
    await expect(page.getByText(/Invalid credentials/)).toContainText(
      "Please make sure you have verified your email address.",
    );
  });

  test("invalid verification links explain expiry and return to login", async ({ page }) => {
    // Load email verification with an invalid token.
    await navigateToPath(page, "/verify-email/aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa");

    // Verify the failure redirects to login and explains token expiry.
    await expect(page).toHaveURL(/\/log-in$/);
    await expect(
      page.getByText("Error verifying email (please note that links are only valid for 24 hours).", {
        exact: true,
      }),
    ).toBeVisible();
  });

  test("authentication forms remain usable on mobile @mobile", async ({ page }) => {
    // Load sign-up using the mobile project viewport.
    await navigateToPath(page, "/sign-up");

    // Verify the complete form remains reachable within the viewport.
    await expect(page.getByRole("heading", { name: "Sign Up" })).toBeVisible();
    await expect(page.getByLabel("Full Name")).toBeInViewport();
    await expect(page.getByLabel("Email Address")).toBeInViewport();
    await page.getByLabel("Email Address").scrollIntoViewIfNeeded();
    await page.getByRole("button", { name: "Create Account" }).scrollIntoViewIfNeeded();
    await expect(page.getByRole("button", { name: "Create Account" })).toBeInViewport();
  });

  test("email sign up requires verification before log in", async ({ page }) => {
    // Create a unique email user for the verification-gated login flow.
    const user = buildAuthUser();

    // Complete the sign-up flow for the test user.
    await signUpWithEmail(page, user);
    await logInWithEmail(page, user);

    // Verify email sign up requires verification before log in.
    await expect(page).toHaveURL(/\/log-in/);
    await expect(page.getByRole("button", { name: "Sign In" })).toBeVisible();
  });

  test("email sign up can verify and then log in", async ({ page }) => {
    // Create a unique email user for the verification flow.
    const user = buildAuthUser();

    // Complete the sign-up flow for the test user.
    await signUpWithEmail(page, user);

    // Use the email verification code from the test inbox.
    const verificationCode = await waitForEmailVerificationCode(user.email);

    // Open the email verification link.
    await navigateToPath(page, `/verify-email/${verificationCode}`);

    // Verify email sign up can verify and then log in.
    await expect(page).toHaveURL(/\/log-in/);
    await expect(
      page.getByText("Email verified successfully. You can now log in using your credentials."),
    ).toBeVisible();

    // Open the protected events page.
    await navigateToPath(page, USER_DASHBOARD_EVENTS_PATH);

    // Assert that the browser lands on the right URL.
    await expect(page).toHaveURL(/\/log-in\?next_url=/);

    // Log in with the email user.
    await Promise.all([
      page.waitForURL((url) => url.pathname === "/dashboard/user"),
      logInWithEmail(page, user),
    ]);

    // Assert that the browser lands on the right URL.
    await expect(page).toHaveURL(
      (url) => url.pathname === "/dashboard/user" && url.searchParams.get("tab") === "events",
    );
    await expect(page.locator("#dashboard-content")).toBeVisible();
  });

  test("used verification links cannot be replayed", async ({ page }) => {
    // Create a unique email user for the replay verification flow.
    const user = buildAuthUser();

    // Complete the sign-up flow for the test user.
    await signUpWithEmail(page, user);

    // Use the email verification code from the test inbox.
    const verificationCode = await waitForEmailVerificationCode(user.email);

    // Consume the verification link once and confirm it succeeds.
    await navigateToPath(page, `/verify-email/${verificationCode}`);
    await expect(page).toHaveURL(/\/log-in/);
    await expect(
      page.getByText("Email verified successfully. You can now log in using your credentials."),
    ).toBeVisible();

    // Reuse the consumed verification link and verify it is rejected.
    await navigateToPath(page, `/verify-email/${verificationCode}`);
    await expect(page).toHaveURL(/\/log-in$/);
    await expect(
      page.getByText("Error verifying email (please note that links are only valid for 24 hours).", {
        exact: true,
      }),
    ).toBeVisible();
  });

  test("seeded user can log in and is redirected to the requested page", async ({ page }) => {
    // Open a protected page to capture the redirect target.
    await navigateToPath(page, USER_DASHBOARD_EVENTS_PATH);

    // Verify seeded user can log in and is redirected to the requested page.
    await expect(page).toHaveURL(/\/log-in\?next_url=/);
    expect(page.url()).toContain(encodeURIComponent(USER_DASHBOARD_EVENTS_PATH));

    // Log in with the email user.
    await Promise.all([
      page.waitForURL((url) => url.pathname === "/dashboard/user"),
      logInWithEmail(page, TEST_USER_CREDENTIALS.member1),
    ]);

    // Assert that the browser lands on the right URL.
    await expect(page).toHaveURL(
      (url) => url.pathname === "/dashboard/user" && url.searchParams.get("tab") === "events",
    );
    await expect(page.locator("#dashboard-content").getByText("My Events", { exact: true })).toBeVisible();
  });

  test("logged in user can log out from the header menu", async ({ page }) => {
    // Log in with a seeded member before using the header menu.
    await logInWithSeededUser(page, TEST_USER_CREDENTIALS.member1);

    // Find the user menu button.
    const userMenuButton = page.locator('#user-dropdown-button[data-logged-in="true"]');

    // Verify logged in user can log out from the header menu.
    await expect(userMenuButton).toBeVisible();
    await userMenuButton.click();

    // Find the Log out control.
    const logOutButton = page.getByRole("menuitem", { name: "Log out" });
    await expect(logOutButton).toBeVisible();

    // Submit a native POST and wait for full-page navigation.
    const [, logOutRequest] = await Promise.all([
      page.waitForURL(/\/log-in/),
      page.waitForRequest(
        (request) => request.method() === "POST" && request.url().endsWith("/log-out"),
      ),
      logOutButton.click(),
    ]);
    expect(logOutRequest.headers()["hx-request"]).toBeUndefined();

    // Assert that Log In replaces the main document rather than the menu.
    await expect(
      page.locator("main#main-content").getByRole("heading", { name: "Log In" }),
    ).toBeVisible();

    // Verify the session no longer grants access to protected pages.
    await navigateToPath(page, USER_DASHBOARD_EVENTS_PATH);
    await expect(page).toHaveURL(/\/log-in\?next_url=/);
    await expect(page.getByRole("heading", { name: "Log In" })).toBeVisible();
  });
});
