import { Buffer } from "node:buffer";
import { readFileSync } from "node:fs";
import { expect, test } from "../../../fixtures.js";
import { queryE2eDatabase, queryE2eDatabaseRows } from "../../../database.js";
import { TEST_GROUP_IDS } from "../../../seed.js";
import { navigateToPath, waitForActionResponse } from "../../../utils.js";
import { TEST_UPLOAD_ASSET_PATHS, uploadImageField } from "../../form-helpers.js";

const ARTWORK_PATH = "/dashboard/group?tab=artwork";

const REMOVABLE_ARTWORK_FILE_NAME = "e2e-removable-badge.png";

test.describe("group badge artwork", () => {
  test("empty state guides the first artwork upload", async ({ organizerEmptyGroupPage }) => {
    // Load artwork for the dedicated group without saved images.
    await navigateToPath(organizerEmptyGroupPage, ARTWORK_PATH);
    const dashboardContent = organizerEmptyGroupPage.locator("#dashboard-content");

    // Verify the count, upload guidance, and disabled save action.
    await expect(dashboardContent.getByText("0 items", { exact: true })).toBeVisible();
    await expect(dashboardContent).toContainText("No artwork yet");
    await expect(dashboardContent).toContainText("Upload an image above and save it to start your library.");
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

    // Open the removal confirmation for referenced artwork.
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
    const originalArtwork = readBadgeArtwork(TEST_GROUP_IDS.community1.alpha, REMOVABLE_ARTWORK_FILE_NAME);

    try {
      // Open the gallery and select the dedicated unreferenced fixture.
      await navigateToPath(organizerGroupPage, ARTWORK_PATH);
      const artworkItem = organizerGroupPage.locator(`li:has(img[src$="${REMOVABLE_ARTWORK_FILE_NAME}"])`);

      // Remove the unreferenced fixture artwork.
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
    } finally {
      // Restore the removed artwork fixture for later tests.
      restoreBadgeArtwork(originalArtwork);
    }
  });

  test("organizer can upload artwork and save it to the library", async ({ organizerEmptyGroupPage }) => {
    let createdArtworkId;

    try {
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
      const saveButton = organizerEmptyGroupPage.getByRole("button", {
        name: "Save to library",
      });
      await expect(saveButton).toBeEnabled();
      await waitForActionResponse(organizerEmptyGroupPage, () => saveButton.click(), {
        method: "POST",
        urlIncludes: "/dashboard/group/badges/artwork",
      });

      // Dismiss the success feedback before checking the refreshed gallery.
      const successAlert = organizerEmptyGroupPage.locator(".swal2-popup");
      await expect(successAlert).toContainText("Artwork added to the gallery.");
      await successAlert.getByRole("button", { name: "OK" }).click();

      // Record the saved artwork ID for cleanup.
      createdArtworkId = readBadgeArtwork(TEST_GROUP_IDS.community1.empty, artworkFileName).badgeArtworkId;

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
    } finally {
      // Delete the saved artwork record if UI cleanup did not finish.
      if (createdArtworkId) {
        deleteBadgeArtwork(createdArtworkId);
      }
    }
  });

  test("artwork uploads explain invalid formats and unreadable files", async ({ organizerGroupPage }) => {
    // Load the artwork field before exercising the server and editor errors.
    await navigateToPath(organizerGroupPage, ARTWORK_PATH);
    const artworkField = organizerGroupPage.locator('image-field[name="badge_artwork_url"]');
    const cropper = artworkField.locator("image-cropper");
    const fileInput = artworkField.locator('input[type="file"]');
    const valueInput = artworkField.locator('input[name="badge_artwork_url"]');
    const uploadRequests = [];
    organizerGroupPage.on("request", (request) => {
      if (request.method() === "POST" && new URL(request.url()).pathname === "/images") {
        uploadRequests.push(request);
      }
    });

    // Upload PNG bytes with a mismatched JPEG extension; the exact 512 × 512
    // size skips the crop editor so the server detects the mismatch.
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
      artworkField.getByRole("button", {
        name: "Retry upload for Upload artwork",
      }),
    ).toBeVisible();
    await formatAlert.locator(".swal2-confirm").click();
    await expect(formatAlert).toBeHidden();
    expect(uploadRequests).toHaveLength(1);

    // Upload a nominal PNG whose bytes cannot be decoded; the cropper rejects
    // it before the editor opens and nothing reaches the server.
    await fileInput.setInputFiles({
      buffer: Buffer.alloc(1024 * 1024 + 1),
      mimeType: "image/png",
      name: "e2e-unreadable-artwork.png",
    });
    const unreadableAlert = organizerGroupPage.locator(".swal2-popup");
    await expect(unreadableAlert).toContainText("This image couldn't be opened.");
    await expect(unreadableAlert).toContainText("Choose a different image in a supported format.");
    await unreadableAlert.locator(".swal2-confirm").click();
    await expect(unreadableAlert).toBeHidden();

    // Verify the editor stayed closed and nothing was uploaded or enabled.
    await expect(cropper.getByRole("dialog")).toBeHidden();
    await expect(fileInput).toHaveValue("");
    await expect(valueInput).toHaveValue("");
    await expect(organizerGroupPage.getByRole("button", { name: "Save to library" })).toBeDisabled();
    expect(uploadRequests).toHaveLength(1);
  });

  test("artwork uploads crop non-square sources to the badge size", async ({ organizerEmptyGroupPage }) => {
    // Load the artwork field and capture the file sent to the image endpoint.
    await navigateToPath(organizerEmptyGroupPage, ARTWORK_PATH);
    const artworkField = organizerEmptyGroupPage.locator('image-field[name="badge_artwork_url"]');
    const cropper = artworkField.locator("image-cropper");
    const fileInput = artworkField.locator('input[type="file"]');
    const valueInput = artworkField.locator('input[name="badge_artwork_url"]');
    const preview = artworkField.getByRole("img", { name: "Image preview" });
    await organizerEmptyGroupPage.evaluate(() => {
      const nativeFetch = window.fetch;
      window.imageUploadMetadata = [];
      window.fetch = (input, init) => {
        if (input === "/images" && init?.body instanceof FormData) {
          const uploadFile = init.body.get("file");
          if (uploadFile instanceof File) {
            window.imageUploadMetadata.push({ name: uploadFile.name, type: uploadFile.type });
          }
        }

        return nativeFetch(input, init);
      };
    });

    // A 1024 × 512 WEBP source does not match the square badge, so the editor opens.
    const uploadPromise = organizerEmptyGroupPage.waitForResponse(
      (response) =>
        response.request().method() === "POST" &&
        new URL(response.url()).pathname === "/images" &&
        response.status() === 201,
    );
    await fileInput.setInputFiles(TEST_UPLOAD_ASSET_PATHS.badgeArtworkSource);
    const dialog = cropper.getByRole("dialog", { name: "Crop Upload artwork" });
    await expect(dialog).toBeVisible();
    await expect(dialog.getByRole("button", { name: "Apply crop" })).toBeEnabled();
    await dialog.getByRole("button", { name: "Apply crop" }).click();
    await uploadPromise;

    // The cropped artwork lands at the exact badge size and enables saving.
    await expect(dialog).toBeHidden();
    await expect(valueInput).toHaveValue(/\/images\//);
    await expect(preview).toHaveJSProperty("naturalWidth", 512);
    await expect(preview).toHaveJSProperty("naturalHeight", 512);
    await expect(organizerEmptyGroupPage.getByRole("button", { name: "Save to library" })).toBeEnabled();
    const uploadMetadata = await organizerEmptyGroupPage.evaluate(() => window.imageUploadMetadata);
    expect(uploadMetadata).toEqual([{ name: "artwork-source-cropped.webp", type: "image/webp" }]);
  });

  test("artwork uploads reject SVG and GIF sources before uploading", async ({ organizerGroupPage }) => {
    // Load the artwork field and track upload requests.
    await navigateToPath(organizerGroupPage, ARTWORK_PATH);
    const artworkField = organizerGroupPage.locator('image-field[name="badge_artwork_url"]');
    const fileInput = artworkField.locator('input[type="file"]');
    const valueInput = artworkField.locator('input[name="badge_artwork_url"]');
    const uploadRequests = [];
    organizerGroupPage.on("request", (request) => {
      if (request.method() === "POST" && new URL(request.url()).pathname === "/images") {
        uploadRequests.push(request);
      }
    });

    // Badges are served as public raster images, so SVG and GIF sources are refused client-side.
    const alert = organizerGroupPage.locator(".swal2-popup");
    for (const [assetPath, formatLabel] of [
      [TEST_UPLOAD_ASSET_PATHS.logo, "SVG"],
      [TEST_UPLOAD_ASSET_PATHS.animatedGifLogo, "GIF"],
    ]) {
      await fileInput.setInputFiles(assetPath);
      await expect(alert).toContainText(`${formatLabel} images are not supported for this field.`);
      await expect(alert).toContainText("Choose a PNG, JPEG or WEBP image.");
      await alert.locator(".swal2-confirm").click();
      await expect(alert).toBeHidden();
      await expect(fileInput).toHaveValue("");
    }

    // Verify nothing was selected, opened, or uploaded.
    await expect(artworkField.locator("image-cropper").getByRole("dialog")).toBeHidden();
    await expect(valueInput).toHaveValue("");
    await expect(organizerGroupPage.getByRole("button", { name: "Save to library" })).toBeDisabled();
    expect(uploadRequests).toHaveLength(0);
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

/** Deletes badge artwork from the badge_artwork table by ID. */
const deleteBadgeArtwork = (badgeArtworkId) => {
  queryE2eDatabase(`
    delete from badge_artwork
    where badge_artwork_id = '${badgeArtworkId}'::uuid;
  `);
};

/** Returns a badge_artwork row for restoring the uploaded file fixture. */
const readBadgeArtwork = (groupId, fileName) => {
  const [row] = queryE2eDatabaseRows(`
    select badge_artwork_id, created_at, file_name, group_id
    from badge_artwork
    where group_id = '${groupId}'::uuid
    and file_name = '${fileName.replaceAll("'", "''")}'
  `);

  if (!row) {
    throw new Error(`Expected badge artwork ${fileName} in group ${groupId}`);
  }

  const [badgeArtworkId, createdAt, restoredFileName, restoredGroupId] = row;

  return {
    badgeArtworkId,
    createdAt,
    fileName: restoredFileName,
    groupId: restoredGroupId,
  };
};

/** Restores a badge_artwork row for the uploaded file fixture. */
const restoreBadgeArtwork = ({ badgeArtworkId, createdAt, fileName, groupId }) => {
  queryE2eDatabase(`
    insert into badge_artwork (
      badge_artwork_id,
      created_at,
      file_name,
      group_id
    ) values (
      '${badgeArtworkId}'::uuid,
      '${createdAt}'::timestamptz,
      '${fileName.replaceAll("'", "''")}',
      '${groupId}'::uuid
    )
    on conflict do nothing;
  `);
};
