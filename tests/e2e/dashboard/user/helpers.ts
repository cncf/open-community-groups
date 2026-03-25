import type { Page } from "@playwright/test";

import { expect } from "../../fixtures";
import {
  buildE2eUrl,
  TEST_COMMUNITY_IDS,
  navigateToPath,
  selectCommunityContext,
  selectGroupContext,
} from "../../utils";

type SessionProposalPayload = {
  co_speaker?: { user_id: string } | null;
  description: string;
  duration_minutes: number;
  session_proposal_id: string;
  session_proposal_level_id: string;
  title: string;
};

export const openUserDashboardPath = async (path: string, page: Page) => {
  await navigateToPath(page, path);
};

const getSessionProposalPayload = async (
  page: Page,
  proposalTitle: string,
): Promise<SessionProposalPayload> => {
  await openUserDashboardPath("/dashboard/user?tab=session-proposals", page);

  const editButton = page
    .locator("#dashboard-content")
    .locator("tr", { hasText: proposalTitle })
    .locator('button[data-action="edit-session-proposal"]');
  const proposalJson = await editButton.getAttribute("data-session-proposal");

  expect(proposalJson).not.toBeNull();

  return JSON.parse(proposalJson ?? "{}") as SessionProposalPayload;
};

export const restoreCoSpeakerInvitation = async (
  page: Page,
  proposalTitle: string,
  coSpeakerUserId: string,
) => {
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

export const resetCommunityInvitation = async (
  page: Page,
  userId: string,
  role: string,
) => {
  await selectCommunityContext(page, TEST_COMMUNITY_IDS.community1);

  const deleteResponse = await page.request.delete(
    buildE2eUrl(`/dashboard/community/team/${userId}/delete`),
  );
  expect([200, 204, 400, 404].includes(deleteResponse.status())).toBeTruthy();

  const addResponse = await page.request.post(
    buildE2eUrl("/dashboard/community/team/add"),
    {
      form: {
        role,
        user_id: userId,
      },
    },
  );
  expect(addResponse.ok()).toBeTruthy();
};

export const resetGroupInvitation = async (
  page: Page,
  groupId: string,
  userId: string,
  role: string,
) => {
  await selectGroupContext(page, TEST_COMMUNITY_IDS.community1, groupId);

  const deleteResponse = await page.request.delete(
    buildE2eUrl(`/dashboard/group/team/${userId}/delete`),
  );
  expect([200, 204, 400, 404].includes(deleteResponse.status())).toBeTruthy();

  const addResponse = await page.request.post(
    buildE2eUrl("/dashboard/group/team/add"),
    {
      form: {
        role,
        user_id: userId,
      },
    },
  );
  expect(addResponse.ok()).toBeTruthy();
};

export const ensureGroupInvitation = async (
  page: Page,
  groupId: string,
  userId: string,
  role: string,
) => {
  await selectGroupContext(page, TEST_COMMUNITY_IDS.community1, groupId);

  const addResponse = await page.request.post(
    buildE2eUrl("/dashboard/group/team/add"),
    {
      form: {
        role,
        user_id: userId,
      },
    },
  );
  expect(addResponse.status()).toBeLessThan(500);
};

export const createSessionProposal = async (page: Page, title: string) => {
  await openUserDashboardPath("/dashboard/user?tab=session-proposals", page);

  const dashboardContent = page.locator("#dashboard-content");
  await expect(
    dashboardContent.getByText("Session proposals", { exact: true }),
  ).toBeVisible();

  await page.getByRole("button", { name: "New proposal" }).click();

  const modal = page.getByRole("dialog", { name: "New session proposal" });
  await expect(modal).toBeVisible();

  await modal.getByLabel("Title").fill(title);
  await modal.getByLabel("Level").selectOption("intermediate");
  await modal.getByLabel("Duration (minutes)").fill("45");
  await modal
    .locator("markdown-editor#session-proposal-description .CodeMirror textarea")
    .fill("A reusable proposal created from the e2e suite.");

  await Promise.all([
    page.waitForResponse(
      (response) =>
        response.request().method() === "POST" &&
        response.url().includes("/dashboard/user/session-proposals") &&
        response.status() === 201,
    ),
    modal.getByRole("button", { name: "Save" }).click(),
  ]);

  await expect(modal).toBeHidden();
  return dashboardContent;
};
