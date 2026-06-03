import { expect, test } from "../../../fixtures.js";

import { fillMarkdownEditor, setImageFieldValue } from "../../form-helpers.js";
import { navigateToPath } from "../../../utils.js";

test.describe("community dashboard settings view", () => {
  test("admin can update and restore community settings", async ({
    adminCommunityPage,
  }) => {
    // Define the settings URL used by the read and submit helpers.
    const settingsPath = "/dashboard/community?tab=settings";

    // Read current community settings values before updating them.
    const readSettingsFormValues = async () => {
      await navigateToPath(adminCommunityPage, settingsPath);

      // Find the Display Name control.
      const displayNameInput = adminCommunityPage.getByLabel("Display Name");
      const descriptionEditor = adminCommunityPage.locator(
        "markdown-editor#description",
      );
      const websiteInput = adminCommunityPage.getByLabel("Website");

      // Assert the expected content is visible.
      await expect(displayNameInput).toBeVisible();

      // Return the values used by the caller.
      return {
        bannerMobileUrl: await adminCommunityPage
          .locator(
            'image-field[name="banner_mobile_url"] input[name="banner_mobile_url"]',
          )
          .inputValue(),
        bannerUrl: await adminCommunityPage
          .locator('image-field[name="banner_url"] input[name="banner_url"]')
          .inputValue(),
        description:
          (await descriptionEditor.getAttribute("content")) ??
          (await descriptionEditor
            .locator('textarea[name="description"]')
            .first()
            .inputValue()),
        displayName: await displayNameInput.inputValue(),
        logoUrl: await adminCommunityPage
          .locator('image-field[name="logo_url"] input[name="logo_url"]')
          .inputValue(),
        websiteUrl: await websiteInput.inputValue(),
      };
    };

    // Submit community settings values and verify they persist.
    const submitSettings = async ({
      bannerMobileUrl,
      bannerUrl,
      description,
      displayName,
      logoUrl,
      websiteUrl,
    }) => {
      await navigateToPath(adminCommunityPage, settingsPath);

      // Fill Display Name.
      await adminCommunityPage.getByLabel("Display Name").fill(displayName);
      await fillMarkdownEditor(adminCommunityPage, "description", description);
      await setImageFieldValue(adminCommunityPage, "logo_url", logoUrl);
      await setImageFieldValue(adminCommunityPage, "banner_url", bannerUrl);
      await setImageFieldValue(
        adminCommunityPage,
        "banner_mobile_url",
        bannerMobileUrl,
      );
      await adminCommunityPage.getByLabel("Website").fill(websiteUrl);

      // Click Update Settings.
      await Promise.all([
        adminCommunityPage.waitForResponse(
          (response) =>
            response.request().method() === "PUT" &&
            response.url().includes("/dashboard/community/settings/update") &&
            response.ok(),
        ),
        adminCommunityPage
          .getByRole("button", { name: "Update Settings" })
          .click(),
      ]);

      // Assert the field value was updated.
      await expect(adminCommunityPage.getByLabel("Display Name")).toHaveValue(
        displayName,
      );
      await expect(
        adminCommunityPage.locator("markdown-editor#description"),
      ).toHaveAttribute("content", description);
      await expect(
        adminCommunityPage.locator(
          'image-field[name="logo_url"] input[name="logo_url"]',
        ),
      ).toHaveValue(logoUrl);
      await expect(
        adminCommunityPage.locator(
          'image-field[name="banner_url"] input[name="banner_url"]',
        ),
      ).toHaveValue(bannerUrl);
      await expect(
        adminCommunityPage.locator(
          'image-field[name="banner_mobile_url"] input[name="banner_mobile_url"]',
        ),
      ).toHaveValue(bannerMobileUrl);
      await expect(adminCommunityPage.getByLabel("Website")).toHaveValue(
        websiteUrl,
      );
    };

    // Set up original values.
    const originalValues = await readSettingsFormValues();
    const updatedValues = {
      ...originalValues,
      bannerMobileUrl:
        "/static/images/e2e/community-secondary-banner-mobile.svg",
      bannerUrl: "/static/images/e2e/community-secondary-banner.svg",
      description:
        "Updated platform engineering community details for settings coverage.",
      displayName: `Platform Engineering Community ${Date.now()}`,
      logoUrl: "/static/images/e2e/community-secondary-logo.svg",
    };

    // Save the updated settings.
    await submitSettings(updatedValues);
    await submitSettings(originalValues);
  });

  test("viewer sees read-only controls on community settings", async ({
    communityViewerPage,
  }) => {
    // Load the community settings tab as a read-only viewer.
    await navigateToPath(
      communityViewerPage,
      "/dashboard/community?tab=settings",
    );

    // Find the dashboard content.
    const dashboardContent = communityViewerPage.locator("#dashboard-content");

    // Verify viewer sees read-only controls on community settings.
    await expect(
      dashboardContent.getByText("General Settings", { exact: true }),
    ).toBeVisible();
    await expect(
      dashboardContent.getByText(
        "Your role cannot update community settings.",
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
    ).toHaveAttribute("title", "Your role cannot update community settings.");
  });
});
