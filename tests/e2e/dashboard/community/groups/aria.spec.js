import { expect, test } from "../../../fixtures.js";

import { setupCommunityTaxonomyItem } from "../../../data-graphs/communities.js";
import { setupTemporaryGroup } from "../../../data-graphs/groups.js";
import { enableDesktopVersion, expectAriaSnapshot, expectPageLayout } from "../../../snapshots.js";
import { openActionsMenu, openCommunityDashboardView, setupAriaCommunity } from "../aria-helpers.js";

test.describe("community dashboard groups ARIA snapshots", () => {
  test("matches the desktop views", async ({ adminCommunityPage, owned }) => {
    await expectGroupsViews({ owned, page: adminCommunityPage });
  });

  test("matches the views in the mobile desktop version @mobile", async ({ adminCommunityPage, owned }) => {
    await enableDesktopVersion(adminCommunityPage);
    await expectGroupsViews({ owned, page: adminCommunityPage });
  });
});

/** Checks the layout of the groups tab views and captures them. */
const expectGroupsViews = async ({ owned, page }) => {
  const { communityId, groupCategoryId } = await setupAriaCommunity({ owned, page });

  await test.step("empty state", async () => {
    // Load the groups of a temporary community without groups and check the layout.
    const content = await openCommunityDashboardView(page, "tab=groups");

    // Capture the title, the search, the add button, the column headers and the empty state.
    await expectAriaSnapshot(page, content, "groups-empty");
  });

  await test.step("search without results", async () => {
    // Load a search that matches no group and check the layout.
    const content = await openCommunityDashboardView(page, "tab=groups&ts_query=nothing");
    await expect(page.getByRole("textbox", { name: "Search groups" })).toHaveValue("nothing");

    // Capture the search with its clear button and the no results state.
    await expectAriaSnapshot(page, content, "groups-no-results");
  });

  // Give the community a region, offered by the group forms and shown by the active group.
  const regionId = setupCommunityTaxonomyItem({ communityId, kind: "region", name: "E2E ARIA region" });

  await test.step("add group form", async () => {
    // Open the add form and check the layout.
    const form = page.locator("#groups-form");
    await openCommunityDashboardView(page, "tab=groups");
    await page.getByRole("button", { name: "Add Group" }).click();
    await expect(form.getByRole("button", { name: "Create Group" })).toBeVisible();
    await expectPageLayout(page, { regions: [form] });

    // Capture the empty group details, location, social links, content and parent group sections.
    await expectAriaSnapshot(page, form, "groups-add-form");
  });

  // Add an active group in the region and an inactive group, both in the community category.
  const active = setupTemporaryGroup({ communityId, groupCategoryId, regionId });
  const inactive = setupTemporaryGroup({ active: false, communityId, groupCategoryId });

  await test.step("group rows", async () => {
    // Load both groups and check the layout.
    const table = page.getByRole("table");
    await openCommunityDashboardView(page, "tab=groups", { regions: [table] });

    // Capture each row, as their order follows the random group names.
    await expectAriaSnapshot(
      page,
      table.getByRole("row").filter({ hasText: active.groupName }),
      "groups-active-row",
    );
    await expectAriaSnapshot(
      page,
      table.getByRole("row").filter({ hasText: inactive.groupName }),
      "groups-inactive-row",
    );
  });

  await test.step("row actions menus", async () => {
    // Open the actions of the active group, then of the inactive group, and check the layout.
    const activeMenu = await openActionsMenu(page, `Open actions menu for group ${active.groupName}`);
    await expectAriaSnapshot(page, activeMenu, "groups-active-actions");
    await openCommunityDashboardView(page, "tab=groups");
    const inactiveMenu = await openActionsMenu(page, `Open actions menu for group ${inactive.groupName}`);
    await expectAriaSnapshot(page, inactiveMenu, "groups-inactive-actions");
  });

  await test.step("update group form", async () => {
    // Open the update form of the active group and check the layout.
    const form = page.locator("#groups-form");
    await openCommunityDashboardView(page, "tab=groups");
    await page.getByRole("button", { name: `Edit group: ${active.groupName}` }).click();
    await expect(form.getByRole("button", { name: "Update Group" })).toBeVisible();
    await expectPageLayout(page, { regions: [form] });

    // Capture the fields filled with the group, its slug and its region.
    await expectAriaSnapshot(page, form, "groups-update-form");
  });
};
