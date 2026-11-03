import { expect, test } from "../../../fixtures.js";
import { restoreRow, snapshotRow } from "../../../database.js";
import {
  cleanupCommunityTeamInvitation,
  countTeamInvitationAuditLogs,
  setupCommunityTeamInvitation,
  setupGroupTeamInvitation,
} from "../../../data-graphs/invitations.js";
import { TEST_COMMUNITY_IDS, TEST_COMMUNITY_TITLE, TEST_GROUP_IDS, TEST_USER_IDS } from "../../../seed.js";
import { buildE2eUrl, confirmAlert, navigateToPath, waitForActionResponse } from "../../../utils.js";
import { openUserDashboardPath } from "../helpers.js";

/** Seeded pending community viewer invitation of pending1. */
const PENDING1_COMMUNITY_INVITATION = {
  communityId: TEST_COMMUNITY_IDS.community1,
  role: "viewer",
  userId: TEST_USER_IDS.pending1,
};

/** Seeded pending group events-manager invitation of pending1. */
const PENDING1_GROUP_INVITATION = {
  groupId: TEST_GROUP_IDS.community1.beta,
  role: "events-manager",
  userId: TEST_USER_IDS.pending1,
};

/** Owned pending community viewer invitation of pending2. */
const PENDING2_COMMUNITY_INVITATION = {
  communityId: TEST_COMMUNITY_IDS.community1,
  role: "viewer",
  userId: TEST_USER_IDS.pending2,
};

/** Seeded pending group viewer invitation of pending2. */
const PENDING2_GROUP_INVITATION = {
  groupId: TEST_GROUP_IDS.community1.alpha,
  role: "viewer",
  userId: TEST_USER_IDS.pending2,
};

test.describe("user dashboard invitations view", () => {
  test("empty state covers every invitation category", async ({ emptyUserPage }) => {
    // Load invitations for the dedicated user without pending relationships.
    await openUserDashboardPath("/dashboard/user?tab=invitations", emptyUserPage);
    const dashboardContent = emptyUserPage.locator("#dashboard-content");

    // Verify each independently empty invitation table remains explicit.
    await expect(dashboardContent).toContainText("You don't have any pending community invitation.");
    await expect(dashboardContent).toContainText("You don't have any pending group invitation.");
    await expect(dashboardContent).toContainText("You don't have any pending event invitation.");
  });

  test("invitations page shows pending community and group roles", async ({ pending1Page }) => {
    // Open the user dashboard page.
    await openUserDashboardPath("/dashboard/user?tab=invitations", pending1Page);

    // Find the dashboard content.
    const dashboardContent = pending1Page.locator("#dashboard-content");

    // Verify invitations page shows pending community and group roles.
    await expect(dashboardContent.getByText("Community Invitations", { exact: true })).toBeVisible();
    await expect(dashboardContent.getByText("Group Invitations", { exact: true })).toBeVisible();

    // Find the community row.
    const communityRow = dashboardContent.locator("tr", {
      hasText: "e2e-test-community",
    });
    await expect(communityRow).toContainText("viewer");
    await expect(communityRow.getByTitle("Approve")).toBeVisible();
    await expect(communityRow.getByTitle("Reject")).toBeVisible();

    // Find the group row.
    const groupRow = dashboardContent.locator("tr", {
      hasText: "Inactive Local Chapter",
    });
    await expect(groupRow).toContainText("events-manager");
    await expect(groupRow.getByTitle("Approve")).toBeVisible();
    await expect(groupRow.getByTitle("Reject")).toBeVisible();
  });

  test("accepting pending invitations removes them from the user dashboard", async ({ pending1Page }) => {
    // Open the user dashboard page.
    await openUserDashboardPath("/dashboard/user?tab=invitations", pending1Page);

    // Find the dashboard content.
    const dashboardContent = pending1Page.locator("#dashboard-content");
    const communityInvitationRow = dashboardContent.locator("tr", {
      hasText: "e2e-test-community",
    });
    const approveCommunityInvitationButton = communityInvitationRow.getByTitle("Approve");

    // Verify accepting pending invitations removes them from the user dashboard.
    await expect(approveCommunityInvitationButton).toBeVisible();
    const communityAuditFilter = {
      action: "community_team_invitation_accepted",
      communityId: PENDING1_COMMUNITY_INVITATION.communityId,
      userId: PENDING1_COMMUNITY_INVITATION.userId,
    };
    const communityAuditCount = countTeamInvitationAuditLogs(communityAuditFilter);

    try {
      // Accept the community invitation.
      await waitForActionResponse(pending1Page, () => approveCommunityInvitationButton.click(), {
        method: "PUT",
        urlEndsWith: "/accept",
        urlIncludes: "/dashboard/user/invitations/community/",
      });
      expect(countTeamInvitationAuditLogs(communityAuditFilter)).toBe(communityAuditCount + 1);

      // Verify the accepted role opens the community dashboard with the community selected.
      await navigateToPath(pending1Page, "/dashboard/community");
      await expect(pending1Page).toHaveURL(buildE2eUrl("/dashboard/community"));
      await expect(pending1Page.locator("community-selector")).toHaveAttribute(
        "selected-community-id",
        PENDING1_COMMUNITY_INVITATION.communityId,
      );
      await expect(pending1Page.locator("#community-selector-button")).toContainText(TEST_COMMUNITY_TITLE);

      // Return to the invited user dashboard.
      await openUserDashboardPath("/dashboard/user?tab=invitations", pending1Page);

      // Find the group invitation row.
      const groupInvitationRow = dashboardContent.locator("tr", {
        hasText: "Inactive Local Chapter",
      });
      const approveGroupInvitationButton = groupInvitationRow.getByTitle("Approve");
      await expect(approveGroupInvitationButton).toBeVisible();

      // Click the approve group invitation button.
      await waitForActionResponse(pending1Page, () => approveGroupInvitationButton.click(), {
        method: "PUT",
        urlEndsWith: "/accept",
        urlIncludes: "/dashboard/user/invitations/group/",
      });

      // Reload the invited user dashboard.
      await pending1Page.reload();

      // Assert how many matching elements are shown.
      await expect(dashboardContent.locator("tr", { hasText: "e2e-test-community" })).toHaveCount(0);
      await expect(dashboardContent.locator("tr", { hasText: "Inactive Local Chapter" })).toHaveCount(0);
    } finally {
      // Restore both pending invitations for later tests.
      setupCommunityTeamInvitation(PENDING1_COMMUNITY_INVITATION);
      setupGroupTeamInvitation(PENDING1_GROUP_INVITATION);
    }
  });

  test("rejecting a pending group invitation removes it from the user dashboard", async ({
    pending2Page,
  }) => {
    // Snapshot the seeded invitation, which the rejection deletes.
    const invitationSnapshot = snapshotRow({
      key: { group_id: PENDING2_GROUP_INVITATION.groupId, user_id: PENDING2_GROUP_INVITATION.userId },
      table: "group_team",
    });

    // Open the user dashboard page.
    await openUserDashboardPath("/dashboard/user?tab=invitations", pending2Page);

    // Find the dashboard content.
    const dashboardContent = pending2Page.locator("#dashboard-content");
    const rejectGroupInvitationButton = dashboardContent.locator(
      `#reject-group-${TEST_GROUP_IDS.community1.alpha}`,
    );

    try {
      // Verify rejecting a pending group invitation removes it from the user dashboard.
      await expect(dashboardContent.getByText("Group Invitations", { exact: true })).toBeVisible();
      await expect(rejectGroupInvitationButton).toBeVisible();

      // Click the reject group invitation button.
      await rejectGroupInvitationButton.click();

      // Click Yes.
      await waitForActionResponse(
        pending2Page,
        () =>
          confirmAlert(pending2Page, { message: "Are you sure you would like to reject this invitation?" }),
        {
          method: "PUT",
          urlEndsWith: "/reject",
          urlIncludes: "/dashboard/user/invitations/group/",
        },
      );

      // Reload the invited user dashboard.
      await pending2Page.reload();

      // Verify the group invitation is gone while similarly named event rows may remain.
      await expect(rejectGroupInvitationButton).toHaveCount(0);
    } finally {
      // Re-create the seeded group invitation with its original values.
      setupGroupTeamInvitation(PENDING2_GROUP_INVITATION);
      restoreRow(invitationSnapshot);
    }
  });

  test("rejecting a pending community invitation removes it from the user dashboard", async ({
    pending2Page,
  }) => {
    // Create a pending community invitation before rejecting it.
    setupCommunityTeamInvitation(PENDING2_COMMUNITY_INVITATION);

    // Open the user dashboard page.
    await openUserDashboardPath("/dashboard/user?tab=invitations", pending2Page);

    // Find the dashboard content.
    const dashboardContent = pending2Page.locator("#dashboard-content");
    const communityInvitationRow = dashboardContent.locator("tr", {
      hasText: "e2e-test-community",
    });
    const rejectCommunityInvitationButton = communityInvitationRow.getByTitle("Reject");

    try {
      // Verify rejection removes the pending invitation from the user dashboard.
      await expect(dashboardContent.getByText("Community Invitations", { exact: true })).toBeVisible();
      await expect(rejectCommunityInvitationButton).toBeVisible();

      // Click the reject community invitation button.
      await rejectCommunityInvitationButton.click();

      // Click Yes.
      await waitForActionResponse(
        pending2Page,
        () =>
          confirmAlert(pending2Page, { message: "Are you sure you would like to reject this invitation?" }),
        {
          method: "PUT",
          urlEndsWith: "/reject",
          urlIncludes: "/dashboard/user/invitations/community/",
        },
      );

      // Reload the invited user dashboard.
      await pending2Page.reload();

      // Assert how many matching elements are shown.
      await expect(dashboardContent.locator("tr", { hasText: "e2e-test-community" })).toHaveCount(0);
    } finally {
      // Remove the owned community invitation if the rejection did not.
      cleanupCommunityTeamInvitation(PENDING2_COMMUNITY_INVITATION);
    }
  });
});
