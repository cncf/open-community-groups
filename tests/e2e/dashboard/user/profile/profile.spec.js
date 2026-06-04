import { expect, test } from "@playwright/test";

import {
  TEST_USER_CREDENTIALS,
  logInWithSeededUser,
  navigateToPath,
  selectTimezone,
} from "../../../utils.js";
import { fillMultipleInputs, setImageFieldValue } from "../../form-helpers.js";

const BASELINE_DETAILS = {
  bio: "Baseline profile bio for account view coverage.",
  blueskyUrl: "https://bsky.app/profile/e2e-admin-two-baseline",
  city: "Barcelona",
  company: "Open Community Groups",
  country: "Spain",
  facebookUrl: "https://facebook.com/e2e.admin.two.baseline",
  githubUrl: "https://github.com/e2e-admin-two-baseline",
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
  githubUrl: "https://github.com/e2e-admin-two-updated",
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
  test("user sees the notifications toggle in the compact switch layout", async ({
    page,
  }) => {
    // Log in as the seeded user before opening account settings.
    await logInWithSeededUser(page, TEST_USER_CREDENTIALS.admin2);
    await navigateToPath(page, ACCOUNT_PATH);

    // Find the notification toggle label.
    const notificationToggleLabel = page.locator(
      'label[for="toggle_optional_notifications_enabled"]',
    );
    const notificationSwitch = notificationToggleLabel.locator(
      "span.relative.w-11.h-6",
    );
    const notificationText = notificationToggleLabel.getByText(
      "Receive optional notifications",
    );
    const notificationDescription = page.getByText(
      "Receive broader announcements such as new event announcements",
    );

    // Verify user sees the notifications toggle in the compact switch layout.
    await expect(notificationToggleLabel).toBeVisible();
    await expect(notificationSwitch).toBeVisible();
    await expect(notificationText).toBeVisible();
    await expect(notificationDescription).toBeVisible();

    // Set up switch box.
    const switchBox = await notificationSwitch.boundingBox();
    const textBox = await notificationText.boundingBox();
    const descriptionBox = await notificationDescription.boundingBox();

    // Assert that the switch was measured.
    expect(switchBox).not.toBeNull();
    expect(textBox).not.toBeNull();
    expect(descriptionBox).not.toBeNull();

    // Fail clearly if profile layout boxes were not measured.
    if (!switchBox || !textBox || !descriptionBox) {
      return;
    }

    // Assert the profile switch layout.
    expect(switchBox.x).toBeLessThan(textBox.x);
    expect(Math.abs(switchBox.y - textBox.y)).toBeLessThanOrEqual(4);
    expect(descriptionBox.y).toBeGreaterThan(switchBox.y + switchBox.height);
    expect(Math.abs(descriptionBox.x - switchBox.x)).toBeLessThanOrEqual(2);
  });

  test("user can update and restore profile details", async ({ page }) => {
    // Allow enough time for the full profile update and restore flow.
    test.setTimeout(60_000);

    // Select the requested timezone only when it differs from the current value.
    const setTimezoneIfNeeded = async (timezone) => {
      const timezoneInput = page.locator(
        'timezone-selector[name="timezone"] input[name="timezone"]',
      );

      // Skip the timezone update when it already matches.
      if ((await timezoneInput.inputValue()) === timezone) {
        return;
      }

      // Select the profile timezone.
      await selectTimezone(page, timezone);
    };

    // Save profile detail values and verify the success feedback.
    const saveProfileDetails = async (values) => {
      await navigateToPath(page, ACCOUNT_PATH);

      // Find the details form.
      const detailsForm = page.locator("#user-details-form");
      await expect(detailsForm).toBeVisible();

      // Fill name.
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
      await page.locator("#github_url").fill(values.githubUrl);

      // Install the browser-side dialog spy.
      await page.evaluate(() => {
        const testWindow = window;
        const swal = testWindow.Swal;

        // Leave the page dialog helper untouched when it is unavailable.
        if (!swal || typeof swal.fire !== "function") {
          return;
        }

        // Keep the original dialog helper for cleanup.
        if (!swal.__ocgOriginalFire) {
          swal.__ocgOriginalFire = swal.fire.bind(swal);
        }

        // Reset the captured dialog calls.
        testWindow.__ocgSwalCalls = [];
        swal.fire = (...args) => {
          testWindow.__ocgSwalCalls?.push(args[0]);
          return swal.__ocgOriginalFire?.(...args);
        };
      });

      // Click Save.
      await Promise.all([
        page.waitForResponse(
          (response) =>
            response.request().method() === "PUT" &&
            response.url().includes("/dashboard/account/update/details") &&
            response.ok(),
        ),
        detailsForm.getByRole("button", { name: "Save" }).click(),
      ]);

      // Assert the expected content is visible.
      await expect(
        page
          .locator(".swal2-popup")
          .filter({ hasText: "User details updated successfully." }),
      ).toBeVisible();
      const successAlertMessages = await page.evaluate(() => {
        const calls = window.__ocgSwalCalls ?? [];

        // Return the values used by the caller.
        return calls
          .filter((call) => call.icon === "success")
          .map((call) => call.text ?? "");
      });

      // Assert the emitted payload.
      expect(successAlertMessages).toEqual([
        "User details updated successfully.",
      ]);
    };

    // Verify profile detail values after saving or restoring them.
    const expectProfileDetails = async (values) => {
      await navigateToPath(page, ACCOUNT_PATH);

      // Assert the field value was updated.
      await expect(page.locator("#name")).toHaveValue(values.name);
      await expect(
        page.locator(
          'timezone-selector[name="timezone"] input[name="timezone"]',
        ),
      ).toHaveValue(values.timezone);
      await expect(page.locator("#company")).toHaveValue(values.company);
      await expect(page.locator("#title")).toHaveValue(values.title);
      await expect(
        page.locator('image-field[name="photo_url"] input[name="photo_url"]'),
      ).toHaveValue(values.photoUrl);
      await expect(page.locator("#bio")).toHaveValue(values.bio);
      await expect(
        page
          .locator(
            'multiple-inputs[field-name="interests"] input.input-primary',
          )
          .nth(0),
      ).toHaveValue(values.interests[0]);
      await expect(
        page
          .locator(
            'multiple-inputs[field-name="interests"] input.input-primary',
          )
          .nth(1),
      ).toHaveValue(values.interests[1]);
      await expect(page.locator("#city")).toHaveValue(values.city);
      await expect(page.locator("#country")).toHaveValue(values.country);
      await expect(page.locator("#website_url")).toHaveValue(values.websiteUrl);
      await expect(page.locator("#linkedin_url")).toHaveValue(
        values.linkedinUrl,
      );
      await expect(page.locator("#bluesky_url")).toHaveValue(values.blueskyUrl);
      await expect(page.locator("#twitter_url")).toHaveValue(values.twitterUrl);
      await expect(page.locator("#facebook_url")).toHaveValue(
        values.facebookUrl,
      );
      await expect(page.locator("#github_url")).toHaveValue(values.githubUrl);
    };

    // Log in before continuing the scenario.
    await logInWithSeededUser(page, TEST_USER_CREDENTIALS.admin2);

    // Restore the page state after the check.
    try {
      await saveProfileDetails(UPDATED_DETAILS);
      await expectProfileDetails(UPDATED_DETAILS);

      // Restore the baseline profile details.
      await saveProfileDetails(BASELINE_DETAILS);
      await expectProfileDetails(BASELINE_DETAILS);
    } finally {
      await saveProfileDetails(BASELINE_DETAILS);
    }
  });

  test("user sees an error when the current password is incorrect", async ({
    page,
  }) => {
    // Log in as the seeded user before submitting the password form.
    await logInWithSeededUser(page, TEST_USER_CREDENTIALS.admin2);
    await navigateToPath(page, ACCOUNT_PATH);

    // Find the password form.
    const passwordForm = page.locator("#password-form");

    // Verify user sees an error when the current password is incorrect.
    await expect(passwordForm).toBeVisible();

    // Fill old password.
    await passwordForm.locator("#old_password").fill("WrongPassword123!");
    await passwordForm.locator("#new_password").fill("TemporaryPassword123!");
    await passwordForm
      .locator("#password_confirmation")
      .fill("TemporaryPassword123!");

    // Set up update password response.
    const updatePasswordResponse = page.waitForResponse(
      (response) =>
        response.request().method() === "PUT" &&
        response.url().includes("/dashboard/account/update/password") &&
        response.status() === 403,
    );

    // Click Save.
    await passwordForm.getByRole("button", { name: "Save" }).click();

    // Wait for the password update response.
    await updatePasswordResponse;
    await expect(page).toHaveURL(/\/dashboard\/user\?tab=account$/);
    await expect(passwordForm.locator("#old_password")).toHaveValue(
      "WrongPassword123!",
    );
    await expect(passwordForm.locator("#new_password")).toHaveValue(
      "TemporaryPassword123!",
    );
  });
});
