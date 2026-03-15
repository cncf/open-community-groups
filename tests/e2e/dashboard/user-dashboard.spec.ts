import { expect, test } from "@playwright/test";

import {
  TEST_EVENT_NAMES,
  TEST_USER_CREDENTIALS,
  logInWithSeededUser,
  navigateToPath,
} from "../utils";

const openUserDashboardPath = async (path: string, page: Parameters<typeof logInWithSeededUser>[0]) => {
  await navigateToPath(page, path);
};

test.describe("user dashboard", () => {
  test("invitations page shows pending community and group roles", async ({ page }) => {
    await logInWithSeededUser(page, TEST_USER_CREDENTIALS.pending1);
    await openUserDashboardPath("/dashboard/user/invitations", page);

    await expect(page.getByText("Community Invitations", { exact: true })).toBeVisible();
    await expect(page.getByText("Group Invitations", { exact: true })).toBeVisible();

    const communityRow = page.locator("tr", { hasText: "E2E Test Community" });
    await expect(communityRow).toContainText("viewer");
    await expect(communityRow.getByTitle("Approve")).toBeVisible();
    await expect(communityRow.getByTitle("Reject")).toBeVisible();

    const groupRow = page.locator("tr", { hasText: "E2E Test Group Beta" });
    await expect(groupRow).toContainText("events-manager");
    await expect(groupRow.getByTitle("Approve")).toBeVisible();
    await expect(groupRow.getByTitle("Reject")).toBeVisible();
  });

  test("my events page lists only upcoming published participation", async ({ page }) => {
    await logInWithSeededUser(page, TEST_USER_CREDENTIALS.member1);
    await openUserDashboardPath("/dashboard/user/events", page);

    await expect(page.getByText("My Events", { exact: true })).toBeVisible();

    const attendeeSpeakerRow = page.locator("tr", {
      hasText: TEST_EVENT_NAMES.alpha[0],
    });
    await expect(attendeeSpeakerRow).toContainText("Attendee");
    await expect(attendeeSpeakerRow).toContainText("Speaker");

    await expect(page.getByText("Alpha Past Roundup")).toHaveCount(0);
    await expect(page.getByText(TEST_EVENT_NAMES.beta[0])).toHaveCount(0);
  });

  test("session proposals page shows seeded proposal states and locks", async ({ page }) => {
    await logInWithSeededUser(page, TEST_USER_CREDENTIALS.member1);
    await openUserDashboardPath("/dashboard/user/session-proposals", page);

    await expect(page.getByText("Session proposals", { exact: true })).toBeVisible();
    await expect(page.getByRole("button", { name: "New proposal" })).toBeVisible();

    const readyRow = page.locator("tr", {
      hasText: "Cloud Native Operations Deep Dive",
    });
    await expect(readyRow).toContainText("Ready for submission");
    await expect(readyRow.getByTitle("Delete proposal")).toBeEnabled();

    const submittedRow = page.locator("tr", {
      hasText: "Platform Reliability Patterns",
    });
    await expect(submittedRow).toContainText("Submitted");
    await expect(
      submittedRow.getByTitle("Submitted proposals cannot be deleted"),
    ).toBeDisabled();

    const linkedRow = page.locator("tr", {
      hasText: "Scaling Community Workshops",
    });
    await expect(linkedRow).toContainText("Linked");
    await expect(
      linkedRow.getByTitle("Linked proposals cannot be edited"),
    ).toBeDisabled();

    const pendingRow = page.locator("tr", {
      hasText: "Collaborative Roadmaps",
    });
    await expect(pendingRow).toContainText("Awaiting co-speaker response");

    const declinedRow = page.locator("tr", {
      hasText: "Co-Speaker Retrospective",
    });
    await expect(declinedRow).toContainText("Declined by co-speaker");
  });

  test("pending co-speaker invitations are surfaced to the invited user", async ({
    page,
  }) => {
    await logInWithSeededUser(page, TEST_USER_CREDENTIALS.member2);
    await openUserDashboardPath("/dashboard/user/session-proposals", page);

    await expect(page.getByRole("alert")).toContainText(
      "co-speaker invitation waiting for your response",
    );

    const invitationRow = page.locator("tr", {
      hasText: "Collaborative Roadmaps",
    });
    await expect(invitationRow).toContainText("E2E Member One");
    await expect(invitationRow.getByTitle("View proposal")).toBeVisible();
    await expect(invitationRow.getByTitle("Accept invitation")).toBeVisible();
    await expect(invitationRow.getByTitle("Decline invitation")).toBeVisible();
  });

  test("submissions page shows review statuses and available actions", async ({ page }) => {
    await logInWithSeededUser(page, TEST_USER_CREDENTIALS.member1);
    await openUserDashboardPath("/dashboard/user/submissions", page);

    await expect(page.getByText("Submissions", { exact: true })).toBeVisible();
    await expect(page.getByText("Platform", { exact: true })).toBeVisible();
    await expect(page.getByText("Workshop", { exact: true })).toBeVisible();

    const notReviewedRow = page.locator("tr", {
      hasText: "Platform Reliability Patterns",
    });
    await expect(notReviewedRow).toContainText("Not reviewed");
    await expect(notReviewedRow.getByTitle("Withdraw")).toBeEnabled();

    const informationRequestedRow = page.locator("tr", {
      hasText: "Observability in Practice",
    });
    await expect(informationRequestedRow).toContainText("Information requested");
    await expect(informationRequestedRow.getByTitle("Resubmit")).toBeVisible();

    const approvedRow = page.locator("tr", {
      hasText: "Scaling Community Workshops",
    });
    await expect(approvedRow).toContainText("Approved");
    await expect(
      approvedRow.getByTitle(
        "This submission has been approved and cannot be removed.",
      ),
    ).toBeDisabled();

    const rejectedRow = page.locator("tr", {
      hasText: "Maintainer Burnout Lessons",
    });
    await expect(rejectedRow).toContainText("Rejected");
    await expect(
      rejectedRow.getByTitle(
        "This submission has been rejected and cannot be removed.",
      ),
    ).toBeDisabled();

    const withdrawnRow = page.locator("tr", {
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
