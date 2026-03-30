import { expect, test } from "../../../fixtures";

import { TEST_GROUP_IDS, TEST_USER_IDS } from "../../../utils";

import {
  ensureGroupInvitation,
  openUserDashboardPath,
  resetCommunityInvitation,
  resetGroupInvitation,
} from "../helpers";

test.describe("user dashboard invitations view", () => {
  test("invitations page shows pending community and group roles", async ({
    adminCommunityPage,
    pending1Page,
  }) => {
    await resetCommunityInvitation(adminCommunityPage, TEST_USER_IDS.pending1, "viewer");
    await resetGroupInvitation(
      adminCommunityPage,
      TEST_GROUP_IDS.community1.beta,
      TEST_USER_IDS.pending1,
      "events-manager",
    );

    await openUserDashboardPath("/dashboard/user?tab=invitations", pending1Page);

    const dashboardContent = pending1Page.locator("#dashboard-content");
    await expect(
      dashboardContent.getByText("Community Invitations", { exact: true }),
    ).toBeVisible();
    await expect(
      dashboardContent.getByText("Group Invitations", { exact: true }),
    ).toBeVisible();

    const communityRow = dashboardContent.locator("tr", {
      hasText: "e2e-test-community",
    });
    await expect(communityRow).toContainText("viewer");
    await expect(communityRow.getByTitle("Approve")).toBeVisible();
    await expect(communityRow.getByTitle("Reject")).toBeVisible();

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
    await resetCommunityInvitation(adminCommunityPage, TEST_USER_IDS.pending1, "viewer");
    await resetGroupInvitation(
      adminCommunityPage,
      TEST_GROUP_IDS.community1.beta,
      TEST_USER_IDS.pending1,
      "events-manager",
    );

    await openUserDashboardPath("/dashboard/user?tab=invitations", pending1Page);

    const dashboardContent = pending1Page.locator("#dashboard-content");
    const communityInvitationRow = dashboardContent.locator("tr", {
      hasText: "e2e-test-community",
    });
    const approveCommunityInvitationButton =
      communityInvitationRow.getByTitle("Approve");
    await expect(approveCommunityInvitationButton).toBeVisible();

    try {
      await Promise.all([
        pending1Page.waitForResponse(
          (response) =>
            response.request().method() === "PUT" &&
            response.ok() &&
            response.url().includes("/dashboard/user/invitations/community/") &&
            response.url().endsWith("/accept"),
        ),
        approveCommunityInvitationButton.click(),
      ]);

      await pending1Page.reload();

      const groupInvitationRow = dashboardContent.locator("tr", {
        hasText: "Inactive Local Chapter",
      });
      const approveGroupInvitationButton = groupInvitationRow.getByTitle("Approve");
      await expect(approveGroupInvitationButton).toBeVisible();

      await Promise.all([
        pending1Page.waitForResponse(
          (response) =>
            response.request().method() === "PUT" &&
            response.ok() &&
            response.url().includes("/dashboard/user/invitations/group/") &&
            response.url().endsWith("/accept"),
        ),
        approveGroupInvitationButton.click(),
      ]);

      await pending1Page.reload();

      await expect(
        dashboardContent.locator("tr", { hasText: "e2e-test-community" }),
      ).toHaveCount(0);
      await expect(
        dashboardContent.locator("tr", { hasText: "Inactive Local Chapter" }),
      ).toHaveCount(0);
    } finally {
      await resetCommunityInvitation(adminCommunityPage, TEST_USER_IDS.pending1, "viewer");
      await resetGroupInvitation(
        adminCommunityPage,
        TEST_GROUP_IDS.community1.beta,
        TEST_USER_IDS.pending1,
        "events-manager",
      );

      await openUserDashboardPath("/dashboard/user?tab=invitations", pending1Page);
      await expect(
        dashboardContent.locator("tr", { hasText: "e2e-test-community" }),
      ).toContainText("viewer");
      await expect(
        dashboardContent.locator("tr", { hasText: "Inactive Local Chapter" }),
      ).toContainText("events-manager");
    }
  });

  test("rejecting a pending group invitation removes it from the user dashboard", async ({
    organizerGroupPage,
    pending2Page,
  }) => {
    await ensureGroupInvitation(
      organizerGroupPage,
      TEST_GROUP_IDS.community1.alpha,
      TEST_USER_IDS.pending2,
      "viewer",
    );

    await openUserDashboardPath("/dashboard/user?tab=invitations", pending2Page);

    const dashboardContent = pending2Page.locator("#dashboard-content");
    const groupInvitationRow = dashboardContent.locator("tr", {
      hasText: "Platform Ops Meetup",
    });
    const rejectGroupInvitationButton = groupInvitationRow.getByTitle("Reject");

    try {
      await expect(
        dashboardContent.getByText("Group Invitations", { exact: true }),
      ).toBeVisible();
      await expect(rejectGroupInvitationButton).toBeVisible();

      await rejectGroupInvitationButton.click();
      await expect(pending2Page.locator(".swal2-popup")).toContainText(
        "Are you sure you would like to reject this invitation?",
      );

      await Promise.all([
        pending2Page.waitForResponse(
          (response) =>
            response.request().method() === "PUT" &&
            response.ok() &&
            response.url().includes("/dashboard/user/invitations/group/") &&
            response.url().endsWith("/reject"),
        ),
        pending2Page.getByRole("button", { name: "Yes" }).click(),
      ]);

      await pending2Page.reload();

      await expect(
        dashboardContent.locator("tr", { hasText: "Platform Ops Meetup" }),
      ).toHaveCount(0);
    } finally {
      await ensureGroupInvitation(
        organizerGroupPage,
        TEST_GROUP_IDS.community1.alpha,
        TEST_USER_IDS.pending2,
        "viewer",
      );
    }
  });
});
