import { expect, test } from "../../fixtures";

import { TEST_GROUP_IDS, navigateToPath } from "../../utils";

test.describe("group dashboard home", () => {
  test("shows the dashboard shell, selectors, and primary navigation", async ({
    organizerGroupPage,
  }) => {
    await navigateToPath(organizerGroupPage, "/dashboard/group?tab=events");

    await expect(
      organizerGroupPage.getByText("Group Dashboard", { exact: true }).last(),
    ).toBeVisible();
    await expect(organizerGroupPage.locator("#dashboard-content")).toBeVisible();
    await expect(organizerGroupPage.locator("#community-selector-button")).toBeVisible();
    await expect(organizerGroupPage.locator("#group-selector-button")).toBeVisible();

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
      organizerGroupPage.getByRole("link", { name: "Group public site" }),
    ).toHaveAttribute("href", /\/e2e-test-community\/group\/test-group-alpha$/);
  });

  test("organizer can filter groups in the dashboard selector", async ({
    organizerGroupPage,
  }) => {
    await navigateToPath(organizerGroupPage, "/dashboard/group?tab=events");

    const groupSelectorButton = organizerGroupPage.locator("#group-selector-button");
    await expect(groupSelectorButton).toContainText("Platform Ops Meetup");

    await groupSelectorButton.click();

    const groupSearchInput = organizerGroupPage.locator("#group-search-input");
    await expect(groupSearchInput).toBeVisible();
    await groupSearchInput.fill("Platform");

    const groupOption = organizerGroupPage.locator(
      `#group-option-${TEST_GROUP_IDS.community1.alpha}`,
    );
    await expect(groupOption).toBeVisible();
    await expect(groupOption).toBeDisabled();

    await groupSearchInput.fill("No matching group");
    await expect(organizerGroupPage.getByText("No groups found.", { exact: true })).toBeVisible();

    await groupSearchInput.press("Escape");
    await expect(groupSearchInput).toBeHidden();
    await expect(groupSelectorButton).toContainText("Platform Ops Meetup");
  });
});
