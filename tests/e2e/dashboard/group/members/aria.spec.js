import { expect, test } from "../../../fixtures.js";

import { TEST_USER_IDS } from "../../../seed.js";
import { enableDesktopVersion, expectAriaSnapshot, expectPageLayout } from "../../../snapshots.js";
import { openGroupDashboardView, setupAriaGroup } from "../aria-helpers.js";

test.describe("group dashboard members ARIA snapshots", () => {
  test("matches the desktop views", async ({ organizerGroupPage, owned }) => {
    await expectMembersViews({ owned, page: organizerGroupPage });
  });

  test("matches the views in the mobile desktop version @mobile", async ({ organizerGroupPage, owned }) => {
    await enableDesktopVersion(organizerGroupPage);
    await expectMembersViews({ owned, page: organizerGroupPage });
  });
});

/** Checks the layout of the members tab views and captures them. */
const expectMembersViews = async ({ owned, page }) => {
  await test.step("empty state", async () => {
    // Load the members of a temporary group without members and check the layout.
    await setupAriaGroup({ owned, page });
    const content = await openGroupDashboardView(page, "tab=members");

    // Capture the title, the disabled email button, the column headers and the empty state.
    await expectAriaSnapshot(page, content, "members-empty");
  });

  await test.step("members list", async () => {
    // Load the members of a temporary group with one member and check the layout.
    await setupAriaGroup({ memberUserId: TEST_USER_IDS.member3, owned, page });
    const content = await openGroupDashboardView(page, "tab=members");

    // Capture the member row; the join date is the test day.
    await expectAriaSnapshot(page, content, "members-list");
  });

  await test.step("send email dialog", async () => {
    // Open the email form for every member and check the layout.
    const dialog = page.getByRole("dialog", { name: "Send email" });
    await page.getByRole("button", { name: "Send email" }).click();
    await expect(dialog).toBeVisible();
    await expectPageLayout(page, { regions: [dialog] });

    // Capture the recipients notice and the empty form.
    await expectAriaSnapshot(page, dialog, "members-send-email-dialog");
  });
};
