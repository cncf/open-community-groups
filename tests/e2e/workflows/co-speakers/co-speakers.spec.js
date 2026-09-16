import { expect, test } from "../../fixtures.js";
import {
  createSessionProposal,
  openUserDashboardPath,
  restoreCoSpeakerInvitation,
} from "../../dashboard/user/helpers.js";
import { queryE2eDatabase } from "../../database.js";
import { deleteNotifications, expectNewNotifications, snapshotNotifications } from "../../notifications.js";
import { TEST_USER_IDS } from "../../seed.js";
import { uniqueName, waitForActionResponse } from "../../utils.js";

test.describe("co-speaker invitation workflow", () => {
  test("owner can invite a co-speaker to a reusable proposal", async ({ member2Page, pending1Page }) => {
    // Create a reusable proposal owned by Pending One.
    const proposalTitle = uniqueName("co-speaker invitation proposal");
    let notificationIds = [];

    try {
      // Create the proposal and resolve its identifier.
      await createSessionProposal(pending1Page, proposalTitle);
      const proposalId = readSessionProposalId(TEST_USER_IDS.pending1, proposalTitle);

      // Add Member Two as co-speaker and assert the invitation notification.
      const snapshot = snapshotNotifications();
      const inviteResponse = await pending1Page.request.put(
        `/dashboard/user/session-proposals/${proposalId}`,
        {
          form: {
            co_speaker_user_id: TEST_USER_IDS.member2,
            description: "A reusable proposal created from the e2e suite.",
            duration_minutes: "45",
            session_proposal_level_id: "intermediate",
            title: proposalTitle,
          },
        },
      );
      expect(inviteResponse.ok()).toBeTruthy();
      notificationIds = expectNewNotifications(snapshot, [
        {
          kind: "session-proposal-co-speaker-invitation",
          templateDataContains: {
            session_proposal_title: proposalTitle,
            speaker_name: "E2E Pending One",
          },
          userIds: [TEST_USER_IDS.member2],
        },
      ]);

      // Verify the invited user sees the new co-speaker invitation.
      await openUserDashboardPath("/dashboard/user?tab=session-proposals", member2Page);
      const member2Dashboard = member2Page.locator("#dashboard-content");
      await expect(member2Dashboard.locator("tr", { hasText: proposalTitle })).toContainText(
        "E2E Pending One",
      );
    } finally {
      // Remove generated notifications and proposal rows.
      deleteNotifications(notificationIds);
      deleteSessionProposalsByTitle(TEST_USER_IDS.pending1, [proposalTitle]);
    }
  });

  test("accepting a co-speaker invitation updates both users' proposal views", async ({
    member1Page,
    member2Page,
  }) => {
    // Load the invited user's session proposals tab before accepting.
    await openUserDashboardPath("/dashboard/user?tab=session-proposals", member2Page);

    // Find the member2 dashboard.
    const member2Dashboard = member2Page.locator("#dashboard-content");
    const invitationRow = member2Dashboard.locator("tr", {
      hasText: "Collaborative Roadmaps",
    });
    const acceptInvitationButton = invitationRow.getByTitle("Accept invitation");

    // Verify accepting a co-speaker invitation updates both users' proposal views.
    await expect(member2Dashboard.locator("[role='alert']")).toContainText(
      "co-speaker invitation waiting for your response",
    );
    await expect(invitationRow).toContainText("E2E Member One");
    await expect(acceptInvitationButton).toBeVisible();

    // Set up invitation accepted.
    let invitationAccepted = false;

    try {
      // Accept the invitation and mark the seeded invitation for restoration.
      await waitForActionResponse(member2Page, () => acceptInvitationButton.click(), {
        method: "PUT",
        urlIncludes: "/co-speaker-invitation/accept",
      });
      invitationAccepted = true;

      // Reload the member dashboard.
      await member2Page.reload();
      await expect(member2Dashboard.locator("[role='alert']")).toHaveCount(0);
      await expect(member2Dashboard.locator("tr", { hasText: "Collaborative Roadmaps" })).toHaveCount(0);

      // Open the user dashboard page.
      await openUserDashboardPath("/dashboard/user?tab=session-proposals", member1Page);

      // Find the member1 dashboard.
      const member1Dashboard = member1Page.locator("#dashboard-content");
      const proposalRow = member1Dashboard.locator("tr", {
        hasText: "Collaborative Roadmaps",
      });

      // Assert the expected text is rendered.
      await expect(proposalRow).toContainText("E2E Member Two");
      await expect(proposalRow).toContainText("Ready for submission");
      await expect(proposalRow).not.toContainText("Awaiting co-speaker response");
    } finally {
      // Restore the invitation when the acceptance changed seeded state.
      if (invitationAccepted) {
        await restoreCoSpeakerInvitation(member1Page, "Collaborative Roadmaps", TEST_USER_IDS.member2);

        // Open the user dashboard page.
        await openUserDashboardPath("/dashboard/user?tab=session-proposals", member2Page);
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
    await openUserDashboardPath("/dashboard/user?tab=session-proposals", member2Page);

    // Find the member2 dashboard.
    const member2Dashboard = member2Page.locator("#dashboard-content");
    const invitationRow = member2Dashboard.locator("tr", {
      hasText: "Collaborative Roadmaps",
    });
    const declineInvitationButton = invitationRow.getByTitle("Decline invitation");

    // Verify the co-speaker invitation can be declined.
    await expect(member2Dashboard.locator("[role='alert']")).toContainText(
      "co-speaker invitation waiting for your response",
    );
    await expect(invitationRow).toContainText("E2E Member One");
    await expect(declineInvitationButton).toBeVisible();

    // Set up invitation declined.
    let invitationDeclined = false;

    try {
      // Open the decline confirmation for the invited co-speaker.
      await declineInvitationButton.click();
      await expect(member2Page.locator(".swal2-popup")).toContainText(
        "Are you sure you want to decline this co-speaker invitation?",
      );

      // Confirm decline.
      await waitForActionResponse(
        member2Page,
        () => member2Page.getByRole("button", { name: "Decline" }).click(),
        {
          method: "PUT",
          urlIncludes: "/co-speaker-invitation/reject",
        },
      );
      invitationDeclined = true;

      // Reload the invited user dashboard.
      await member2Page.reload();
      await expect(member2Dashboard.locator("[role='alert']")).toHaveCount(0);
      await expect(member2Dashboard.locator("tr", { hasText: "Collaborative Roadmaps" })).toHaveCount(0);

      // Open the owner dashboard page and verify declined state.
      await openUserDashboardPath("/dashboard/user?tab=session-proposals", member1Page);
      const member1Dashboard = member1Page.locator("#dashboard-content");
      const proposalRow = member1Dashboard.locator("tr", {
        hasText: "Collaborative Roadmaps",
      });
      await expect(proposalRow).toContainText("Declined by co-speaker");
    } finally {
      // Restore the invitation when the decline changed seeded state.
      if (invitationDeclined) {
        await restoreCoSpeakerInvitation(member1Page, "Collaborative Roadmaps", TEST_USER_IDS.member2);
      }
    }
  });
});

/** Deletes matching session_proposal rows for the supplied user. */
const deleteSessionProposalsByTitle = (userId, proposalTitles) => {
  if (proposalTitles.length === 0) {
    return;
  }

  const titleList = proposalTitles.map((title) => `'${title.replace(/'/g, "''")}'`).join(", ");

  queryE2eDatabase(`
    delete from session_proposal
    where user_id = '${userId}'
    and title in (${titleList});
  `);
};

/** Returns a session_proposal identifier for the supplied user and title. */
const readSessionProposalId = (userId, proposalTitle) => {
  const escapedTitle = proposalTitle.replace(/'/g, "''");

  return queryE2eDatabase(`
    select session_proposal_id
    from session_proposal
    where user_id = '${userId}'
    and title = '${escapedTitle}'
  `);
};
