import { expect, test } from "../../fixtures.js";

import { openUserDashboardPath, restoreCoSpeakerInvitation } from "../../dashboard/user/helpers.js";
import { TEST_USER_IDS, waitForActionResponse } from "../../utils.js";

test.describe("co-speaker invitation workflow", () => {
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

    // Click the accept invitation button.
    try {
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

    // Click the decline invitation button.
    try {
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
      if (invitationDeclined) {
        await restoreCoSpeakerInvitation(member1Page, "Collaborative Roadmaps", TEST_USER_IDS.member2);
      }
    }
  });
});
