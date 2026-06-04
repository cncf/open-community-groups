import { expect, test } from "../../../fixtures.js";

import { TEST_GROUP_IDS, navigateToPath } from "../../../utils.js";

test.describe("group dashboard home", () => {
  test("shows the dashboard shell, selectors, and primary navigation", async ({
    organizerGroupPage,
  }) => {
    // Load the group events tab before checking the dashboard shell.
    await navigateToPath(organizerGroupPage, "/dashboard/group?tab=events");

    // Verify shows the dashboard shell, selectors, and primary navigation.
    await expect(
      organizerGroupPage.getByText("Group Dashboard", { exact: true }).last(),
    ).toBeVisible();
    await expect(
      organizerGroupPage.locator("#dashboard-content"),
    ).toBeVisible();
    await expect(
      organizerGroupPage.locator("#community-selector-button"),
    ).toBeVisible();
    await expect(
      organizerGroupPage.locator("#group-selector-button"),
    ).toBeVisible();

    // Assert the expected text is rendered.
    await expect(
      organizerGroupPage.locator('a[hx-get="/dashboard/group?tab=settings"]'),
    ).toContainText("Settings");
    await expect(
      organizerGroupPage.locator('a[hx-get="/dashboard/group?tab=team"]'),
    ).toContainText("Team");
    await expect(
      organizerGroupPage.locator('a[hx-get="/dashboard/group?tab=events"]'),
    ).toContainText("Events");
    await expect(
      organizerGroupPage.locator('a[hx-get="/dashboard/group?tab=members"]'),
    ).toContainText("Members");
    await expect(
      organizerGroupPage.locator('a[hx-get="/dashboard/group?tab=sponsors"]'),
    ).toContainText("Sponsors");
    await expect(
      organizerGroupPage.locator('a[hx-get="/dashboard/group?tab=analytics"]'),
    ).toContainText("Analytics");
    await expect(
      organizerGroupPage.locator('a[hx-get="/dashboard/group?tab=logs"]'),
    ).toContainText("Logs");
    await expect(
      organizerGroupPage.getByRole("link", { name: "Group public site" }),
    ).toHaveAttribute("href", /\/e2e-test-community\/group\/test-group-alpha$/);
  });

  test("organizer can filter groups in the dashboard selector", async ({
    organizerGroupPage,
  }) => {
    // Load the group events tab before opening the group selector.
    await navigateToPath(organizerGroupPage, "/dashboard/group?tab=events");

    // Find the group selector button.
    const groupSelectorButton = organizerGroupPage.locator(
      "#group-selector-button",
    );

    // Verify organizer can filter groups in the dashboard selector.
    await expect(groupSelectorButton).toContainText("Platform Ops Meetup");

    // Click the group selector button.
    await groupSelectorButton.click();

    // Find the group search input.
    const groupSearchInput = organizerGroupPage.locator("#group-search-input");
    await expect(groupSearchInput).toBeVisible();
    await groupSearchInput.fill("Platform");

    // Find the group option.
    const groupOption = organizerGroupPage.locator(
      `#group-option-${TEST_GROUP_IDS.community1.alpha}`,
    );
    await expect(groupOption).toBeVisible();
    await expect(groupOption).toBeDisabled();

    // Fill the form field.
    await groupSearchInput.fill("No matching group");
    await expect(
      organizerGroupPage.getByText("No groups found.", { exact: true }),
    ).toBeVisible();

    // Close the group selector with Escape.
    await groupSearchInput.press("Escape");
    await expect(groupSearchInput).toBeHidden();
    await expect(groupSelectorButton).toContainText("Platform Ops Meetup");
  });
});
