import { expect, test } from "../../../fixtures.js";

import { cleanupGroupMute, setupGroupMute } from "../../../data-graphs/notification-preferences.js";
import { TEST_GROUP_IDS, TEST_USER_IDS } from "../../../seed.js";
import { enableDesktopVersion, expectAriaSnapshot, expectPageLayout } from "../../../snapshots.js";
import { openUserDashboardView } from "../aria-helpers.js";

// Preference tests restore the categories they change, so the seeded checkbox states are captured.
test.describe("user dashboard notifications ARIA snapshots", () => {
  test("matches the desktop views", async ({ emptyUserPage, member1Page, organizerGroupPage, owned }) => {
    await expectNotificationsViews({ emptyUserPage, member1Page, organizerGroupPage, owned });
  });

  test("matches the views in the mobile desktop version @mobile", async ({
    emptyUserPage,
    member1Page,
    organizerGroupPage,
    owned,
  }) => {
    await enableDesktopVersion(emptyUserPage);
    await enableDesktopVersion(member1Page);
    await enableDesktopVersion(organizerGroupPage);
    await expectNotificationsViews({ emptyUserPage, member1Page, organizerGroupPage, owned });
  });
});

/** Checks the layout of the notifications tab views and captures them. */
const expectNotificationsViews = async ({ emptyUserPage, member1Page, organizerGroupPage, owned }) => {
  await test.step("member preferences and muted groups", async () => {
    // Load the notifications of a user without groups and check the layout.
    const form = emptyUserPage.locator("#notification-preferences-form");
    const mutedGroups = emptyUserPage.getByRole("region", { name: "Muted groups" });
    await openUserDashboardView(emptyUserPage, "tab=notifications", { regions: [form, mutedGroups] });

    // Capture the member categories with their descriptions.
    await expectAriaSnapshot(emptyUserPage, form, "notifications-preferences-form");

    // Capture the mute picker and the empty muted groups list.
    await expectAriaSnapshot(emptyUserPage, mutedGroups, "notifications-muted-groups-empty");
  });

  await test.step("always sent dialog", async () => {
    // Open the list of emails that are always sent and check the layout.
    const dialog = emptyUserPage.getByRole("dialog", { name: "Always sent" });
    await emptyUserPage
      .getByRole("button", { name: "things that need your attention are always sent" })
      .click();
    await expect(dialog).toBeVisible();
    await expectPageLayout(emptyUserPage, { regions: [dialog] });

    // Capture the always sent email kinds.
    await expectAriaSnapshot(emptyUserPage, dialog, "notifications-always-sent-dialog");
  });

  await test.step("organizer preferences", async () => {
    // Load the notifications of a group organizer and check the layout.
    const form = organizerGroupPage.locator("#notification-preferences-form");
    await openUserDashboardView(organizerGroupPage, "tab=notifications", { regions: [form] });

    // Capture the categories, with the group organizing ones only team members get.
    await expectAriaSnapshot(organizerGroupPage, form, "notifications-preferences-form-organizer");
  });

  await test.step("muted group", async () => {
    // Mute the seeded group for the first member, then load the list and check the layout.
    setupGroupMute({ groupId: TEST_GROUP_IDS.community1.alpha, userId: TEST_USER_IDS.member1 });
    owned.defer(() =>
      cleanupGroupMute({ groupId: TEST_GROUP_IDS.community1.alpha, userId: TEST_USER_IDS.member1 }),
    );
    const mutedGroups = member1Page.getByRole("region", { name: "Muted groups" });
    await openUserDashboardView(member1Page, "tab=notifications", { regions: [mutedGroups] });

    // Capture the muted group row and its unmute action.
    await expectAriaSnapshot(member1Page, mutedGroups.getByRole("list"), "notifications-muted-group");
  });
};
