import { expect, test } from "../../../fixtures.js";

import { cleanupGroupTeamInvitation, setupGroupTeamInvitation } from "../../../data-graphs/invitations.js";
import { TEST_USER_IDS } from "../../../seed.js";
import { enableDesktopVersion, expectAriaSnapshot, expectPageLayout } from "../../../snapshots.js";
import { openActionsMenu, openGroupDashboardView, setupAriaGroup } from "../aria-helpers.js";

test.describe("group dashboard team ARIA snapshots", () => {
  test("matches the desktop views", async ({ organizerGroupPage, owned }) => {
    await expectTeamViews({ owned, page: organizerGroupPage });
  });

  test("matches the views in the mobile desktop version @mobile", async ({ organizerGroupPage, owned }) => {
    await enableDesktopVersion(organizerGroupPage);
    await expectTeamViews({ owned, page: organizerGroupPage });
  });
});

/** Checks the layout of the team tab views and captures them. */
const expectTeamViews = async ({ owned, page }) => {
  // Give a temporary group a pending viewer invitation next to the organizer, its only admin.
  const { groupId } = await setupAriaGroup({ owned, page });
  owned.track(setupGroupTeamInvitation({ groupId, role: "viewer", userId: TEST_USER_IDS.member3 }), () =>
    cleanupGroupTeamInvitation({ groupId, userId: TEST_USER_IDS.member3 }),
  );

  await test.step("team list", async () => {
    // Load the team and check the layout.
    const content = await openGroupDashboardView(page, "tab=team");

    // Capture the title, the add member button and the rows with their role selects.
    await expectAriaSnapshot(page, content, "team-list");
  });

  await test.step("member actions menu", async () => {
    // Open the actions of the pending member and check the layout.
    const menu = await openActionsMenu(page, "Open team member actions for E2E Member Three");

    // Capture the menu items.
    await expectAriaSnapshot(page, menu, "team-member-actions");
  });

  await test.step("add member dialog", async () => {
    // Open the add member form and check the layout.
    const modal = page.locator("team-add-member .modal-card");
    await openGroupDashboardView(page, "tab=team");
    await page.getByRole("button", { name: "Add member" }).click();
    await expect(modal).toBeVisible();
    await expectPageLayout(page, { regions: [modal] });

    // Capture the user search and the role select.
    await expectAriaSnapshot(page, modal, "team-add-member-dialog");
  });
};
