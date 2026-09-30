import { expect, test } from "../../../fixtures.js";

import { queryE2eDatabase } from "../../../database.js";
import { TEST_GROUP_IDS, TEST_GROUP_NAMES, TEST_USER_IDS } from "../../../seed.js";
import { navigateToPath, waitForActionResponse, waitForHtmxSettle } from "../../../utils.js";

const NOTIFICATIONS_PATH = "/dashboard/user?tab=notifications";

test.describe("user dashboard notifications view", () => {
  test("shows notification sections for member, group organizer, and community admin roles", async ({
    adminCommunityPage,
    member1Page,
    organizerGroupPage,
  }) => {
    // Verify a regular group member sees only member preference sections.
    await navigateToPath(member1Page, NOTIFICATIONS_PATH);
    await expectPreferenceSections(member1Page, {
      hidden: ["Group organizing", "Community organizing"],
      visible: ["Events and groups"],
    });
    await expect(member1Page.getByRole("heading", { name: "Always sent" })).toBeVisible();
    await expect(member1Page.getByRole("heading", { name: "Muted groups" })).toBeVisible();

    // Verify an accepted group admin sees the group organizing categories.
    await navigateToPath(organizerGroupPage, NOTIFICATIONS_PATH);
    await expectPreferenceSections(organizerGroupPage, {
      hidden: ["Community organizing"],
      visible: ["Events and groups", "Group organizing"],
    });

    // Verify an accepted community admin sees community organizing categories.
    await navigateToPath(adminCommunityPage, NOTIFICATIONS_PATH);
    await expectPreferenceSections(adminCommunityPage, {
      hidden: [],
      visible: ["Events and groups", "Group organizing", "Community organizing"],
    });
  });

  test("saved toggle persists across reload", async ({ member1Page }) => {
    const category = "event-reminders";
    let originalPreference;

    try {
      // Save the opposite preference through the notifications form.
      await navigateToPath(member1Page, NOTIFICATIONS_PATH);
      originalPreference = await getPreferenceToggle(member1Page, category).isChecked();
      await saveNotificationPreference(member1Page, category, !originalPreference);

      // Reload the tab and verify the saved state persists.
      await navigateToPath(member1Page, NOTIFICATIONS_PATH);
      await expectPreferenceState(member1Page, category, !originalPreference);
    } finally {
      if (typeof originalPreference === "boolean") {
        restoreNotificationPreference(TEST_USER_IDS.member1, category, originalPreference);
      }
    }
  });

  test("user can mute and unmute a group from the combobox", async ({ member1Page }) => {
    const groupId = TEST_GROUP_IDS.community1.alpha;
    const groupName = TEST_GROUP_NAMES.alpha;

    try {
      // Load the notifications tab with no muted groups for this scenario.
      clearGroupMute(TEST_USER_IDS.member1, groupId);
      await navigateToPath(member1Page, NOTIFICATIONS_PATH);
      await expectMutedGroupEmptyState(member1Page);

      // Mute the primary group through the combobox and verify it appears in the list.
      await muteGroupThroughCombobox(member1Page, { groupId, groupName });
      await expectMutedGroup(member1Page, groupId, groupName);

      // Unmute the group and verify the empty state returns.
      await unmuteGroup(member1Page, { groupId, groupName });
      await expectMutedGroupEmptyState(member1Page);
    } finally {
      clearGroupMute(TEST_USER_IDS.member1, groupId);
    }
  });

  test("mute refreshes preserve unsaved toggle changes until reload", async ({ member1Page }) => {
    const groups = [
      { groupId: TEST_GROUP_IDS.community1.alpha, groupName: TEST_GROUP_NAMES.alpha },
      { groupId: TEST_GROUP_IDS.community1.beta, groupName: "Inactive Local Chapter" },
    ];
    const category = "group-announcements";
    let originalPreference;

    try {
      // Start with no muted groups and stage an unsaved preference change.
      for (const group of groups) {
        clearGroupMute(TEST_USER_IDS.member1, group.groupId);
      }
      await navigateToPath(member1Page, NOTIFICATIONS_PATH);
      originalPreference = await getPreferenceToggle(member1Page, category).isChecked();
      await setNotificationPreference(member1Page, category, !originalPreference);

      // Exercise consecutive muted-list refreshes while keeping the unsaved toggle state intact.
      await muteGroupThroughCombobox(member1Page, groups[0]);
      await expectMutedGroup(member1Page, groups[0].groupId, groups[0].groupName);
      await expectPreferenceState(member1Page, category, !originalPreference);

      await muteGroupThroughCombobox(member1Page, groups[1]);
      await expectMutedGroup(member1Page, groups[0].groupId, groups[0].groupName);
      await expectMutedGroup(member1Page, groups[1].groupId, groups[1].groupName);
      await expectPreferenceState(member1Page, category, !originalPreference);

      await unmuteGroup(member1Page, groups[0]);
      await expectNoMutedGroup(member1Page, groups[0].groupId);
      await expectMutedGroup(member1Page, groups[1].groupId, groups[1].groupName);
      await expectPreferenceState(member1Page, category, !originalPreference);

      await unmuteGroup(member1Page, groups[1]);
      await expectMutedGroupEmptyState(member1Page);
      await expectPreferenceState(member1Page, category, !originalPreference);

      // Reloading discards the unsaved preference change.
      await navigateToPath(member1Page, NOTIFICATIONS_PATH);
      await expectPreferenceState(member1Page, category, originalPreference);
    } finally {
      for (const group of groups) {
        clearGroupMute(TEST_USER_IDS.member1, group.groupId);
      }
    }
  });
});

/** Clears a user's mute for one group. */
const clearGroupMute = (userId, groupId) => {
  queryE2eDatabase(`
    delete from user_group_notification_mute
    where user_id = '${userId}'::uuid
    and group_id = '${groupId}'::uuid;
  `);
};

/** Dismisses the active success alert when one is visible. */
const dismissAlertIfVisible = async (page) => {
  const dialog = page.locator(".swal2-popup");
  if ((await dialog.count()) === 0 || !(await dialog.first().isVisible())) {
    return;
  }

  await dialog.first().getByRole("button", { name: "OK", exact: true }).click();
};

/** Escapes a string for use in a regular expression. */
const escapeRegExp = (value) => value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");

/** Verifies a muted group row is absent. */
const expectNoMutedGroup = async (page, groupId) => {
  await expect(page.locator(`#muted-groups [data-muted-group-id="${groupId}"]`)).toHaveCount(0);
};

/** Verifies a muted group row is present. */
const expectMutedGroup = async (page, groupId, groupName) => {
  const row = page.locator(`#muted-groups [data-muted-group-id="${groupId}"]`);
  await expect(row).toBeVisible();
  await expect(row).toContainText(groupName);
};

/** Verifies the muted groups empty state is rendered. */
const expectMutedGroupEmptyState = async (page) => {
  await expect(page.locator("#muted-groups")).toContainText("You haven't muted any groups.");
};

/** Verifies visible and hidden preference fieldsets. */
const expectPreferenceSections = async (page, { hidden, visible }) => {
  for (const section of visible) {
    await expect(page.getByRole("group", { name: section })).toBeVisible();
  }

  for (const section of hidden) {
    await expect(page.getByRole("group", { name: section })).toHaveCount(0);
  }
};

/** Verifies a preference toggle and submitted hidden input state. */
const expectPreferenceState = async (page, category, enabled) => {
  await expect(getPreferenceToggle(page, category)).toBeChecked({ checked: enabled });
  await expect(getPreferenceInput(page, category)).toHaveValue(String(enabled));
};

/** Returns one notification preference hidden input. */
const getPreferenceInput = (page, category) => page.locator(`#preference-${category}`);

/** Returns one notification preference checkbox. */
const getPreferenceToggle = (page, category) => page.locator(`#toggle-preference-${category}`);

/** Mutes one group through the dashboard combobox. */
const muteGroupThroughCombobox = async (page, { groupId, groupName }) => {
  const picker = page.locator("notification-group-mutes");
  const search = picker.locator("#notification-group-mute-search");

  await expect(search).toBeEnabled();
  await search.fill(groupName);
  const option = picker.getByRole("option", { name: new RegExp(escapeRegExp(groupName), "u") });
  await expect(option).toBeVisible();

  const muteResponse = page.waitForResponse(
    (response) =>
      response.request().method() === "PUT" &&
      response.url().endsWith(`/dashboard/user/notifications/muted-groups/${groupId}`),
  );
  const refreshResponse = page.waitForResponse(
    (response) =>
      response.request().method() === "GET" &&
      response.url().includes("/dashboard/user/notifications/muted-groups") &&
      response.ok(),
  );

  await option.click();
  expect((await muteResponse).ok()).toBeTruthy();
  await refreshResponse;
  await waitForHtmxSettle(page);
  await dismissAlertIfVisible(page);
};

/** Restores one persisted preference to the requested enabled state. */
const restoreNotificationPreference = (userId, category, enabled) => {
  if (enabled) {
    queryE2eDatabase(`
      delete from user_notification_opt_out
      where user_id = '${userId}'::uuid
      and notification_category_id = '${category}';
    `);
    return;
  }

  queryE2eDatabase(`
    insert into user_notification_opt_out (user_id, notification_category_id)
    values ('${userId}'::uuid, '${category}')
    on conflict do nothing;
  `);
};

/** Saves one notification preference through the form. */
const saveNotificationPreference = async (page, category, enabled) => {
  await setNotificationPreference(page, category, enabled);
  await waitForActionResponse(
    page,
    () => page.locator("#notification-preferences-form").getByRole("button", { name: "Save" }).click(),
    {
      method: "PUT",
      urlIncludes: "/dashboard/user/notifications/preferences",
    },
  );

  const dialog = page.locator(".swal2-popup");
  await expect(dialog).toContainText("Notification preferences updated.");
  await dismissAlertIfVisible(page);
};

/** Stages one notification preference without submitting the form. */
const setNotificationPreference = async (page, category, enabled) => {
  const toggle = getPreferenceToggle(page, category);

  if ((await toggle.isChecked()) !== enabled) {
    await page.locator(`label[for="toggle-preference-${category}"]`).click();
  }

  await expectPreferenceState(page, category, enabled);
};

/** Unmutes one group from the server-rendered muted groups list. */
const unmuteGroup = async (page, { groupId, groupName }) => {
  const refreshResponse = page.waitForResponse(
    (response) =>
      response.request().method() === "GET" &&
      response.url().includes("/dashboard/user/notifications/muted-groups") &&
      response.ok(),
  );

  await waitForActionResponse(page, () => page.getByRole("button", { name: `Unmute ${groupName}` }).click(), {
    method: "DELETE",
    urlEndsWith: `/dashboard/user/notifications/muted-groups/${groupId}`,
  });
  await refreshResponse;
  await waitForHtmxSettle(page);
  await dismissAlertIfVisible(page);
};
