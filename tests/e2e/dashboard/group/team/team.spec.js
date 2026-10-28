import { withRowRestore } from "../../../database.js";
import { expect, test } from "../../../fixtures.js";

import { cleanupGroupTeamInvitation } from "../../../data-graphs/invitations.js";
import { TEST_GROUP_IDS, TEST_USER_IDS } from "../../../seed.js";
import {
  confirmAlert,
  expectPaginationNavigation,
  navigateToPath,
  waitForActionResponse,
} from "../../../utils.js";
import { inviteTeamMember } from "../../team-helpers.js";

const GROUP_VIEWER_TEAM_ROW = {
  key: { group_id: TEST_GROUP_IDS.community1.alpha, user_id: TEST_USER_IDS.groupViewer1 },
  table: "group_team",
};

test.describe("group dashboard team view", () => {
  test("organizer can move between group team result pages", async ({ organizerGroupPage }) => {
    // Paginate the seeded team rows with one result per page.
    await expectPaginationNavigation(
      organizerGroupPage,
      "/dashboard/group?tab=team&limit=1&offset=0",
      "#dashboard-content tbody tr",
    );
  });

  test("group team page shows seeded roles and last-admin protection", async ({ organizerGroupPage }) => {
    // Load the team tab before checking team permissions.
    await navigateToPath(organizerGroupPage, "/dashboard/group?tab=team");

    // Find the dashboard content.
    const dashboardContent = organizerGroupPage.locator("#dashboard-content");

    // Verify group team page shows seeded roles and last-admin protection.
    await expect(dashboardContent.getByText("Group Team", { exact: true })).toBeVisible();
    await expect(dashboardContent.getByRole("button", { name: "Add member" })).toBeEnabled();

    // Find the admin row.
    const adminRow = dashboardContent.locator("tr", {
      hasText: "E2E Organizer One",
    });
    await expect(adminRow.locator("select")).toBeDisabled();
    await expect(adminRow.locator("select")).toHaveAttribute(
      "title",
      "At least one accepted admin is required.",
    );

    // Find the events manager row.
    const eventsManagerRow = dashboardContent.locator("tr", {
      hasText: "E2E Events Manager One",
    });
    await expect(eventsManagerRow.locator('select[name="role"]')).toHaveValue("events-manager");

    // Find the viewer row.
    const viewerRow = dashboardContent.locator("tr", {
      hasText: "E2E Group Viewer One",
    });
    await expect(viewerRow.locator('select[name="role"]')).toHaveValue("viewer");
  });

  test("organizer can invite and remove a pending group team member @smoke", async ({
    notifications,
    organizerGroupPage,
  }) => {
    try {
      // Clear any leftover pending invitation before the invite flow.
      cleanupGroupTeamInvitation({
        groupId: TEST_GROUP_IDS.community1.alpha,
        userId: TEST_USER_IDS.pending1,
      });

      // Invite the pending user as a viewer through the add member form.
      const pendingRow = await inviteTeamMember(organizerGroupPage, {
        fullName: "E2E Pending One",
        role: "viewer",
        scope: "group",
        username: "e2e-pending-1",
      });
      notifications.expectNew([
        {
          kind: "group-team-invitation",
          templateDataContains: { group: { group_id: TEST_GROUP_IDS.community1.alpha } },
          userIds: [TEST_USER_IDS.pending1],
        },
      ]);

      // Verify the pending member keeps the invited role.
      await expect(pendingRow.locator('select[name="role"]')).toHaveValue("viewer");

      // Find the remove button.
      const removeButton = pendingRow.locator(`#remove-member-${TEST_USER_IDS.pending1}`);
      await pendingRow.locator('summary[aria-label="Open team member actions for E2E Pending One"]').click();
      await removeButton.click();

      // Click Yes.
      await waitForActionResponse(
        organizerGroupPage,
        () =>
          confirmAlert(organizerGroupPage, {
            message: "Are you sure you would like to delete this team member?",
          }),
        {
          method: "DELETE",
          urlIncludes: `/dashboard/group/team/${TEST_USER_IDS.pending1}/delete`,
        },
      );

      // Assert how many matching elements are shown.
      await expect(pendingRow).toHaveCount(0);
    } finally {
      // Reset pending team state.
      cleanupGroupTeamInvitation({
        groupId: TEST_GROUP_IDS.community1.alpha,
        userId: TEST_USER_IDS.pending1,
      });
    }
  });

  test("organizer can update and restore a group team member role", async ({ organizerGroupPage }) => {
    // Define the seeded team member role that must be restored.
    const seededRole = "viewer";
    const updatedRole = "events-manager";
    const teamTabPath = "/dashboard/group?tab=team";

    // Restore the seeded viewer role after this check.
    await withRowRestore(GROUP_VIEWER_TEAM_ROW, async () => {
      // Load the team tab and target the seeded viewer role.
      await navigateToPath(organizerGroupPage, teamTabPath);

      // Find the dashboard content.
      const dashboardContent = organizerGroupPage.locator("#dashboard-content");
      const currentRoleSelect = dashboardContent
        .locator("tr", { hasText: "E2E Group Viewer One" })
        .locator('select[name="role"]');

      // Verify organizer can update and restore a group team member role.
      await expect(dashboardContent.getByText("Group Team", { exact: true })).toBeVisible();
      await expect(currentRoleSelect).toHaveValue(seededRole);

      // Submit and wait for the server response.
      await waitForActionResponse(organizerGroupPage, () => currentRoleSelect.selectOption(updatedRole), {
        method: "PUT",
        urlIncludes: "/dashboard/group/team/",
        urlEndsWith: "/role",
      });

      // Assert the field value was updated.
      await expect(currentRoleSelect).toHaveValue(updatedRole);
    });
  });
});
