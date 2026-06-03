import { execFileSync } from "node:child_process";
import { existsSync, readFileSync } from "node:fs";
import * as path from "node:path";

import { expect, test } from "@playwright/test";

import {
  buildAuthUser,
  logInWithSeededUser,
  navigateToPath,
  TEST_USER_CREDENTIALS,
} from "../utils.js";

const USER_DASHBOARD_EVENTS_PATH = "/dashboard/user?tab=events";

// Return the configured psql executable path for E2E DB access.
const getPsqlPath = () => {
  const pgBin = process.env.OCG_PG_BIN;

  return pgBin ? `${pgBin}/psql` : "psql";
};

// Normalize a simple YAML scalar value from server config.
const parseYamlScalar = (value) => {
  const trimmedValue = value.trim();

  if (
    (trimmedValue.startsWith('"') && trimmedValue.endsWith('"')) ||
    (trimmedValue.startsWith("'") && trimmedValue.endsWith("'"))
  ) {
    return trimmedValue.slice(1, -1);
  }

  return trimmedValue;
};

// Read DB settings from the local server config when env vars are unset.
const readServerDbConfig = () => {
  const configDir =
    process.env.OCG_CONFIG || path.join(process.env.HOME || "", ".config/ocg");
  const serverConfigPath = path.join(configDir, "server-tests-e2e.yml");

  if (!existsSync(serverConfigPath)) {
    return {};
  }

  const config = readFileSync(serverConfigPath, "utf8");
  const dbConfig = {};
  let dbSectionIndent = -1;

  for (const line of config.split(/\r?\n/u)) {
    const trimmedLine = line.trim();

    if (!trimmedLine || trimmedLine.startsWith("#")) {
      continue;
    }

    const indent = line.length - line.trimStart().length;

    if (dbSectionIndent === -1) {
      if (trimmedLine === "db:") {
        dbSectionIndent = indent;
      }

      continue;
    }

    if (indent <= dbSectionIndent && /^[A-Za-z0-9_-]+:/u.test(trimmedLine)) {
      break;
    }

    const match = trimmedLine.match(
      /^(host|port|dbname|user|password):\s*(.+)$/u,
    );

    if (!match) {
      continue;
    }

    const [, key, rawValue] = match;
    const parsedValue = parseYamlScalar(rawValue);

    switch (key) {
      case "host":
        dbConfig.host = parsedValue;
        break;
      case "port":
        dbConfig.port = parsedValue;
        break;
      case "dbname":
        dbConfig.database = parsedValue;
        break;
      case "user":
        dbConfig.user = parsedValue;
        break;
      case "password":
        dbConfig.password = parsedValue;
        break;
    }
  }

  return dbConfig;
};

// Resolve the DB connection used by the email verification helper.
const getDbConfig = () => {
  const serverDbConfig = readServerDbConfig();

  return {
    host: process.env.OCG_DB_HOST ?? serverDbConfig.host ?? "localhost",
    port: process.env.OCG_DB_PORT ?? serverDbConfig.port ?? "5432",
    user: process.env.OCG_DB_USER ?? serverDbConfig.user ?? "postgres",
    password: process.env.OCG_DB_PASSWORD ?? serverDbConfig.password ?? "",
    database:
      process.env.OCG_DB_NAME_TESTS_E2E ??
      serverDbConfig.database ??
      process.env.OCG_DB_NAME ??
      "ocg_tests_e2e",
  };
};

const emailVerificationDbConfig = getDbConfig();

// Read the email verification code for a newly created user from the E2E DB.
const readEmailVerificationCode = (email) => {
  const escapedEmail = email.replace(/'/g, "''");
  const sql = `
    select evc.email_verification_code_id
    from email_verification_code evc
    join "user" u on u.user_id = evc.user_id
    where u.email = '${escapedEmail}'
  `;

  const output = execFileSync(
    getPsqlPath(),
    [
      "-h",
      emailVerificationDbConfig.host,
      "-p",
      emailVerificationDbConfig.port,
      "-U",
      emailVerificationDbConfig.user,
      "-d",
      emailVerificationDbConfig.database,
      "-tA",
      "-c",
      sql,
    ],
    {
      encoding: "utf8",
      env: {
        ...process.env,
        PGPASSWORD: emailVerificationDbConfig.password,
      },
    },
  ).trim();

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

// Complete the sign-up form using email and password credentials.
const signUpWithEmail = async (page, user) => {
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

// Log in using email username and password credentials.
const logInWithEmail = async (page, user) => {
  await expect(page.getByRole("heading", { name: "Log In" })).toBeVisible();
  await page.getByLabel("Username").fill(user.username);
  await page
    .getByRole("textbox", { name: "Password required" })
    .fill(user.password);
  await page.getByRole("button", { name: "Sign In" }).click();
};

test.describe("authentication", () => {
  test("email sign up requires verification before log in", async ({
    page,
  }) => {
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
      page.getByText(
        "Email verified successfully. You can now log in using your credentials.",
      ),
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
      (url) =>
        url.pathname === "/dashboard/user" &&
        url.searchParams.get("tab") === "events",
    );
    await expect(page.locator("#dashboard-content")).toBeVisible();
  });

  test("seeded user can log in and is redirected to the requested page", async ({
    page,
  }) => {
    // Open a protected page to capture the redirect target.
    await navigateToPath(page, USER_DASHBOARD_EVENTS_PATH);

    // Verify seeded user can log in and is redirected to the requested page.
    await expect(page).toHaveURL(/\/log-in\?next_url=/);
    expect(page.url()).toContain(
      encodeURIComponent(USER_DASHBOARD_EVENTS_PATH),
    );

    // Log in with the email user.
    await Promise.all([
      page.waitForURL((url) => url.pathname === "/dashboard/user"),
      logInWithEmail(page, TEST_USER_CREDENTIALS.member1),
    ]);

    // Assert that the browser lands on the right URL.
    await expect(page).toHaveURL(
      (url) =>
        url.pathname === "/dashboard/user" &&
        url.searchParams.get("tab") === "events",
    );
    await expect(
      page
        .locator("#dashboard-content")
        .getByText("My Events", { exact: true }),
    ).toBeVisible();
  });

  test("logged in user can log out from the header menu", async ({ page }) => {
    // Log in with a seeded member before using the header menu.
    await logInWithSeededUser(page, TEST_USER_CREDENTIALS.member1);

    // Find the user menu button.
    const userMenuButton = page.locator(
      '#user-dropdown-button[data-logged-in="true"]',
    );

    // Verify logged in user can log out from the header menu.
    await expect(userMenuButton).toBeVisible();
    await userMenuButton.click();

    // Find the Log out control.
    const logOutLink = page.getByRole("menuitem", { name: "Log out" });
    await expect(logOutLink).toBeVisible();

    // Submit the action and wait for navigation.
    await Promise.all([page.waitForURL(/\/log-in/), logOutLink.click()]);

    // Assert that Log In is visible.
    await expect(page.getByRole("heading", { name: "Log In" })).toBeVisible();
  });
});
