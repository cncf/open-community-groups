import { expect, test } from "../../fixtures.js";

import {
  TEST_COMMUNITY_NAME,
  TEST_GROUP_SLUGS,
  navigateToEvent,
} from "../../utils.js";

const CFS_EVENT_SLUG = "alpha-cfs-summit";

test.describe("event page call for speakers", () => {
  test("public event page renders the call for speakers section for an open event", async ({
    page,
  }) => {
    // Load the event page with an open call for speakers.
    await navigateToEvent(
      page,
      TEST_COMMUNITY_NAME,
      TEST_GROUP_SLUGS.community1.alpha,
      CFS_EVENT_SLUG,
    );

    // Verify the call for speakers section describes the open submission.
    await expect(
      page.getByText("Call for Speakers", { exact: true }),
    ).toBeVisible();
    await expect(page.getByText(/Submissions open:/)).toBeVisible();
    await expect(
      page.getByRole("button", { name: "Submit session proposal" }),
    ).toBeEnabled();
  });

  test("anonymous users are prompted to sign in before opening the submission flow", async ({
    page,
  }) => {
    // Load the CFS event as a guest.
    await navigateToEvent(
      page,
      TEST_COMMUNITY_NAME,
      TEST_GROUP_SLUGS.community1.alpha,
      CFS_EVENT_SLUG,
    );

    // Request proposal submission from the public event page.
    await page.getByRole("button", { name: "Submit session proposal" }).click();

    // Verify guests are prompted to sign in before submitting proposals.
    await expect(
      page.getByText(
        "You need to sign in to submit a proposal for this event.",
      ),
    ).toBeVisible();
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
    await adminCommunityPage
      .getByRole("button", { name: "Submit session proposal" })
      .click();

    // Target the empty proposal modal and manage link.
    const modal = adminCommunityPage.getByRole("dialog", {
      name: "Submit a proposal",
    });
    const manageLink = modal.getByRole("link", {
      name: "Manage session proposals",
    });

    // Verify members without proposals can reach proposal management.
    await expect(
      modal.getByText(
        "It looks like you haven't created any session proposals yet.",
      ),
    ).toBeVisible();
    await expect(manageLink).toHaveAttribute(
      "href",
      "/dashboard/user?tab=session-proposals",
    );
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
    await member1Page
      .getByRole("button", { name: "Submit session proposal" })
      .click();

    // Verify the proposal modal separates eligible and submitted proposals.
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

    await expect(readyOption).toContainText(
      "Cloud Native Operations Deep Dive",
    );
    await expect(submittedOption).toContainText(
      "Platform Reliability Patterns",
    );
    await expect(submittedOption).toHaveAttribute("disabled", "");
  });
});
