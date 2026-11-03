import { expect, test } from "../../../fixtures.js";

import {
  cleanupCommunityTeamInvitation,
  cleanupEventEnrollment,
  cleanupGroupTeamInvitation,
  setupCommunityTeamInvitation,
  setupEventInvitation,
  setupGroupTeamInvitation,
} from "../../../data-graphs/invitations.js";
import { TEST_COMMUNITY_IDS, TEST_GROUP_IDS, TEST_USER_IDS } from "../../../seed.js";
import { enableDesktopVersion, expectAriaSnapshot, expectPageLayout } from "../../../snapshots.js";
import { openUserDashboardView } from "../aria-helpers.js";

// Name of the owned event the user without data is invited to; its dates are matched with regexes.
const INVITED_EVENT_NAME = "E2E ARIA invited event";

// The user without data gets one owned invitation of each kind, since invitation tests accept,
// decline and restore the seeded ones.
test.describe("user dashboard invitations ARIA snapshots", () => {
  test("matches the desktop views", async ({ emptyUserPage, owned }) => {
    await expectInvitationsViews({ emptyUserPage, owned });
  });

  test("matches the views in the mobile desktop version @mobile", async ({ emptyUserPage, owned }) => {
    await enableDesktopVersion(emptyUserPage);
    await expectInvitationsViews({ emptyUserPage, owned });
  });
});

/** Checks the layout of the invitations tab views and captures them. */
const expectInvitationsViews = async ({ emptyUserPage, owned }) => {
  await test.step("empty state", async () => {
    // Load the invitations of a user without invitations and check the layout.
    const content = await openUserDashboardView(emptyUserPage, "tab=invitations");

    // Capture the three sections with their column headers and empty states.
    await expectAriaSnapshot(emptyUserPage, content, "invitations-empty");
  });

  // Invite the user to an owned event, a group team and a community team.
  const userId = TEST_USER_IDS.empty;
  const { eventId } = owned.event({ groupId: TEST_GROUP_IDS.community1.alpha, name: INVITED_EVENT_NAME });
  setupEventInvitation({ eventId, userId });
  owned.defer(() => cleanupEventEnrollment({ eventId, userId }));
  setupGroupTeamInvitation({ groupId: TEST_GROUP_IDS.community1.alpha, role: "viewer", userId });
  owned.defer(() => cleanupGroupTeamInvitation({ groupId: TEST_GROUP_IDS.community1.alpha, userId }));
  setupCommunityTeamInvitation({ communityId: TEST_COMMUNITY_IDS.community1, role: "viewer", userId });
  owned.defer(() => cleanupCommunityTeamInvitation({ communityId: TEST_COMMUNITY_IDS.community1, userId }));

  await test.step("pending invitations", async () => {
    // Load the pending invitations and check the layout.
    const content = await openUserDashboardView(emptyUserPage, "tab=invitations");

    // Capture the rows of each section; the dates follow the seed day.
    await expectAriaSnapshot(emptyUserPage, content, "invitations-pending");
  });

  await test.step("event offer actions", async () => {
    // Open the actions menu of the event offer and check the layout.
    const actions = emptyUserPage
      .locator("#dashboard-content")
      .getByRole("row")
      .filter({ hasText: INVITED_EVENT_NAME })
      .getByRole("group");
    await actions.getByLabel(`Open offer actions for ${INVITED_EVENT_NAME}`).click();
    await expect(actions.getByRole("menu")).toBeVisible();
    await expectPageLayout(emptyUserPage, { regions: [actions.getByRole("menu")] });

    // Capture the claim and decline actions.
    await expectAriaSnapshot(emptyUserPage, actions, "invitations-offer-actions");
  });

  await test.step("event offer claim dialog", async () => {
    // Open the claim form of the event offer and check the layout.
    const dialog = emptyUserPage.getByRole("dialog", { name: "Claim offer" });
    await emptyUserPage.getByRole("menuitem", { name: "Claim offer" }).click();
    await expect(dialog).toBeVisible();
    await expectPageLayout(emptyUserPage, { regions: [dialog] });

    // Capture the RSVP summary and the form actions without submitting it.
    await expectAriaSnapshot(emptyUserPage, dialog, "invitations-claim-offer-dialog");
    await dialog.getByRole("button", { name: "Close modal" }).click();
    await expect(dialog).toBeHidden();
  });
};
