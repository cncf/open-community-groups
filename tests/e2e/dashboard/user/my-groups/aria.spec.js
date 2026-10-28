import { expect, test } from "../../../fixtures.js";

import { TEST_GROUP_NAME } from "../../../seed.js";
import { enableDesktopVersion, expectAriaSnapshot, expectPageLayout } from "../../../snapshots.js";
import { openUserDashboardView } from "../aria-helpers.js";

// Only the actions menu of the first member's seeded group is captured: membership tests leave
// and rejoin seeded groups, which changes the join dates.
test.describe("user dashboard my groups ARIA snapshots", () => {
  test("matches the desktop views", async ({ emptyUserPage, member1Page }) => {
    await expectMyGroupsViews({ emptyUserPage, member1Page });
  });

  test("matches the views in the mobile desktop version @mobile", async ({ emptyUserPage, member1Page }) => {
    await enableDesktopVersion(emptyUserPage);
    await enableDesktopVersion(member1Page);
    await expectMyGroupsViews({ emptyUserPage, member1Page });
  });
});

/** Checks the layout of the my groups tab views and captures them. */
const expectMyGroupsViews = async ({ emptyUserPage, member1Page }) => {
  await test.step("empty state", async () => {
    // Load the groups of a user without groups and check the layout.
    const content = await openUserDashboardView(emptyUserPage, "tab=groups");

    // Capture the title, the column headers and the empty state.
    await expectAriaSnapshot(emptyUserPage, content, "my-groups-empty");
  });

  await test.step("group row actions", async () => {
    // Load the groups of the first member and open the seeded group's actions menu.
    const content = await openUserDashboardView(member1Page, "tab=groups");
    const actions = content.getByRole("row").filter({ hasText: TEST_GROUP_NAME }).getByRole("group");
    await actions.getByLabel(`Open group actions for ${TEST_GROUP_NAME}`).click();
    await expect(actions.getByRole("button", { name: "Leave group" })).toBeVisible();
    await expectPageLayout(member1Page, { regions: [actions] });

    // Capture the open actions menu.
    await expectAriaSnapshot(member1Page, actions, "my-groups-row-actions");
  });
};
