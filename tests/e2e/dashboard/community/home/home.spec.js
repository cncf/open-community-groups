import { expect, test } from "../../../fixtures.js";

import { TEST_GROUP_SLUGS, navigateToPath } from "../../../utils.js";

test.describe("community dashboard home", () => {
  test("shows the dashboard shell, selector, and primary navigation", async ({
    adminCommunityPage,
  }) => {
    // Load the community groups tab before checking the dashboard shell.
    await navigateToPath(adminCommunityPage, "/dashboard/community?tab=groups");

    // Verify the dashboard shell and selector are visible.
    await expect(
      adminCommunityPage
        .getByText("Community Dashboard", { exact: true })
        .last(),
    ).toBeVisible();
    await expect(
      adminCommunityPage.locator("#dashboard-content"),
    ).toBeVisible();
    await expect(
      adminCommunityPage.locator("#community-selector-button"),
    ).toBeVisible();

    // Verify the primary community navigation links are available.
    await expect(
      adminCommunityPage.locator(
        'a[hx-get="/dashboard/community?tab=settings"]',
      ),
    ).toContainText("Settings");
    await expect(
      adminCommunityPage.locator('a[hx-get="/dashboard/community?tab=team"]'),
    ).toContainText("Team");
    await expect(
      adminCommunityPage.locator(
        'a[hx-get="/dashboard/community?tab=regions"]',
      ),
    ).toContainText("Regions");
    await expect(
      adminCommunityPage.locator(
        'a[hx-get="/dashboard/community?tab=group-categories"]',
      ),
    ).toContainText("Group Categories");
    await expect(
      adminCommunityPage.locator(
        'a[hx-get="/dashboard/community?tab=event-categories"]',
      ),
    ).toContainText("Event Categories");
    await expect(
      adminCommunityPage.locator('a[hx-get="/dashboard/community?tab=groups"]'),
    ).toContainText("Groups");
    await expect(
      adminCommunityPage.locator(
        'a[hx-get="/dashboard/community?tab=analytics"]',
      ),
    ).toContainText("Analytics");
    await expect(
      adminCommunityPage.locator('a[hx-get="/dashboard/community?tab=logs"]'),
    ).toContainText("Logs");
  });

  test("community navigation can open a selected group dashboard", async ({
    adminCommunityPage,
  }) => {
    // Load the community groups tab before choosing a group dashboard.
    await navigateToPath(adminCommunityPage, "/dashboard/community?tab=groups");

    // Target the seeded group dashboard action.
    const dashboardContent = adminCommunityPage.locator("#dashboard-content");
    const openGroupButton = dashboardContent.getByRole("button", {
      name: "Open group dashboard: Observability Guild",
    });

    // Assert the expected content is visible.
    await expect(openGroupButton).toBeVisible();

    // Open the group dashboard and verify the selected group context.
    await Promise.all([
      adminCommunityPage.waitForURL(/\/dashboard\/group$/),
      openGroupButton.click(),
    ]);

    // Assert that Group Dashboard is visible.
    await expect(
      adminCommunityPage.getByText("Group Dashboard", { exact: true }).last(),
    ).toBeVisible();
    await expect(
      adminCommunityPage.locator("#group-selector-button"),
    ).toContainText("Observability Guild");
    await expect(
      adminCommunityPage.locator("#dashboard-content"),
    ).toHaveAttribute("data-group-slug", TEST_GROUP_SLUGS.community1.gamma);
  });
});
