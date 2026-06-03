import { expect, test } from "../../../fixtures.js";

import {
  createSessionProposal,
  openUserDashboardPath,
  submitProposalToOpenCfsEvent,
} from "../helpers.js";

test.describe("user dashboard submissions view", () => {
  test("submissions page shows review statuses and available actions", async ({
    member1Page,
  }) => {
    // Load the submissions tab before checking seeded review states.
    await openUserDashboardPath("/dashboard/user?tab=submissions", member1Page);

    // Find the dashboard content.
    const dashboardContent = member1Page.locator("#dashboard-content");

    // Verify submissions page shows review statuses and available actions.
    await expect(
      dashboardContent.getByText("Submissions", { exact: true }),
    ).toBeVisible();

    // Find the not reviewed row.
    const notReviewedRow = dashboardContent.locator("tr", {
      hasText: "Platform Reliability Patterns",
    });
    await expect(notReviewedRow).toContainText("Platform");
    await expect(notReviewedRow).toContainText("Not reviewed");
    await expect(notReviewedRow.getByTitle("Withdraw")).toBeEnabled();

    // Find the information requested row.
    const informationRequestedRow = dashboardContent.locator("tr", {
      hasText: "Observability in Practice",
    });
    await expect(informationRequestedRow).toContainText("Workshop");
    await expect(informationRequestedRow).toContainText(
      "Information requested",
    );
    await expect(informationRequestedRow.getByTitle("Resubmit")).toBeVisible();

    // Find the approved row.
    const approvedRow = dashboardContent.locator("tr", {
      hasText: "Scaling Community Workshops",
    });
    await expect(approvedRow).toContainText("Approved");
    await expect(
      approvedRow.getByTitle(
        "This submission has been approved and cannot be removed.",
      ),
    ).toBeDisabled();

    // Find the rejected row.
    const rejectedRow = dashboardContent.locator("tr", {
      hasText: "Maintainer Burnout Lessons",
    });
    await expect(rejectedRow).toContainText("Rejected");
    await expect(
      rejectedRow.getByTitle(
        "This submission has been rejected and cannot be removed.",
      ),
    ).toBeDisabled();

    // Find the withdrawn row.
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

  test("user can submit a newly created proposal and see it in submissions", async ({
    pending1Page,
  }) => {
    // Create a unique proposal title for the temporary submission flow.
    const proposalTitle = `Pending1 CFS proposal ${Date.now()}`;

    // Create a session proposal for this member.
    await createSessionProposal(pending1Page, proposalTitle);
    await submitProposalToOpenCfsEvent(pending1Page, proposalTitle);
    await openUserDashboardPath(
      "/dashboard/user?tab=submissions",
      pending1Page,
    );

    // Find the dashboard content.
    const dashboardContent = pending1Page.locator("#dashboard-content");
    const submissionRow = dashboardContent.locator("tr", {
      hasText: proposalTitle,
    });

    // Verify user can submit a newly created proposal and see it in submissions.
    await expect(
      dashboardContent.getByText("Submissions", { exact: true }),
    ).toBeVisible();
    await expect(submissionRow).toContainText("Event With Active CFS");
    await expect(submissionRow).toContainText("Not reviewed");
  });

  test("user can withdraw a newly submitted CFS submission from submissions", async ({
    pending2Page,
  }) => {
    // Create a unique proposal title for the temporary withdrawal flow.
    const proposalTitle = `Pending2 CFS proposal ${Date.now()}`;

    // Create a session proposal for this member.
    await createSessionProposal(pending2Page, proposalTitle);
    await submitProposalToOpenCfsEvent(pending2Page, proposalTitle);
    await openUserDashboardPath(
      "/dashboard/user?tab=submissions",
      pending2Page,
    );

    // Find the dashboard content.
    const dashboardContent = pending2Page.locator("#dashboard-content");
    const submissionRow = dashboardContent.locator("tr", {
      hasText: proposalTitle,
    });
    const withdrawButton = submissionRow.getByTitle("Withdraw");

    // Verify user can withdraw a newly submitted CFS submission from submissions.
    await expect(
      dashboardContent.getByText("Submissions", { exact: true }),
    ).toBeVisible();
    await expect(submissionRow).toContainText("Not reviewed");
    await expect(withdrawButton).toBeVisible();

    // Click the withdraw button.
    await withdrawButton.click();
    await expect(pending2Page.locator(".swal2-popup")).toContainText(
      "Are you sure you want to withdraw this submission?",
    );

    // Click Withdraw.
    await Promise.all([
      pending2Page.waitForResponse(
        (response) =>
          response.request().method() === "PUT" &&
          response.url().includes("/dashboard/user/submissions/") &&
          response.url().endsWith("/withdraw") &&
          response.ok(),
      ),
      pending2Page.getByRole("button", { name: "Withdraw" }).click(),
    ]);

    // Reload the invited user dashboard.
    await pending2Page.reload();

    // Set up withdrawn row.
    const withdrawnRow = pending2Page
      .locator("#dashboard-content")
      .locator("tr", {
        hasText: proposalTitle,
      });
    await expect(withdrawnRow).toContainText("Withdrawn");
    await expect(
      withdrawnRow.getByTitle(
        "This submission has been withdrawn and cannot be removed.",
      ),
    ).toBeDisabled();
  });
});
