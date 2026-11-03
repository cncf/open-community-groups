import { expect, test } from "../../../fixtures.js";

import {
  cleanupBadgeDefinition,
  cleanupCredential,
  setupBadgeDefinition,
  setupRevocableCredential,
} from "../../../data-graphs/badges.js";
import { BADGE_ARTWORK_FILE_NAME } from "../../../data-graphs/groups.js";
import { TEST_USER_IDS } from "../../../seed.js";
import { enableDesktopVersion, expectAriaSnapshot, expectPageLayout } from "../../../snapshots.js";
import { openGroupDashboardView, setupAriaGroup } from "../aria-helpers.js";

// Name of the owned badge of the temporary group.
const OWNED_BADGE_NAME = "E2E ARIA badge";

test.describe("group dashboard awards ARIA snapshots", () => {
  test("matches the desktop views", async ({ organizerGroupPage, owned }) => {
    await expectAwardsViews({ owned, page: organizerGroupPage });
  });

  test("matches the views in the mobile desktop version @mobile", async ({ organizerGroupPage, owned }) => {
    await enableDesktopVersion(organizerGroupPage);
    await expectAwardsViews({ owned, page: organizerGroupPage });
  });
});

/** Checks the layout of the awards tab views and captures them. */
const expectAwardsViews = async ({ owned, page }) => {
  const { groupId } = await setupAriaGroup({ owned, page, withArtwork: true });
  const awards = page.getByRole("region", { name: "Badges Awards" });

  await test.step("empty state", async () => {
    // Load the awards of a temporary group without awards and check the layout.
    await openGroupDashboardView(page, "tab=awards", { regions: [awards] });

    // Capture the title, the filters and the empty state.
    await expectAriaSnapshot(page, awards, "awards-empty");
  });

  // Award an owned badge of the group to a member.
  const { badgeId } = owned.track(
    setupBadgeDefinition({ groupId, imageFileName: BADGE_ARTWORK_FILE_NAME, name: OWNED_BADGE_NAME }),
    cleanupBadgeDefinition,
  );
  owned.track(
    setupRevocableCredential({ badgeId, groupId, userId: TEST_USER_IDS.member3 }),
    cleanupCredential,
  );

  await test.step("awards list", async () => {
    // Load the owned award and check the layout.
    const table = page.getByRole("table", { name: "Awards list" });
    await openGroupDashboardView(page, "tab=awards", { regions: [table] });

    // Capture the column headers and the award row; the award date is the test day.
    await expectAriaSnapshot(page, table, "awards-list");
  });

  await test.step("revoke credential dialog", async () => {
    // Open the revoke confirmation of the owned award and check the layout.
    const dialog = page.getByRole("dialog", { name: `Revoke ${OWNED_BADGE_NAME}` });
    await page.getByRole("button", { name: `Revoke credential: ${OWNED_BADGE_NAME}` }).click();
    await expect(dialog).toBeVisible();
    await expectPageLayout(page, { regions: [dialog] });

    // Capture the reason field and the confirmation actions.
    await expectAriaSnapshot(page, dialog, "awards-revoke-dialog");
  });
};
