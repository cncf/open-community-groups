import type { Page } from "@playwright/test";

import { expect, test } from "../fixtures";

import {
  TEST_EVENT_NAMES,
  navigateToPath,
} from "../utils";

const openUserDashboardPath = async (path: string, page: Page) => {
  await navigateToPath(page, path);
};

test.describe("user dashboard", () => {
  test("invitations page shows pending community and group roles", async ({
    pending1Page,
  }) => {
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
      hasText: "E2E Test Group Beta",
    });
    await expect(groupRow).toContainText("events-manager");
    await expect(groupRow.getByTitle("Approve")).toBeVisible();
    await expect(groupRow.getByTitle("Reject")).toBeVisible();
  });

  test("my events page lists only upcoming published participation", async ({
    member1Page,
  }) => {
    await openUserDashboardPath("/dashboard/user?tab=events", member1Page);

    const dashboardContent = member1Page.locator("#dashboard-content");
    await expect(
      dashboardContent.getByText("My Events", { exact: true }),
    ).toBeVisible();

    const attendeeSpeakerRow = dashboardContent.locator("tr", {
      hasText: TEST_EVENT_NAMES.alpha[0],
    });
    await expect(attendeeSpeakerRow).toContainText("Attendee");
    await expect(attendeeSpeakerRow).toContainText("Speaker");

    await expect(dashboardContent.getByText("Alpha Past Roundup")).toHaveCount(0);
    await expect(dashboardContent.getByText(TEST_EVENT_NAMES.beta[0])).toHaveCount(0);
  });

  test("session proposals page shows seeded proposal states and locks", async ({
    member1Page,
  }) => {
    await openUserDashboardPath(
      "/dashboard/user?tab=session-proposals",
      member1Page,
    );

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
    await expect(pendingRow).toContainText("Awaiting co-speaker response");

    const declinedRow = dashboardContent.locator("tr", {
      hasText: "Co-Speaker Retrospective",
    });
    await expect(declinedRow).toContainText("Declined by co-speaker");
  });

  test("pending co-speaker invitations are surfaced to the invited user", async ({
    member2Page,
  }) => {
    await openUserDashboardPath(
      "/dashboard/user?tab=session-proposals",
      member2Page,
    );

    const dashboardContent = member2Page.locator("#dashboard-content");

    await expect(dashboardContent.locator("[role='alert']")).toContainText(
      "co-speaker invitation waiting for your response",
    );

    const invitationRow = dashboardContent.locator("tr", {
      hasText: "Collaborative Roadmaps",
    });
    await expect(invitationRow).toContainText("E2E Member One");
    await expect(invitationRow.getByTitle("View proposal")).toBeVisible();
    await expect(invitationRow.getByTitle("Accept invitation")).toBeVisible();
    await expect(invitationRow.getByTitle("Decline invitation")).toBeVisible();
  });

  test("accepting a co-speaker invitation updates both users' proposal views", async ({
    member1Page,
    member2Page,
  }) => {
    await openUserDashboardPath(
      "/dashboard/user?tab=session-proposals",
      member2Page,
    );

    const member2Dashboard = member2Page.locator("#dashboard-content");
    const invitationRow = member2Dashboard.locator("tr", {
      hasText: "Collaborative Roadmaps",
    });

    if ((await invitationRow.getByTitle("Accept invitation").count()) > 0) {
      await expect(member2Dashboard.locator("[role='alert']")).toContainText(
        "co-speaker invitation waiting for your response",
      );
      await expect(invitationRow).toContainText("E2E Member One");

      await Promise.all([
        member2Page.waitForResponse(
          (response) =>
            response.request().method() === "PUT" &&
            response.ok() &&
            response
              .url()
              .includes("/co-speaker-invitation/accept"),
        ),
        invitationRow.getByTitle("Accept invitation").click(),
      ]);
    }

    await member2Page.reload();
    await expect(member2Dashboard.locator("[role='alert']")).toHaveCount(0);
    await expect(
      member2Dashboard.locator("tr", { hasText: "Collaborative Roadmaps" }),
    ).toHaveCount(0);

    await openUserDashboardPath(
      "/dashboard/user?tab=session-proposals",
      member1Page,
    );

    const member1Dashboard = member1Page.locator("#dashboard-content");
    const proposalRow = member1Dashboard.locator("tr", {
      hasText: "Collaborative Roadmaps",
    });

    await expect(proposalRow).toContainText("E2E Member Two");
    await expect(proposalRow).toContainText("Ready for submission");
    await expect(proposalRow).not.toContainText("Awaiting co-speaker response");
  });

  test("submissions page shows review statuses and available actions", async ({
    member1Page,
  }) => {
    await openUserDashboardPath("/dashboard/user?tab=submissions", member1Page);

    const dashboardContent = member1Page.locator("#dashboard-content");
    await expect(
      dashboardContent.getByText("Submissions", { exact: true }),
    ).toBeVisible();

    const notReviewedRow = dashboardContent.locator("tr", {
      hasText: "Platform Reliability Patterns",
    });
    await expect(notReviewedRow).toContainText("Platform");
    await expect(notReviewedRow).toContainText("Not reviewed");
    await expect(notReviewedRow.getByTitle("Withdraw")).toBeEnabled();

    const informationRequestedRow = dashboardContent.locator("tr", {
      hasText: "Observability in Practice",
    });
    await expect(informationRequestedRow).toContainText("Workshop");
    await expect(informationRequestedRow).toContainText("Information requested");
    await expect(informationRequestedRow.getByTitle("Resubmit")).toBeVisible();

    const approvedRow = dashboardContent.locator("tr", {
      hasText: "Scaling Community Workshops",
    });
    await expect(approvedRow).toContainText("Approved");
    await expect(
      approvedRow.getByTitle(
        "This submission has been approved and cannot be removed.",
      ),
    ).toBeDisabled();

    const rejectedRow = dashboardContent.locator("tr", {
      hasText: "Maintainer Burnout Lessons",
    });
    await expect(rejectedRow).toContainText("Rejected");
    await expect(
      rejectedRow.getByTitle(
        "This submission has been rejected and cannot be removed.",
      ),
    ).toBeDisabled();

    const withdrawnRow = dashboardContent.locator("tr", {
      hasText: "Speaker Office Hours",
    });
    await expect(withdrawnRow).toContainText("Withdrawn");
    await expect(
      withdrawnRow.getByTitle(
        "This submission has been withdrawn and cannot be removed.",
      ),
    ).toBeDisabled();
  });
});
