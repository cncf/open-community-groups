import { expect, test } from "../../../fixtures.js";

import { fillMarkdownEditor, setImageFieldValue } from "../../form-helpers.js";
import { navigateToPath } from "../../../utils.js";

test.describe("alliance dashboard settings view", () => {
  test("admin can update and restore alliance settings", async ({
    adminAlliancePage,
  }) => {
    // Define the settings URL used by the read and submit helpers.
    const settingsPath = "/dashboard/alliance?tab=settings";

    // Read current alliance settings values before updating them.
    const readSettingsFormValues = async () => {
      await navigateToPath(adminAlliancePage, settingsPath);

      // Find the Display Name control.
      const displayNameInput = adminAlliancePage.getByLabel("Display Name");
      const descriptionEditor = adminAlliancePage.locator(
        "markdown-editor#description",
      );
      const websiteInput = adminAlliancePage.getByLabel("Website");

      // Assert the expected content is visible.
      await expect(displayNameInput).toBeVisible();

      // Return the values used by the caller.
      return {
        bannerMobileUrl: await adminAlliancePage
          .locator(
            'image-field[name="banner_mobile_url"] input[name="banner_mobile_url"]',
          )
          .inputValue(),
        bannerUrl: await adminAlliancePage
          .locator('image-field[name="banner_url"] input[name="banner_url"]')
          .inputValue(),
        description:
          (await descriptionEditor.getAttribute("content")) ??
          (await descriptionEditor
            .locator('textarea[name="description"]')
            .first()
            .inputValue()),
        displayName: await displayNameInput.inputValue(),
        logoUrl: await adminAlliancePage
          .locator('image-field[name="logo_url"] input[name="logo_url"]')
          .inputValue(),
        websiteUrl: await websiteInput.inputValue(),
      };
    };

    // Submit alliance settings values and verify they persist.
    const submitSettings = async ({
      bannerMobileUrl,
      bannerUrl,
      description,
      displayName,
      logoUrl,
      websiteUrl,
    }) => {
      await navigateToPath(adminAlliancePage, settingsPath);

      // Fill Display Name.
      await adminAlliancePage.getByLabel("Display Name").fill(displayName);
      await fillMarkdownEditor(adminAlliancePage, "description", description);
      await setImageFieldValue(adminAlliancePage, "logo_url", logoUrl);
      await setImageFieldValue(adminAlliancePage, "banner_url", bannerUrl);
      await setImageFieldValue(
        adminAlliancePage,
        "banner_mobile_url",
        bannerMobileUrl,
      );
      await adminAlliancePage.getByLabel("Website").fill(websiteUrl);

      // Click Update Settings.
      await Promise.all([
        adminAlliancePage.waitForResponse(
          (response) =>
            response.request().method() === "PUT" &&
            response.url().includes("/dashboard/alliance/settings/update") &&
            response.ok(),
        ),
        adminAlliancePage
          .getByRole("button", { name: "Update Settings" })
          .click(),
      ]);

      // Assert the field value was updated.
      await expect(adminAlliancePage.getByLabel("Display Name")).toHaveValue(
        displayName,
      );
      await expect(
        adminAlliancePage.locator("markdown-editor#description"),
      ).toHaveAttribute("content", description);
      await expect(
        adminAlliancePage.locator(
          'image-field[name="logo_url"] input[name="logo_url"]',
        ),
      ).toHaveValue(logoUrl);
      await expect(
        adminAlliancePage.locator(
          'image-field[name="banner_url"] input[name="banner_url"]',
        ),
      ).toHaveValue(bannerUrl);
      await expect(
        adminAlliancePage.locator(
          'image-field[name="banner_mobile_url"] input[name="banner_mobile_url"]',
        ),
      ).toHaveValue(bannerMobileUrl);
      await expect(adminAlliancePage.getByLabel("Website")).toHaveValue(
        websiteUrl,
      );
    };

    // Set up original values.
    const originalValues = await readSettingsFormValues();
    const updatedValues = {
      ...originalValues,
      bannerMobileUrl:
        "/static/images/e2e/alliance-secondary-banner-mobile.svg",
      bannerUrl: "/static/images/e2e/alliance-secondary-banner.svg",
      description: "Updated GOUP Alliance details for settings coverage.",
      displayName: `GOUP Alliance ${Date.now()}`,
      logoUrl: "/static/images/e2e/alliance-secondary-logo.svg",
    };

    // Save the updated settings.
    await submitSettings(updatedValues);
    await submitSettings(originalValues);
  });

  test("viewer sees read-only controls on alliance settings", async ({
    allianceViewerPage,
  }) => {
    // Load the alliance settings tab as a read-only viewer.
    await navigateToPath(
      allianceViewerPage,
      "/dashboard/alliance?tab=settings",
    );

    // Find the dashboard content.
    const dashboardContent = allianceViewerPage.locator("#dashboard-content");

    // Verify viewer sees read-only controls on alliance settings.
    await expect(
      dashboardContent.getByText("General Settings", { exact: true }),
    ).toBeVisible();
    await expect(
      dashboardContent.getByText(
        "Your role cannot update alliance settings.",
        {
          exact: true,
        },
      ),
    ).toBeVisible();
    await expect(dashboardContent.locator(".inert-form")).toHaveAttribute(
      "inert",
      "",
    );
    await expect(
      dashboardContent.getByRole("button", { name: "Update Settings" }),
    ).toBeDisabled();
    await expect(
      dashboardContent.getByRole("button", { name: "Update Settings" }),
    ).toHaveAttribute("title", "Your role cannot update alliance settings.");
  });
});
