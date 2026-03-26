import { expect, test } from "../../fixtures";

import { TEST_GROUP_SLUGS, navigateToPath } from "../../utils";

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
    await expect(
      adminCommunityPage.locator('a[hx-get="/dashboard/community?tab=analytics"]'),
    ).toContainText("Analytics");
  });

  test("community navigation can open a selected group dashboard", async ({
    adminCommunityPage,
  }) => {
    await navigateToPath(adminCommunityPage, "/dashboard/community?tab=groups");

    const dashboardContent = adminCommunityPage.locator("#dashboard-content");
    const openGroupButton = dashboardContent.getByRole("button", {
      name: "Open group dashboard: Observability Guild",
    });

    await expect(openGroupButton).toBeVisible();

    await Promise.all([
      adminCommunityPage.waitForURL(/\/dashboard\/group$/),
      openGroupButton.click(),
    ]);

    await expect(
      adminCommunityPage.getByText("Group Dashboard", { exact: true }).last(),
    ).toBeVisible();
    await expect(adminCommunityPage.locator("#group-selector-button")).toContainText(
      "Observability Guild",
    );
    await expect(adminCommunityPage.locator("#dashboard-content")).toHaveAttribute(
      "data-group-slug",
      TEST_GROUP_SLUGS.community1.gamma,
    );
  });
});
