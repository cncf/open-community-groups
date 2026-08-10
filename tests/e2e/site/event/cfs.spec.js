import { expect, test } from "../../fixtures.js";

import {
  TEST_CFS_WINDOW_EVENTS,
  TEST_COMMUNITY_NAME,
  TEST_EVENT_IDS,
  TEST_GROUP_SLUGS,
  navigateToEvent,
  waitForActionResponse,
} from "../../utils.js";

const CFS_EVENT_SLUG = "alpha-cfs-summit";

test.describe("event page call for speakers", () => {
  for (const [windowState, cfsEvent] of Object.entries(TEST_CFS_WINDOW_EVENTS)) {
    test(`${windowState} submission windows explain why proposals are disabled`, async ({ page }) => {
      // Load the event representing the current submission window state.
      await navigateToEvent(page, TEST_COMMUNITY_NAME, TEST_GROUP_SLUGS.community1.alpha, cfsEvent.slug);

      // Verify the event and Call for Speakers section are visible.
      await expect(page.getByRole("heading", { level: 1, name: cfsEvent.name })).toBeVisible();
      await expect(page.getByText("Call for Speakers", { exact: true })).toBeVisible();

      // Find the proposal action and verify its state-specific explanation.
      const submitButton = page.getByRole("button", {
        name: "Submit session proposal",
      });
      await expect(submitButton).toBeDisabled();
      await expect(submitButton).toHaveAttribute(
        "title",
        windowState === "upcoming" ? "Call for Speakers will open soon" : "Call for Speakers is now closed",
      );
    });
  }

  test("public event page renders the call for speakers section for an open event", async ({ page }) => {
    // Load the event page with an open call for speakers.
    await navigateToEvent(page, TEST_COMMUNITY_NAME, TEST_GROUP_SLUGS.community1.alpha, CFS_EVENT_SLUG);

    // Verify the call for speakers section describes the open submission.
    await expect(page.getByText("Call for Speakers", { exact: true })).toBeVisible();
    await expect(page.getByText(/Submissions open:/)).toBeVisible();
    await expect(page.getByRole("button", { name: "Submit session proposal" })).toBeEnabled();
  });

  test("anonymous users are prompted to sign in before opening the submission flow", async ({ page }) => {
    // Load the CFS event as a guest.
    await navigateToEvent(page, TEST_COMMUNITY_NAME, TEST_GROUP_SLUGS.community1.alpha, CFS_EVENT_SLUG);

    // Request proposal submission from the public event page.
    await page.getByRole("button", { name: "Submit session proposal" }).click();

    // Verify guests are prompted to sign in before submitting proposals.
    await expect(page.getByText("You need to sign in to submit a proposal for this event.")).toBeVisible();
    await expect(page.getByRole("link", { name: "Sign in" })).toBeVisible();
  });

  test("logged in users without proposals see a link to manage session proposals", async ({
    adminCommunityPage,
  }) => {
    // Load the CFS event as a logged-in user without proposals.
    await navigateToEvent(
      adminCommunityPage,
      TEST_COMMUNITY_NAME,
      TEST_GROUP_SLUGS.community1.alpha,
      CFS_EVENT_SLUG,
    );

    // Open the proposal submission modal.
    await adminCommunityPage.getByRole("button", { name: "Submit session proposal" }).click();

    // Target the empty proposal modal and manage link.
    const modal = adminCommunityPage.getByRole("dialog", {
      name: "Submit a proposal",
    });
    const manageLink = modal.getByRole("link", {
      name: "Manage session proposals",
    });

    // Verify members without proposals can reach proposal management.
    await expect(
      modal.getByText("It looks like you haven't created any session proposals yet."),
    ).toBeVisible();
    await expect(manageLink).toHaveAttribute("href", "/dashboard/user?tab=session-proposals");
  });

  test("the submit proposal modal distinguishes eligible and already-submitted proposals", async ({
    member1Page,
  }) => {
    // Load the CFS event as a member with proposal options.
    await navigateToEvent(
      member1Page,
      TEST_COMMUNITY_NAME,
      TEST_GROUP_SLUGS.community1.alpha,
      CFS_EVENT_SLUG,
    );

    // Open the proposal submission modal.
    await member1Page.getByRole("button", { name: "Submit session proposal" }).click();

    // Verify the proposal modal separates eligible and submitted proposals.
    await expect(member1Page.getByRole("dialog", { name: "Submit a proposal" })).toBeVisible();
    await expect(member1Page.locator("#session_proposal_id")).toBeVisible();
    await expect(member1Page.locator("cfs-label-selector")).toBeVisible();
    await expect(
      member1Page.getByText("Proposals already submitted to this event will appear disabled."),
    ).toBeVisible();

    // Find the ready option.
    const readyOption = member1Page.locator('option[value="99999999-9999-9999-9999-999999999801"]');
    const submittedOption = member1Page.locator('option[value="99999999-9999-9999-9999-999999999802"]');

    // Assert the expected text is rendered.
    await expect(readyOption).toContainText("Cloud Native Operations Deep Dive");
    await expect(submittedOption).toContainText("Platform Reliability Patterns");
    await expect(submittedOption).toHaveAttribute("disabled", "");
  });

  test("proposal submission stays disabled until an eligible proposal is selected", async ({
    member1Page,
  }) => {
    // Load the open Call for Speakers event as a member with proposals.
    await navigateToEvent(
      member1Page,
      TEST_COMMUNITY_NAME,
      TEST_GROUP_SLUGS.community1.alpha,
      CFS_EVENT_SLUG,
    );

    // Open the proposal submission modal.
    const openModalButton = member1Page.getByRole("button", {
      name: "Submit session proposal",
    });
    await openModalButton.click();

    // Find the proposal controls and verify submission starts disabled.
    const modal = member1Page.getByRole("dialog", {
      name: "Submit a proposal",
    });
    const proposalSelect = modal.getByLabel("Session proposal");
    const submitButton = modal.getByRole("button", {
      name: "Submit proposal",
    });
    await expect(submitButton).toBeDisabled();
    await expect(
      modal.getByText("Optional labels help organizers categorize your submission."),
    ).toBeVisible();

    // Select an eligible proposal and verify submission becomes available.
    await proposalSelect.selectOption("99999999-9999-9999-9999-999999999801");
    await expect(submitButton).toBeEnabled();

    // Cancel the flow and verify the public action remains available.
    await modal.getByRole("button", { name: "Cancel" }).click();
    await expect(modal).toBeHidden();
    await expect(openModalButton).toBeVisible();
  });

  test("failed proposal submission preserves the selection for retry", async ({
    member1Page,
  }) => {
    // Load the open CFS event before intercepting its submission endpoint.
    await navigateToEvent(
      member1Page,
      TEST_COMMUNITY_NAME,
      TEST_GROUP_SLUGS.community1.alpha,
      CFS_EVENT_SLUG,
    );
    const submissionPath =
      `**/${TEST_COMMUNITY_NAME}/event/${TEST_EVENT_IDS.alpha.cfsSummit}/cfs-submissions`;
    try {
      await member1Page.route(submissionPath, (route) =>
        route.fulfill({
          body: "Temporary proposal failure",
          contentType: "text/plain",
          status: 500,
        }),
      );

      // Select an eligible proposal and submit the simulated failure.
      await member1Page
        .getByRole("button", { name: "Submit session proposal" })
        .click();
      const modal = member1Page.getByRole("dialog", {
        name: "Submit a proposal",
      });
      const proposalSelect = modal.getByLabel("Session proposal");
      const submitButton = modal.getByRole("button", {
        name: "Submit proposal",
      });
      await proposalSelect.selectOption(
        "99999999-9999-9999-9999-999999999801",
      );
      await waitForActionResponse(member1Page, () => submitButton.click(), {
        method: "POST",
        status: 500,
        urlIncludes: "/cfs-submissions",
      });

      // Verify the modal keeps the user's choice and restores retry controls.
      await expect(modal).toBeVisible();
      await expect(proposalSelect).toHaveValue(
        "99999999-9999-9999-9999-999999999801",
      );
      await expect(submitButton).toBeEnabled();
    } finally {
      await member1Page.unroute(submissionPath);
    }
  });
});
