import { expect, test } from "../../fixtures.js";

import { TEST_COMMUNITY_NAME, TEST_GROUP_SLUGS, TEST_SITE_TITLE } from "../../seed.js";
import { expectDialogClosed, navigateToGroup, navigateToPath } from "../../utils.js";

/**
 * Presses Tab a number of times and verifies focus never leaves the dialog.
 * @param {import("@playwright/test").Page} page - Page under test.
 * @param {import("@playwright/test").Locator} dialog - Open dialog.
 * @param {number} presses - Number of Tab presses.
 * @returns {Promise<void>} Resolves after the last press.
 */
const expectTabStaysInside = async (page, dialog, presses) => {
  for (let press = 0; press < presses; press += 1) {
    await page.keyboard.press("Tab");
    expect(await dialog.evaluate((element) => element.contains(document.activeElement))).toBe(true);
  }
};

test.describe("sheet focus", () => {
  test("profile sheet takes focus, traps Tab and returns focus to the card @mobile", async ({ page }) => {
    // Open the profile from an organizer card.
    await navigateToGroup(page, TEST_COMMUNITY_NAME, TEST_GROUP_SLUGS.community1.alpha);
    const organizerCard = page.getByRole("button", { name: /^View profile:\s*E2E Organizer One\b/ });
    await organizerCard.scrollIntoViewIfNeeded();
    const scrollY = await page.evaluate(() => Math.round(window.scrollY));
    await organizerCard.click();
    const profileDialog = page.getByRole("dialog", { name: /^User/ });
    const closeButton = profileDialog.getByRole("button", { name: "Close modal" });

    // Verify focus enters the sheet and stays there.
    await expect(closeButton).toBeFocused();
    await expectTabStaysInside(page, profileDialog, 5);

    // Close the sheet and verify focus goes back to the card without a scroll jump.
    await closeButton.click();
    await expectDialogClosed(page, profileDialog, { opener: organizerCard, scrollY });
  });

  test("a tap on the backdrop returns focus to the opener @mobile", async ({ page }) => {
    // Open the profile from an organizer card.
    await navigateToGroup(page, TEST_COMMUNITY_NAME, TEST_GROUP_SLUGS.community1.alpha);
    const organizerCard = page.getByRole("button", { name: /^View profile:\s*E2E Organizer One\b/ });
    await organizerCard.click();
    const profileDialog = page.getByRole("dialog", { name: /^User/ });
    await expect(profileDialog.getByRole("button", { name: "Close modal" })).toBeFocused();

    // Tap the dimmed area above the sheet and verify focus outlives the mouse press.
    await page.mouse.click(20, 20);
    await expectDialogClosed(page, profileDialog, { opener: organizerCard });
  });

  test("share sheet takes focus, traps Tab and returns focus to its trigger @mobile", async ({ page }) => {
    // Load the group without the system share, so the pill opens the sheet.
    await page.addInitScript(() => {
      delete Navigator.prototype.canShare;
      delete Navigator.prototype.share;
    });
    await navigateToGroup(page, TEST_COMMUNITY_NAME, TEST_GROUP_SLUGS.community1.alpha);
    const sharePill = page
      .locator('share-modal[trigger-variant="pill"]')
      .getByRole("button", { name: "Share" });

    // Open the sheet.
    await sharePill.click();
    const shareDialog = page.getByRole("dialog", { name: "Share" });

    // Verify focus enters the sheet and stays there.
    await expect(shareDialog.getByRole("button", { name: "Close modal" })).toBeFocused();
    await expectTabStaysInside(page, shareDialog, 12);

    // Close the sheet and verify focus goes back to the pill.
    await page.keyboard.press("Escape");
    await expectDialogClosed(page, shareDialog, { opener: sharePill });
  });

  test("account sheet makes the site title inert, but not its own Home row @mobile", async ({ page }) => {
    // Load a page that shows the title in place of a logo.
    await navigateToPath(page, "/stats");
    const header = page.locator("#header");
    const titleLink = header.locator(`a[aria-label="Go to ${TEST_SITE_TITLE} homepage"]`);
    const userButton = header.locator("#user-dropdown-button");

    // Open the sheet.
    await userButton.click();
    const userMenu = page.locator("#user-dropdown");
    await expect(userMenu).toBeVisible();

    // Verify the title goes behind the scrim while the sheet's own Home row stays.
    await expect(titleLink).toHaveJSProperty("inert", true);
    await expect(userMenu.getByRole("menuitem", { name: "Home" })).toHaveJSProperty("inert", false);

    // Close the sheet and verify the title comes back.
    await userMenu.getByRole("menuitem", { name: "Close menu" }).click();
    await expect(titleLink).toHaveJSProperty("inert", false);
  });

  test("open sheets leave pinch zoom on and keep the title row for dragging @mobile", async ({ page }) => {
    // Open the account sheet.
    await navigateToPath(page, "/stats");
    await page.locator("#user-dropdown-button").click();
    const userMenu = page.locator("#user-dropdown");

    // Verify the scrim and list leave zooming to the browser, and the title row does not.
    await expect(userMenu).toHaveCSS("touch-action", "pinch-zoom");
    await expect(userMenu.locator(".sheet-body")).toHaveCSS("touch-action", "pan-y pinch-zoom");
    await expect(userMenu.locator(".sheet-head")).toHaveCSS("touch-action", "none");
  });
});
