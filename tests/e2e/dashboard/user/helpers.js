import { expect } from "../../fixtures.js";
import { TEST_COMMUNITY_NAME, TEST_GROUP_SLUGS } from "../../seed.js";
import { buildE2eUrl, navigateToEvent, navigateToPath, waitForActionResponse } from "../../utils.js";
import { fillMarkdownEditor } from "../form-helpers.js";

/** Opens a user dashboard path. */
export const openUserDashboardPath = async (path, page) => {
  await navigateToPath(page, path);
};

/** Returns the session proposal payload embedded in the edit action. */
const getSessionProposalPayload = async (page, proposalTitle) => {
  await openUserDashboardPath("/dashboard/user?tab=session-proposals", page);

  const editButton = page
    .locator("#dashboard-content")
    .locator("tr", { hasText: proposalTitle })
    .locator('button[data-action="edit-session-proposal"]');
  const proposalJson = await editButton.getAttribute("data-session-proposal");

  expect(proposalJson).not.toBeNull();

  return JSON.parse(proposalJson ?? "{}");
};

/** Restores a co-speaker invitation through dashboard requests. */
export const restoreCoSpeakerInvitation = async (page, proposalTitle, coSpeakerUserId) => {
  const proposal = await getSessionProposalPayload(page, proposalTitle);
  const baseForm = {
    description: proposal.description,
    duration_minutes: String(proposal.duration_minutes),
    session_proposal_level_id: proposal.session_proposal_level_id,
    title: proposal.title,
  };

  const clearCoSpeakerResponse = await page.request.put(
    `/dashboard/user/session-proposals/${proposal.session_proposal_id}`,
    {
      form: baseForm,
    },
  );
  expect(clearCoSpeakerResponse.ok()).toBeTruthy();

  const restoreInvitationResponse = await page.request.put(
    `/dashboard/user/session-proposals/${proposal.session_proposal_id}`,
    {
      form: {
        ...baseForm,
        co_speaker_user_id: coSpeakerUserId,
      },
    },
  );
  expect(restoreInvitationResponse.ok()).toBeTruthy();
};

/** Deletes event attendee state through the dashboard request API. */
export const clearEventAttendeeState = async (page, eventId, userId) => {
  await page.request.delete(buildE2eUrl(`/dashboard/group/events/${eventId}/attendees/${userId}/attendance`));
};

/** Creates a reusable session proposal and returns the dashboard content. */
export const createSessionProposal = async (page, title) => {
  await openUserDashboardPath("/dashboard/user?tab=session-proposals", page);

  const dashboardContent = page.locator("#dashboard-content");
  await expect(dashboardContent.getByText("Session proposals", { exact: true })).toBeVisible();

  await page.getByRole("button", { name: "New proposal" }).click();

  const modal = page.getByRole("dialog", { name: "New session proposal" });
  await expect(modal).toBeVisible();

  await modal.getByLabel("Title").fill(title);
  await modal.getByLabel("Level").selectOption("intermediate");
  await modal.getByLabel("Duration (minutes)").fill("45");
  await fillMarkdownEditor(
    page,
    "session-proposal-description",
    "A reusable proposal created from the e2e suite.",
  );

  await waitForActionResponse(page, () => modal.getByRole("button", { name: "Save" }).click(), {
    method: "POST",
    status: 201,
    urlIncludes: "/dashboard/user/session-proposals",
  });

  await expect(modal).toBeHidden();
  return dashboardContent;
};

/** Returns the purchases dashboard row matching the event name. */
export const getPurchaseRow = (dashboardContent, eventName) =>
  dashboardContent.locator("tbody tr", { hasText: eventName });

/** Opens the user purchases dashboard and returns the loaded content region. */
export const openPurchasesDashboard = async (page) => {
  await openUserDashboardPath("/dashboard/user?tab=purchases", page);

  const dashboardContent = page.locator("#dashboard-content");
  await expect(dashboardContent.getByText("Purchases & documents", { exact: true })).toBeVisible();

  return dashboardContent;
};

/** Submits a session proposal to the open CFS event. */
export const submitProposalToOpenCfsEvent = async (page, proposalTitle) => {
  await navigateToEvent(page, TEST_COMMUNITY_NAME, TEST_GROUP_SLUGS.community1.alpha, "alpha-cfs-summit");

  await page.getByRole("button", { name: "Submit session proposal" }).click();

  const modal = page.getByRole("dialog", { name: "Submit a proposal" });
  await expect(modal).toBeVisible();

  await modal.locator("#session_proposal_id").selectOption({ label: proposalTitle });

  await waitForActionResponse(page, () => modal.getByRole("button", { name: "Submit proposal" }).click(), {
    method: "POST",
    urlIncludes: "/cfs-submissions",
  });

  await expect(modal.getByText("Submission received. We'll review it soon.")).toBeVisible();
};
