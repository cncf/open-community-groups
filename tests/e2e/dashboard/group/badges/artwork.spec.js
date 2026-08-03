import { Buffer } from "node:buffer";
import { readFileSync } from "node:fs";

import { expect, test } from "../../../fixtures.js";

import { navigateToPath, waitForActionResponse } from "../../../utils.js";
import { TEST_UPLOAD_ASSET_PATHS, uploadImageField } from "../../form-helpers.js";

const ARTWORK_PATH = "/dashboard/group?tab=artwork";

test.describe("group badge artwork", () => {
  test("empty state guides the first artwork upload", async ({
    organizerEmptyGroupPage,
  }) => {
    // Load artwork for the dedicated group without saved images.
    await navigateToPath(organizerEmptyGroupPage, ARTWORK_PATH);
    const dashboardContent = organizerEmptyGroupPage.locator(
      "#dashboard-content",
    );

    // Verify the count, upload guidance, and disabled save action.
    await expect(
      dashboardContent.getByText("0 items", { exact: true }),
    ).toBeVisible();
    await expect(dashboardContent).toContainText("No artwork yet");
    await expect(dashboardContent).toContainText(
      "Upload an image above and save it to start your library.",
    );
    await expect(
      dashboardContent.getByRole("button", {
        name: "Save to library",
      }),
    ).toBeDisabled();
  });

  test("organizer cannot remove artwork referenced by a definition", async ({ organizerGroupPage }) => {
    // Open the gallery and target the artwork used by the Host definition.
    await navigateToPath(organizerGroupPage, ARTWORK_PATH);
    const artworkItem = organizerGroupPage.locator('li:has(img[src*="7744970f"])').first();

    await expect(artworkItem).toBeVisible();
    await artworkItem.getByRole("button", { name: /Remove artwork/u }).click();

    // Confirm the server protects referenced artwork.
    await Promise.all([
      organizerGroupPage.waitForResponse(
        (response) =>
          response.request().method() === "DELETE" &&
          response.url().includes("/dashboard/group/badges/artwork/") &&
          !response.ok(),
      ),
      organizerGroupPage.getByRole("button", { name: "Remove", exact: true }).click(),
    ]);
    await expect(organizerGroupPage.locator(".swal2-popup")).toContainText(
      "The artwork could not be removed.",
    );
    await expect(artworkItem).toBeVisible();
  });

  test("organizer can remove unreferenced artwork", async ({ organizerGroupPage }) => {
    // Open the gallery and select the dedicated unreferenced fixture.
    await navigateToPath(organizerGroupPage, ARTWORK_PATH);
    const artworkItem = organizerGroupPage.locator('li:has(img[src$="e2e-removable-badge.png"])');

    await expect(artworkItem).toBeVisible();
    await artworkItem.getByRole("button", { name: /Remove artwork/u }).click();
    await waitForActionResponse(
      organizerGroupPage,
      () => organizerGroupPage.getByRole("button", { name: "Remove", exact: true }).click(),
      {
        method: "DELETE",
        urlIncludes: "/dashboard/group/badges/artwork/",
        status: 204,
      },
    );

    // Verify the HTMX refresh removed the item and updated the gallery count.
    await expect(artworkItem).toHaveCount(0);
    await expect(organizerGroupPage.getByText("3 items", { exact: true })).toBeVisible();
  });

  test("organizer can upload artwork and save it to the library", async ({ organizerEmptyGroupPage }) => {
    // Use the empty group gallery because the uploaded asset is content
    // addressed and already seeded in the primary group library.
    await navigateToPath(organizerEmptyGroupPage, ARTWORK_PATH);
    const dashboardContent = organizerEmptyGroupPage.locator("#dashboard-content");
    const galleryItems = dashboardContent.locator("li:has(img[src^='/images/badges/'])");
    await expect(galleryItems).toHaveCount(0);

    // Upload a new artwork image through the upload field.
    await uploadImageField(
      organizerEmptyGroupPage,
      "badge_artwork_url",
      TEST_UPLOAD_ASSET_PATHS.badgeArtwork,
    );
    const artworkUrl = await organizerEmptyGroupPage
      .locator('image-field[name="badge_artwork_url"] input[name="badge_artwork_url"]')
      .inputValue();
    const artworkFileName = artworkUrl.split("/").filter(Boolean).pop();

    // Save the uploaded image to the artwork library.
    const saveButton = organizerEmptyGroupPage.getByRole("button", { name: "Save to library" });
    await expect(saveButton).toBeEnabled();
    await waitForActionResponse(organizerEmptyGroupPage, () => saveButton.click(), {
      method: "POST",
      urlIncludes: "/dashboard/group/badges/artwork",
    });

    // Dismiss the success feedback before checking the refreshed gallery.
    const successAlert = organizerEmptyGroupPage.locator(".swal2-popup");
    await expect(successAlert).toContainText("Artwork added to the gallery.");
    await successAlert.getByRole("button", { name: "OK" }).click();

    // Verify the new artwork joined the gallery.
    const newArtworkItem = dashboardContent.locator(`li:has(img[src$="${artworkFileName}"])`);
    await expect(newArtworkItem).toBeVisible();
    await expect(galleryItems).toHaveCount(1);

    // Remove the temporary artwork to restore the empty gallery.
    await newArtworkItem.getByRole("button", { name: /Remove artwork/u }).click();
    await waitForActionResponse(
      organizerEmptyGroupPage,
      () => organizerEmptyGroupPage.getByRole("button", { name: "Remove", exact: true }).click(),
      {
        method: "DELETE",
        urlIncludes: "/dashboard/group/badges/artwork/",
        status: 204,
      },
    );
    await expect(newArtworkItem).toHaveCount(0);
    await expect(galleryItems).toHaveCount(0);
  });

  test("artwork uploads explain invalid formats and oversized files", async ({ organizerGroupPage }) => {
    // Load the direct-upload artwork field before exercising server errors.
    await navigateToPath(organizerGroupPage, ARTWORK_PATH);
    const artworkField = organizerGroupPage.locator('image-field[name="badge_artwork_url"]');
    const fileInput = artworkField.locator('input[type="file"]');
    const valueInput = artworkField.locator('input[name="badge_artwork_url"]');

    // Upload PNG bytes with a mismatched JPEG extension.
    await waitForActionResponse(
      organizerGroupPage,
      () =>
        fileInput.setInputFiles({
          buffer: readFileSync(TEST_UPLOAD_ASSET_PATHS.badgeArtwork),
          mimeType: "image/jpeg",
          name: "e2e-mismatched-artwork.jpg",
        }),
      { method: "POST", urlEndsWith: "/images", status: 422 },
    );

    // Verify the server error and badge format guidance are available for recovery.
    const formatAlert = organizerGroupPage.locator(".swal2-popup");
    await expect(formatAlert).toContainText("file extension does not match detected image format");
    await expect(formatAlert).toContainText("Supported formats: PNG, JPEG and WEBP.");
    await expect(valueInput).toHaveValue("");
    await expect(
      artworkField.getByRole("button", { name: "Retry upload for Upload artwork" }),
    ).toBeVisible();
    await formatAlert.locator(".swal2-confirm").click();
    await expect(formatAlert).toBeHidden();

    // Upload a nominal PNG that exceeds the one-megabyte server limit.
    await waitForActionResponse(
      organizerGroupPage,
      () =>
        fileInput.setInputFiles({
          buffer: Buffer.alloc(1024 * 1024 + 1),
          mimeType: "image/png",
          name: "e2e-oversized-artwork.png",
        }),
      { method: "POST", urlEndsWith: "/images", status: 413 },
    );

    // Verify size guidance appears without enabling the save action.
    const sizeAlert = organizerGroupPage.locator(".swal2-popup");
    await expect(sizeAlert).toContainText("image exceeds 1MB limit");
    await expect(sizeAlert).toContainText("Maximum size: 1MB.");
    await expect(valueInput).toHaveValue("");
    await expect(organizerGroupPage.getByRole("button", { name: "Save to library" })).toBeDisabled();
  });

  test("artwork form requires an uploaded image", async ({ organizerGroupPage }) => {
    // Open the gallery without selecting a file.
    await navigateToPath(organizerGroupPage, ARTWORK_PATH);
    const saveButton = organizerGroupPage.getByRole("button", {
      name: "Save to library",
    });

    // Verify the unavailable action explains how to enable it.
    await expect(saveButton).toBeDisabled();
    await expect(saveButton).toHaveAttribute("title", "Upload an image first.");
    await expect(organizerGroupPage.getByRole("heading", { name: "Badges Artwork" })).toBeVisible();
  });
});
