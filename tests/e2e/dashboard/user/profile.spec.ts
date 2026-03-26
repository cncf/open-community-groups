import { expect, test } from "@playwright/test";

import {
  TEST_USER_CREDENTIALS,
  logInWithSeededUser,
  navigateToPath,
  selectTimezone,
} from "../../utils";
import {
  fillMultipleInputs,
  setImageFieldValue,
} from "../form-helpers";

const BASELINE_DETAILS = {
  bio: "Baseline profile bio for account view coverage.",
  blueskyUrl: "https://bsky.app/profile/e2e-admin-two-baseline",
  city: "Barcelona",
  company: "Open Community Groups",
  country: "Spain",
  facebookUrl: "https://facebook.com/e2e.admin.two.baseline",
  interests: ["platform engineering", "community operations"],
  linkedinUrl: "https://linkedin.com/in/e2e-admin-two-baseline",
  name: "E2E Admin Two Baseline",
  photoUrl: "/static/images/e2e/community-secondary-logo.svg",
  timezone: "Europe/Madrid",
  title: "Community Administrator",
  twitterUrl: "https://x.com/e2e_admin_two_baseline",
  websiteUrl: "https://baseline-admin-two.example.com",
};

const UPDATED_DETAILS = {
  bio: "Updated profile bio for account view coverage.",
  blueskyUrl: "https://bsky.app/profile/e2e-admin-two-updated",
  city: "Lisbon",
  company: "Platform Guild",
  country: "Portugal",
  facebookUrl: "https://facebook.com/e2e.admin.two.updated",
  interests: ["developer experience", "event operations"],
  linkedinUrl: "https://linkedin.com/in/e2e-admin-two-updated",
  name: "E2E Admin Two Updated",
  photoUrl: "/static/images/e2e/community-primary-logo.svg",
  timezone: "UTC",
  title: "Program Lead",
  twitterUrl: "https://x.com/e2e_admin_two_updated",
  websiteUrl: "https://updated-admin-two.example.com",
};

const ACCOUNT_PATH = "/dashboard/user?tab=account";

test.describe("user dashboard profile view", () => {
  test("user can update and restore profile details", async ({ page }) => {
    test.setTimeout(60_000);

    const setTimezoneIfNeeded = async (timezone: string) => {
      const timezoneInput = page.locator(
        'timezone-selector[name="timezone"] input[name="timezone"]',
      );

      if ((await timezoneInput.inputValue()) === timezone) {
        return;
      }

      await selectTimezone(page, timezone);
    };

    const saveProfileDetails = async (values: typeof BASELINE_DETAILS) => {
      await navigateToPath(page, ACCOUNT_PATH);

      const detailsForm = page.locator("#user-details-form");
      await expect(detailsForm).toBeVisible();

      await page.locator("#name").fill(values.name);
      await setTimezoneIfNeeded(values.timezone);
      await page.locator("#company").fill(values.company);
      await page.locator("#title").fill(values.title);
      await setImageFieldValue(page, "photo_url", values.photoUrl);
      await page.locator("#bio").fill(values.bio);
      await fillMultipleInputs(
        page.locator('multiple-inputs[field-name="interests"]'),
        values.interests,
        "Interest",
      );
      await page.locator("#city").fill(values.city);
      await page.locator("#country").fill(values.country);
      await page.locator("#website_url").fill(values.websiteUrl);
      await page.locator("#linkedin_url").fill(values.linkedinUrl);
      await page.locator("#bluesky_url").fill(values.blueskyUrl);
      await page.locator("#twitter_url").fill(values.twitterUrl);
      await page.locator("#facebook_url").fill(values.facebookUrl);

      await Promise.all([
        page.waitForResponse(
          (response) =>
            response.request().method() === "PUT" &&
            response.url().includes("/dashboard/account/update/details") &&
            response.ok(),
        ),
        detailsForm.getByRole("button", { name: "Save" }).click(),
      ]);
    };

    const expectProfileDetails = async (values: typeof BASELINE_DETAILS) => {
      await navigateToPath(page, ACCOUNT_PATH);

      await expect(page.locator("#name")).toHaveValue(values.name);
      await expect(page.locator('timezone-selector[name="timezone"] input[name="timezone"]')).toHaveValue(
        values.timezone,
      );
      await expect(page.locator("#company")).toHaveValue(values.company);
      await expect(page.locator("#title")).toHaveValue(values.title);
      await expect(
        page.locator('image-field[name="photo_url"] input[name="photo_url"]'),
      ).toHaveValue(values.photoUrl);
      await expect(page.locator("#bio")).toHaveValue(values.bio);
      await expect(
        page.locator('multiple-inputs[field-name="interests"] input.input-primary').nth(0),
      ).toHaveValue(values.interests[0]);
      await expect(
        page.locator('multiple-inputs[field-name="interests"] input.input-primary').nth(1),
      ).toHaveValue(values.interests[1]);
      await expect(page.locator("#city")).toHaveValue(values.city);
      await expect(page.locator("#country")).toHaveValue(values.country);
      await expect(page.locator("#website_url")).toHaveValue(values.websiteUrl);
      await expect(page.locator("#linkedin_url")).toHaveValue(values.linkedinUrl);
      await expect(page.locator("#bluesky_url")).toHaveValue(values.blueskyUrl);
      await expect(page.locator("#twitter_url")).toHaveValue(values.twitterUrl);
      await expect(page.locator("#facebook_url")).toHaveValue(values.facebookUrl);
    };

    await logInWithSeededUser(page, TEST_USER_CREDENTIALS.admin2);

    try {
      await saveProfileDetails(UPDATED_DETAILS);
      await expectProfileDetails(UPDATED_DETAILS);

      await saveProfileDetails(BASELINE_DETAILS);
      await expectProfileDetails(BASELINE_DETAILS);
    } finally {
      await saveProfileDetails(BASELINE_DETAILS);
    }
  });

  test("user sees an error when the current password is incorrect", async ({ page }) => {
    await logInWithSeededUser(page, TEST_USER_CREDENTIALS.admin2);
    await navigateToPath(page, ACCOUNT_PATH);

    const passwordForm = page.locator("#password-form");
    await expect(passwordForm).toBeVisible();

    await passwordForm.locator("#old_password").fill("WrongPassword123!");
    await passwordForm.locator("#new_password").fill("TemporaryPassword123!");
    await passwordForm.locator("#password_confirmation").fill("TemporaryPassword123!");

    const updatePasswordResponse = page.waitForResponse(
      (response) =>
        response.request().method() === "PUT" &&
        response.url().includes("/dashboard/account/update/password") &&
        response.status() === 403,
    );

    await passwordForm.getByRole("button", { name: "Save" }).click();

    await updatePasswordResponse;
    await expect(page).toHaveURL(/\/dashboard\/user\?tab=account$/);
    await expect(passwordForm.locator("#old_password")).toHaveValue("WrongPassword123!");
    await expect(passwordForm.locator("#new_password")).toHaveValue("TemporaryPassword123!");
  });
});
