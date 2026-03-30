import { execFileSync } from "node:child_process";
import { existsSync, readFileSync } from "node:fs";
import * as path from "node:path";

import { expect, test } from "@playwright/test";
import type { Page } from "@playwright/test";

import {
  buildAuthUser,
  logInWithSeededUser,
  navigateToPath,
  TEST_USER_CREDENTIALS,
  type AuthUser,
} from "../utils";

const USER_DASHBOARD_EVENTS_PATH = "/dashboard/user?tab=events";
type EmailCredentials = Pick<AuthUser, "username" | "password">;
type DbConfig = {
  host: string;
  port: string;
  user: string;
  password: string;
  database: string;
};

/** Returns the configured psql executable path for E2E DB access. */
const getPsqlPath = () => {
  const pgBin = process.env.OCG_PG_BIN;

  return pgBin ? `${pgBin}/psql` : "psql";
};

/** Normalizes a simple YAML scalar value from server config. */
const parseYamlScalar = (value: string) => {
  const trimmedValue = value.trim();

  if (
    (trimmedValue.startsWith('"') && trimmedValue.endsWith('"')) ||
    (trimmedValue.startsWith("'") && trimmedValue.endsWith("'"))
  ) {
    return trimmedValue.slice(1, -1);
  }

  return trimmedValue;
};

/** Reads DB settings from the local server config when env vars are unset. */
const readServerDbConfig = (): Partial<DbConfig> => {
  const configDir = process.env.OCG_CONFIG || path.join(process.env.HOME || "", ".config/ocg");
  const serverConfigPath = path.join(configDir, "server.yml");

  if (!existsSync(serverConfigPath)) {
    return {};
  }

  const config = readFileSync(serverConfigPath, "utf8");
  const dbConfig: Partial<DbConfig> = {};
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

    const match = trimmedLine.match(/^(host|port|dbname|user|password):\s*(.+)$/u);

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

/** Resolves the DB connection used by the email verification helper. */
const getDbConfig = (): DbConfig => {
  const serverDbConfig = readServerDbConfig();

  return {
    host: process.env.OCG_DB_HOST ?? serverDbConfig.host ?? "localhost",
    port: process.env.OCG_DB_PORT ?? serverDbConfig.port ?? "5432",
    user: process.env.OCG_DB_USER ?? serverDbConfig.user ?? "postgres",
    password: process.env.OCG_DB_PASSWORD ?? serverDbConfig.password ?? "",
    database:
      process.env.OCG_DB_NAME_E2E ??
      process.env.OCG_DB_NAME ??
      serverDbConfig.database ??
      "ocg",
  };
};

const emailVerificationDbConfig = getDbConfig();

/** Reads the email verification code for a newly created user from the E2E DB. */
const readEmailVerificationCode = (email: string) => {
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

/** Waits until sign-up persistence creates an email verification code. */
const waitForEmailVerificationCode = async (email: string) => {
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

/** Completes the sign-up form using email and password credentials. */
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

/** Logs in using email username and password credentials. */
const logInWithEmail = async (page: Page, user: EmailCredentials) => {
  await expect(page.getByRole("heading", { name: "Log In" })).toBeVisible();
  await page.getByLabel("Username").fill(user.username);
  await page
    .getByRole("textbox", { name: "Password required" })
    .fill(user.password);
  await page.getByRole("button", { name: "Sign In" }).click();
};

test.describe("authentication", () => {
  test("email sign up requires verification before log in", async ({ page }) => {
    const user = buildAuthUser();

    await signUpWithEmail(page, user);
    await logInWithEmail(page, user);

    await expect(page).toHaveURL(/\/log-in/);
    await expect(page.getByRole("button", { name: "Sign In" })).toBeVisible();
  });

  test("email sign up can verify and then log in", async ({ page }) => {
    const user = buildAuthUser();

    await signUpWithEmail(page, user);

    const verificationCode = await waitForEmailVerificationCode(user.email);

    await navigateToPath(page, `/verify-email/${verificationCode}`);
    await expect(page).toHaveURL(/\/log-in/);
    await expect(
      page.getByText("Email verified successfully. You can now log in using your credentials."),
    ).toBeVisible();

    await navigateToPath(page, USER_DASHBOARD_EVENTS_PATH);

    await expect(page).toHaveURL(/\/log-in\?next_url=/);

    await Promise.all([
      page.waitForURL((url) => url.pathname === "/dashboard/user"),
      logInWithEmail(page, user),
    ]);

    await expect(page).toHaveURL(
      (url) =>
        url.pathname === "/dashboard/user" && url.searchParams.get("tab") === "events",
    );
    await expect(page.locator("#dashboard-content")).toBeVisible();
  });

  test("seeded user can log in and is redirected to the requested page", async ({
    page,
  }) => {
    await navigateToPath(page, USER_DASHBOARD_EVENTS_PATH);

    await expect(page).toHaveURL(/\/log-in\?next_url=/);
    expect(page.url()).toContain(encodeURIComponent(USER_DASHBOARD_EVENTS_PATH));

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
