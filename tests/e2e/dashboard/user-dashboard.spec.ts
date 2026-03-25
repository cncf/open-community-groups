import type { Page } from "@playwright/test";

import { expect, test } from "../fixtures";

import {
  buildE2eUrl,
  TEST_EVENT_NAMES,
  TEST_COMMUNITY_IDS,
  TEST_GROUP_IDS,
  navigateToPath,
  selectCommunityContext,
  selectGroupContext,
} from "../utils";

const MEMBER2_USER_ID = "77777777-7777-7777-7777-777777777706";
const PENDING1_USER_ID = "77777777-7777-7777-7777-777777777707";
const PENDING2_USER_ID = "77777777-7777-7777-7777-777777777708";

type SessionProposalPayload = {
  co_speaker?: { user_id: string } | null;
  description: string;
  duration_minutes: number;
  session_proposal_id: string;
  session_proposal_level_id: string;
  title: string;
};

const openUserDashboardPath = async (path: string, page: Page) => {
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

const restoreCoSpeakerInvitation = async (
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

/**
 * Resets a community team invitation to a pending state for the target user.
 */
const resetCommunityInvitation = async (
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

/**
 * Resets a group team invitation to a pending state for the target user.
 */
const resetGroupInvitation = async (
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

/**
 * Ensures a pending group invitation exists for the target user.
 */
const ensureGroupInvitation = async (
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

const createSessionProposal = async (page: Page, title: string) => {
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

test.describe("user dashboard", () => {
  test("invitations page shows pending community and group roles", async ({
    adminCommunityPage,
    pending1Page,
  }) => {
    await resetCommunityInvitation(adminCommunityPage, PENDING1_USER_ID, "viewer");
    await resetGroupInvitation(
      adminCommunityPage,
      TEST_GROUP_IDS.community1.beta,
      PENDING1_USER_ID,
      "events-manager",
    );

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
    await expect(pendingRow).toContainText(
      /Awaiting co-speaker response|Ready for submission/,
    );

    const declinedRow = dashboardContent.locator("tr", {
      hasText: "Co-Speaker Retrospective",
    });
    await expect(declinedRow).toContainText("Declined by co-speaker");
  });

  test("user can create and delete a session proposal", async ({
    pending1Page,
  }) => {
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
    await openUserDashboardPath(
      "/dashboard/user?tab=session-proposals",
      member2Page,
    );

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
    await openUserDashboardPath(
      "/dashboard/user?tab=session-proposals",
      member2Page,
    );

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
            response
              .url()
              .includes("/co-speaker-invitation/accept"),
        ),
        acceptInvitationButton.click(),
      ]);
      invitationAccepted = true;

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
    } finally {
      if (invitationAccepted) {
        await restoreCoSpeakerInvitation(
          member1Page,
          "Collaborative Roadmaps",
          MEMBER2_USER_ID,
        );

        await openUserDashboardPath(
          "/dashboard/user?tab=session-proposals",
          member2Page,
        );
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

  test("accepting pending invitations removes them from the user dashboard", async ({
    adminCommunityPage,
    pending1Page,
  }) => {
    await resetCommunityInvitation(adminCommunityPage, PENDING1_USER_ID, "viewer");
    await resetGroupInvitation(
      adminCommunityPage,
      TEST_GROUP_IDS.community1.beta,
      PENDING1_USER_ID,
      "events-manager",
    );

    await openUserDashboardPath("/dashboard/user?tab=invitations", pending1Page);

    const dashboardContent = pending1Page.locator("#dashboard-content");
    const communityInvitationRow = dashboardContent.locator("tr", {
      hasText: "e2e-test-community",
    });
    const approveCommunityInvitationButton =
      communityInvitationRow.getByTitle("Approve");
    await expect(approveCommunityInvitationButton).toBeVisible();

    try {
      await Promise.all([
        pending1Page.waitForResponse(
          (response) =>
            response.request().method() === "PUT" &&
            response.ok() &&
            response.url().includes("/dashboard/user/invitations/community/") &&
            response.url().endsWith("/accept"),
        ),
        approveCommunityInvitationButton.click(),
      ]);

      await pending1Page.reload();

      const groupInvitationRow = dashboardContent.locator("tr", {
        hasText: "E2E Test Group Beta",
      });
      const approveGroupInvitationButton = groupInvitationRow.getByTitle("Approve");
      await expect(approveGroupInvitationButton).toBeVisible();

      await Promise.all([
        pending1Page.waitForResponse(
          (response) =>
            response.request().method() === "PUT" &&
            response.ok() &&
            response.url().includes("/dashboard/user/invitations/group/") &&
            response.url().endsWith("/accept"),
        ),
        approveGroupInvitationButton.click(),
      ]);

      await pending1Page.reload();

      await expect(
        dashboardContent.locator("tr", { hasText: "e2e-test-community" }),
      ).toHaveCount(0);
      await expect(
        dashboardContent.locator("tr", { hasText: "E2E Test Group Beta" }),
      ).toHaveCount(0);
    } finally {
      await resetCommunityInvitation(adminCommunityPage, PENDING1_USER_ID, "viewer");
      await resetGroupInvitation(
        adminCommunityPage,
        TEST_GROUP_IDS.community1.beta,
        PENDING1_USER_ID,
        "events-manager",
      );

      await openUserDashboardPath("/dashboard/user?tab=invitations", pending1Page);
      await expect(
        dashboardContent.locator("tr", { hasText: "e2e-test-community" }),
      ).toContainText("viewer");
      await expect(
        dashboardContent.locator("tr", { hasText: "E2E Test Group Beta" }),
      ).toContainText("events-manager");
    }
  });

  test("rejecting a pending group invitation removes it from the user dashboard", async ({
    organizerGroupPage,
    pending2Page,
  }) => {
    await ensureGroupInvitation(
      organizerGroupPage,
      TEST_GROUP_IDS.community1.alpha,
      PENDING2_USER_ID,
      "viewer",
    );

    await openUserDashboardPath("/dashboard/user?tab=invitations", pending2Page);

    const dashboardContent = pending2Page.locator("#dashboard-content");
    const groupInvitationRow = dashboardContent.locator("tr", {
      hasText: "E2E Test Group Alpha",
    });
    const rejectGroupInvitationButton = groupInvitationRow.getByTitle("Reject");

    try {
      await expect(
        dashboardContent.getByText("Group Invitations", { exact: true }),
      ).toBeVisible();
      await expect(rejectGroupInvitationButton).toBeVisible();

      await rejectGroupInvitationButton.click();
      await expect(pending2Page.locator(".swal2-popup")).toContainText(
        "Are you sure you would like to reject this invitation?",
      );

      await Promise.all([
        pending2Page.waitForResponse(
          (response) =>
            response.request().method() === "PUT" &&
            response.ok() &&
            response.url().includes("/dashboard/user/invitations/group/") &&
            response.url().endsWith("/reject"),
        ),
        pending2Page.getByRole("button", { name: "Yes" }).click(),
      ]);

      await pending2Page.reload();

      await expect(
        dashboardContent.locator("tr", { hasText: "E2E Test Group Alpha" }),
      ).toHaveCount(0);
    } finally {
      await ensureGroupInvitation(
        organizerGroupPage,
        TEST_GROUP_IDS.community1.alpha,
        PENDING2_USER_ID,
        "viewer",
      );
    }
  });
});
