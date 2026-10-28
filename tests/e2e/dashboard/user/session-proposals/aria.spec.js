import { expect, test } from "../../../fixtures.js";

import { TEST_USER_IDS } from "../../../seed.js";
import { enableDesktopVersion, expectAriaSnapshot, expectPageLayout } from "../../../snapshots.js";
import { openUserDashboardView } from "../aria-helpers.js";

// Seeded proposal of the first member awaiting the second member's co-speaker answer; co-speaker
// tests restore the invitation after answering it.
const CO_SPEAKER_PROPOSAL = "Collaborative Roadmaps";

// Title of the owned proposal of the user without data.
const OWNED_PROPOSAL_TITLE = "E2E ARIA session proposal";

test.describe("user dashboard session proposals ARIA snapshots", () => {
  test("matches the desktop views", async ({ emptyUserPage, member2Page, owned }) => {
    await expectSessionProposalsViews({ emptyUserPage, member2Page, owned });
  });

  test("matches the views in the mobile desktop version @mobile", async ({
    emptyUserPage,
    member2Page,
    owned,
  }) => {
    await enableDesktopVersion(emptyUserPage);
    await enableDesktopVersion(member2Page);
    await expectSessionProposalsViews({ emptyUserPage, member2Page, owned });
  });
});

/** Checks the layout of the session proposals tab views and captures them. */
const expectSessionProposalsViews = async ({ emptyUserPage, member2Page, owned }) => {
  await test.step("empty state", async () => {
    // Load the proposals of a user without proposals and check the layout.
    const content = await openUserDashboardView(emptyUserPage, "tab=session-proposals");

    // Capture the title, the new proposal button, the column headers and the empty state.
    await expectAriaSnapshot(emptyUserPage, content, "session-proposals-empty");
  });

  await test.step("new proposal dialog", async () => {
    // Open the new proposal form and check the layout.
    const dialog = emptyUserPage.getByRole("dialog", { name: "New session proposal" });
    await emptyUserPage.getByRole("button", { name: "New proposal" }).click();
    await expect(dialog).toBeVisible();
    await expectPageLayout(emptyUserPage, { regions: [dialog] });

    // Capture the empty form with the markdown editor toolbar.
    await expectAriaSnapshot(emptyUserPage, dialog, "session-proposals-new-dialog");
  });

  // Give the user an owned proposal ready for submission.
  owned.sessionProposal({ title: OWNED_PROPOSAL_TITLE, userId: TEST_USER_IDS.empty });
  const row = emptyUserPage
    .locator("#dashboard-content")
    .getByRole("row")
    .filter({ hasText: OWNED_PROPOSAL_TITLE });

  await test.step("proposal row", async () => {
    // Load the owned proposal and check the layout.
    await openUserDashboardView(emptyUserPage, "tab=session-proposals", { regions: [row] });

    // Capture the row with its status and actions.
    await expectAriaSnapshot(emptyUserPage, row, "session-proposals-row");
  });

  await test.step("edit proposal dialog", async () => {
    // Open the update form of the owned proposal and check the layout.
    const dialog = emptyUserPage.getByRole("dialog", { name: "Edit session proposal" });
    await row.getByRole("button", { name: "Edit proposal" }).click();
    await expect(dialog).toBeVisible();
    await expectPageLayout(emptyUserPage, { regions: [dialog] });

    // Capture the form filled with the proposal.
    await expectAriaSnapshot(emptyUserPage, dialog, "session-proposals-edit-dialog");
    await dialog.getByRole("button", { name: "Cancel" }).click();
    await expect(dialog).toBeHidden();
  });

  await test.step("proposal details dialog", async () => {
    // Open the details of the owned proposal and check the layout.
    const dialog = emptyUserPage.getByRole("dialog", { name: "Session proposal details" });
    await row.getByRole("button", { name: "View proposal" }).click();
    await expect(dialog).toBeVisible();
    await expectPageLayout(emptyUserPage, { regions: [dialog] });

    // Capture the read-only proposal details.
    await expectAriaSnapshot(emptyUserPage, dialog, "session-proposals-view-dialog");
  });

  await test.step("co-speaker invitations", async () => {
    // Load the proposals of the second member, invited as co-speaker, and check the layout.
    const content = member2Page.locator("#dashboard-content");
    const alert = content.getByRole("alert");
    const invitations = content.getByRole("table").filter({ hasText: CO_SPEAKER_PROPOSAL });
    await openUserDashboardView(member2Page, "tab=session-proposals", { regions: [alert, invitations] });

    // Capture the pending invitations alert.
    await expectAriaSnapshot(member2Page, alert, "session-proposals-co-speaker-alert");

    // Capture the invitations table; the update date follows the seed day.
    await expectAriaSnapshot(member2Page, invitations, "session-proposals-co-speaker-invitations");
  });
};
