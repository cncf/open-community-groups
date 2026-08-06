import { expect, test } from "../../../fixtures.js";

import {
  buildE2eUrl,
  TEST_COMMUNITY_NAME,
  TEST_EVENT_IDS,
  TEST_GROUP_IDS,
  TEST_USER_IDS,
} from "../../../utils.js";

import {
  clearCommunityInvitation,
  clearEventAttendeeState,
  ensureGroupInvitation,
  ensureEventInvitation,
  openUserDashboardPath,
  resetCommunityInvitation,
  resetGroupInvitation,
} from "../helpers.js";

// Open the actions menu for an event offer row.
const openEventOfferActions = async (offerRow) => {
  await offerRow.getByLabel(/Open offer actions/).click();
};

test.describe("user dashboard invitations view", () => {
  test("invitations page shows pending community and group roles", async ({
    adminCommunityPage,
    pending1Page,
  }) => {
    // Reset seeded invitations before checking the pending roles.
    await resetCommunityInvitation(
      adminCommunityPage,
      TEST_USER_IDS.pending1,
      "viewer",
    );
    await resetGroupInvitation(
      adminCommunityPage,
      TEST_GROUP_IDS.community1.beta,
      TEST_USER_IDS.pending1,
      "events-manager",
    );

    // Open the user dashboard page.
    await openUserDashboardPath(
      "/dashboard/user?tab=invitations",
      pending1Page,
    );

    // Find the dashboard content.
    const dashboardContent = pending1Page.locator("#dashboard-content");

    // Verify invitations page shows pending community and group roles.
    await expect(
      dashboardContent.getByText("Community Invitations", { exact: true }),
    ).toBeVisible();
    await expect(
      dashboardContent.getByText("Group Invitations", { exact: true }),
    ).toBeVisible();

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
    await resetCommunityInvitation(
      adminCommunityPage,
      TEST_USER_IDS.pending1,
      "viewer",
    );
    await resetGroupInvitation(
      adminCommunityPage,
      TEST_GROUP_IDS.community1.beta,
      TEST_USER_IDS.pending1,
      "events-manager",
    );

    // Open the user dashboard page.
    await openUserDashboardPath(
      "/dashboard/user?tab=invitations",
      pending1Page,
    );

    // Find the dashboard content.
    const dashboardContent = pending1Page.locator("#dashboard-content");
    const communityInvitationRow = dashboardContent.locator("tr", {
      hasText: "e2e-test-community",
    });
    const approveCommunityInvitationButton =
      communityInvitationRow.getByTitle("Approve");

    // Verify accepting pending invitations removes them from the user dashboard.
    await expect(approveCommunityInvitationButton).toBeVisible();

    // Click the approve community invitation button.
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

      // Reload the invited user dashboard.
      await pending1Page.reload();

      // Find the group invitation row.
      const groupInvitationRow = dashboardContent.locator("tr", {
        hasText: "Inactive Local Chapter",
      });
      const approveGroupInvitationButton =
        groupInvitationRow.getByTitle("Approve");
      await expect(approveGroupInvitationButton).toBeVisible();

      // Click the approve group invitation button.
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

      // Reload the invited user dashboard.
      await pending1Page.reload();

      // Assert how many matching elements are shown.
      await expect(
        dashboardContent.locator("tr", { hasText: "e2e-test-community" }),
      ).toHaveCount(0);
      await expect(
        dashboardContent.locator("tr", { hasText: "Inactive Local Chapter" }),
      ).toHaveCount(0);
    } finally {
      await resetCommunityInvitation(
        adminCommunityPage,
        TEST_USER_IDS.pending1,
        "viewer",
      );
      await resetGroupInvitation(
        adminCommunityPage,
        TEST_GROUP_IDS.community1.beta,
        TEST_USER_IDS.pending1,
        "events-manager",
      );

      // Open the user dashboard page.
      await openUserDashboardPath(
        "/dashboard/user?tab=invitations",
        pending1Page,
      );
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
    // Ensure the seeded group invitation exists before rejecting it.
    await ensureGroupInvitation(
      organizerGroupPage,
      TEST_GROUP_IDS.community1.alpha,
      TEST_USER_IDS.pending2,
      "viewer",
    );

    // Open the user dashboard page.
    await openUserDashboardPath(
      "/dashboard/user?tab=invitations",
      pending2Page,
    );

    // Find the dashboard content.
    const dashboardContent = pending2Page.locator("#dashboard-content");
    const rejectGroupInvitationButton = dashboardContent.locator(
      `#reject-group-${TEST_GROUP_IDS.community1.alpha}`,
    );

    // Restore the page state after the check.
    try {
      // Verify rejecting a pending group invitation removes it from the user dashboard.
      await expect(
        dashboardContent.getByText("Group Invitations", { exact: true }),
      ).toBeVisible();
      await expect(rejectGroupInvitationButton).toBeVisible();

      // Click the reject group invitation button.
      await rejectGroupInvitationButton.click();
      await expect(pending2Page.locator(".swal2-popup")).toContainText(
        "Are you sure you would like to reject this invitation?",
      );

      // Click Yes.
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

      // Reload the invited user dashboard.
      await pending2Page.reload();

      // Verify the group invitation is gone while similarly named event rows may remain.
      await expect(rejectGroupInvitationButton).toHaveCount(0);
    } finally {
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
    await resetCommunityInvitation(
      adminCommunityPage,
      TEST_USER_IDS.pending2,
      "viewer",
    );

    // Open the user dashboard page.
    await openUserDashboardPath(
      "/dashboard/user?tab=invitations",
      pending2Page,
    );

    // Find the dashboard content.
    const dashboardContent = pending2Page.locator("#dashboard-content");
    const communityInvitationRow = dashboardContent.locator("tr", {
      hasText: "e2e-test-community",
    });
    const rejectCommunityInvitationButton =
      communityInvitationRow.getByTitle("Reject");

    try {
      // Verify rejecting a pending community invitation removes it from the user dashboard.
      await expect(
        dashboardContent.getByText("Community Invitations", { exact: true }),
      ).toBeVisible();
      await expect(rejectCommunityInvitationButton).toBeVisible();

      // Click the reject community invitation button.
      await rejectCommunityInvitationButton.click();
      await expect(pending2Page.locator(".swal2-popup")).toContainText(
        "Are you sure you would like to reject this invitation?",
      );

      // Click Yes.
      await Promise.all([
        pending2Page.waitForResponse(
          (response) =>
            response.request().method() === "PUT" &&
            response.ok() &&
            response.url().includes("/dashboard/user/invitations/community/") &&
            response.url().endsWith("/reject"),
        ),
        pending2Page.getByRole("button", { name: "Yes" }).click(),
      ]);

      // Reload the invited user dashboard.
      await pending2Page.reload();

      // Assert how many matching elements are shown.
      await expect(
        dashboardContent.locator("tr", { hasText: "e2e-test-community" }),
      ).toHaveCount(0);
    } finally {
      await clearCommunityInvitation(
        adminCommunityPage,
        TEST_USER_IDS.pending2,
      );
    }
  });

  test("claiming an event invitation through checkout removes it from the user dashboard", async ({
    organizerGroupPage,
    pending1Page,
  }) => {
    // Ensure the seeded event invitation exists before accepting it.
    await ensureEventInvitation(
      organizerGroupPage,
      TEST_GROUP_IDS.community1.alpha,
      TEST_EVENT_IDS.alpha.two,
      TEST_USER_IDS.pending1,
    );

    // Open the user dashboard page.
    await openUserDashboardPath(
      "/dashboard/user?tab=invitations",
      pending1Page,
    );

    // Find the dashboard content.
    const dashboardContent = pending1Page.locator("#dashboard-content");
    const eventInvitationRow = dashboardContent.locator("tr", {
      hasText: "Upcoming Virtual Event",
    });
    try {
      // Verify the invitation is exposed as a checkout-owned RSVP offer.
      await expect(
        dashboardContent.getByText("Event Invitations", { exact: true }),
      ).toBeVisible();
      await expect(eventInvitationRow).toContainText("Platform Ops Meetup");
      await openEventOfferActions(eventInvitationRow);
      const claimEventInvitationButton = eventInvitationRow.getByRole(
        "menuitem",
        {
          name: "Claim offer",
        },
      );
      await expect(claimEventInvitationButton).toBeVisible();

      // Open the offer claim modal.
      await claimEventInvitationButton.click();
      const claimModal = pending1Page.getByRole("dialog", {
        name: "Claim offer",
      });
      await expect(claimModal).toBeVisible();

      // Complete the free offer through the unified checkout endpoint.
      await Promise.all([
        pending1Page.waitForResponse(
          (response) =>
            response.request().method() === "POST" &&
            response.ok() &&
            response
              .url()
              .includes(`/event/${TEST_EVENT_IDS.alpha.two}/checkout`),
        ),
        claimModal
          .getByRole("button", { name: "Claim offer", exact: true })
          .click(),
      ]);

      // Reload the invited user dashboard.
      await pending1Page.reload();

      // Assert how many matching elements are shown.
      await expect(
        dashboardContent.locator("tr", { hasText: "Upcoming Virtual Event" }),
      ).toHaveCount(0);
    } finally {
      await pending1Page.request.post(
        buildE2eUrl(
          `/${TEST_COMMUNITY_NAME}/event/${TEST_EVENT_IDS.alpha.two}/attend`,
        ),
        { form: {} },
      );
      await clearEventAttendeeState(
        organizerGroupPage,
        TEST_EVENT_IDS.alpha.two,
        TEST_USER_IDS.pending1,
      );
    }
  });

  test("claiming a waitlist offer completes through checkout", async ({
    member2Page,
    organizerGroupPage,
  }) => {
    const eventId = TEST_EVENT_IDS.alpha.dashboardWaitlist;

    try {
      // Free the only seat so reconciliation promotes the seeded waitlist entry.
      await clearEventAttendeeState(
        organizerGroupPage,
        eventId,
        TEST_USER_IDS.organizer1,
      );

      // Open the promoted user's invitations and target the waitlist offer.
      await openUserDashboardPath(
        "/dashboard/user?tab=invitations",
        member2Page,
      );
      const dashboardContent = member2Page.locator("#dashboard-content");
      const offerRow = dashboardContent.locator("tr", {
        hasText: "Dashboard Waitlist Table Lab",
      });
      await expect(offerRow).toContainText("Waiting list offer");

      // Claim the promoted seat through the unified checkout endpoint.
      await openEventOfferActions(offerRow);
      await offerRow.getByRole("menuitem", { name: "Claim offer" }).click();
      const claimModal = member2Page.getByRole("dialog", {
        name: "Claim offer",
      });
      await expect(claimModal).toBeVisible();
      await Promise.all([
        member2Page.waitForResponse(
          (response) =>
            response.request().method() === "POST" &&
            response.ok() &&
            response.url().includes(`/event/${eventId}/checkout`),
        ),
        claimModal
          .getByRole("button", { name: "Claim offer", exact: true })
          .click(),
      ]);
      await expect(offerRow).toHaveCount(0);
    } finally {
      // Restore the seeded full-event state for repeatable local runs.
      await clearEventAttendeeState(
        organizerGroupPage,
        eventId,
        TEST_USER_IDS.member2,
      );
      const restoreResponse = await organizerGroupPage.request.post(
        buildE2eUrl(`/${TEST_COMMUNITY_NAME}/event/${eventId}/attend`),
        { form: {} },
      );
      expect(restoreResponse.ok()).toBeTruthy();
      const restoreWaitlistResponse = await member2Page.request.post(
        buildE2eUrl(`/${TEST_COMMUNITY_NAME}/event/${eventId}/attend`),
        { form: {} },
      );
      expect(restoreWaitlistResponse.ok()).toBeTruthy();
    }
  });

  test("rejecting an event invitation removes it from the user dashboard", async ({
    organizerGroupPage,
    pending1Page,
  }) => {
    // Ensure the seeded event invitation exists before rejecting it.
    await ensureEventInvitation(
      organizerGroupPage,
      TEST_GROUP_IDS.community1.alpha,
      TEST_EVENT_IDS.alpha.two,
      TEST_USER_IDS.pending1,
    );

    // Open the user dashboard page.
    await openUserDashboardPath(
      "/dashboard/user?tab=invitations",
      pending1Page,
    );

    // Find the dashboard content.
    const dashboardContent = pending1Page.locator("#dashboard-content");
    const eventInvitationRow = dashboardContent.locator("tr", {
      hasText: "Upcoming Virtual Event",
    });
    try {
      // Verify rejecting an event invitation removes it from the dashboard.
      await expect(
        dashboardContent.getByText("Event Invitations", { exact: true }),
      ).toBeVisible();
      await expect(eventInvitationRow).toContainText("Platform Ops Meetup");
      await openEventOfferActions(eventInvitationRow);
      const rejectEventInvitationButton = eventInvitationRow.getByRole(
        "menuitem",
        {
          exact: true,
          name: "Decline offer",
        },
      );
      await expect(rejectEventInvitationButton).toBeVisible();

      // Click the reject event invitation button.
      await rejectEventInvitationButton.click();
      await expect(pending1Page.locator(".swal2-popup")).toContainText(
        "Are you sure you would like to decline this offer?",
      );

      // Click Yes.
      await Promise.all([
        pending1Page.waitForResponse(
          (response) =>
            response.request().method() === "PUT" &&
            response.ok() &&
            response
              .url()
              .includes("/dashboard/user/invitations/event-offers/") &&
            response.url().endsWith("/decline"),
        ),
        pending1Page.getByRole("button", { name: "Yes" }).click(),
      ]);

      // Reload the invited user dashboard.
      await pending1Page.reload();

      // Assert how many matching elements are shown.
      await expect(
        dashboardContent.locator("tr", { hasText: "Upcoming Virtual Event" }),
      ).toHaveCount(0);
    } finally {
      await pending1Page.request.post(
        buildE2eUrl(
          `/${TEST_COMMUNITY_NAME}/event/${TEST_EVENT_IDS.alpha.two}/attend`,
        ),
        { form: {} },
      );
      await clearEventAttendeeState(
        organizerGroupPage,
        TEST_EVENT_IDS.alpha.two,
        TEST_USER_IDS.pending1,
      );
    }
  });
});
