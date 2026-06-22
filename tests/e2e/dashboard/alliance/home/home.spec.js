import { expect, test } from "../../../fixtures.js";

import { TEST_GROUP_SLUGS, navigateToPath } from "../../../utils.js";

test.describe("alliance dashboard home", () => {
  test("shows the dashboard shell, selector, and primary navigation", async ({
    adminAlliancePage,
  }) => {
    // Load the alliance groups tab before checking the dashboard shell.
    await navigateToPath(adminAlliancePage, "/dashboard/alliance?tab=groups");

    // Verify the dashboard shell and selector are visible.
    await expect(
      adminAlliancePage
        .getByText("Alliance Dashboard", { exact: true })
        .last(),
    ).toBeVisible();
    await expect(
      adminAlliancePage.locator("#dashboard-content"),
    ).toBeVisible();
    await expect(
      adminAlliancePage.locator("#alliance-selector-button"),
    ).toBeVisible();

    // Verify the primary alliance navigation links are available.
    await expect(
      adminAlliancePage.locator(
        'a[hx-get="/dashboard/alliance?tab=settings"]',
      ),
    ).toContainText("Settings");
    await expect(
      adminAlliancePage.locator('a[hx-get="/dashboard/alliance?tab=team"]'),
    ).toContainText("Team");
    await expect(
      adminAlliancePage.locator(
        'a[hx-get="/dashboard/alliance?tab=regions"]',
      ),
    ).toContainText("Regions");
    await expect(
      adminAlliancePage.locator(
        'a[hx-get="/dashboard/alliance?tab=group-categories"]',
      ),
    ).toContainText("Group Categories");
    await expect(
      adminAlliancePage.locator(
        'a[hx-get="/dashboard/alliance?tab=event-categories"]',
      ),
    ).toContainText("Event Categories");
    await expect(
      adminAlliancePage.locator('a[hx-get="/dashboard/alliance?tab=groups"]'),
    ).toContainText("Groups");
    await expect(
      adminAlliancePage.locator(
        'a[hx-get="/dashboard/alliance?tab=analytics"]',
      ),
    ).toContainText("Analytics");
    await expect(
      adminAlliancePage.locator('a[hx-get="/dashboard/alliance?tab=logs"]'),
    ).toContainText("Logs");
  });

  test("alliance navigation can open a selected group dashboard", async ({
    adminAlliancePage,
  }) => {
    // Load the alliance groups tab before choosing a group dashboard.
    await navigateToPath(adminAlliancePage, "/dashboard/alliance?tab=groups");

    // Target the seeded group dashboard action.
    const dashboardContent = adminAlliancePage.locator("#dashboard-content");
    const openGroupButton = dashboardContent.getByRole("button", {
      name: "Open group dashboard: Observability Guild",
    });

    // Assert the expected content is visible.
    await expect(openGroupButton).toBeVisible();

    // Open the group dashboard and verify the selected group context.
    await Promise.all([
      adminAlliancePage.waitForURL(/\/dashboard\/group$/),
      openGroupButton.click(),
    ]);

    // Assert that Group Dashboard is visible.
    await expect(
      adminAlliancePage.getByText("Group Dashboard", { exact: true }).last(),
    ).toBeVisible();
    await expect(
      adminAlliancePage.locator("#group-selector-button"),
    ).toContainText("Observability Guild");
    await expect(
      adminAlliancePage.locator("#dashboard-content"),
    ).toHaveAttribute("data-group-slug", TEST_GROUP_SLUGS.alliance1.gamma);
  });
});
