import type { Page } from "@playwright/test";

import { expect, test } from "../../fixtures";

import {
  TEST_COMMUNITY_NAME,
  TEST_GROUP_SLUGS,
  navigateToPath,
  navigateToEvent,
} from "../../utils";

const CFS_EVENT_SLUG = "alpha-cfs-summit";

/** Creates a new reusable session proposal from the user dashboard. */
const createSessionProposal = async (title: string, page: Page) => {
  await navigateToPath(page, "/dashboard/user?tab=session-proposals");

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
    .fill("A proposal created from the e2e suite.");

  await Promise.all([
    page.waitForResponse(
      (response) =>
        response.request().method() === "POST" &&
        response.url().includes("/dashboard/user/session-proposals") &&
        response.ok(),
    ),
    modal.getByRole("button", { name: "Save" }).click(),
  ]);

  await expect(modal).toBeHidden();
  await expect(dashboardContent.locator("tr", { hasText: title })).toContainText(
    "Ready for submission",
  );
};

/** Submits a reusable proposal to the open CFS event from the public event page. */
const submitProposalToCfs = async (proposalTitle: string, page: Page) => {
  await navigateToEvent(
    page,
    TEST_COMMUNITY_NAME,
    TEST_GROUP_SLUGS.community1.alpha,
    CFS_EVENT_SLUG,
  );

  await page.getByRole("button", { name: "Submit session proposal" }).click();

  const modal = page.getByRole("dialog", { name: "Submit a proposal" });
  await expect(modal).toBeVisible();

  await modal.locator("#session_proposal_id").selectOption({ label: proposalTitle });

  await Promise.all([
    page.waitForResponse(
      (response) =>
        response.request().method() === "POST" &&
        response.url().includes("/cfs-submissions") &&
        response.ok(),
    ),
    modal.getByRole("button", { name: "Submit proposal" }).click(),
  ]);

  await expect(modal.getByText("Submission received. We'll review it soon.")).toBeVisible();
};

test.describe("call for speakers", () => {
  test("public event page renders the CFS section for an open event", async ({
    page,
  }) => {
    await navigateToEvent(
      page,
      TEST_COMMUNITY_NAME,
      TEST_GROUP_SLUGS.community1.alpha,
      CFS_EVENT_SLUG,
    );

    await expect(page.getByText("Call for Speakers", { exact: true })).toBeVisible();
    await expect(page.getByText(/Submissions open:/)).toBeVisible();
    await expect(
      page.getByRole("button", { name: "Submit session proposal" }),
    ).toBeEnabled();
  });

  test("anonymous users are prompted to sign in before submitting", async ({
    page,
  }) => {
    await navigateToEvent(
      page,
      TEST_COMMUNITY_NAME,
      TEST_GROUP_SLUGS.community1.alpha,
      CFS_EVENT_SLUG,
    );

    await page.getByRole("button", { name: "Submit session proposal" }).click();

    await expect(
      page.getByText("You need to sign in to submit a proposal for this event."),
    ).toBeVisible();
    await expect(page.getByRole("link", { name: "Sign in" })).toBeVisible();
  });

  test("logged in users without proposals are sent to manage session proposals", async ({
    adminCommunityPage,
  }) => {
    await navigateToEvent(
      adminCommunityPage,
      TEST_COMMUNITY_NAME,
      TEST_GROUP_SLUGS.community1.alpha,
      CFS_EVENT_SLUG,
    );

    await adminCommunityPage
      .getByRole("button", { name: "Submit session proposal" })
      .click();

    const modal = adminCommunityPage.getByRole("dialog", { name: "Submit a proposal" });
    const manageLink = modal.getByRole("link", { name: "Manage session proposals" });

    await expect(
      modal.getByText("It looks like you haven't created any session proposals yet."),
    ).toBeVisible();
    await expect(manageLink).toHaveAttribute("href", "/dashboard/user?tab=session-proposals");

    await Promise.all([
      adminCommunityPage.waitForURL(/\/dashboard\/user\?tab=session-proposals/),
      manageLink.click(),
    ]);

    await expect(
      adminCommunityPage.locator("#dashboard-content").getByText(
        "Session proposals",
        { exact: true },
      ),
    ).toBeVisible();
  });

  test("eligible and already-submitted proposals are distinguished in the modal", async ({
    member1Page,
  }) => {
    await navigateToEvent(
      member1Page,
      TEST_COMMUNITY_NAME,
      TEST_GROUP_SLUGS.community1.alpha,
      CFS_EVENT_SLUG,
    );

    await member1Page
      .getByRole("button", { name: "Submit session proposal" })
      .click();

    await expect(
      member1Page.getByRole("dialog", { name: "Submit a proposal" }),
    ).toBeVisible();
    await expect(member1Page.locator("#session_proposal_id")).toBeVisible();
    await expect(member1Page.locator("cfs-label-selector")).toBeVisible();
    await expect(
      member1Page.getByText(
        "Proposals already submitted to this event will appear disabled.",
      ),
    ).toBeVisible();

    const readyOption = member1Page.locator(
      'option[value="99999999-9999-9999-9999-999999999801"]',
    );
    const submittedOption = member1Page.locator(
      'option[value="99999999-9999-9999-9999-999999999802"]',
    );

    await expect(readyOption).toContainText("Cloud Native Operations Deep Dive");
    await expect(submittedOption).toContainText("Platform Reliability Patterns");
    await expect(submittedOption).toHaveAttribute("disabled", "");
  });

  test("user can create a proposal and submit it to the open CFS event", async ({
    pending1Page,
  }) => {
    const proposalTitle = `Pending1 CFS proposal ${Date.now()}`;

    await createSessionProposal(proposalTitle, pending1Page);
    await submitProposalToCfs(proposalTitle, pending1Page);

    await navigateToPath(pending1Page, "/dashboard/user?tab=submissions");

    const dashboardContent = pending1Page.locator("#dashboard-content");
    const submissionRow = dashboardContent.locator("tr", { hasText: proposalTitle });

    await expect(dashboardContent.getByText("Submissions", { exact: true })).toBeVisible();
    await expect(submissionRow).toContainText("Event With Active CFS");
    await expect(submissionRow).toContainText("Not reviewed");
  });

  test("user can withdraw a newly submitted CFS submission", async ({
    pending2Page,
  }) => {
    const proposalTitle = `Pending2 CFS proposal ${Date.now()}`;

    await createSessionProposal(proposalTitle, pending2Page);
    await submitProposalToCfs(proposalTitle, pending2Page);

    await navigateToPath(pending2Page, "/dashboard/user?tab=submissions");

    const dashboardContent = pending2Page.locator("#dashboard-content");
    const submissionRow = dashboardContent.locator("tr", { hasText: proposalTitle });
    const withdrawButton = submissionRow.getByTitle("Withdraw");

    await expect(dashboardContent.getByText("Submissions", { exact: true })).toBeVisible();
    await expect(submissionRow).toContainText("Not reviewed");
    await expect(withdrawButton).toBeVisible();

    await withdrawButton.click();
    await expect(pending2Page.locator(".swal2-popup")).toContainText(
      "Are you sure you want to withdraw this submission?",
    );

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

    await pending2Page.reload();

    const withdrawnRow = pending2Page.locator("#dashboard-content").locator("tr", {
      hasText: proposalTitle,
    });
    await expect(withdrawnRow).toContainText("Withdrawn");
    await expect(
      withdrawnRow.getByTitle("This submission has been withdrawn and cannot be removed."),
    ).toBeDisabled();
  });
});
