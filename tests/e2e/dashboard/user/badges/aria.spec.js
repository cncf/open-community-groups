import { expect, test } from "../../../fixtures.js";

import { enableDesktopVersion, expectAriaSnapshot, expectPageLayout } from "../../../snapshots.js";
import { openUserDashboardView } from "../aria-helpers.js";

// The seeded Host credential is captured: badge tests that hide, reorder or revoke seeded
// credentials restore them, and revocations use owned credentials.
test.describe("user dashboard badges ARIA snapshots", () => {
  test("matches the desktop views", async ({ emptyUserPage, member1Page }) => {
    await expectBadgesViews({ emptyUserPage, member1Page });
  });

  test("matches the views in the mobile desktop version @mobile", async ({ emptyUserPage, member1Page }) => {
    await enableDesktopVersion(emptyUserPage);
    await enableDesktopVersion(member1Page);
    await expectBadgesViews({ emptyUserPage, member1Page });
  });
});

/** Checks the layout of the badges tab views and captures them. */
const expectBadgesViews = async ({ emptyUserPage, member1Page }) => {
  await test.step("empty state", async () => {
    // Load the badges of a user without badges and check the layout.
    const badges = emptyUserPage.getByRole("region", { name: "Badges" });
    await openUserDashboardView(emptyUserPage, "tab=badges", { regions: [badges] });

    // Capture the heading, the help text and the empty state.
    await expectAriaSnapshot(emptyUserPage, badges, "badges-empty");
  });

  const hostBadge = member1Page
    .getByRole("listitem")
    .filter({ has: member1Page.getByRole("heading", { name: "Host", exact: true }) });

  await test.step("credential card", async () => {
    // Load the badges of the user with seeded credentials and check the layout.
    await openUserDashboardView(member1Page, "tab=badges", { regions: [hostBadge] });

    // Capture the Host card with its reorder handle, actions and profile toggle.
    await expectAriaSnapshot(member1Page, hostBadge, "badges-card");
  });

  await test.step("share dialog", async () => {
    // Open the share dialog of the Host credential and check the layout.
    const dialog = member1Page.getByRole("dialog", { name: "Share" });
    await hostBadge.getByRole("button", { name: "Share Host badge credential" }).click();
    await expect(dialog).toBeVisible();
    await expectPageLayout(member1Page, { regions: [dialog] });

    // Capture the share targets and the copy link; the host varies per stack.
    await expectAriaSnapshot(member1Page, dialog, "badges-share-dialog");
  });
};
