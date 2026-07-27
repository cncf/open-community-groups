import { expect, test } from "../../../fixtures.js";

import { navigateToPath } from "../../../utils.js";

const ARTWORK_PATH = "/dashboard/group?tab=artwork";

test.describe("group badge artwork", () => {
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
    await Promise.all([
      organizerGroupPage.waitForResponse(
        (response) =>
          response.request().method() === "DELETE" &&
          response.url().includes("/dashboard/group/badges/artwork/") &&
          response.status() === 204,
      ),
      organizerGroupPage.getByRole("button", { name: "Remove", exact: true }).click(),
    ]);

    // Verify the HTMX refresh removed the item and updated the gallery count.
    await expect(artworkItem).toHaveCount(0);
    await expect(organizerGroupPage.getByText("3 items", { exact: true })).toBeVisible();
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
