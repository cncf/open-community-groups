import { expect, test } from "../../../fixtures.js";

import {
  E2E_PAYMENTS_ENABLED,
  TEST_GROUP_IDS,
  TEST_GROUP_NAMES,
  TEST_GROUP_SLUGS,
  navigateToPath,
  waitForActionResponse,
} from "../../../utils.js";

test.describe("group dashboard navigation", () => {
  test("leaving Check-In keeps the page header mounted", async ({
    organizerGroupPage,
  }) => {
    // Load Check-In and mark the header node before desktop tab navigation.
    await navigateToPath(organizerGroupPage, "/dashboard/group?tab=check-in");
    const header = organizerGroupPage.locator("#dashboard-header");
    await header.evaluate((element) => {
      element.dataset.navigationSentinel = "preserved";
    });

    // Open Events through the dashboard menu and wait for its HTMX response.
    const eventsResponse = organizerGroupPage.waitForResponse(
      (response) => response.url().includes("/dashboard/group?tab=events"),
    );
    await organizerGroupPage.locator('a[hx-get="/dashboard/group?tab=events"]').click();
    expect((await eventsResponse).ok()).toBe(true);

    // Verify navigation updates dashboard state without replacing the page header.
    await expect(organizerGroupPage).toHaveURL(/\/dashboard\/group\?tab=events$/u);
    await expect(header).toHaveAttribute("data-navigation-sentinel", "preserved");
    await expect(organizerGroupPage.getByRole("button", { name: "Add Event" })).toBeVisible();
  });

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
    if (E2E_PAYMENTS_ENABLED) {
      await expect(
        organizerGroupPage.locator('a[hx-get="/dashboard/group?tab=refunds"]'),
      ).toContainText("Refunds");
    }
    await expect(
      organizerGroupPage.locator('a[hx-get="/dashboard/group?tab=badges"]'),
    ).toContainText("Badges");
    await expect(
      organizerGroupPage.locator('a[hx-get="/dashboard/group?tab=artwork"]'),
    ).toContainText("Artwork");
    await expect(
      organizerGroupPage.locator('a[hx-get="/dashboard/group?tab=awards"]'),
    ).toContainText("Awards");
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

  test("organizer can switch groups and restore the original selection", async ({
    organizerGroupPage,
  }) => {
    // Load the group dashboard before changing the active group.
    await navigateToPath(organizerGroupPage, "/dashboard/group?tab=events");

    // Find the selector and verify the primary group is active.
    const groupSelectorButton = organizerGroupPage.locator(
      "#group-selector-button",
    );
    await expect(groupSelectorButton).toContainText(TEST_GROUP_NAMES.alpha);

    try {
      // Select the secondary group and verify its restricted dashboard state.
      await groupSelectorButton.click();
      const secondaryGroup = organizerGroupPage.locator(
        `#group-option-${TEST_GROUP_IDS.community1.gamma}`,
      );
      await expect(secondaryGroup).toContainText(TEST_GROUP_NAMES.gamma);
      await waitForActionResponse(
        organizerGroupPage,
        () => secondaryGroup.click(),
        {
          method: "PUT",
          urlEndsWith: `/dashboard/group/${TEST_GROUP_IDS.community1.gamma}/select`,
        },
      );
      await expect(groupSelectorButton).toContainText(TEST_GROUP_NAMES.gamma);
      await expect(
        organizerGroupPage.locator("#dashboard-content"),
      ).toHaveAttribute("data-group-slug", TEST_GROUP_SLUGS.community1.gamma);
      await expect(
        organizerGroupPage.getByRole("button", { name: "Add Event" }),
      ).toBeDisabled();
    } finally {
      // Restore the primary group so later scenarios retain their fixture state.
      await groupSelectorButton.click();
      const primaryGroup = organizerGroupPage.locator(
        `#group-option-${TEST_GROUP_IDS.community1.alpha}`,
      );
      await waitForActionResponse(
        organizerGroupPage,
        () => primaryGroup.click(),
        {
          method: "PUT",
          urlEndsWith: `/dashboard/group/${TEST_GROUP_IDS.community1.alpha}/select`,
        },
      );
      await expect(groupSelectorButton).toContainText(TEST_GROUP_NAMES.alpha);
    }
  });
});
