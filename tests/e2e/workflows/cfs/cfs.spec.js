import { expect, test } from "../../fixtures.js";
import { queryE2eDatabase } from "../../database.js";
import { deleteNotifications, expectNewNotifications, snapshotNotifications } from "../../notifications.js";
import { TEST_EVENT_IDS, TEST_USER_IDS } from "../../seed.js";
import { navigateToPath, uniqueName, waitForActionResponse } from "../../utils.js";
import {
  createSessionProposal,
  openUserDashboardPath,
  submitProposalToOpenCfsEvent,
} from "../../dashboard/user/helpers.js";

test.describe("CFS submission workflow", () => {
  test("submitted proposal can be approved end to end", async ({ eventsManagerGroupPage, pending1Page }) => {
    // Create a unique proposal and submit it through the public CFS event page.
    const proposalTitle = uniqueName("pending1 approved workflow proposal");
    let notificationIds = [];

    try {
      // Submit the temporary proposal to the open CFS event.
      await createSessionProposal(pending1Page, proposalTitle);
      await submitProposalToOpenCfsEvent(pending1Page, proposalTitle);

      // Verify the speaker sees the fresh submission awaiting review.
      await openUserDashboardPath("/dashboard/user?tab=submissions", pending1Page);
      const speakerSubmissionRow = pending1Page.locator("#dashboard-content").locator("tr", {
        hasText: proposalTitle,
      });
      await expect(speakerSubmissionRow).toContainText("Not reviewed");

      // Approve the submission from the group dashboard review modal.
      const submissionsContent = await openCfsEventSubmissionsTab(eventsManagerGroupPage);
      const snapshot = snapshotNotifications();
      await saveSubmissionDecision(eventsManagerGroupPage, submissionsContent, proposalTitle, "Approved");
      notificationIds = expectNewNotifications(snapshot, [
        {
          kind: "cfs-submission-updated",
          templateDataContains: { status_name: "Approved" },
          userIds: [TEST_USER_IDS.pending1],
        },
      ]);
      await expect(submissionsContent.locator("tr", { hasText: proposalTitle })).toContainText("Approved");

      // Verify the speaker sees the approved final state with removal locked.
      await pending1Page.reload();
      await expect(speakerSubmissionRow).toContainText("Approved");
      await expect(
        speakerSubmissionRow.getByTitle("This submission has been approved and cannot be removed."),
      ).toBeDisabled();

      // Verify the linked proposal can no longer be deleted by the speaker.
      await openUserDashboardPath("/dashboard/user?tab=session-proposals", pending1Page);
      const proposalRow = pending1Page.locator("#dashboard-content").locator("tr", {
        hasText: proposalTitle,
      });
      await expect(proposalRow).toContainText("Submitted");
      await expect(proposalRow.getByTitle("Submitted proposals cannot be deleted")).toBeDisabled();
    } finally {
      // Remove notifications and the temporary proposal graph.
      deleteNotifications(notificationIds);
      deleteSessionProposalsByTitle(TEST_USER_IDS.pending1, [proposalTitle]);
    }
  });

  test("submitted proposal can be rejected end to end", async ({ eventsManagerGroupPage, pending2Page }) => {
    // Create a unique proposal and submit it through the public CFS event page.
    const proposalTitle = uniqueName("pending2 rejected workflow proposal");
    let notificationIds = [];

    try {
      // Submit the temporary proposal to the open CFS event.
      await createSessionProposal(pending2Page, proposalTitle);
      await submitProposalToOpenCfsEvent(pending2Page, proposalTitle);

      // Reject the submission from the group dashboard review modal.
      const submissionsContent = await openCfsEventSubmissionsTab(eventsManagerGroupPage);
      const snapshot = snapshotNotifications();
      await saveSubmissionDecision(eventsManagerGroupPage, submissionsContent, proposalTitle, "Rejected");
      notificationIds = expectNewNotifications(snapshot, [
        {
          kind: "cfs-submission-updated",
          templateDataContains: { status_name: "Rejected" },
          userIds: [TEST_USER_IDS.pending2],
        },
      ]);
      await expect(submissionsContent.locator("tr", { hasText: proposalTitle })).toContainText("Rejected");

      // Verify the speaker sees the rejected final state with removal locked.
      await openUserDashboardPath("/dashboard/user?tab=submissions", pending2Page);
      const speakerSubmissionRow = pending2Page.locator("#dashboard-content").locator("tr", {
        hasText: proposalTitle,
      });
      await expect(speakerSubmissionRow).toContainText("Rejected");
      await expect(
        speakerSubmissionRow.getByTitle("This submission has been rejected and cannot be removed."),
      ).toBeDisabled();
      await expect(speakerSubmissionRow.getByTitle("Resubmit")).toHaveCount(0);
    } finally {
      // Remove notifications and the temporary proposal graph.
      deleteNotifications(notificationIds);
      deleteSessionProposalsByTitle(TEST_USER_IDS.pending2, [proposalTitle]);
    }
  });

  test("events manager can request changes and user can resubmit", async ({
    eventsManagerGroupPage,
    pending1Page,
  }) => {
    // Create a unique proposal before submitting it to the open CFS event.
    const proposalTitle = uniqueName("pending1 reviewed cfs proposal");
    const actionRequiredMessage = "Please add more operational details before the next review.";
    let notificationIds = [];

    try {
      // Submit the temporary proposal to the open CFS event.
      await createSessionProposal(pending1Page, proposalTitle);
      await submitProposalToOpenCfsEvent(pending1Page, proposalTitle);

      // Open the review modal for the temporary submission.
      const submissionsContent = await openCfsEventSubmissionsTab(eventsManagerGroupPage);
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
      await reviewModal.locator("label", { hasText: "Information requested" }).click();
      await reviewModal.locator("#cfs-submission-message").fill(actionRequiredMessage);

      // Save the organizer review and assert the speaker notification.
      const snapshot = snapshotNotifications();
      await waitForActionResponse(
        eventsManagerGroupPage,
        () => reviewModal.getByRole("button", { name: "Save" }).click(),
        {
          method: "PUT",
          urlIncludes: `/dashboard/group/events/${TEST_EVENT_IDS.alpha.cfsSummit}/submissions/`,
        },
      );
      notificationIds = expectNewNotifications(snapshot, [
        {
          kind: "cfs-submission-updated",
          templateDataContains: {
            action_required_message: actionRequiredMessage,
            status_name: "Information requested",
          },
          userIds: [TEST_USER_IDS.pending1],
        },
      ]);
      await expect(reviewModal).toBeHidden();

      // Reopen submissions to verify the saved decision and labels.
      const updatedSubmissionsContent = await openCfsEventSubmissionsTab(eventsManagerGroupPage);
      const updatedSubmissionRow = updatedSubmissionsContent.locator("tr", {
        hasText: proposalTitle,
      });
      await expect(updatedSubmissionRow).toContainText("Information requested");
      await expect(updatedSubmissionRow).toContainText("Workshop");

      // Open the user submissions tab and resubmit after making updates.
      await openUserDashboardPath("/dashboard/user?tab=submissions", pending1Page);
      const userSubmissionRow = pending1Page.locator("#dashboard-content").locator("tr", {
        hasText: proposalTitle,
      });
      await expect(userSubmissionRow).toContainText("Information requested");

      // Confirm the resubmission and wait for the update.
      await userSubmissionRow.getByTitle("Resubmit").click();
      await expect(pending1Page.locator(".swal2-popup")).toContainText(
        "Before resubmitting, please make sure all required changes have been addressed.",
      );
      await waitForActionResponse(
        pending1Page,
        () => pending1Page.getByRole("button", { name: "Resubmit" }).click(),
        {
          method: "PUT",
          urlIncludes: "/dashboard/user/submissions/",
          urlEndsWith: "/resubmit",
        },
      );

      // Reload the submissions tab and verify the submission returns to review.
      await pending1Page.reload();
      await expect(userSubmissionRow).toContainText("Not reviewed");
      await expect(userSubmissionRow.getByTitle("Withdraw")).toBeEnabled();
    } finally {
      // Remove notifications and the temporary proposal graph.
      deleteNotifications(notificationIds);
      deleteSessionProposalsByTitle(TEST_USER_IDS.pending1, [proposalTitle]);
    }
  });
});

/** Deletes a temporary proposal and its CFS submission graph by exact owner and title. */
const deleteSessionProposalsByTitle = (userId, proposalTitles) => {
  if (proposalTitles.length === 0) {
    return;
  }

  const titleList = proposalTitles.map((title) => `'${title.replace(/'/g, "''")}'`).join(", ");

  queryE2eDatabase(`
    do $$
    declare
      v_proposal_ids uuid[];
      v_submission_ids uuid[];
    begin
      select coalesce(array_agg(session_proposal_id), '{}')
      into v_proposal_ids
      from session_proposal
      where user_id = '${userId}'
      and title in (${titleList});

      select coalesce(array_agg(cfs_submission_id), '{}')
      into v_submission_ids
      from cfs_submission
      where session_proposal_id = any(v_proposal_ids);

      delete from cfs_submission_label where cfs_submission_id = any(v_submission_ids);
      delete from cfs_submission_rating where cfs_submission_id = any(v_submission_ids);
      delete from session_speaker
      where session_id in (select session_id from session where cfs_submission_id = any(v_submission_ids));
      delete from session where cfs_submission_id = any(v_submission_ids);
      delete from cfs_submission where cfs_submission_id = any(v_submission_ids);
      delete from session_proposal where session_proposal_id = any(v_proposal_ids);
    end $$;
  `);
};

/** Opens the submissions tab of the seeded CFS event in the group dashboard. */
const openCfsEventSubmissionsTab = async (page) => {
  await navigateToPath(page, "/dashboard/group?tab=events");

  const cfsEventRow = page.locator("tr", {
    hasText: "Event With Active CFS",
  });
  await expect(cfsEventRow).toBeVisible();

  // Open the event update form before switching to submissions.
  await waitForActionResponse(
    page,
    () => cfsEventRow.locator('td button[aria-label="Edit event: Event With Active CFS"]').click(),
    {
      method: "GET",
      urlIncludes: `/dashboard/group/events/${TEST_EVENT_IDS.alpha.cfsSummit}/update`,
    },
  );

  // Load the submissions tab for the CFS event.
  await waitForActionResponse(page, () => page.locator('button[data-section="submissions"]').click(), {
    method: "GET",
    urlIncludes: `/dashboard/group/events/${TEST_EVENT_IDS.alpha.cfsSummit}/submissions`,
  });

  return page.locator("#submissions-content");
};

/** Saves the given final decision for a submission through the review modal. */
const saveSubmissionDecision = async (page, submissionsContent, proposalTitle, decision) => {
  // Open the review modal for the target submission.
  const submissionRow = submissionsContent.locator("tr", {
    hasText: proposalTitle,
  });
  await submissionRow.getByTitle("Review submission").click();
  const reviewModal = page.getByRole("dialog", { name: "Review submission" });
  await expect(reviewModal).toBeVisible();

  // Pick the final decision on the decision tab and save the review.
  await reviewModal.getByRole("tab", { name: "Decision" }).click();
  await reviewModal.locator("label", { hasText: decision }).click();
  await waitForActionResponse(page, () => reviewModal.getByRole("button", { name: "Save" }).click(), {
    method: "PUT",
    urlIncludes: `/dashboard/group/events/${TEST_EVENT_IDS.alpha.cfsSummit}/submissions/`,
  });
  await expect(reviewModal).toBeHidden();
};
