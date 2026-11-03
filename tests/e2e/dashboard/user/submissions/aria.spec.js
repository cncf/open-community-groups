import { expect, test } from "../../../fixtures.js";

import { setupCfsSubmission } from "../../../data-graphs/cfs.js";
import { TEST_EVENT_IDS, TEST_USER_IDS } from "../../../seed.js";
import { enableDesktopVersion, expectAriaSnapshot, expectPageLayout } from "../../../snapshots.js";
import { openUserDashboardView } from "../aria-helpers.js";

// Title of the owned proposal the user without data submits to the seeded open CFS.
const SUBMITTED_PROPOSAL_TITLE = "E2E ARIA submitted proposal";

// Seeded submission of the first member waiting for more information; resubmit tests restore it.
const INFORMATION_REQUESTED_PROPOSAL = "Observability in Practice";

test.describe("user dashboard submissions ARIA snapshots", () => {
  test("matches the desktop views", async ({ emptyUserPage, member1Page, owned }) => {
    await expectSubmissionsViews({ emptyUserPage, member1Page, owned });
  });

  test("matches the views in the mobile desktop version @mobile", async ({
    emptyUserPage,
    member1Page,
    owned,
  }) => {
    await enableDesktopVersion(emptyUserPage);
    await enableDesktopVersion(member1Page);
    await expectSubmissionsViews({ emptyUserPage, member1Page, owned });
  });
});

/** Checks the layout of the submissions tab views and captures them. */
const expectSubmissionsViews = async ({ emptyUserPage, member1Page, owned }) => {
  await test.step("empty state", async () => {
    // Load the submissions of a user without submissions and check the layout.
    const content = await openUserDashboardView(emptyUserPage, "tab=submissions");

    // Capture the title, the column headers and the empty state.
    await expectAriaSnapshot(emptyUserPage, content, "submissions-empty");
  });

  // Submit an owned proposal of the user to the seeded open CFS; the proposal cleanup deletes it.
  const { proposalId } = owned.sessionProposal({
    title: SUBMITTED_PROPOSAL_TITLE,
    userId: TEST_USER_IDS.empty,
  });
  setupCfsSubmission({ eventId: TEST_EVENT_IDS.alpha.cfsSummit, proposalId });

  await test.step("submission row", async () => {
    // Load the owned submission and check the layout.
    const content = await openUserDashboardView(emptyUserPage, "tab=submissions");
    const row = content.getByRole("row").filter({ hasText: SUBMITTED_PROPOSAL_TITLE });

    // Capture the row with its event, proposal, status and withdraw action.
    await expectAriaSnapshot(emptyUserPage, row, "submissions-row");
  });

  await test.step("action required dialog", async () => {
    // Load the first member's submissions and open the information request of the seeded one.
    const content = await openUserDashboardView(member1Page, "tab=submissions");
    const dialog = member1Page.getByRole("dialog", { name: "Action required" });
    await content
      .getByRole("row")
      .filter({ hasText: INFORMATION_REQUESTED_PROPOSAL })
      .getByRole("button", { name: "View action required details" })
      .click();
    await expect(dialog).toBeVisible();
    await expectPageLayout(member1Page, { regions: [dialog] });

    // Capture the organizer message and the close actions.
    await expectAriaSnapshot(member1Page, dialog, "submissions-action-required-dialog");
  });
};
