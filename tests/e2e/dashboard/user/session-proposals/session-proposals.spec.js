import { expect, test } from "../../../fixtures.js";

import { TEST_USER_IDS } from "../../../utils.js";

import {
  createSessionProposal,
  openUserDashboardPath,
  restoreCoSpeakerInvitation,
} from "../helpers.js";

test.describe("user dashboard session proposals view", () => {
  test("session proposals page shows seeded proposal states and locks", async ({
    member1Page,
  }) => {
    // Load the session proposals tab before checking seeded states.
    await openUserDashboardPath(
      "/dashboard/user?tab=session-proposals",
      member1Page,
    );

    // Find the dashboard content.
    const dashboardContent = member1Page.locator("#dashboard-content");

    // Verify session proposals page shows seeded proposal states and locks.
    await expect(
      dashboardContent.getByText("Session proposals", { exact: true }),
    ).toBeVisible();
    await expect(
      dashboardContent.getByRole("button", { name: "New proposal" }),
    ).toBeVisible();

    // Find the ready row.
    const readyRow = dashboardContent.locator("tr", {
      hasText: "Cloud Native Operations Deep Dive",
    });
    await expect(readyRow).toContainText("Ready for submission");
    await expect(readyRow.getByTitle("Delete proposal")).toBeEnabled();

    // Find the submitted row.
    const submittedRow = dashboardContent.locator("tr", {
      hasText: "Platform Reliability Patterns",
    });
    await expect(submittedRow).toContainText("Submitted");
    await expect(
      submittedRow.getByTitle("Submitted proposals cannot be deleted"),
    ).toBeDisabled();

    // Find the linked row.
    const linkedRow = dashboardContent.locator("tr", {
      hasText: "Scaling Community Workshops",
    });
    await expect(linkedRow).toContainText("Linked");
    await expect(
      linkedRow.getByTitle("Linked proposals cannot be edited"),
    ).toBeDisabled();

    // Find the pending row.
    const pendingRow = dashboardContent.locator("tr", {
      hasText: "Collaborative Roadmaps",
    });
    await expect(pendingRow).toContainText(
      /Awaiting co-speaker response|Ready for submission/,
    );

    // Find the declined row.
    const declinedRow = dashboardContent.locator("tr", {
      hasText: "Co-Speaker Retrospective",
    });
    await expect(declinedRow).toContainText("Declined by co-speaker");
  });

  test("user can create and delete a session proposal", async ({
    pending1Page,
  }) => {
    // Create a unique proposal title for the temporary proposal flow.
    const proposalTitle = `Pending1 reusable proposal ${Date.now()}`;
    const dashboardContent = await createSessionProposal(
      pending1Page,
      proposalTitle,
    );

    // Find the proposal row.
    const proposalRow = dashboardContent.locator("tr", {
      hasText: proposalTitle,
    });

    // Verify user can create and delete a session proposal.
    await expect(proposalRow).toContainText("Ready for submission");

    // Find the delete proposal button.
    const deleteProposalButton = proposalRow.getByTitle("Delete proposal");
    await expect(deleteProposalButton).toBeVisible();

    // Click the delete proposal button.
    await deleteProposalButton.click();
    await expect(pending1Page.locator(".swal2-popup")).toBeVisible();

    // Click Delete.
    await Promise.all([
      pending1Page.waitForResponse(
        (response) =>
          response.request().method() === "DELETE" &&
          response.url().includes("/dashboard/user/session-proposals/") &&
          response.ok(),
      ),
      pending1Page.getByRole("button", { name: "Delete" }).click(),
    ]);

    // Assert how many matching elements are shown.
    await expect(
      dashboardContent.locator("tr", { hasText: proposalTitle }),
    ).toHaveCount(0);
  });

  test("pending co-speaker invitations are surfaced to the invited user", async ({
    member2Page,
  }) => {
    // Load the invited user's session proposals tab.
    await openUserDashboardPath(
      "/dashboard/user?tab=session-proposals",
      member2Page,
    );

    // Find the dashboard content.
    const dashboardContent = member2Page.locator("#dashboard-content");
    const invitationAlert = dashboardContent.locator("[role='alert']");
    const invitationRow = dashboardContent.locator("tr", {
      hasText: "Collaborative Roadmaps",
    });

    // Verify pending co-speaker invitations are surfaced to the invited user.
    await expect(invitationAlert).toContainText(
      "co-speaker invitation waiting for your response",
    );
    await expect(invitationRow).toContainText("E2E Member One");
    await expect(invitationRow.getByTitle("View proposal")).toBeVisible();
    await expect(invitationRow.getByTitle("Accept invitation")).toBeVisible();
    await expect(invitationRow.getByTitle("Decline invitation")).toBeVisible();
  });

  test("accepting a co-speaker invitation updates both users' proposal views", async ({
    member1Page,
    member2Page,
  }) => {
    // Load the invited user's session proposals tab before accepting.
    await openUserDashboardPath(
      "/dashboard/user?tab=session-proposals",
      member2Page,
    );

    // Find the member2 dashboard.
    const member2Dashboard = member2Page.locator("#dashboard-content");
    const invitationRow = member2Dashboard.locator("tr", {
      hasText: "Collaborative Roadmaps",
    });
    const acceptInvitationButton =
      invitationRow.getByTitle("Accept invitation");

    // Verify accepting a co-speaker invitation updates both users' proposal views.
    await expect(member2Dashboard.locator("[role='alert']")).toContainText(
      "co-speaker invitation waiting for your response",
    );
    await expect(invitationRow).toContainText("E2E Member One");
    await expect(acceptInvitationButton).toBeVisible();

    // Set up invitation accepted.
    let invitationAccepted = false;

    // Click the accept invitation button.
    try {
      await Promise.all([
        member2Page.waitForResponse(
          (response) =>
            response.request().method() === "PUT" &&
            response.ok() &&
            response.url().includes("/co-speaker-invitation/accept"),
        ),
        acceptInvitationButton.click(),
      ]);
      invitationAccepted = true;

      // Reload the member dashboard.
      await member2Page.reload();
      await expect(member2Dashboard.locator("[role='alert']")).toHaveCount(0);
      await expect(
        member2Dashboard.locator("tr", { hasText: "Collaborative Roadmaps" }),
      ).toHaveCount(0);

      // Open the user dashboard page.
      await openUserDashboardPath(
        "/dashboard/user?tab=session-proposals",
        member1Page,
      );

      // Find the member1 dashboard.
      const member1Dashboard = member1Page.locator("#dashboard-content");
      const proposalRow = member1Dashboard.locator("tr", {
        hasText: "Collaborative Roadmaps",
      });

      // Assert the expected text is rendered.
      await expect(proposalRow).toContainText("E2E Member Two");
      await expect(proposalRow).toContainText("Ready for submission");
      await expect(proposalRow).not.toContainText(
        "Awaiting co-speaker response",
      );
    } finally {
      if (invitationAccepted) {
        await restoreCoSpeakerInvitation(
          member1Page,
          "Collaborative Roadmaps",
          TEST_USER_IDS.member2,
        );

        // Open the user dashboard page.
        await openUserDashboardPath(
          "/dashboard/user?tab=session-proposals",
          member2Page,
        );
        await expect(member2Dashboard.locator("[role='alert']")).toContainText(
          "co-speaker invitation waiting for your response",
        );
        await expect(
          member2Dashboard.locator("tr", {
            hasText: "Collaborative Roadmaps",
          }),
        ).toContainText("E2E Member One");
      }
    }
  });

  test("declining a co-speaker invitation updates both users' proposal views", async ({
    member1Page,
    member2Page,
  }) => {
    // Load the invited user's session proposals tab before declining.
    await openUserDashboardPath(
      "/dashboard/user?tab=session-proposals",
      member2Page,
    );

    // Find the member2 dashboard.
    const member2Dashboard = member2Page.locator("#dashboard-content");
    const invitationRow = member2Dashboard.locator("tr", {
      hasText: "Collaborative Roadmaps",
    });
    const declineInvitationButton =
      invitationRow.getByTitle("Decline invitation");

    // Verify the co-speaker invitation can be declined.
    await expect(member2Dashboard.locator("[role='alert']")).toContainText(
      "co-speaker invitation waiting for your response",
    );
    await expect(invitationRow).toContainText("E2E Member One");
    await expect(declineInvitationButton).toBeVisible();

    // Set up invitation declined.
    let invitationDeclined = false;

    // Click the decline invitation button.
    try {
      await declineInvitationButton.click();
      await expect(member2Page.locator(".swal2-popup")).toContainText(
        "Are you sure you want to decline this co-speaker invitation?",
      );

      // Confirm decline.
      await Promise.all([
        member2Page.waitForResponse(
          (response) =>
            response.request().method() === "PUT" &&
            response.ok() &&
            response.url().includes("/co-speaker-invitation/reject"),
        ),
        member2Page.getByRole("button", { name: "Decline" }).click(),
      ]);
      invitationDeclined = true;

      // Reload the invited user dashboard.
      await member2Page.reload();
      await expect(member2Dashboard.locator("[role='alert']")).toHaveCount(0);
      await expect(
        member2Dashboard.locator("tr", { hasText: "Collaborative Roadmaps" }),
      ).toHaveCount(0);

      // Open the owner dashboard page and verify declined state.
      await openUserDashboardPath(
        "/dashboard/user?tab=session-proposals",
        member1Page,
      );
      const member1Dashboard = member1Page.locator("#dashboard-content");
      const proposalRow = member1Dashboard.locator("tr", {
        hasText: "Collaborative Roadmaps",
      });
      await expect(proposalRow).toContainText("Declined by co-speaker");
    } finally {
      if (invitationDeclined) {
        await restoreCoSpeakerInvitation(
          member1Page,
          "Collaborative Roadmaps",
          TEST_USER_IDS.member2,
        );
      }
    }
  });
});
