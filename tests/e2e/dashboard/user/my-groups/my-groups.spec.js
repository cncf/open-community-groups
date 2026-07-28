import { expect, test } from "../../../fixtures.js";

import {
  TEST_COMMUNITY_NAME,
  TEST_COMMUNITY_TITLE,
  TEST_GROUP_IDS,
  TEST_GROUP_NAMES,
  TEST_GROUP_SLUGS,
  navigateToGroup,
  navigateToPath,
} from "../../../utils.js";

const groupId = TEST_GROUP_IDS.community1.alpha;

/** Returns the public membership container for the current group page. */
const getMembershipContainer = (page) => page.locator("#membership-container");

/** Leaves the public group when the reusable user is already a member. */
const leavePublicGroup = async (page) => {
  const leaveButton = getMembershipContainer(page).locator("#leave-btn");

  await leaveButton.click();
  await expect(page.getByRole("button", { name: "Yes" })).toBeVisible();
  await Promise.all([
    page.waitForResponse(
      (response) =>
        response.request().method() === "DELETE" &&
        response.url().includes(`/group/${groupId}/leave`) &&
        response.ok(),
    ),
    page.getByRole("button", { name: "Yes" }).click(),
  ]);
  await expect(getMembershipContainer(page).locator("#join-btn")).toBeVisible();
};

/** Waits until the public membership widget resolves. */
const waitForMembershipState = async (page) => {
  await Promise.race([
    getMembershipContainer(page).locator("#join-btn").waitFor({
      state: "visible",
    }),
    getMembershipContainer(page).locator("#leave-btn").waitFor({
      state: "visible",
    }),
  ]);
};

test.describe("user dashboard my groups view", () => {
  test("empty state explains when the user has no groups", async ({ pending1Page }) => {
    // Load My Groups for a user without a group relationship
    await navigateToPath(pending1Page, "/dashboard/user?tab=groups");
    const dashboardContent = pending1Page.locator("#dashboard-content");

    // Verify the empty result remains explicit
    await expect(dashboardContent).toContainText("0 groups");
    await expect(dashboardContent).toContainText("You don't belong to any groups yet.");
  });

  test("header user menu navigates to My Groups", async ({ member1Page }) => {
    // Load another user dashboard tab before using the global menu
    await navigateToPath(member1Page, "/dashboard/user?tab=events");

    // Open the avatar menu and select My Groups
    await member1Page.locator("#user-dropdown-button").click();
    await member1Page.getByRole("menuitem", { name: "My Groups" }).click();

    // Verify the user reaches the groups tab
    await expect(member1Page).toHaveURL(/\/dashboard\/user\?tab=groups$/);
    await expect(
      member1Page.locator("#dashboard-content").getByText("My Groups", { exact: true }),
    ).toBeVisible();
  });

  test("member can leave a group from My Groups", async ({ pending2Page }) => {
    // Load the public group and reset the reusable user's membership
    await navigateToGroup(pending2Page, TEST_COMMUNITY_NAME, TEST_GROUP_SLUGS.community1.alpha);
    await waitForMembershipState(pending2Page);
    if (await getMembershipContainer(pending2Page).locator("#leave-btn").isVisible()) {
      await leavePublicGroup(pending2Page);
    }

    // Join the group through the public membership action
    const joinButton = getMembershipContainer(pending2Page).locator("#join-btn");
    await Promise.all([
      pending2Page.waitForResponse(
        (response) =>
          response.request().method() === "POST" &&
          response.url().includes(`/group/${groupId}/join`) &&
          response.ok(),
      ),
      joinButton.click(),
    ]);

    // Load My Groups and verify the new relationship row
    await navigateToPath(pending2Page, "/dashboard/user?tab=groups");
    const dashboardContent = pending2Page.locator("#dashboard-content");
    const groupRow = dashboardContent.locator("tr", {
      hasText: TEST_GROUP_NAMES.alpha,
    });
    await expect(groupRow).toContainText(TEST_COMMUNITY_TITLE);
    await expect(groupRow).toContainText("Member since");
    await expect(groupRow.locator("td").getByText("Member", { exact: true })).toBeVisible();
    await expect(groupRow.getByRole("link", { name: TEST_GROUP_NAMES.alpha })).toHaveAttribute(
      "href",
      `/${TEST_COMMUNITY_NAME}/group/${TEST_GROUP_SLUGS.community1.alpha}`,
    );

    // Leave through the row actions menu
    await groupRow.getByLabel(`Open group actions for ${TEST_GROUP_NAMES.alpha}`).click();
    await groupRow.getByRole("button", { name: "Leave group" }).click();
    await expect(pending2Page.locator(".swal2-popup")).toContainText(
      "Are you sure you want to leave this group?",
    );

    // Confirm the mutation and verify the row is removed
    await Promise.all([
      pending2Page.waitForResponse(
        (response) =>
          response.request().method() === "DELETE" &&
          response.url().includes(`/dashboard/user/groups/${TEST_COMMUNITY_NAME}/${groupId}/membership`) &&
          response.ok(),
      ),
      pending2Page.getByRole("button", { name: "Yes" }).click(),
    ]);
    await expect(groupRow).toHaveCount(0);
  });

  test("team-only group keeps leave action disabled", async ({ organizerGroupPage }) => {
    // Load My Groups for a user with an accepted team role only
    await navigateToPath(organizerGroupPage, "/dashboard/user?tab=groups");
    const groupRow = organizerGroupPage.locator("#dashboard-content").locator("tr", {
      hasText: TEST_GROUP_NAMES.alpha,
    });

    // Open the actions menu and verify the membership-only action is unavailable
    await groupRow.getByLabel(`Open group actions for ${TEST_GROUP_NAMES.alpha}`).click();
    const leaveButton = groupRow.getByRole("button", { name: "Leave group" });
    await expect(groupRow.locator("td").getByText("Team member", { exact: true })).toBeVisible();
    await expect(leaveButton).toBeDisabled();
    await expect(leaveButton).toHaveAttribute("title", "Team memberships cannot be left from My Groups.");
  });

  test("My Groups lists member relationships in group name order", async ({ member1Page }) => {
    // Load the user's seeded group relationships
    await navigateToPath(member1Page, "/dashboard/user?tab=groups");
    const groupLinks = member1Page.locator("#dashboard-content tbody th").getByRole("link");

    // Verify active groups are ordered by display name
    await expect(groupLinks).toHaveText([TEST_GROUP_NAMES.beta, TEST_GROUP_NAMES.alpha]);
  });
});
