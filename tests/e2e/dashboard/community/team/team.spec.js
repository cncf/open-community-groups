import { queryScalar, sqlUuid, withRowRestore } from "../../../database.js";
import { expect, test } from "../../../fixtures.js";

import { cleanupCommunityTeamInvitation } from "../../../data-graphs/invitations.js";
import { TEST_COMMUNITY_IDS, TEST_USER_IDS } from "../../../seed.js";
import {
  confirmAlert,
  expectPaginationNavigation,
  navigateToPath,
  waitForActionResponse,
} from "../../../utils.js";
import { inviteTeamMember } from "../../team-helpers.js";

const GROUPS_MANAGER_TEAM_ROW = {
  key: { community_id: TEST_COMMUNITY_IDS.community1, user_id: TEST_USER_IDS.groupsManager1 },
  table: "community_team",
};

const LAST_ADMIN_TITLE = "At least one accepted admin is required.";

const READ_ONLY_TEAM_ROLES = [
  { fixture: "communityViewerPage", label: "community viewer" },
  { fixture: "groupsManagerPage", label: "groups manager" },
];

test.describe("community dashboard team view", () => {
  test("admin can move between community team result pages", async ({ adminCommunityPage }) => {
    // Paginate the seeded team rows with one result per page.
    await expectPaginationNavigation(
      adminCommunityPage,
      "/dashboard/community?tab=team&limit=1&offset=0",
      "#dashboard-content tbody tr",
    );
  });

  test("community team page shows seeded roles and final-admin protection", async ({
    adminCommunityPage,
  }) => {
    // Load the community team tab before checking seeded roles.
    await navigateToPath(adminCommunityPage, "/dashboard/community?tab=team");

    // Find the dashboard content.
    const dashboardContent = adminCommunityPage.locator("#dashboard-content");

    // Verify community team page shows seeded roles and final-admin protection.
    await expect(dashboardContent.getByText("Community Team", { exact: true })).toBeVisible();
    await expect(dashboardContent.getByRole("button", { name: "Add member" })).toBeEnabled();

    // Find the admin row.
    const adminRow = dashboardContent.locator("tr", {
      hasText: "E2E Admin One",
    });
    await expect(adminRow.locator("select")).toBeDisabled();
    await expect(adminRow.locator("select")).toHaveAttribute("title", LAST_ADMIN_TITLE);

    // Verify the final admin cannot be deleted either.
    const adminRemoveButton = adminRow.locator(`#remove-member-${TEST_USER_IDS.admin1}`);
    await expect(adminRemoveButton).toBeDisabled();
    await expect(adminRemoveButton).toHaveAttribute("title", LAST_ADMIN_TITLE);

    // Find the groups manager row.
    const groupsManagerRow = dashboardContent.locator("tr", {
      hasText: "E2E Groups Manager One",
    });
    await expect(groupsManagerRow.locator('select[name="role"]')).toBeEnabled();

    // Find the viewer row.
    const viewerRow = dashboardContent.locator("tr", {
      hasText: "E2E Community Viewer One",
    });
    await expect(viewerRow.locator('select[name="role"]')).toHaveValue("viewer");

    // Find the pending row.
    const pendingRow = dashboardContent.locator("tr", {
      hasText: "E2E Pending One",
    });
    await expect(pendingRow).toContainText("e2e-pending-1");
    await expect(pendingRow.locator('select[name="role"]')).toHaveValue("viewer");
  });

  test("admin can invite and remove a pending community team member", async ({
    adminCommunityPage,
    notifications,
  }) => {
    try {
      // Clear any leftover pending invitation before inviting the member.
      cleanupCommunityTeamInvitation({
        communityId: TEST_COMMUNITY_IDS.community1,
        userId: TEST_USER_IDS.pending2,
      });

      // Invite the pending user as a viewer through the add member form.
      const pendingRow = await inviteTeamMember(adminCommunityPage, {
        fullName: "E2E Pending Two",
        role: "viewer",
        scope: "community",
        username: "e2e-pending-2",
      });
      notifications.expectNew([
        {
          kind: "community-team-invitation",
          templateDataContains: { community_name: "Platform Engineering Community" },
          userIds: [TEST_USER_IDS.pending2],
        },
      ]);

      // Verify the pending member keeps the invited role.
      await expect(pendingRow.locator('select[name="role"]')).toHaveValue("viewer");

      // Find the remove button.
      const removeButton = pendingRow.locator(`#remove-member-${TEST_USER_IDS.pending2}`);
      await removeButton.click();

      // Click Yes.
      await waitForActionResponse(
        adminCommunityPage,
        () =>
          confirmAlert(adminCommunityPage, {
            message: "Are you sure you would like to delete this team member?",
          }),
        {
          method: "DELETE",
          urlIncludes: `/dashboard/community/team/${TEST_USER_IDS.pending2}/delete`,
        },
      );

      // Assert how many matching elements are shown.
      await expect(pendingRow).toHaveCount(0);
    } finally {
      // Remove invitation state created by the test.
      cleanupCommunityTeamInvitation({
        communityId: TEST_COMMUNITY_IDS.community1,
        userId: TEST_USER_IDS.pending2,
      });
    }
  });

  test("admin can update and restore a community team member role", async ({ adminCommunityPage }) => {
    // Define the seeded team member role that must be restored.
    const seededRole = "groups-manager";
    const teamTabPath = "/dashboard/community?tab=team";

    // Restore the seeded groups manager role after this check.
    await withRowRestore(GROUPS_MANAGER_TEAM_ROW, async () => {
      // Open the team tab before changing the seeded role.
      await navigateToPath(adminCommunityPage, teamTabPath);

      // Find the dashboard content.
      const dashboardContent = adminCommunityPage.locator("#dashboard-content");
      const groupsManagerRow = dashboardContent.locator("tr", {
        hasText: "E2E Groups Manager One",
      });
      const currentRoleSelect = groupsManagerRow.locator('select[name="role"]');

      // Verify admin can update and restore a community team member role.
      await expect(dashboardContent.getByText("Community Team", { exact: true })).toBeVisible();
      await expect(currentRoleSelect).toHaveValue(seededRole);

      // Submit and wait for the server response.
      await waitForActionResponse(adminCommunityPage, () => currentRoleSelect.selectOption("viewer"), {
        method: "PUT",
        urlEndsWith: "/role",
        urlIncludes: "/dashboard/community/team/",
      });

      // Assert the field value and the stored role were updated.
      await expect(currentRoleSelect).toHaveValue("viewer");
      expect(
        queryScalar(`
          select role
          from community_team
          where community_id = ${sqlUuid(TEST_COMMUNITY_IDS.community1)}
            and user_id = ${sqlUuid(TEST_USER_IDS.groupsManager1)}
        `),
      ).toBe("viewer");
    });
  });

  for (const { fixture, label } of READ_ONLY_TEAM_ROLES) {
    test(`${label} sees the community team as read-only`, async ({ pageAs }) => {
      // Load the community team tab with a role that cannot manage the team.
      const page = await pageAs(fixture);
      await navigateToPath(page, "/dashboard/community?tab=team");

      // Find the dashboard content.
      const dashboardContent = page.locator("#dashboard-content");
      await expect(dashboardContent.getByText("Community Team", { exact: true })).toBeVisible();

      // Verify inviting and role changes are unavailable.
      const addMemberButton = dashboardContent.getByRole("button", { name: "Add member" });
      await expect(addMemberButton).toBeDisabled();
      await expect(addMemberButton).toHaveAttribute("title", "Your role cannot invite team members.");
      await expect(dashboardContent.locator('select[name="role"]')).toHaveCount(0);

      // Verify the final admin keeps its protection title.
      const adminRemoveButton = dashboardContent.locator(`#remove-member-${TEST_USER_IDS.admin1}`);
      await expect(adminRemoveButton).toBeDisabled();
      await expect(adminRemoveButton).toHaveAttribute("title", LAST_ADMIN_TITLE);

      // Verify every other delete button is disabled for this role.
      const removeButtons = dashboardContent.locator(
        `button[id^="remove-member-"]:not(#remove-member-${TEST_USER_IDS.admin1})`,
      );
      await expect(removeButtons.first()).toBeVisible();
      for (const removeButton of await removeButtons.all()) {
        await expect(removeButton).toBeDisabled();
        await expect(removeButton).toHaveAttribute("title", "Your role cannot delete team members.");
      }
    });
  }
});
