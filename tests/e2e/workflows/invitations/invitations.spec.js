import { expect, test } from "../../fixtures.js";
import {
  cleanupCommunityTeamInvitation,
  cleanupGroupTeamMember,
  countTeamInvitationAuditLogs,
} from "../../data-graphs/invitations.js";
import { inviteTeamMember } from "../../dashboard/team-helpers.js";
import { openUserDashboardPath } from "../../dashboard/user/helpers.js";
import { TEST_COMMUNITY_IDS, TEST_GROUP_IDS, TEST_GROUP_NAMES, TEST_USER_IDS } from "../../seed.js";
import {
  buildE2eUrl,
  confirmAlert,
  dismissAlert,
  navigateToPath,
  waitForActionResponse,
} from "../../utils.js";

// Destination of privileged dashboards for users without an accepted team role.
const USER_INVITATIONS_URL = buildE2eUrl("/dashboard/user?tab=invitations");

test.describe("team invitation workflow", () => {
  test("group team invitation is accepted end to end", async ({
    notifications,
    organizerGroupPage,
    pending1Page,
  }) => {
    const acceptedAuditFilter = {
      action: "group_team_invitation_accepted",
      groupId: TEST_GROUP_IDS.community1.alpha,
      userId: TEST_USER_IDS.pending1,
    };

    try {
      // Verify the invitee has no group dashboard access before accepting.
      await navigateToPath(pending1Page, "/dashboard/group");
      await expect(pending1Page).toHaveURL(USER_INVITATIONS_URL);

      // Invite the pending user to the group team through the dashboard UI.
      await inviteTeamMember(organizerGroupPage, {
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

      // Open the invited user's invitations tab and accept the invitation.
      await openUserDashboardPath("/dashboard/user?tab=invitations", pending1Page);
      const inviteeContent = pending1Page.locator("#dashboard-content");
      // Event offer rows also mention the group name, so anchor the group
      // invitation row through its unique reject button id.
      const groupRejectButton = pending1Page.locator(`#reject-group-${TEST_GROUP_IDS.community1.alpha}`);
      const groupInvitationRow = inviteeContent.locator("tr", { has: groupRejectButton });
      await expect(groupInvitationRow).toContainText("viewer");
      const acceptedAuditCount = countTeamInvitationAuditLogs(acceptedAuditFilter);
      await waitForActionResponse(pending1Page, () => groupInvitationRow.getByTitle("Approve").click(), {
        method: "PUT",
        urlIncludes: `/dashboard/user/invitations/group/${TEST_GROUP_IDS.community1.alpha}`,
        urlEndsWith: "/accept",
      });
      await dismissAlert(pending1Page, { message: "Team invitation accepted." });
      expect(countTeamInvitationAuditLogs(acceptedAuditFilter)).toBe(acceptedAuditCount + 1);

      // Verify the accepted invitation leaves the invitations tab.
      await pending1Page.reload();
      await expect(pending1Page.locator(`#reject-group-${TEST_GROUP_IDS.community1.alpha}`)).toHaveCount(0);

      // Verify the accepted role opens the group dashboard with the invited group selected.
      await navigateToPath(pending1Page, "/dashboard/group");
      await expect(pending1Page).toHaveURL(buildE2eUrl("/dashboard/group"));
      await expect(pending1Page.locator("group-selector")).toHaveAttribute(
        "selected-group-id",
        TEST_GROUP_IDS.community1.alpha,
      );
      await expect(pending1Page.locator("#group-selector-button")).toContainText(TEST_GROUP_NAMES.alpha);

      // Verify the organizer now sees the invitee as an accepted team member.
      await navigateToPath(organizerGroupPage, "/dashboard/group?tab=team");
      const acceptedRow = organizerGroupPage.locator("#dashboard-content tr", {
        hasText: "E2E Pending One",
      });
      await expect(acceptedRow).toBeVisible();
      await expect(acceptedRow).not.toContainText("Invitation sent");
    } finally {
      // Remove the accepted (or still pending) team row to restore the seeded state.
      cleanupGroupTeamMember({
        groupId: TEST_GROUP_IDS.community1.alpha,
        userId: TEST_USER_IDS.pending1,
      });
    }
  });

  test("community team invitation is rejected end to end", async ({
    adminCommunityPage,
    notifications,
    pending2Page,
  }) => {
    try {
      // Invite the pending user to the community team through the dashboard UI.
      await inviteTeamMember(adminCommunityPage, {
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

      // Open the invited user's invitations tab and reject the invitation.
      await openUserDashboardPath("/dashboard/user?tab=invitations", pending2Page);
      const inviteeContent = pending2Page.locator("#dashboard-content");
      // Anchor the community invitation row through its unique reject button.
      const communityRejectButton = pending2Page.locator(
        `#reject-community-${TEST_COMMUNITY_IDS.community1}`,
      );
      const communityInvitationRow = inviteeContent.locator("tr", { has: communityRejectButton });
      await expect(communityInvitationRow).toContainText("viewer");
      await communityInvitationRow.getByTitle("Reject").click();
      await waitForActionResponse(
        pending2Page,
        () =>
          confirmAlert(pending2Page, { message: "Are you sure you would like to reject this invitation?" }),
        {
          method: "PUT",
          urlIncludes: "/dashboard/user/invitations/community/",
          urlEndsWith: "/reject",
        },
      );
      await dismissAlert(pending2Page, { message: "Team invitation rejected." });

      // Verify the rejected invitation leaves the invitations tab.
      await pending2Page.reload();
      await expect(pending2Page.locator(`#reject-community-${TEST_COMMUNITY_IDS.community1}`)).toHaveCount(0);

      // Verify the rejection grants no community dashboard access.
      await navigateToPath(pending2Page, "/dashboard/community");
      await expect(pending2Page).toHaveURL(USER_INVITATIONS_URL);

      // Verify the admin no longer sees the invitee in the community team.
      await navigateToPath(adminCommunityPage, "/dashboard/community?tab=team");
      await expect(
        adminCommunityPage.locator("#dashboard-content tr", { hasText: "E2E Pending Two" }),
      ).toHaveCount(0);
    } finally {
      // Clear any leftover invitation to restore the seeded state.
      cleanupCommunityTeamInvitation({
        communityId: TEST_COMMUNITY_IDS.community1,
        userId: TEST_USER_IDS.pending2,
      });
    }
  });
});
