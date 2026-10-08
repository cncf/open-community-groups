import { expect, test } from "../../fixtures.js";
import { queryE2eDatabase, queryE2eDatabaseRows } from "../../database.js";
import { deleteNotifications, expectNewNotifications, snapshotNotifications } from "../../notifications.js";
import { TEST_COMMUNITY_NAME, TEST_EVENT_IDS, TEST_GROUP_SLUGS, TEST_USER_IDS } from "../../seed.js";
import { navigateToEvent, navigateToPath, uniqueName, waitForActionResponse } from "../../utils.js";
import {
  listEventLabels,
  listSessionLabels,
  waitForEventEditorAfterSave,
} from "../../dashboard/group/events/helpers.js";
import {
  expectSessionCardLabels,
  openSessionsSection,
  selectLabels,
} from "../../dashboard/group/events/event-form-helpers.js";
import {
  createSessionProposal,
  openUserDashboardPath,
  submitProposalToOpenCfsEvent,
} from "../../dashboard/user/helpers.js";

const CFS_EVENT_ID = TEST_EVENT_IDS.alpha.cfsSummit;

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
      await reviewModal.locator("label-selector#cfs-submission-labels input").fill("Workshop");
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

  test("approved submission labels are copied to its linked session and then evolve separately", async ({
    eventsManagerGroupPage,
    pending1Page,
  }) => {
    test.setTimeout(90_000);

    // Create a unique proposal and remember the seeded label colors the editor normalizes on save.
    const proposalTitle = uniqueName("pending1 labeled workflow proposal");
    const seededLabels = listEventLabels(CFS_EVENT_ID);
    let notificationIds = [];

    try {
      // Submit the temporary proposal to the open CFS event.
      await createSessionProposal(pending1Page, proposalTitle);
      await submitProposalToOpenCfsEvent(pending1Page, proposalTitle);
      const submissionId = readSubmissionIdByTitle(proposalTitle);

      // Label and approve the submission in one review.
      const submissionsContent = await openCfsEventSubmissionsTab(eventsManagerGroupPage);
      const reviewModal = await openSubmissionReview(
        eventsManagerGroupPage,
        submissionsContent,
        proposalTitle,
      );
      await selectLabels(reviewModal.locator("label-selector#cfs-submission-labels"), ["Workshop"]);
      await reviewModal.getByRole("tab", { name: "Decision" }).click();
      await reviewModal.locator("label", { hasText: "Approved" }).click();
      const approvalSnapshot = snapshotNotifications();
      await saveSubmissionReview(eventsManagerGroupPage, reviewModal, submissionId);
      notificationIds = expectNewNotifications(approvalSnapshot, [
        {
          kind: "cfs-submission-updated",
          templateDataContains: { status_name: "Approved" },
          userIds: [TEST_USER_IDS.pending1],
        },
      ]);

      // Link the approved submission to a new session and verify its labels are pre-filled.
      await openSessionsSection(eventsManagerGroupPage);
      await eventsManagerGroupPage
        .locator("sessions-section")
        .getByRole("button", { name: "Add session" })
        .first()
        .click();
      const sessionModal = eventsManagerGroupPage.locator("session-form-modal");
      const addSessionDialog = sessionModal.getByRole("dialog", { name: "Add session" });
      await expect(addSessionDialog).toBeVisible();
      await sessionModal.locator('input[data-name="name"]').fill(proposalTitle);
      await sessionModal.locator('select[data-name="kind"]').selectOption("virtual");
      await sessionModal.locator('input[type="time"]').nth(0).fill("12:30");
      await sessionModal.locator('input[type="time"]').nth(1).fill("13:00");
      await sessionModal.getByText("From Call for Speakers submission", { exact: true }).click();
      await sessionModal.locator('select[data-name="cfs_submission_id"]').selectOption(submissionId);
      const sessionLabelSelector = sessionModal.locator("label-selector");
      await expect(sessionLabelSelector.locator('button[aria-label^="Remove "]')).toHaveCount(1);
      await expect(
        sessionLabelSelector.getByRole("button", { name: "Remove Workshop", exact: true }),
      ).toBeVisible();
      await sessionModal.getByRole("button", { name: "Add session" }).click();
      await expect(addSessionDialog).toHaveCount(0);
      await expectSessionCardLabels(eventsManagerGroupPage, proposalTitle, ["Workshop"]);

      // Save the event and verify the session stores the copied labels.
      await saveCfsEventUpdate(eventsManagerGroupPage);
      expect(readSessionLabelsByName(proposalTitle)).toEqual(["Workshop"]);

      // Add another label to the session without touching the submission.
      await openSessionsSection(eventsManagerGroupPage);
      await eventsManagerGroupPage
        .locator("sessions-section session-card")
        .filter({ hasText: proposalTitle })
        .getByTitle("Edit")
        .click();
      const editSessionDialog = sessionModal.getByRole("dialog", { name: "Edit session" });
      await expect(editSessionDialog).toBeVisible();
      await selectLabels(sessionModal.locator("label-selector"), ["Platform"]);
      await sessionModal.getByRole("button", { name: "Save changes" }).click();
      await expect(editSessionDialog).toHaveCount(0);
      await expectSessionCardLabels(eventsManagerGroupPage, proposalTitle, ["Platform", "Workshop"]);
      await saveCfsEventUpdate(eventsManagerGroupPage);
      expect(readSessionLabelsByName(proposalTitle)).toEqual(["Platform", "Workshop"]);
      expect(readSubmissionLabels(submissionId)).toEqual(["Workshop"]);

      // Change the submission labels later without a new decision or notification.
      const updatedSubmissionsContent = await openCfsEventSubmissionsTab(eventsManagerGroupPage);
      const updatedReviewModal = await openSubmissionReview(
        eventsManagerGroupPage,
        updatedSubmissionsContent,
        proposalTitle,
      );
      const reviewLabelSelector = updatedReviewModal.locator("label-selector#cfs-submission-labels");
      await reviewLabelSelector.getByRole("button", { name: "Remove Workshop", exact: true }).click();
      await expect(reviewLabelSelector.locator('button[aria-label^="Remove "]')).toHaveCount(0);
      const labelsSnapshot = snapshotNotifications();
      await saveSubmissionReview(eventsManagerGroupPage, updatedReviewModal, submissionId);
      notificationIds = notificationIds.concat(expectNewNotifications(labelsSnapshot, []));
      expect(readSubmissionLabels(submissionId)).toEqual([]);

      // Verify the linked session keeps its own labels after reloading the editor.
      await openCfsEventSubmissionsTab(eventsManagerGroupPage);
      await openSessionsSection(eventsManagerGroupPage);
      await expectSessionCardLabels(eventsManagerGroupPage, proposalTitle, ["Platform", "Workshop"]);
      expect(readSessionLabelsByName(proposalTitle)).toEqual(["Platform", "Workshop"]);
    } finally {
      // Remove notifications and the temporary proposal graph, and restore the seeded label colors.
      deleteNotifications(notificationIds);
      deleteSessionProposalsByTitle(TEST_USER_IDS.pending1, [proposalTitle]);
      restoreEventLabelColors(seededLabels);
    }
  });

  test("speaker labels picked in the public modal reach the review modal", async ({
    eventsManagerGroupPage,
    pending2Page,
  }) => {
    // Create a unique proposal before opening the public CFS modal.
    const proposalTitle = uniqueName("pending2 public labels proposal");

    try {
      await createSessionProposal(pending2Page, proposalTitle);
      await navigateToEvent(
        pending2Page,
        TEST_COMMUNITY_NAME,
        TEST_GROUP_SLUGS.community1.alpha,
        "alpha-cfs-summit",
      );
      await pending2Page.getByRole("button", { name: "Submit session proposal" }).click();
      const submitModal = pending2Page.getByRole("dialog", { name: "Submit a proposal" });
      await expect(submitModal).toBeVisible();
      await submitModal.locator("#session_proposal_id").selectOption({ label: proposalTitle });

      // Verify the public picker lists the event labels and the assigned labels limit.
      const publicLabelSelector = submitModal.locator("label-selector#cfs-submission-labels");
      await publicLabelSelector.getByRole("combobox").click();
      await expect(publicLabelSelector.getByRole("option")).toHaveCount(2);
      await expect(publicLabelSelector.getByRole("option", { name: "Platform", exact: true })).toBeVisible();
      await expect(publicLabelSelector.getByRole("option", { name: "Workshop", exact: true })).toBeVisible();
      await expect(submitModal.getByText("You can select up to 10 labels.")).toBeVisible();

      // Pick one label and submit the proposal.
      await selectLabels(publicLabelSelector, ["Workshop"]);
      await waitForActionResponse(
        pending2Page,
        () => submitModal.getByRole("button", { name: "Submit proposal" }).click(),
        {
          method: "POST",
          urlIncludes: "/cfs-submissions",
        },
      );
      await expect(submitModal.getByText("Submission received. We'll review it soon.")).toBeVisible();

      // Verify the submission stores the picked label.
      const submissionId = readSubmissionIdByTitle(proposalTitle);
      expect(readSubmissionLabels(submissionId)).toEqual(["Workshop"]);

      // Open the review modal and verify the speaker label and the labels limit hint.
      const submissionsContent = await openCfsEventSubmissionsTab(eventsManagerGroupPage);
      const reviewModal = await openSubmissionReview(
        eventsManagerGroupPage,
        submissionsContent,
        proposalTitle,
      );
      const reviewLabelSelector = reviewModal.locator("label-selector#cfs-submission-labels");
      await expect(
        reviewLabelSelector.getByRole("button", { name: "Remove Workshop", exact: true }),
      ).toBeVisible();
      await expect(
        reviewModal.getByText(
          "Add labels to categorize this submission for your review team. You can select up to 10 labels.",
        ),
      ).toBeVisible();

      // Escape closes the labels dropdown first and keeps the review modal open.
      const reviewCombobox = reviewLabelSelector.getByRole("combobox");
      await reviewCombobox.click();
      await expect(reviewCombobox).toHaveAttribute("aria-expanded", "true");
      await eventsManagerGroupPage.keyboard.press("Escape");
      await expect(reviewCombobox).toHaveAttribute("aria-expanded", "false");
      await expect(reviewModal).toBeVisible();

      // A second Escape closes the review modal.
      await eventsManagerGroupPage.keyboard.press("Escape");
      await expect(reviewModal).toBeHidden();
    } finally {
      // Remove the temporary proposal graph.
      deleteSessionProposalsByTitle(TEST_USER_IDS.pending2, [proposalTitle]);
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

/** Opens the review modal of a submission row and returns the dialog. */
const openSubmissionReview = async (page, submissionsContent, proposalTitle) => {
  await submissionsContent.locator("tr", { hasText: proposalTitle }).getByTitle("Review submission").click();
  const reviewModal = page.getByRole("dialog", { name: "Review submission" });
  await expect(reviewModal).toBeVisible();

  return reviewModal;
};

/** Returns the label names of the temporary session with the given name. */
const readSessionLabelsByName = (sessionName) =>
  listSessionLabels(CFS_EVENT_ID).find((session) => session.name === sessionName)?.labels ?? null;

/** Returns the submission id of a temporary proposal sent to the seeded CFS event. */
const readSubmissionIdByTitle = (proposalTitle) =>
  queryE2eDatabase(`
    select cs.cfs_submission_id
    from cfs_submission cs
    join session_proposal sp on sp.session_proposal_id = cs.session_proposal_id
    where cs.event_id = '${CFS_EVENT_ID}'
    and sp.title = '${proposalTitle.replace(/'/g, "''")}'
  `);

/** Returns the label names of a CFS submission, sorted by name. */
const readSubmissionLabels = (submissionId) =>
  queryE2eDatabaseRows(`
    select el.name
    from cfs_submission_label csl
    join event_label el on el.event_label_id = csl.event_label_id
    where csl.cfs_submission_id = '${submissionId}'
    order by el.name
  `).map(([name]) => name);

/** Restores event label colors changed when the editor saves the seeded CFS event. */
const restoreEventLabelColors = (labels) => {
  for (const label of labels) {
    queryE2eDatabase(`update event_label set color = '${label.color}' where event_label_id = '${label.id}'`);
  }
};

/** Saves the seeded CFS event editor and waits for it to reload. */
const saveCfsEventUpdate = async (page) => {
  await waitForEventEditorAfterSave(
    page,
    () => page.locator("#pending-changes-alert:not(.hidden) #update-event-button").click(),
    {
      eventId: CFS_EVENT_ID,
      method: "PUT",
      urlIncludes: `/dashboard/group/events/${CFS_EVENT_ID}/update`,
    },
  );
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

/** Saves the review modal of a submission and waits for it to close. */
const saveSubmissionReview = async (page, reviewModal, submissionId) => {
  await waitForActionResponse(page, () => reviewModal.getByRole("button", { name: "Save" }).click(), {
    method: "PUT",
    urlIncludes: `/dashboard/group/events/${CFS_EVENT_ID}/submissions/${submissionId}`,
  });
  await expect(reviewModal).toBeHidden();
};
