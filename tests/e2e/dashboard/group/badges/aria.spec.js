import { expect, test } from "../../../fixtures.js";

import { cleanupBadgeDefinition, setupBadgeDefinition } from "../../../data-graphs/badges.js";
import { BADGE_ARTWORK_FILE_NAME } from "../../../data-graphs/groups.js";
import { enableDesktopVersion, expectAriaSnapshot, expectPageLayout } from "../../../snapshots.js";
import { openActionsMenu, openGroupDashboardView, setupAriaGroup } from "../aria-helpers.js";

// Name of the owned badge of the temporary group.
const OWNED_BADGE_NAME = "E2E ARIA badge";

test.describe("group dashboard badges ARIA snapshots", () => {
  test("matches the desktop views", async ({ organizerGroupPage, owned }) => {
    await expectBadgesViews({ owned, page: organizerGroupPage });
  });

  test("matches the views in the mobile desktop version @mobile", async ({ organizerGroupPage, owned }) => {
    await enableDesktopVersion(organizerGroupPage);
    await expectBadgesViews({ owned, page: organizerGroupPage });
  });
});

/** Checks the layout of the badges tab views and the award dialog, and captures them. */
const expectBadgesViews = async ({ owned, page }) => {
  const { groupId } = await setupAriaGroup({ owned, page, withArtwork: true });
  const badges = page.getByRole("region", { name: "Badges" });

  await test.step("empty state", async () => {
    // Load the badges of a temporary group without badges and check the layout.
    await openGroupDashboardView(page, "tab=badges", { regions: [badges] });

    // Capture the title, the search, the add button and the first badge prompt.
    await expectAriaSnapshot(page, badges, "badges-empty");
  });

  await test.step("add badge dialog", async () => {
    // Open the add form and check the layout.
    const dialog = page.getByRole("dialog", { name: "Add badge" });
    await badges.getByRole("button", { name: "Add badge" }).click();
    await expect(dialog).toBeVisible();
    await expectPageLayout(page, { regions: [dialog] });

    // Capture the empty badge fields and the artwork library picker.
    await expectAriaSnapshot(page, dialog, "badges-add-dialog");
  });

  // Give the group an owned badge using its library artwork.
  owned.track(
    setupBadgeDefinition({
      criteria: "Help run an E2E ARIA event.",
      description: "Recognizes E2E ARIA contributors.",
      groupId,
      imageFileName: BADGE_ARTWORK_FILE_NAME,
      name: OWNED_BADGE_NAME,
    }),
    cleanupBadgeDefinition,
  );

  await test.step("badges list", async () => {
    // Load the owned badge and check the layout.
    const table = page.getByRole("table", { name: "Badges list" });
    await openGroupDashboardView(page, "tab=badges", { regions: [table] });

    // Capture the column headers and the badge row with its actions.
    await expectAriaSnapshot(page, table, "badges-list");
  });

  await test.step("edit badge dialog", async () => {
    // Open the update form of the owned badge and check the layout.
    const dialog = page.getByRole("dialog", { name: `Edit ${OWNED_BADGE_NAME}` });
    await page.getByRole("button", { name: `Edit badge: ${OWNED_BADGE_NAME}` }).click();
    await expect(dialog).toBeVisible();
    await expectPageLayout(page, { regions: [dialog] });

    // Capture the fields filled with the badge.
    await expectAriaSnapshot(page, dialog, "badges-edit-dialog");
  });

  await test.step("award badge dialog", async () => {
    // Open the award dialog from the organizer's team row and check the layout.
    const dialog = page.getByRole("dialog", { name: "Award badge" });
    await openGroupDashboardView(page, "tab=team");
    const menu = await openActionsMenu(page, "Open team member actions for E2E Organizer One");
    await menu.getByRole("menuitem", { name: "Award badge" }).click();
    await expect(dialog.getByRole("radiogroup", { name: "Badge" })).toBeVisible();
    await expectPageLayout(page, { regions: [dialog] });

    // Capture the badge choice with the owned badge and the award form.
    await expectAriaSnapshot(page, dialog, "badges-award-dialog");
  });
};
