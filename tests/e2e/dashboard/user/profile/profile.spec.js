import { withRowRestore } from "../../../database.js";
import { expect, test } from "../../../fixtures.js";

import { TEST_USER_CREDENTIALS, TEST_USER_IDS } from "../../../seed.js";
import {
  logInWithSeededUser,
  navigateToPath,
  selectTimezone,
  waitForActionResponse,
} from "../../../utils.js";
import { fillMultipleInputs, setImageFieldValue } from "../../form-helpers.js";

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
const ADMIN2_USER_ROW = { key: { user_id: TEST_USER_IDS.admin2 }, table: "user" };

test.describe("user dashboard profile view", () => {
  test("user can update profile details", async ({ page }) => {
    // Select the requested timezone only when it differs from the current value.
    const setTimezoneIfNeeded = async (timezone) => {
      const timezoneInput = page.locator('timezone-selector[name="timezone"] input[name="timezone"]');

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
      await waitForActionResponse(page, () => detailsForm.getByRole("button", { name: "Save" }).click(), {
        method: "PUT",
        urlIncludes: "/dashboard/account/update/details",
      });

      // Wait for the backend flash success dialog call.
      await page.waitForFunction(() =>
        (window.__ocgSwalCalls ?? []).some(
          (call) => call.icon === "success" && call.text === "User details updated successfully.",
        ),
      );
      const successAlertMessages = await page.evaluate(() => {
        const calls = window.__ocgSwalCalls ?? [];

        // Return the values used by the caller.
        return calls.filter((call) => call.icon === "success").map((call) => call.text ?? "");
      });

      // Assert the backend flash payload.
      expect(successAlertMessages).toEqual(["User details updated successfully."]);
    };

    // Verify profile detail values after saving them.
    const expectProfileDetails = async (values) => {
      await navigateToPath(page, ACCOUNT_PATH);

      // Assert the field value was updated.
      await expect(page.locator("#name")).toHaveValue(values.name);
      await expect(page.locator('timezone-selector[name="timezone"] input[name="timezone"]')).toHaveValue(
        values.timezone,
      );
      await expect(page.locator("#company")).toHaveValue(values.company);
      await expect(page.locator("#title")).toHaveValue(values.title);
      await expect(page.locator('image-field[name="photo_url"] input[name="photo_url"]')).toHaveValue(
        values.photoUrl,
      );
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
      await expect(page.locator("#github_url")).toHaveValue(values.githubUrl);
    };

    // Log in before continuing the scenario.
    await logInWithSeededUser(page, TEST_USER_CREDENTIALS.admin2);

    // Save updated profile details and verify persistence, restoring the seeded row afterwards.
    await withRowRestore(ADMIN2_USER_ROW, async () => {
      await saveProfileDetails(UPDATED_DETAILS);
      await expectProfileDetails(UPDATED_DETAILS);
    });
  });

  test("failed profile save preserves the entered details for retry", async ({ page }) => {
    // Load the account form before intercepting its update request.
    await logInWithSeededUser(page, TEST_USER_CREDENTIALS.admin2);
    await navigateToPath(page, ACCOUNT_PATH);
    const detailsForm = page.locator("#user-details-form");
    const companyInput = detailsForm.locator("#company");
    const saveButton = detailsForm.getByRole("button", { name: "Save" });
    const retryValue = "Profile save retry value";
    const updatePath = "**/dashboard/account/update/details";

    try {
      // Return a local server failure without changing the stored profile.
      await page.route(updatePath, (route) =>
        route.fulfill({
          body: "Temporary profile failure",
          contentType: "text/plain",
          status: 500,
        }),
      );
      await companyInput.fill(retryValue);
      await waitForActionResponse(page, () => saveButton.click(), {
        method: "PUT",
        status: 500,
        urlIncludes: "/dashboard/account/update/details",
      });

      // Verify the error and retry state keep the user's unsaved value intact.
      await expect(page.locator(".swal2-popup")).toContainText(
        "Something went wrong updating the user details. Please try again later.",
      );
      await expect(companyInput).toHaveValue(retryValue);
      await expect(saveButton).toBeEnabled();
    } finally {
      // Remove the local failure route.
      await page.unroute(updatePath);
    }
  });

  test("user sees an error when the current password is incorrect", async ({ page }) => {
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
    await passwordForm.locator("#password_confirmation").fill("TemporaryPassword123!");

    // Set up update password response.
    const updatePasswordResponse = waitForActionResponse(
      page,
      () => passwordForm.getByRole("button", { name: "Save" }).click(),
      {
        method: "PUT",
        status: 403,
        urlIncludes: "/dashboard/account/update/password",
      },
    );

    // Wait for the password update response.
    await updatePasswordResponse;
    await expect(page).toHaveURL(/\/dashboard\/user\?tab=account$/);
    await expect(passwordForm.locator("#old_password")).toHaveValue("WrongPassword123!");
    await expect(passwordForm.locator("#new_password")).toHaveValue("TemporaryPassword123!");
  });

  test("browser validation blocks mismatched replacement passwords", async ({ page }) => {
    // Log in and load account settings before submitting the password form.
    await logInWithSeededUser(page, TEST_USER_CREDENTIALS.admin2);
    await navigateToPath(page, ACCOUNT_PATH);

    // Find the password form and confirmation field.
    const passwordForm = page.locator("#password-form");
    const confirmation = passwordForm.locator("#password_confirmation");

    // Submit mismatched replacement passwords.
    await passwordForm.locator("#old_password").fill("Password123!");
    await passwordForm.locator("#new_password").fill("TemporaryPassword123!");
    await confirmation.fill("DifferentPassword123!");
    await passwordForm.getByRole("button", { name: "Save" }).click();

    // Verify browser validation blocks navigation and explains the mismatch.
    await expect(confirmation).toBeFocused();
    await expect(confirmation).toHaveJSProperty("validationMessage", "Passwords do not match");
    await expect(page).toHaveURL(/\/dashboard\/user\?tab=account$/);
  });

  test("user can replace the password and is logged out from the current session", async ({ page }) => {
    // Use a temporary replacement; the row restore puts the seeded password hash back.
    const originalCredentials = TEST_USER_CREDENTIALS.admin2;
    const temporaryCredentials = {
      ...originalCredentials,
      password: "TemporaryPassword123!",
    };

    // Submit one password replacement through the account form.
    const replacePassword = async (currentPassword, replacementPassword) => {
      await navigateToPath(page, ACCOUNT_PATH);
      const passwordForm = page.locator("#password-form");

      await passwordForm.locator("#old_password").fill(currentPassword);
      await passwordForm.locator("#new_password").fill(replacementPassword);
      await passwordForm.locator("#password_confirmation").fill(replacementPassword);

      // The server invalidates the session and redirects to log in.
      await waitForActionResponse(page, () => passwordForm.getByRole("button", { name: "Save" }).click(), {
        method: "PUT",
        pathname: "/dashboard/account/update/password",
        status: 303,
      });
    };

    // Submit credentials without assuming that authentication succeeds.
    const submitLogin = async (credentials) => {
      await navigateToPath(page, "/log-in");
      await page.getByLabel("Username").fill(credentials.username);
      await page.getByRole("textbox", { name: "Password required" }).fill(credentials.password);
      await page.getByRole("button", { name: "Sign In" }).click();
    };

    // Restore the seeded password hash after exercising both authentication outcomes.
    await withRowRestore(ADMIN2_USER_ROW, async () => {
      // Replace the seeded password with a temporary password.
      await logInWithSeededUser(page, originalCredentials);
      await replacePassword(originalCredentials.password, temporaryCredentials.password);
      await expect(page.getByRole("heading", { name: "Log In" })).toBeVisible();

      // Verify protected navigation now requires a new authenticated session.
      await navigateToPath(page, "/dashboard/user");
      await expect(page).toHaveURL(/\/log-in\?next_url=/);

      // Verify the previous password no longer authenticates.
      await submitLogin(originalCredentials);
      await expect(page).toHaveURL(/\/log-in$/);
      await expect(page.getByText(/Invalid credentials/)).toBeVisible();

      // Verify the replacement password authenticates successfully.
      await logInWithSeededUser(page, temporaryCredentials);
      await expect(page).not.toHaveURL(/\/log-in/);
    });
  });
});
