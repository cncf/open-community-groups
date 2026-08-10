import { expect, test } from "../../fixtures.js";

import {
  TEST_COMMUNITY_IDS,
  TEST_GROUP_IDS,
  TEST_USER_IDS,
  buildE2eUrl,
  navigateToPath,
  waitForActionResponse,
} from "../../utils.js";
import { openUserDashboardPath } from "../../dashboard/user/helpers.js";

// Invite a user to the current dashboard team through the add member form.
const inviteTeamMemberThroughForm = async (page, scope, username, fullName) => {
  await navigateToPath(page, `/dashboard/${scope}?tab=team`);

  // Open the add member form from the team tab.
  const dashboardContent = page.locator("#dashboard-content");
  await dashboardContent.getByRole("button", { name: "Add member" }).click();
  const addMemberForm = page.locator("#team-add-form");
  await expect(addMemberForm).toBeVisible();

  // Search the invitee and pick the matching user suggestion.
  await waitForActionResponse(page, () => addMemberForm.locator("#search-input").fill(username), {
    method: "GET",
    urlIncludes: `/dashboard/${scope}/users/search?q=${username}`,
  });
  await addMemberForm.getByText(fullName, { exact: true }).click();
  await addMemberForm.locator("#team-add-role").selectOption("viewer");

  // Submit the invitation and wait for it to be created.
  await waitForActionResponse(page, () => addMemberForm.locator("#team-add-submit").click(), {
    method: "POST",
    urlIncludes: `/dashboard/${scope}/team/add`,
    status: 201,
  });

  // Verify the invitee shows up as a pending team member.
  const pendingRow = dashboardContent.locator("tr", { hasText: fullName });
  await expect(pendingRow).toContainText("Invitation sent");
};

test.describe("team invitation workflow", () => {
  test("group team invitation is accepted end to end", async ({ organizerGroupPage, pending1Page }) => {
    try {
      // Invite the pending user to the group team through the dashboard UI.
      await inviteTeamMemberThroughForm(organizerGroupPage, "group", "e2e-pending-1", "E2E Pending One");

      // Open the invited user's invitations tab and accept the invitation.
      await openUserDashboardPath("/dashboard/user?tab=invitations", pending1Page);
      const inviteeContent = pending1Page.locator("#dashboard-content");
      // Event offer rows also mention the group name, so anchor the group
      // invitation row through its unique reject button id.
      const groupRejectButton = pending1Page.locator(
        `#reject-group-${TEST_GROUP_IDS.community1.alpha}`,
      );
      const groupInvitationRow = inviteeContent.locator("tr", { has: groupRejectButton });
      await expect(groupInvitationRow).toContainText("viewer");
      await waitForActionResponse(pending1Page, () => groupInvitationRow.getByTitle("Approve").click(), {
        method: "PUT",
        urlIncludes: `/dashboard/user/invitations/group/${TEST_GROUP_IDS.community1.alpha}`,
        urlEndsWith: "/accept",
      });

      // Verify the accepted invitation leaves the invitations tab.
      await pending1Page.reload();
      await expect(
        pending1Page.locator(`#reject-group-${TEST_GROUP_IDS.community1.alpha}`),
      ).toHaveCount(0);

      // Verify the organizer now sees the invitee as an accepted team member.
      await navigateToPath(organizerGroupPage, "/dashboard/group?tab=team");
      const acceptedRow = organizerGroupPage.locator("#dashboard-content tr", {
        hasText: "E2E Pending One",
      });
      await expect(acceptedRow).toBeVisible();
      await expect(acceptedRow).not.toContainText("Invitation sent");
    } finally {
      // Remove the temporary team member to restore the seeded state.
      await organizerGroupPage.request.delete(
        buildE2eUrl(`/dashboard/group/team/${TEST_USER_IDS.pending1}/delete`),
      );
    }
  });

  test("community team invitation is rejected end to end", async ({ adminCommunityPage, pending2Page }) => {
    try {
      // Invite the pending user to the community team through the dashboard UI.
      await inviteTeamMemberThroughForm(adminCommunityPage, "community", "e2e-pending-2", "E2E Pending Two");

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
      await expect(pending2Page.locator(".swal2-popup")).toContainText(
        "Are you sure you would like to reject this invitation?",
      );
      await waitForActionResponse(
        pending2Page,
        () => pending2Page.getByRole("button", { name: "Yes" }).click(),
        {
          method: "PUT",
          urlIncludes: "/dashboard/user/invitations/community/",
          urlEndsWith: "/reject",
        },
      );

      // Verify the rejected invitation leaves the invitations tab.
      await pending2Page.reload();
      await expect(
        pending2Page.locator(`#reject-community-${TEST_COMMUNITY_IDS.community1}`),
      ).toHaveCount(0);

      // Verify the admin no longer sees the invitee in the community team.
      await navigateToPath(adminCommunityPage, "/dashboard/community?tab=team");
      await expect(
        adminCommunityPage.locator("#dashboard-content tr", { hasText: "E2E Pending Two" }),
      ).toHaveCount(0);
    } finally {
      // Clear any leftover invitation to restore the seeded state.
      await adminCommunityPage.request.delete(
        buildE2eUrl(`/dashboard/community/team/${TEST_USER_IDS.pending2}/delete`),
      );
    }
  });
});
