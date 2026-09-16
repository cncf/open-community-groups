import { expect, test } from "../../fixtures.js";
import { queryE2eDatabase } from "../../database.js";
import { TEST_USER_CREDENTIALS } from "../../seed.js";
import { buildE2eUrl, logInWithSeededUser, navigateToPath } from "../../utils.js";

// Cookie holding the tower-sessions id, which is also the `auth_session` primary key.
const SESSION_COOKIE_NAME = "id";

// The fixture-recovery test depends on the session expired by the test before it.
test.describe.configure({ mode: "serial" });

test.describe("session expiry", () => {
  test("an expired session is redirected instead of served", async ({ browser }) => {
    // Create an isolated browser context and page.
    const context = await browser.newContext();
    const page = await context.newPage();

    try {
      // Log in with a dedicated context so no cached fixture state is involved.
      await logInWithSeededUser(page, TEST_USER_CREDENTIALS.empty);
      await expireSession(context);

      // Verify the raw probe reports the redirect rather than following it to the login page.
      const probe = await page.request.get(buildE2eUrl("/dashboard/user"), { maxRedirects: 0 });
      expect(probe.status()).toBeGreaterThanOrEqual(300);
      expect(probe.status()).toBeLessThan(400);
      expect(probe.headers().location).toContain("/log-in");

      // Verify a page navigation lands on the login form.
      await navigateToPath(page, "/dashboard/user");
      await expect(page).toHaveURL(/\/log-in/);
      await expect(page.getByRole("heading", { name: "Log In" })).toBeVisible();
    } finally {
      // Close the isolated browser context.
      await context.close();
    }
  });

  test("an HTMX action after expiry redirects to the login page", async ({ browser }) => {
    // Create an isolated browser context and page.
    const context = await browser.newContext();
    const page = await context.newPage();

    try {
      // Open the dashboard while the session is still valid.
      await logInWithSeededUser(page, TEST_USER_CREDENTIALS.empty);
      await navigateToPath(page, "/dashboard/user");
      await expect(page.locator("#dashboard-content")).toBeVisible();

      // Expire the session, then trigger an HTMX tab swap.
      await expireSession(context);
      await page.locator('a[hx-get="/dashboard/user?tab=account"]').first().click();

      // Verify the HX-Redirect response navigates the whole page to the login form.
      await expect(page).toHaveURL(/\/log-in/);
      await expect(page.getByRole("heading", { name: "Log In" })).toBeVisible();
    } finally {
      // Close the isolated browser context.
      await context.close();
    }
  });

  test("cached fixture sessions are refreshed after expiry", async ({ emptyUserPage }) => {
    // Expire the session behind the cached fixture storage state.
    await expireSession(emptyUserPage.context());

    // Verify the current page now sees an expired session.
    const probe = await emptyUserPage.request.get(buildE2eUrl("/dashboard/user"), { maxRedirects: 0 });
    expect(probe.status()).not.toBe(200);
  });

  test("a fixture page re-authenticates instead of reusing the expired state", async ({ emptyUserPage }) => {
    // Verify the fixture detected the stale cached session and logged in again.
    const probe = await emptyUserPage.request.get(buildE2eUrl("/dashboard/user"), { maxRedirects: 0 });
    expect(probe.status()).toBe(200);

    // Load the dashboard with the refreshed fixture session.
    await navigateToPath(emptyUserPage, "/dashboard/user");
    await expect(emptyUserPage).toHaveURL(/\/dashboard\/user/);
    await expect(emptyUserPage.locator("#dashboard-content")).toBeVisible();
  });
});

/** Deletes the server-side session backing a browser context so its cookie becomes stale. */
const expireSession = async (context) => {
  const sessionCookie = (await context.cookies()).find((cookie) => cookie.name === SESSION_COOKIE_NAME);

  expect(sessionCookie, "authenticated context should carry a session cookie").toBeDefined();
  queryE2eDatabase(`delete from auth_session where auth_session_id = '${sessionCookie.value}'`);
};
