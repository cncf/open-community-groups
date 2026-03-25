import { expect, test } from "../../fixtures";

import { TEST_USER_IDS } from "../../utils";

import {
  createSessionProposal,
  openUserDashboardPath,
  restoreCoSpeakerInvitation,
} from "./helpers";

test.describe("user dashboard session proposals tab", () => {
  test("session proposals page shows seeded proposal states and locks", async ({
    member1Page,
  }) => {
    await openUserDashboardPath("/dashboard/user?tab=session-proposals", member1Page);

    const dashboardContent = member1Page.locator("#dashboard-content");
    await expect(
      dashboardContent.getByText("Session proposals", { exact: true }),
    ).toBeVisible();
    await expect(
      dashboardContent.getByRole("button", { name: "New proposal" }),
    ).toBeVisible();

    const readyRow = dashboardContent.locator("tr", {
      hasText: "Cloud Native Operations Deep Dive",
    });
    await expect(readyRow).toContainText("Ready for submission");
    await expect(readyRow.getByTitle("Delete proposal")).toBeEnabled();

    const submittedRow = dashboardContent.locator("tr", {
      hasText: "Platform Reliability Patterns",
    });
    await expect(submittedRow).toContainText("Submitted");
    await expect(
      submittedRow.getByTitle("Submitted proposals cannot be deleted"),
    ).toBeDisabled();

    const linkedRow = dashboardContent.locator("tr", {
      hasText: "Scaling Community Workshops",
    });
    await expect(linkedRow).toContainText("Linked");
    await expect(
      linkedRow.getByTitle("Linked proposals cannot be edited"),
    ).toBeDisabled();

    const pendingRow = dashboardContent.locator("tr", {
      hasText: "Collaborative Roadmaps",
    });
    await expect(pendingRow).toContainText(
      /Awaiting co-speaker response|Ready for submission/,
    );

    const declinedRow = dashboardContent.locator("tr", {
      hasText: "Co-Speaker Retrospective",
    });
    await expect(declinedRow).toContainText("Declined by co-speaker");
  });

  test("user can create and delete a session proposal", async ({ pending1Page }) => {
    const proposalTitle = `Pending1 reusable proposal ${Date.now()}`;
    const dashboardContent = await createSessionProposal(pending1Page, proposalTitle);

    const proposalRow = dashboardContent.locator("tr", {
      hasText: proposalTitle,
    });
    await expect(proposalRow).toContainText("Ready for submission");

    await proposalRow.getByTitle("Delete proposal").click();
    await expect(pending1Page.locator(".swal2-popup")).toContainText(
      "Are you sure you want to delete this session proposal?",
    );

    await Promise.all([
      pending1Page.waitForResponse(
        (response) =>
          response.request().method() === "DELETE" &&
          response.url().includes("/dashboard/user/session-proposals/") &&
          response.ok(),
      ),
      pending1Page.getByRole("button", { name: "Delete" }).click(),
    ]);

    await expect(
      dashboardContent.locator("tr", { hasText: proposalTitle }),
    ).toHaveCount(0);
  });

  test("pending co-speaker invitations are surfaced to the invited user", async ({
    member2Page,
  }) => {
    await openUserDashboardPath("/dashboard/user?tab=session-proposals", member2Page);

    const dashboardContent = member2Page.locator("#dashboard-content");
    const invitationAlert = dashboardContent.locator("[role='alert']");
    const invitationRow = dashboardContent.locator("tr", {
      hasText: "Collaborative Roadmaps",
    });

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
    await openUserDashboardPath("/dashboard/user?tab=session-proposals", member2Page);

    const member2Dashboard = member2Page.locator("#dashboard-content");
    const invitationRow = member2Dashboard.locator("tr", {
      hasText: "Collaborative Roadmaps",
    });
    const acceptInvitationButton = invitationRow.getByTitle("Accept invitation");
    await expect(member2Dashboard.locator("[role='alert']")).toContainText(
      "co-speaker invitation waiting for your response",
    );
    await expect(invitationRow).toContainText("E2E Member One");
    await expect(acceptInvitationButton).toBeVisible();

    let invitationAccepted = false;

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

      await member2Page.reload();
      await expect(member2Dashboard.locator("[role='alert']")).toHaveCount(0);
      await expect(
        member2Dashboard.locator("tr", { hasText: "Collaborative Roadmaps" }),
      ).toHaveCount(0);

      await openUserDashboardPath("/dashboard/user?tab=session-proposals", member1Page);

      const member1Dashboard = member1Page.locator("#dashboard-content");
      const proposalRow = member1Dashboard.locator("tr", {
        hasText: "Collaborative Roadmaps",
      });

      await expect(proposalRow).toContainText("E2E Member Two");
      await expect(proposalRow).toContainText("Ready for submission");
      await expect(proposalRow).not.toContainText("Awaiting co-speaker response");
    } finally {
      if (invitationAccepted) {
        await restoreCoSpeakerInvitation(
          member1Page,
          "Collaborative Roadmaps",
          TEST_USER_IDS.member2,
        );

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
});
