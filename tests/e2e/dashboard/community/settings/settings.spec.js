import { expect, test } from "../../../fixtures.js";
import { withRowRestore } from "../../../database.js";

import {
  TEST_UPLOAD_ASSET_PATHS,
  fillMarkdownEditor,
  setImageFieldValue,
  waitForImageUpload,
} from "../../form-helpers.js";
import { TEST_COMMUNITY_IDS } from "../../../seed.js";
import { navigateToPath, uniqueName, waitForActionResponse } from "../../../utils.js";

// Seeded community row changed by the settings round-trip tests.
const COMMUNITY_ROW = { key: { community_id: TEST_COMMUNITY_IDS.community1 }, table: "community" };

test.describe("community dashboard settings view", () => {
  test("settings form exposes every community configuration area", async ({ adminCommunityPage }) => {
    // Load community settings before checking the complete form contract.
    await navigateToPath(adminCommunityPage, "/dashboard/community?tab=settings");

    // Find the dashboard and verify every settings section is present.
    const dashboardContent = adminCommunityPage.locator("#dashboard-content");
    for (const sectionName of [
      "General Settings",
      "Branding",
      "Social Links",
      "Advertisement",
      "Additional Content",
    ]) {
      await expect(dashboardContent.getByText(sectionName, { exact: true })).toBeVisible();
    }

    // Verify required controls and community-specific configuration fields.
    await expect(adminCommunityPage.getByLabel("Display Name")).toHaveAttribute("required", "");
    await expect(adminCommunityPage.locator("markdown-editor#description")).toHaveAttribute("required", "");
    await expect(
      adminCommunityPage.getByRole("checkbox", {
        name: "Restrict group team management to community admins and groups managers",
      }),
    ).toBeVisible();
    await expect(adminCommunityPage.locator('input[name="community_site_layout_id"]')).toHaveAttribute(
      "type",
      "hidden",
    );

    // Verify every community image field is available with its required size guidance.
    for (const { helpText, name } of [
      { helpText: "Images must be 360 x 360 px (square).", name: "logo_url" },
      { helpText: "Size required 2428 x 192 px.", name: "banner_url" },
      { helpText: "Size required 1220 x 192 px.", name: "banner_mobile_url" },
      { helpText: "Size required 1200 x 630 px. Format must be PNG, JPEG, or WebP.", name: "og_image_url" },
      { helpText: "Size required 2400 x 300 px.", name: "ad_banner_url" },
    ]) {
      const imageField = adminCommunityPage.locator(`image-field[name="${name}"]`);
      await expect(imageField).toBeVisible();
      await expect(imageField).toContainText(helpText);
    }
    await expect(adminCommunityPage.locator('image-field[name="logo_url"]')).not.toContainText(
      "Size required",
    );

    // Verify social and advertisement destinations use URL inputs.
    for (const socialLabel of [
      "Website",
      "Bluesky",
      "Facebook",
      "Flickr",
      "GitHub",
      "Instagram",
      "LinkedIn",
      "Slack",
      "X (formerly Twitter)",
      "WeChat",
      "YouTube",
      "Banner Link URL",
    ]) {
      await expect(adminCommunityPage.getByLabel(socialLabel)).toHaveAttribute("type", "url");
    }

    // Verify the remaining rich content and repeatable fields.
    await expect(adminCommunityPage.locator("markdown-editor#new_group_details")).toBeVisible();
    await expect(adminCommunityPage.locator('gallery-field[field-name="photos_urls"]')).toBeVisible();
    await expect(adminCommunityPage.locator('key-value-inputs[field-name="extra_links"]')).toBeVisible();
  });

  test("admin can crop an oversized advertisement banner to WEBP", async ({ adminCommunityPage }) => {
    // Load the advertisement banner field and capture the files sent to the image endpoint.
    await navigateToPath(adminCommunityPage, "/dashboard/community?tab=settings");
    const advertisementBannerField = adminCommunityPage.locator('image-field[name="ad_banner_url"]');
    const cropper = advertisementBannerField.locator("image-cropper");
    const fileInput = advertisementBannerField.locator('input[type="file"]');
    const preview = advertisementBannerField.getByRole("img", { name: "Image preview" });
    const valueInput = advertisementBannerField.locator('input[name="ad_banner_url"]');
    const readUploadMetadata = await trackImageUploadMetadata(adminCommunityPage);

    // Open the crop editor and verify its required size and controls.
    await fileInput.setInputFiles(TEST_UPLOAD_ASSET_PATHS.advertisementBanner);
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

    // Upload the mandatory crop.
    const uploadPromise = waitForImageUpload(adminCommunityPage);
    await cropper.getByRole("button", { name: "Apply crop" }).click();
    await uploadPromise;

    // Verify the generated file, its validated target, and the uploaded preview dimensions.
    await expect(dialog).toBeHidden();
    await expect(valueInput).toHaveValue(/\/images\//);
    await expect(preview).toHaveJSProperty("naturalWidth", 2400);
    await expect(preview).toHaveJSProperty("naturalHeight", 300);
    expect(await readUploadMetadata()).toEqual([
      { name: "community-secondary-ad-banner-cropped.webp", target: "ad_banner", type: "image/webp" },
    ]);
  });

  test("admin can crop a WEBP logo and upload a same-ratio SVG logo as-is", async ({
    adminCommunityPage,
  }) => {
    // Load the logo field and capture the files sent to the image endpoint.
    await navigateToPath(adminCommunityPage, "/dashboard/community?tab=settings");
    const logoField = adminCommunityPage.locator('image-field[name="logo_url"]');
    const cropper = logoField.locator("image-cropper");
    const fileInput = logoField.locator('input[type="file"]');
    const valueInput = logoField.locator('input[name="logo_url"]');
    const preview = logoField.getByRole("img", { name: "Image preview" });
    const readUploadMetadata = await trackImageUploadMetadata(adminCommunityPage);

    // Crop a real WEBP source whose aspect ratio does not match the square logo.
    const webpUploadPromise = waitForImageUpload(adminCommunityPage);
    await fileInput.setInputFiles(TEST_UPLOAD_ASSET_PATHS.webpLogoSource);
    await expect(cropper.getByRole("dialog", { name: "Crop Logo" })).toBeVisible();
    await expect(cropper.getByRole("button", { name: "Apply crop" })).toBeEnabled();
    await cropper.getByRole("button", { name: "Apply crop" }).click();
    await webpUploadPromise;

    // The cropped WEBP keeps its format and lands at the required size.
    await expect(valueInput).toHaveValue(/\/images\//);
    await expect(preview).toHaveJSProperty("naturalWidth", 360);
    await expect(preview).toHaveJSProperty("naturalHeight", 360);
    const webpValue = await valueInput.inputValue();

    // Upload a square SVG, which is scalable and skips the crop editor entirely.
    const svgUploadPromise = waitForImageUpload(adminCommunityPage);
    await fileInput.setInputFiles(TEST_UPLOAD_ASSET_PATHS.alternateLogo);
    await svgUploadPromise;
    await expect(cropper.getByRole("dialog")).toBeHidden();
    await expect(valueInput).not.toHaveValue(webpValue);
    await expect(valueInput).toHaveValue(/\/images\/.*\.svg$/);

    // Both uploads sent the expected file names and types.
    expect(await readUploadMetadata()).toEqual([
      { name: "community-secondary-logo-source-cropped.webp", target: "logo", type: "image/webp" },
      { name: "community-secondary-logo.svg", target: "logo", type: "image/svg+xml" },
    ]);
  });

  test("admin can upload a static GIF logo as-is or cropped to PNG", async ({ adminCommunityPage }) => {
    // Load the logo field and capture the files sent to the image endpoint.
    await navigateToPath(adminCommunityPage, "/dashboard/community?tab=settings");
    const logoField = adminCommunityPage.locator('image-field[name="logo_url"]');
    const cropper = logoField.locator("image-cropper");
    const fileInput = logoField.locator('input[type="file"]');
    const valueInput = logoField.locator('input[name="logo_url"]');
    const preview = logoField.getByRole("img", { name: "Image preview" });
    const readUploadMetadata = await trackImageUploadMetadata(adminCommunityPage);

    // A static GIF that already has the logo size is uploaded byte-for-byte.
    const staticExactUploadPromise = waitForImageUpload(adminCommunityPage);
    await fileInput.setInputFiles(TEST_UPLOAD_ASSET_PATHS.staticGifLogo);
    await staticExactUploadPromise;
    await expect(cropper.getByRole("dialog")).toBeHidden();
    await expect(valueInput).toHaveValue(/\/images\/.*\.gif$/);
    await expect(preview).toHaveJSProperty("naturalWidth", 360);
    await expect(preview).toHaveJSProperty("naturalHeight", 360);
    const staticExactValue = await valueInput.inputValue();

    // A static GIF with a different aspect ratio opens the editor and is saved as PNG.
    const staticUploadPromise = waitForImageUpload(adminCommunityPage);
    await fileInput.setInputFiles(TEST_UPLOAD_ASSET_PATHS.staticGifLogoSource);
    await expect(cropper.getByRole("dialog", { name: "Crop Logo" })).toBeVisible();
    await expect(cropper.getByRole("button", { name: "Apply crop" })).toBeEnabled();
    await cropper.getByRole("button", { name: "Apply crop" }).click();
    await staticUploadPromise;
    await expect(valueInput).not.toHaveValue(staticExactValue);
    await expect(valueInput).toHaveValue(/\/images\/.*\.png$/);
    await expect(preview).toHaveJSProperty("naturalWidth", 360);
    await expect(preview).toHaveJSProperty("naturalHeight", 360);

    // Both uploads sent the expected file names and types.
    expect(await readUploadMetadata()).toEqual([
      { name: "community-logo-static.gif", target: "logo", type: "image/gif" },
      { name: "community-logo-static-source-cropped.png", target: "logo", type: "image/png" },
    ]);
  });

  test("admin can update community settings", async ({ adminCommunityPage }) => {
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
      await expect(advertisementBannerField).toHaveAttribute("target", "ad_banner");
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
      await waitForActionResponse(
        adminCommunityPage,
        () => adminCommunityPage.getByRole("button", { name: "Update Settings" }).click(),
        { method: "PUT", pathname: "/dashboard/community/settings/update", status: 204 },
      );

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
      displayName: uniqueName("Platform Engineering Community"),
      logoUrl: "/static/images/e2e/community-secondary-logo.svg",
    };

    // Save the updated settings, restoring the seeded community row afterwards.
    await withRowRestore(COMMUNITY_ROW, () => submitSettings(updatedValues));
  });

  test("admin can update and restore extended community settings", async ({ adminCommunityPage }) => {
    // Restore the seeded community row even when the UI restore below fails.
    await withRowRestore(COMMUNITY_ROW, async () => {
      // Define the settings URL and the extended settings locators.
      const settingsPath = "/dashboard/community?tab=settings";
      const ogImageInput = adminCommunityPage.locator(
        'image-field[name="og_image_url"] input[name="og_image_url"]',
      );
      const adBannerInput = adminCommunityPage.locator(
        'image-field[name="ad_banner_url"] input[name="ad_banner_url"]',
      );
      const bannerLinkInput = adminCommunityPage.getByLabel("Banner Link URL");
      const newGroupDetailsEditor = adminCommunityPage.locator("markdown-editor#new_group_details");
      const restrictionToggle = adminCommunityPage.locator("#toggle_group_team_management_restricted");
      const restrictionHiddenInput = adminCommunityPage.locator("#group_team_management_restricted");
      const extraLinksField = adminCommunityPage.locator('key-value-inputs[field-name="extra_links"]');
      const extraLinkHiddenInput = adminCommunityPage.locator('input[name="extra_links[E2E Extra Docs]"]');

      // Submit the settings form and wait for the update to complete.
      const saveSettings = async () => {
        await waitForActionResponse(
          adminCommunityPage,
          () => adminCommunityPage.getByRole("button", { name: "Update Settings" }).click(),
          { method: "PUT", pathname: "/dashboard/community/settings/update", status: 204 },
        );
      };

      // Read the current extended settings values before updating them.
      await navigateToPath(adminCommunityPage, settingsPath);
      const originalValues = {
        adBannerLinkUrl: await bannerLinkInput.inputValue(),
        adBannerUrl: await adBannerInput.inputValue(),
        newGroupDetails: (await newGroupDetailsEditor.getAttribute("content")) ?? "",
        ogImageUrl: await ogImageInput.inputValue(),
        restricted: await restrictionToggle.isChecked(),
      };

      // Update the extended settings fields, including a new extra link.
      await setImageFieldValue(adminCommunityPage, "og_image_url", "/static/images/e2e/event-banner.svg");
      await setImageFieldValue(adminCommunityPage, "ad_banner_url", "/static/images/e2e/event-banner.svg");
      await bannerLinkInput.fill("https://example.com/e2e-extended-banner");
      await fillMarkdownEditor(
        adminCommunityPage,
        "new_group_details",
        "Extended details shown to organizers creating new groups.",
      );
      await restrictionToggle.setChecked(!originalValues.restricted, {
        force: true,
      });
      await expect(restrictionHiddenInput).toHaveValue(String(!originalValues.restricted));
      await extraLinksField.getByPlaceholder("Link Name").last().fill("E2E Extra Docs");
      await extraLinksField.getByPlaceholder("URL").last().fill("https://example.com/e2e-extra-docs");
      await expect(extraLinkHiddenInput).toHaveValue("https://example.com/e2e-extra-docs");
      await saveSettings();

      // Reload the settings tab and verify the extended values persisted.
      await navigateToPath(adminCommunityPage, settingsPath);
      await expect(ogImageInput).toHaveValue("/static/images/e2e/event-banner.svg");
      await expect(adBannerInput).toHaveValue("/static/images/e2e/event-banner.svg");
      await expect(bannerLinkInput).toHaveValue("https://example.com/e2e-extended-banner");
      await expect(newGroupDetailsEditor).toHaveAttribute(
        "content",
        "Extended details shown to organizers creating new groups.",
      );
      await expect(restrictionToggle).toBeChecked({
        checked: !originalValues.restricted,
      });
      await expect(extraLinkHiddenInput).toHaveValue("https://example.com/e2e-extra-docs");

      // Restore the original extended settings values.
      await setImageFieldValue(adminCommunityPage, "og_image_url", originalValues.ogImageUrl);
      await setImageFieldValue(adminCommunityPage, "ad_banner_url", originalValues.adBannerUrl);
      await bannerLinkInput.fill(originalValues.adBannerLinkUrl);
      await fillMarkdownEditor(adminCommunityPage, "new_group_details", originalValues.newGroupDetails);
      await restrictionToggle.setChecked(originalValues.restricted, {
        force: true,
      });
      await extraLinksField.locator('button[title="Remove item"]').first().click();
      await expect(extraLinkHiddenInput).toHaveCount(0);
      await saveSettings();

      // Reload once more and verify the original values are back.
      await navigateToPath(adminCommunityPage, settingsPath);
      await expect(ogImageInput).toHaveValue(originalValues.ogImageUrl);
      await expect(bannerLinkInput).toHaveValue(originalValues.adBannerLinkUrl);
      await expect(restrictionToggle).toBeChecked({
        checked: originalValues.restricted,
      });
      await expect(extraLinkHiddenInput).toHaveCount(0);
    });
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

/**
 * Wraps the page's fetch to record the file name, target and type of every image upload.
 * @param {import("@playwright/test").Page} page - Page with an image field.
 * @returns {Promise<() => Promise<{ name: string, target: string, type: string }[]>>} Reader
 *   for the recorded uploads, in request order.
 */
const trackImageUploadMetadata = async (page) => {
  await page.evaluate(() => {
    const nativeFetch = window.fetch;
    window.imageUploadMetadata = [];
    window.fetch = (input, init) => {
      if (input === "/images" && init?.body instanceof FormData) {
        const uploadFile = init.body.get("file");
        if (uploadFile instanceof File) {
          window.imageUploadMetadata.push({
            name: uploadFile.name,
            target: init.body.get("target"),
            type: uploadFile.type,
          });
        }
      }

      return nativeFetch(input, init);
    };
  });

  return () => page.evaluate(() => window.imageUploadMetadata);
};
