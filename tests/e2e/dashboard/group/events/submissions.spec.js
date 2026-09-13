import { expect, test } from "../../../fixtures.js";
import { queryE2eDatabase } from "../../../database.js";
import { TEST_COMMUNITY_NAME, TEST_EVENT_IDS, TEST_EVENT_SLUGS, TEST_GROUP_SLUGS } from "../../../seed.js";
import {
  expectCurrentPaginationNavigation,
  navigateToPath,
  routeNextRequestWithQuery,
  waitForActionResponse,
} from "../../../utils.js";
import { openEventUpdateFormByName, waitForEventEditorAfterSave } from "./helpers.js";

const CFS_APPROVAL_SUBMISSION_ID = "99999999-9999-9999-9999-999999999911";

const CFS_APPROVAL_TITLE = "Platform Reliability Patterns";

const CFS_EVENT_ID = TEST_EVENT_IDS.alpha.cfsSummit;

const CFS_EVENT_PUBLIC_PATH = `/${TEST_COMMUNITY_NAME}/group/${TEST_GROUP_SLUGS.community1.alpha}/event/${TEST_EVENT_SLUGS.alphaDashboard[0]}`;

const CFS_SPEAKER_NAME = "E2E Member One";

test.describe("group dashboard submissions tab", () => {
  test("events manager can move between submission result pages", async ({ eventsManagerGroupPage }) => {
    // Open seeded submissions with one result per page.
    await openSubmissionsTab(eventsManagerGroupPage, "?limit=1&offset=0");

    // Verify pagination swaps submission rows in both directions.
    await expectCurrentPaginationNavigation(eventsManagerGroupPage, "#submissions-content tbody tr");
  });

  test("events manager can review CFS submissions with labels and ratings", async ({
    eventsManagerGroupPage,
  }) => {
    // Load the CFS event editor before reviewing submissions.
    await openEventUpdateFormByName(
      eventsManagerGroupPage,
      "Event With Active CFS",
      TEST_EVENT_IDS.alpha.cfsSummit,
    );

    // Submit and wait for the server response.
    await waitForActionResponse(
      eventsManagerGroupPage,
      () => eventsManagerGroupPage.locator('button[data-section="submissions"]').click(),
      {
        method: "GET",
        urlIncludes: `/dashboard/group/events/${TEST_EVENT_IDS.alpha.cfsSummit}/submissions`,
      },
    );

    // Assert that Submissions is visible.
    await expect(
      eventsManagerGroupPage.locator("#submissions-content").getByText("Submissions", {
        exact: true,
      }),
    ).toBeVisible();
    const sortBy = eventsManagerGroupPage.getByLabel("Sort by");
    await expect(sortBy).toBeVisible();
    await expect(sortBy).toContainText("Stars (high to low)");
    await expect(sortBy).toContainText("Ratings count (high to low)");
    const submissionsContent = eventsManagerGroupPage.locator("#submissions-content");

    // Find the not reviewed row.
    const notReviewedRow = submissionsContent.locator("tr", {
      hasText: "Platform Reliability Patterns",
    });
    await expect(notReviewedRow).toContainText("Platform");

    // Find the information requested row.
    const informationRequestedRow = submissionsContent.locator("tr", {
      hasText: "Observability in Practice",
    });
    await expect(informationRequestedRow).toContainText("Workshop");
    await expect(informationRequestedRow).toContainText("1 rating");

    // Find the approved row.
    const approvedRow = submissionsContent.locator("tr", {
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
    // Load the CFS event editor as a read-only viewer.
    await openEventUpdateFormByName(groupViewerPage, "Event With Active CFS", TEST_EVENT_IDS.alpha.cfsSummit);

    // Submit and wait for the server response.
    await waitForActionResponse(
      groupViewerPage,
      () => groupViewerPage.locator('button[data-section="submissions"]').click(),
      {
        method: "GET",
        urlIncludes: `/dashboard/group/events/${TEST_EVENT_IDS.alpha.cfsSummit}/submissions`,
      },
    );

    // Find the review buttons.
    const reviewButtons = groupViewerPage.getByTitle("Your role cannot manage events.");
    await expect(reviewButtons.first()).toBeDisabled();
  });

  test("organizer can approve a CFS proposal and publish it to the public agenda", async ({
    organizerGroupPage,
  }) => {
    test.setTimeout(90_000);

    try {
      // Reset any prior approved agenda fixture before the review flow.
      deleteCfsApprovalAgendaFixture();

      // Approve the seeded proposal through the submissions review modal.
      const submissionsContent = await openSubmissionsTab(organizerGroupPage);
      const proposalRow = submissionsContent.locator("tr", {
        hasText: CFS_APPROVAL_TITLE,
      });
      await expect(proposalRow).toContainText("Not reviewed");
      await proposalRow.getByTitle("Review submission").click();
      const reviewModal = organizerGroupPage.locator("review-submission-modal");
      await expect(reviewModal.getByRole("dialog", { name: "Review submission" })).toBeVisible();
      await reviewModal.getByRole("tab", { name: "Decision" }).click();
      await reviewModal.locator("label", { hasText: "Approved" }).click();
      await expect(reviewModal.locator('input[name="status_id"]')).toHaveValue("approved");
      await waitForActionResponse(
        organizerGroupPage,
        () => reviewModal.getByRole("button", { name: "Save" }).click(),
        {
          method: "PUT",
          status: 204,
          urlIncludes: `/dashboard/group/events/${CFS_EVENT_ID}/submissions/${CFS_APPROVAL_SUBMISSION_ID}`,
        },
      );
      await expect(reviewModal.getByRole("dialog", { name: "Review submission" })).toHaveCount(0);
      await expect(proposalRow).toContainText("Approved");

      // Link the approved CFS submission into a saved event session.
      await organizerGroupPage.locator('button[data-section="sessions"]').click();
      const sessionsSection = organizerGroupPage.locator("sessions-section");
      await sessionsSection.getByRole("button", { name: "Add session" }).click();
      const sessionModal = organizerGroupPage.locator("session-form-modal");
      await expect(sessionModal.getByRole("dialog", { name: "Add session" })).toBeVisible();
      await sessionModal.locator('input[data-name="name"]').fill(CFS_APPROVAL_TITLE);
      await sessionModal.locator('select[data-name="kind"]').selectOption("virtual");
      await sessionModal.locator('input[type="time"]').nth(0).fill("13:00");
      await sessionModal.locator('input[type="time"]').nth(1).fill("13:30");
      await sessionModal.getByText("From Call for Speakers submission", { exact: true }).click();
      await sessionModal
        .locator('select[data-name="cfs_submission_id"]')
        .selectOption(CFS_APPROVAL_SUBMISSION_ID);
      await sessionModal.getByRole("button", { name: "Add session" }).click();
      await expect(sessionModal.getByRole("dialog", { name: "Add session" })).toHaveCount(0);
      await expect(sessionsSection.locator(`input[value="${CFS_APPROVAL_SUBMISSION_ID}"]`)).toHaveCount(1);
      await waitForEventEditorAfterSave(
        organizerGroupPage,
        () => organizerGroupPage.locator("#pending-changes-alert:not(.hidden) #update-event-button").click(),
        {
          eventId: CFS_EVENT_ID,
          method: "PUT",
          urlIncludes: `/dashboard/group/events/${CFS_EVENT_ID}/update`,
        },
      );
      expect(readCfsApprovalSessionId()).not.toBe("");

      // Verify the public agenda renders the persisted CFS session and speaker.
      await navigateToPath(organizerGroupPage, CFS_EVENT_PUBLIC_PATH);
      await expect(organizerGroupPage.getByText("Agenda", { exact: true })).toBeVisible();
      const agendaSession = organizerGroupPage.locator("li", {
        hasText: CFS_APPROVAL_TITLE,
      });
      await expect(agendaSession).toBeVisible();
      await expect(agendaSession).toContainText(CFS_SPEAKER_NAME);
    } finally {
      // Remove the approved agenda fixture after verification.
      deleteCfsApprovalAgendaFixture();
    }
  });
});

/** Resets CFS approval session and submission rows in the database. */
const deleteCfsApprovalAgendaFixture = () => {
  queryE2eDatabase(`
    delete from session
    where event_id = '${CFS_EVENT_ID}'
    and cfs_submission_id = '${CFS_APPROVAL_SUBMISSION_ID}';

    update cfs_submission
    set
      action_required_message = null,
      reviewed_by = null,
      status_id = 'not-reviewed'
    where cfs_submission_id = '${CFS_APPROVAL_SUBMISSION_ID}';
  `);
};

/** Opens the event submissions tab and returns its content region. */
const openSubmissionsTab = async (page, query = "") => {
  await openEventUpdateFormByName(page, "Event With Active CFS", TEST_EVENT_IDS.alpha.cfsSummit);

  // The tab buttons only exist once the event update form has loaded.
  const submissionsTab = page.locator('button[data-section="submissions"]');
  if (query !== "") {
    await routeNextRequestWithQuery(
      page,
      `/dashboard/group/events/${TEST_EVENT_IDS.alpha.cfsSummit}/submissions`,
      query,
    );
  }

  await waitForActionResponse(page, () => submissionsTab.click(), {
    method: "GET",
    urlIncludes: `/dashboard/group/events/${TEST_EVENT_IDS.alpha.cfsSummit}/submissions`,
  });

  return page.locator("#submissions-content");
};

/** Returns the generated approval session ID from the session table. */
const readCfsApprovalSessionId = () =>
  queryE2eDatabase(`
    select session_id
    from session
    where event_id = '${CFS_EVENT_ID}'
    and cfs_submission_id = '${CFS_APPROVAL_SUBMISSION_ID}'
    order by created_at desc
    limit 1
  `);
