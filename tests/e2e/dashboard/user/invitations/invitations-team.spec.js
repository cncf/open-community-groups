import { expect, test } from "../../../fixtures.js";

import { TEST_GROUP_IDS, TEST_USER_IDS } from "../../../seed.js";

import { waitForActionResponse } from "../../../utils.js";

import {
  clearCommunityInvitation,
  ensureGroupInvitation,
  openUserDashboardPath,
  resetCommunityInvitation,
  resetGroupInvitation,
} from "../helpers.js";

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

  test("invitations page shows pending community and group roles", async ({
    adminCommunityPage,
    pending1Page,
  }) => {
    // Reset seeded invitations before checking the pending roles.
    await resetCommunityInvitation(adminCommunityPage, TEST_USER_IDS.pending1, "viewer");
    await resetGroupInvitation(
      adminCommunityPage,
      TEST_GROUP_IDS.community1.beta,
      TEST_USER_IDS.pending1,
      "events-manager",
    );

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

  test("accepting pending invitations removes them from the user dashboard", async ({
    adminCommunityPage,
    pending1Page,
  }) => {
    // Reset seeded invitations before accepting them.
    await resetCommunityInvitation(adminCommunityPage, TEST_USER_IDS.pending1, "viewer");
    await resetGroupInvitation(
      adminCommunityPage,
      TEST_GROUP_IDS.community1.beta,
      TEST_USER_IDS.pending1,
      "events-manager",
    );

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

    try {
      // Accept the community invitation.
      await waitForActionResponse(pending1Page, () => approveCommunityInvitationButton.click(), {
        method: "PUT",
        urlEndsWith: "/accept",
        urlIncludes: "/dashboard/user/invitations/community/",
      });

      // Reload the invited user dashboard.
      await pending1Page.reload();

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
      await resetCommunityInvitation(adminCommunityPage, TEST_USER_IDS.pending1, "viewer");
      await resetGroupInvitation(
        adminCommunityPage,
        TEST_GROUP_IDS.community1.beta,
        TEST_USER_IDS.pending1,
        "events-manager",
      );

      // Open the user dashboard page.
      await openUserDashboardPath("/dashboard/user?tab=invitations", pending1Page);
      await expect(dashboardContent.locator("tr", { hasText: "e2e-test-community" })).toContainText("viewer");
      await expect(dashboardContent.locator("tr", { hasText: "Inactive Local Chapter" })).toContainText(
        "events-manager",
      );
    }
  });

  test("rejecting a pending group invitation removes it from the user dashboard", async ({
    organizerGroupPage,
    pending2Page,
  }) => {
    // Ensure the seeded group invitation exists before rejecting it.
    await ensureGroupInvitation(
      organizerGroupPage,
      TEST_GROUP_IDS.community1.alpha,
      TEST_USER_IDS.pending2,
      "viewer",
    );

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
      await expect(pending2Page.locator(".swal2-popup")).toContainText(
        "Are you sure you would like to reject this invitation?",
      );

      // Click Yes.
      await waitForActionResponse(
        pending2Page,
        () => pending2Page.getByRole("button", { name: "Yes" }).click(),
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
      // Restore the seeded group invitation for later tests.
      await ensureGroupInvitation(
        organizerGroupPage,
        TEST_GROUP_IDS.community1.alpha,
        TEST_USER_IDS.pending2,
        "viewer",
      );
    }
  });

  test("rejecting a pending community invitation removes it from the user dashboard", async ({
    adminCommunityPage,
    pending2Page,
  }) => {
    // Reset a pending community invitation before rejecting it.
    await resetCommunityInvitation(adminCommunityPage, TEST_USER_IDS.pending2, "viewer");

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
      await expect(pending2Page.locator(".swal2-popup")).toContainText(
        "Are you sure you would like to reject this invitation?",
      );

      // Click Yes.
      await waitForActionResponse(
        pending2Page,
        () => pending2Page.getByRole("button", { name: "Yes" }).click(),
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
      // Clear the rejected community invitation state.
      await clearCommunityInvitation(adminCommunityPage, TEST_USER_IDS.pending2);
    }
  });
});
