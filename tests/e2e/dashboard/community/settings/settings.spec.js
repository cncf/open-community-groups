import { expect, test } from "../../../fixtures.js";

import { TEST_UPLOAD_ASSET_PATHS, fillMarkdownEditor, setImageFieldValue } from "../../form-helpers.js";
import { navigateToPath } from "../../../utils.js";

test.describe("community dashboard settings view", () => {
  test("admin can cancel and apply advertisement banner cropping", async ({ adminCommunityPage }) => {
    // Load the croppable advertisement banner field.
    await navigateToPath(adminCommunityPage, "/dashboard/community?tab=settings");

    const advertisementBannerField = adminCommunityPage.locator('image-field[name="ad_banner_url"]');
    const cropper = advertisementBannerField.locator("image-cropper");
    const fileInput = advertisementBannerField.locator('input[type="file"]');
    const uploadButton = advertisementBannerField.getByRole("button", {
      name: "Upload image for Banner Image",
    });
    const valueInput = advertisementBannerField.locator('input[name="ad_banner_url"]');
    const initialValue = await valueInput.inputValue();
    const uploadRequests = [];
    adminCommunityPage.on("request", (request) => {
      if (request.method() === "POST" && new URL(request.url()).pathname === "/images") {
        uploadRequests.push(request);
      }
    });

    // Open the crop editor and verify its required size and controls.
    await fileInput.setInputFiles(TEST_UPLOAD_ASSET_PATHS.alternateBanner);
    await expect(adminCommunityPage.getByText("Enlarging it may reduce image quality.")).toBeVisible();
    await adminCommunityPage.getByRole("button", { name: "Continue" }).click();
    const dialog = cropper.getByRole("dialog", { name: "Crop Banner Image" });
    const cropArea = cropper.getByRole("application", {
      name: "Image crop area",
    });
    await expect(dialog).toBeVisible();
    await expect(dialog).toContainText("2400 × 300 px");
    await expect(cropArea).toHaveAttribute("aria-busy", "false");
    await expect(cropArea).toBeFocused();
    await expect(cropper.getByRole("button", { name: "Zoom out" })).toBeDisabled();
    await cropper.getByRole("button", { name: "Zoom in" }).click();
    await expect(cropper.getByText("110%", { exact: true })).toBeVisible();
    await cropper.getByRole("button", { name: "Reset position" }).click();
    await expect(cropper.getByText("Fit", { exact: true })).toBeVisible();

    // Cancel without uploading or changing the saved form value.
    await cropper.getByRole("button", { name: "Cancel" }).click();
    await expect(dialog).toBeHidden();
    await expect(fileInput).toHaveValue("");
    await expect(valueInput).toHaveValue(initialValue);
    await expect(uploadButton).toBeFocused();
    expect(uploadRequests).toHaveLength(0);

    // Reopen the editor and upload the mandatory crop.
    await adminCommunityPage.evaluate(() => {
      const nativeFetch = window.fetch;
      window.fetch = (input, init) => {
        if (input === "/images" && init?.body instanceof FormData) {
          const uploadFile = init.body.get("file");
          if (uploadFile instanceof File) {
            window.imageUploadMetadata = {
              name: uploadFile.name,
              type: uploadFile.type,
            };
          }
        }

        return nativeFetch(input, init);
      };
    });
    await fileInput.setInputFiles(TEST_UPLOAD_ASSET_PATHS.alternateBanner);
    await adminCommunityPage.getByRole("button", { name: "Continue" }).click();
    await expect(cropper.getByRole("button", { name: "Apply crop" })).toBeEnabled();
    const uploadResponsePromise = adminCommunityPage.waitForResponse(
      (response) =>
        response.request().method() === "POST" &&
        new URL(response.url()).pathname === "/images" &&
        response.status() === 201,
    );
    await cropper.getByRole("button", { name: "Apply crop" }).click();
    await uploadResponsePromise;

    // Verify the generated file and the uploaded preview dimensions.
    const uploadMetadata = await adminCommunityPage.evaluate(() => window.imageUploadMetadata);
    expect(uploadMetadata).toEqual({
      name: "community-secondary-banner-cropped.webp",
      type: "image/webp",
    });
    await expect(dialog).toBeHidden();
    await expect(valueInput).toHaveValue(/\/images\//);
    await expect(advertisementBannerField.getByRole("img", { name: "Image preview" })).toHaveJSProperty(
      "naturalWidth",
      2400,
    );
    await expect(advertisementBannerField.getByRole("img", { name: "Image preview" })).toHaveJSProperty(
      "naturalHeight",
      300,
    );
    expect(uploadRequests).toHaveLength(1);
  });

  test("admin can update and restore community settings", async ({ adminCommunityPage }) => {
    // Define the settings URL used by the read and submit helpers.
    const settingsPath = "/dashboard/community?tab=settings";

    // Read current community settings values before updating them.
    const readSettingsFormValues = async () => {
      await navigateToPath(adminCommunityPage, settingsPath);

      // Find the Display Name control.
      const displayNameInput = adminCommunityPage.getByLabel("Display Name");
      const descriptionEditor = adminCommunityPage.locator("markdown-editor#description");
      const websiteInput = adminCommunityPage.getByLabel("Website");

      // Assert the expected content is visible.
      await expect(displayNameInput).toBeVisible();
      const advertisementBannerField = adminCommunityPage.locator('image-field[name="ad_banner_url"]');
      await expect(advertisementBannerField).toHaveAttribute("crop-target", "ad_banner");
      await expect(advertisementBannerField).toContainText("Size required 2400 x 300 px.");

      // Return the values used by the caller.
      return {
        bannerMobileUrl: await adminCommunityPage
          .locator('image-field[name="banner_mobile_url"] input[name="banner_mobile_url"]')
          .inputValue(),
        bannerUrl: await adminCommunityPage
          .locator('image-field[name="banner_url"] input[name="banner_url"]')
          .inputValue(),
        description:
          (await descriptionEditor.getAttribute("content")) ??
          (await descriptionEditor.locator('textarea[name="description"]').first().inputValue()),
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
      await setImageFieldValue(adminCommunityPage, "banner_mobile_url", bannerMobileUrl);
      await adminCommunityPage.getByLabel("Website").fill(websiteUrl);

      // Click Update Settings.
      await Promise.all([
        adminCommunityPage.waitForResponse(
          (response) =>
            response.request().method() === "PUT" &&
            response.url().includes("/dashboard/community/settings/update") &&
            response.ok(),
        ),
        adminCommunityPage.getByRole("button", { name: "Update Settings" }).click(),
      ]);

      // Assert the field value was updated.
      await expect(adminCommunityPage.getByLabel("Display Name")).toHaveValue(displayName);
      await expect(adminCommunityPage.locator("markdown-editor#description")).toHaveAttribute(
        "content",
        description,
      );
      await expect(
        adminCommunityPage.locator('image-field[name="logo_url"] input[name="logo_url"]'),
      ).toHaveValue(logoUrl);
      await expect(
        adminCommunityPage.locator('image-field[name="banner_url"] input[name="banner_url"]'),
      ).toHaveValue(bannerUrl);
      await expect(
        adminCommunityPage.locator('image-field[name="banner_mobile_url"] input[name="banner_mobile_url"]'),
      ).toHaveValue(bannerMobileUrl);
      await expect(adminCommunityPage.getByLabel("Website")).toHaveValue(websiteUrl);
    };

    // Set up original values.
    const originalValues = await readSettingsFormValues();
    const updatedValues = {
      ...originalValues,
      bannerMobileUrl: "/static/images/e2e/community-secondary-banner-mobile.svg",
      bannerUrl: "/static/images/e2e/community-secondary-banner.svg",
      description: "Updated platform engineering community details for settings coverage.",
      displayName: `Platform Engineering Community ${Date.now()}`,
      logoUrl: "/static/images/e2e/community-secondary-logo.svg",
    };

    // Save the updated settings.
    await submitSettings(updatedValues);
    await submitSettings(originalValues);
  });

  test("viewer sees read-only controls on community settings", async ({ communityViewerPage }) => {
    // Load the community settings tab as a read-only viewer.
    await navigateToPath(communityViewerPage, "/dashboard/community?tab=settings");

    // Find the dashboard content.
    const dashboardContent = communityViewerPage.locator("#dashboard-content");

    // Verify viewer sees read-only controls on community settings.
    await expect(dashboardContent.getByText("General Settings", { exact: true })).toBeVisible();
    await expect(
      dashboardContent.getByText("Your role cannot update community settings.", {
        exact: true,
      }),
    ).toBeVisible();
    await expect(dashboardContent.locator(".inert-form")).toHaveAttribute("inert", "");
    await expect(dashboardContent.getByRole("button", { name: "Update Settings" })).toBeDisabled();
    await expect(dashboardContent.getByRole("button", { name: "Update Settings" })).toHaveAttribute(
      "title",
      "Your role cannot update community settings.",
    );
  });
});
