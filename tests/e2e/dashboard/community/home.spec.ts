import { expect, test } from "../../fixtures";

import { navigateToPath } from "../../utils";

test.describe("community dashboard home", () => {
  test("shows the dashboard shell, selector, and primary navigation", async ({
    adminCommunityPage,
  }) => {
    await navigateToPath(adminCommunityPage, "/dashboard/community?tab=groups");

    await expect(
      adminCommunityPage.getByText("Community Dashboard", { exact: true }).last(),
    ).toBeVisible();
    await expect(adminCommunityPage.locator("#dashboard-content")).toBeVisible();
    await expect(adminCommunityPage.locator("#community-selector-button")).toBeVisible();

    await expect(
      adminCommunityPage.locator('a[hx-get="/dashboard/community?tab=settings"]'),
    ).toContainText("Settings");
    await expect(
      adminCommunityPage.locator('a[hx-get="/dashboard/community?tab=team"]'),
    ).toContainText("Team");
    await expect(
      adminCommunityPage.locator('a[hx-get="/dashboard/community?tab=regions"]'),
    ).toContainText("Regions");
    await expect(
      adminCommunityPage.locator('a[hx-get="/dashboard/community?tab=group-categories"]'),
    ).toContainText("Group Categories");
    await expect(
      adminCommunityPage.locator('a[hx-get="/dashboard/community?tab=event-categories"]'),
    ).toContainText("Event Categories");
    await expect(
      adminCommunityPage.locator('a[hx-get="/dashboard/community?tab=groups"]'),
    ).toContainText("Groups");
  });
});
