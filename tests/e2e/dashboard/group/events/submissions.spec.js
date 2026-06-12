import { expect, test } from "../../../fixtures.js";

import { TEST_EVENT_IDS, navigateToPath } from "../../../utils.js";
import {
  createSessionProposal,
  openUserDashboardPath,
  submitProposalToOpenCfsEvent,
} from "../../user/helpers.js";

test.describe("group dashboard submissions tab", () => {
  test("events manager can review CFS submissions with labels and ratings", async ({
    eventsManagerGroupPage,
  }) => {
    // Load the group events dashboard before opening the CFS event.
    await navigateToPath(eventsManagerGroupPage, "/dashboard/group?tab=events");

    // Find the cfs event row.
    const cfsEventRow = eventsManagerGroupPage.locator("tr", {
      hasText: "Event With Active CFS",
    });

    // Verify events manager can review CFS submissions with labels and ratings.
    await expect(cfsEventRow).toBeVisible();

    // Submit and wait for the server response.
    await Promise.all([
      eventsManagerGroupPage.waitForResponse(
        (response) =>
          response.request().method() === "GET" &&
          response
            .url()
            .includes(
              `/dashboard/group/events/${TEST_EVENT_IDS.alpha.cfsSummit}/update`,
            ) &&
          response.ok(),
      ),
      cfsEventRow
        .locator('td button[aria-label="Edit event: Event With Active CFS"]')
        .click(),
    ]);

    // Submit and wait for the server response.
    await Promise.all([
      eventsManagerGroupPage.waitForResponse(
        (response) =>
          response.request().method() === "GET" &&
          response
            .url()
            .includes(
              `/dashboard/group/events/${TEST_EVENT_IDS.alpha.cfsSummit}/submissions`,
            ) &&
          response.ok(),
      ),
      eventsManagerGroupPage
        .locator('button[data-section="submissions"]')
        .click(),
    ]);

    // Assert that Submissions is visible.
    await expect(
      eventsManagerGroupPage
        .locator("#submissions-content")
        .getByText("Submissions", {
          exact: true,
        }),
    ).toBeVisible();
    const sortBy = eventsManagerGroupPage.getByLabel("Sort by");
    await expect(sortBy).toBeVisible();
    await expect(sortBy).toContainText("Stars (high to low)");
    await expect(sortBy).toContainText("Ratings count (high to low)");

    // Find the not reviewed row.
    const notReviewedRow = eventsManagerGroupPage.locator("tr", {
      hasText: "Platform Reliability Patterns",
    });
    await expect(notReviewedRow).toContainText("Platform");

    // Find the information requested row.
    const informationRequestedRow = eventsManagerGroupPage.locator("tr", {
      hasText: "Observability in Practice",
    });
    await expect(informationRequestedRow).toContainText("Workshop");
    await expect(informationRequestedRow).toContainText("1 rating");

    // Find the approved row.
    const approvedRow = eventsManagerGroupPage.locator("tr", {
      hasText: "Scaling Community Workshops",
    });
    await expect(approvedRow).toContainText("Platform");
    await expect(approvedRow).toContainText("Workshop");
    await expect(approvedRow).toContainText("2 ratings");
    await expect(approvedRow).toContainText("Approved");
    await expect(approvedRow.getByTitle("Review submission")).toBeEnabled();
  });

  test("viewer sees read-only event and submission controls on the submissions tab", async ({
    groupViewerPage,
  }) => {
    // Load the group events dashboard as a read-only viewer.
    await navigateToPath(groupViewerPage, "/dashboard/group?tab=events");

    // Find the dashboard content.
    const dashboardContent = groupViewerPage.locator("#dashboard-content");

    // Verify viewer sees read-only event and submission controls on the submissions tab.
    await expect(
      dashboardContent.getByText("Events", { exact: true }),
    ).toBeVisible();
    await expect(
      dashboardContent.getByRole("button", { name: "Add Event" }),
    ).toBeDisabled();

    // Find the cfs event row.
    const cfsEventRow = groupViewerPage.locator("tr", {
      hasText: "Event With Active CFS",
    });
    await expect(cfsEventRow).toBeVisible();

    // Submit and wait for the server response.
    await Promise.all([
      groupViewerPage.waitForResponse(
        (response) =>
          response.request().method() === "GET" &&
          response
            .url()
            .includes(
              `/dashboard/group/events/${TEST_EVENT_IDS.alpha.cfsSummit}/update`,
            ) &&
          response.ok(),
      ),
      cfsEventRow
        .locator('td button[aria-label="Edit event: Event With Active CFS"]')
        .click(),
    ]);

    // Submit and wait for the server response.
    await Promise.all([
      groupViewerPage.waitForResponse(
        (response) =>
          response.request().method() === "GET" &&
          response
            .url()
            .includes(
              `/dashboard/group/events/${TEST_EVENT_IDS.alpha.cfsSummit}/submissions`,
            ) &&
          response.ok(),
      ),
      groupViewerPage.locator('button[data-section="submissions"]').click(),
    ]);

    // Find the review buttons.
    const reviewButtons = groupViewerPage.getByTitle(
      "Your role cannot manage events.",
    );
    await expect(reviewButtons.first()).toBeDisabled();
  });

  test("events manager can request changes and user can resubmit", async ({
    eventsManagerGroupPage,
    pending1Page,
  }) => {
    // Create a unique proposal before submitting it to the open CFS event.
    const proposalTitle = `Pending1 reviewed CFS proposal ${Date.now()}`;
    await createSessionProposal(pending1Page, proposalTitle);
    await submitProposalToOpenCfsEvent(pending1Page, proposalTitle);

    // Load the group events dashboard before opening the CFS event.
    await navigateToPath(eventsManagerGroupPage, "/dashboard/group?tab=events");

    // Find the cfs event row.
    const cfsEventRow = eventsManagerGroupPage.locator("tr", {
      hasText: "Event With Active CFS",
    });
    await expect(cfsEventRow).toBeVisible();

    // Open the event update form before switching to submissions.
    await Promise.all([
      eventsManagerGroupPage.waitForResponse(
        (response) =>
          response.request().method() === "GET" &&
          response
            .url()
            .includes(
              `/dashboard/group/events/${TEST_EVENT_IDS.alpha.cfsSummit}/update`,
            ) &&
          response.ok(),
      ),
      cfsEventRow
        .locator('td button[aria-label="Edit event: Event With Active CFS"]')
        .click(),
    ]);

    // Load the submissions tab for the CFS event.
    await Promise.all([
      eventsManagerGroupPage.waitForResponse(
        (response) =>
          response.request().method() === "GET" &&
          response
            .url()
            .includes(
              `/dashboard/group/events/${TEST_EVENT_IDS.alpha.cfsSummit}/submissions`,
            ) &&
          response.ok(),
      ),
      eventsManagerGroupPage
        .locator('button[data-section="submissions"]')
        .click(),
    ]);

    // Open the review modal for the temporary submission.
    const submissionsContent = eventsManagerGroupPage.locator(
      "#submissions-content",
    );
    const submissionRow = submissionsContent.locator("tr", {
      hasText: proposalTitle,
    });
    await expect(submissionRow).toContainText("Not reviewed");
    await submissionRow.getByTitle("Review submission").click();

    // Update labels and request information from the speaker.
    const reviewModal = eventsManagerGroupPage.getByRole("dialog", {
      name: "Review submission",
    });
    await expect(reviewModal).toBeVisible();
    await reviewModal.locator("cfs-label-selector input").fill("Workshop");
    await reviewModal.getByRole("option", { name: /Workshop/ }).click();
    await reviewModal.getByRole("tab", { name: "Decision" }).click();
    await reviewModal
      .locator("label", { hasText: "Information requested" })
      .click();
    await reviewModal
      .locator("#cfs-submission-message")
      .fill("Please add more operational details before the next review.");

    // Save the organizer review.
    await Promise.all([
      eventsManagerGroupPage.waitForResponse(
        (response) =>
          response.request().method() === "PUT" &&
          response
            .url()
            .includes(
              `/dashboard/group/events/${TEST_EVENT_IDS.alpha.cfsSummit}/submissions/`,
            ) &&
          response.ok(),
      ),
      reviewModal.getByRole("button", { name: "Save" }).click(),
    ]);
    await expect(reviewModal).toBeHidden();

    // Reopen submissions to verify the saved decision and labels.
    await navigateToPath(eventsManagerGroupPage, "/dashboard/group?tab=events");
    const updatedCfsEventRow = eventsManagerGroupPage.locator("tr", {
      hasText: "Event With Active CFS",
    });
    await expect(updatedCfsEventRow).toBeVisible();
    await Promise.all([
      eventsManagerGroupPage.waitForResponse(
        (response) =>
          response.request().method() === "GET" &&
          response
            .url()
            .includes(
              `/dashboard/group/events/${TEST_EVENT_IDS.alpha.cfsSummit}/update`,
            ) &&
          response.ok(),
      ),
      updatedCfsEventRow
        .locator('td button[aria-label="Edit event: Event With Active CFS"]')
        .click(),
    ]);
    await Promise.all([
      eventsManagerGroupPage.waitForResponse(
        (response) =>
          response.request().method() === "GET" &&
          response
            .url()
            .includes(
              `/dashboard/group/events/${TEST_EVENT_IDS.alpha.cfsSummit}/submissions`,
            ) &&
          response.ok(),
      ),
      eventsManagerGroupPage
        .locator('button[data-section="submissions"]')
        .click(),
    ]);
    const updatedSubmissionRow = eventsManagerGroupPage
      .locator("#submissions-content")
      .locator("tr", {
        hasText: proposalTitle,
      });
    await expect(updatedSubmissionRow).toContainText("Information requested");
    await expect(updatedSubmissionRow).toContainText("Workshop");

    // Open the user submissions tab and resubmit after making updates.
    await openUserDashboardPath(
      "/dashboard/user?tab=submissions",
      pending1Page,
    );
    const userSubmissionRow = pending1Page
      .locator("#dashboard-content")
      .locator("tr", {
        hasText: proposalTitle,
      });
    await expect(userSubmissionRow).toContainText("Information requested");

    // Confirm the resubmission and wait for the update.
    await userSubmissionRow.getByTitle("Resubmit").click();
    await expect(pending1Page.locator(".swal2-popup")).toContainText(
      "Before resubmitting, please make sure all required changes have been addressed.",
    );
    await Promise.all([
      pending1Page.waitForResponse(
        (response) =>
          response.request().method() === "PUT" &&
          response.url().includes("/dashboard/user/submissions/") &&
          response.url().endsWith("/resubmit") &&
          response.ok(),
      ),
      pending1Page.getByRole("button", { name: "Resubmit" }).click(),
    ]);

    // Reload the submissions tab and verify the submission returns to review.
    await pending1Page.reload();
    await expect(userSubmissionRow).toContainText("Not reviewed");
    await expect(userSubmissionRow.getByTitle("Withdraw")).toBeEnabled();
  });
});
