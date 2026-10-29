import { test } from "../../../fixtures.js";

import { enableDesktopVersion, expectAriaSnapshot } from "../../../snapshots.js";
import { openActionsMenu, openGroupDashboardView, setupAriaGroup } from "../aria-helpers.js";

test.describe("group dashboard co-hosts ARIA snapshots", () => {
  test("matches the desktop views", async ({ organizerGroupPage, owned }) => {
    await expectCohostsViews({ owned, page: organizerGroupPage });
  });

  test("matches the views in the mobile desktop version @mobile", async ({ organizerGroupPage, owned }) => {
    await enableDesktopVersion(organizerGroupPage);
    await expectCohostsViews({ owned, page: organizerGroupPage });
  });
});

/** Checks the layout of the co-hosts tab views and captures them. */
const expectCohostsViews = async ({ owned, page }) => {
  const { groupId } = await setupAriaGroup({ owned, page });

  await test.step("empty state", async () => {
    // Load the invitations of a temporary group without any and check the layout.
    const content = await openGroupDashboardView(page, "tab=cohosts");

    // Capture the title, the column headers and the empty state.
    await expectAriaSnapshot(page, content, "cohosts-empty");
  });

  // Invite the group to co-host an owned event of the primary group.
  const event = owned.cohostEvent({ cohosts: [{ groupId }] });

  await test.step("pending invitation", async () => {
    // Load the pending invitation and check the layout.
    const table = page.getByRole("table", { name: "Co-hosted events list" });
    await openGroupDashboardView(page, "tab=cohosts", { regions: [table] });

    // Capture the invitation row; the event name and date are generated.
    await expectAriaSnapshot(page, table, "cohosts-pending");
  });

  await test.step("invitation actions menu", async () => {
    // Open the invitation actions and check the layout.
    const menu = await openActionsMenu(page, `Open co-host actions for ${event.name}`);

    // Capture the approve and reject actions.
    await expectAriaSnapshot(page, menu, "cohosts-actions");
  });
};
