import { expect, test } from "../../../fixtures.js";

import {
  cleanupCommunityTeamInvitation,
  setupCommunityTeamInvitation,
} from "../../../data-graphs/invitations.js";
import { TEST_USER_IDS } from "../../../seed.js";
import { enableDesktopVersion, expectAriaSnapshot, expectPageLayout } from "../../../snapshots.js";
import { openCommunityDashboardView, setupAriaCommunity } from "../aria-helpers.js";

test.describe("community dashboard team ARIA snapshots", () => {
  test("matches the desktop views", async ({ adminCommunityPage, owned }) => {
    await expectTeamViews({ owned, page: adminCommunityPage });
  });

  test("matches the views in the mobile desktop version @mobile", async ({ adminCommunityPage, owned }) => {
    await enableDesktopVersion(adminCommunityPage);
    await expectTeamViews({ owned, page: adminCommunityPage });
  });
});

/** Checks the layout of the team tab views and captures them. */
const expectTeamViews = async ({ owned, page }) => {
  // Give a temporary community a pending viewer invitation next to the admin, its only admin.
  const { communityId } = await setupAriaCommunity({ owned, page });
  owned.track(
    setupCommunityTeamInvitation({ communityId, role: "viewer", userId: TEST_USER_IDS.member3 }),
    () => cleanupCommunityTeamInvitation({ communityId, userId: TEST_USER_IDS.member3 }),
  );

  await test.step("team list", async () => {
    // Load the team and check the layout.
    const content = await openCommunityDashboardView(page, "tab=team");

    // Capture the title, the add member button and the rows with their role selects and actions.
    await expectAriaSnapshot(page, content, "team-list");
  });

  await test.step("add member dialog", async () => {
    // Open the add member form and check the layout.
    const modal = page.locator("team-add-member .modal-card");
    await page.getByRole("button", { name: "Add member" }).click();
    await expect(modal).toBeVisible();
    await expectPageLayout(page, { regions: [modal] });

    // Capture the user search and the role select.
    await expectAriaSnapshot(page, modal, "team-add-member-dialog");
  });
};
