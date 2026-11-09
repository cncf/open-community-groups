import { expect, test } from "../../fixtures.js";

import { TEST_COMMUNITY_NAME, TEST_EVENT_NAME, TEST_EVENT_SLUG, TEST_GROUP_SLUG } from "../../seed.js";
import { expectDialogClosed, expectFocusIndicator, navigateToEvent } from "../../utils.js";

/**
 * Opens the event gallery's lightbox from its first tile.
 * @param {import("@playwright/test").Page} page - Page under test.
 * @returns {Promise<object>} Lightbox nodes.
 */
const openLightbox = async (page) => {
  await navigateToEvent(page, TEST_COMMUNITY_NAME, TEST_GROUP_SLUG, TEST_EVENT_SLUG);
  const gallery = page.locator("images-gallery");
  const tile = gallery.getByRole("button", { name: `Open Event ${TEST_EVENT_NAME} image 1` });
  await tile.tap();

  const dialog = page.getByRole("dialog", { name: "Gallery" });
  await expect(dialog).toBeVisible();
  return { closeButton: dialog.getByRole("button", { name: "Close" }), dialog, gallery, tile };
};

test.describe("lightbox accessibility", () => {
  test("opens as a dialog with focus on Close and closes back to the tile @mobile", async ({ page }) => {
    const { closeButton, dialog, gallery, tile } = await openLightbox(page);

    // Verify the dialog semantics and the focus entry.
    await expect(dialog).toHaveAttribute("aria-modal", "true");
    await expect(closeButton).toBeFocused();

    // Close and verify the attributes go and focus returns.
    await closeButton.tap();
    await expectDialogClosed(page, dialog, { opener: tile });
    // opacity-0 is the lightbox script's closed-state contract; Playwright counts it as visible.
    await expect(gallery.locator(".modal")).toHaveClass(/opacity-0/);
    await expect(gallery.locator(".modal")).not.toHaveAttribute("aria-modal", /.*/);
  });

  test("keeps Tab inside the lightbox and shows where focus is @mobile", async ({ page }) => {
    const { closeButton, dialog } = await openLightbox(page);
    const previousButton = dialog.getByRole("button", { name: "Previous" });
    const nextButton = dialog.getByRole("button", { name: "Next" });

    // Verify Tab walks the three controls and wraps, each with a visible ring.
    for (const control of [previousButton, nextButton, closeButton]) {
      await expectFocusIndicator(control, () => page.keyboard.press("Tab"));
    }

    // Verify Shift+Tab wraps the other way.
    await page.keyboard.press("Shift+Tab");
    await expect(nextButton).toBeFocused();
  });

  test("returns focus to the tile on Escape @mobile", async ({ page }) => {
    const { dialog, tile } = await openLightbox(page);

    await page.keyboard.press("Escape");

    await expectDialogClosed(page, dialog, { opener: tile });
  });

  test("a tap on the backdrop returns focus to the tile @mobile", async ({ page }) => {
    const { dialog, tile } = await openLightbox(page);

    // Tap the dimmed corner and verify focus outlives the mouse press.
    await page.mouse.click(20, 20);
    await expectDialogClosed(page, dialog, { opener: tile });
  });

  test("keeps the closed controls out of the Tab order and the accessibility tree @mobile", async ({
    page,
  }) => {
    await navigateToEvent(page, TEST_COMMUNITY_NAME, TEST_GROUP_SLUG, TEST_EVENT_SLUG);
    const gallery = page.locator("images-gallery");
    const lightbox = gallery.locator(".modal");

    // Verify the closed lightbox holds no button for assistive tech.
    await expect(lightbox).toHaveCSS("visibility", "hidden");
    await expect(lightbox.getByRole("button")).toHaveCount(0);

    // Verify Tab from the last tile skips its controls.
    await gallery
      .getByRole("button", { name: /^Open / })
      .last()
      .focus();
    await page.keyboard.press("Tab");
    await expect(lightbox.locator(":focus")).toHaveCount(0);
  });

  test("drops the dialog on rotation and still closes back to the tile @mobile", async ({ page }) => {
    const { dialog, gallery, tile } = await openLightbox(page);
    const lightbox = gallery.locator(".modal");

    // Rotate past the phone width.
    await page.setViewportSize({ height: 390, width: 844 });

    // Verify the lightbox stays open as the plain one.
    await expect(dialog).toHaveCount(0);
    // opacity-0 is the lightbox script's closed-state contract; Playwright counts it as visible.
    await expect(lightbox).not.toHaveClass(/opacity-0/);
    await expect(lightbox).not.toHaveAttribute("aria-modal", /.*/);

    // Close and verify focus returns all the same.
    await lightbox.getByRole("button", { name: "Close" }).click();
    // opacity-0 is the lightbox script's closed-state contract; Playwright counts it as visible.
    await expect(lightbox).toHaveClass(/opacity-0/);
    await expectDialogClosed(page, dialog, { opener: tile });
  });

  test("binds the dialog again when rotated back @mobile", async ({ page }) => {
    const { closeButton, dialog, gallery, tile } = await openLightbox(page);
    const nextButton = dialog.getByRole("button", { name: "Next" });

    // Rotate past the phone width and back, with the lightbox still open.
    await page.setViewportSize({ height: 390, width: 844 });
    await expect(dialog).toHaveCount(0);
    await page.setViewportSize({ height: 844, width: 390 });

    // Verify the semantics and the focus trap are back.
    await expect(dialog).toHaveAttribute("aria-modal", "true");
    await nextButton.focus();
    await page.keyboard.press("Tab");
    await expect(closeButton).toBeFocused();

    // Close and verify nothing stays, and focus returns.
    await closeButton.tap();
    await expectDialogClosed(page, dialog, { opener: tile });
    await expect(gallery.locator(".modal")).not.toHaveAttribute("role", /.*/);
  });
});
