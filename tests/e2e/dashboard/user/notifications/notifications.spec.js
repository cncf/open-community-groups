import { expect, test } from "../../../fixtures.js";

import {
  cleanupGroupMute,
  restoreNotificationPreference,
  setupGroupMute,
} from "../../../data-graphs/notification-preferences.js";
import { TEST_GROUP_IDS, TEST_GROUP_NAMES, TEST_USER_IDS } from "../../../seed.js";
import { navigateToPath, waitForActionResponse, waitForHtmxSettle } from "../../../utils.js";

const GROUP_OPTIONS_PATH = "/dashboard/user/notifications/group-options";
const MUTED_GROUPS_PATH = "/dashboard/user/notifications/muted-groups";
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
    await expect(member1Page.getByRole("heading", { name: "Muted groups" })).toBeVisible();

    // Verify the always-sent details open from the page description and close with Escape.
    const alwaysSentTrigger = member1Page.getByRole("button", {
      name: "things that need your attention are always sent",
    });
    const alwaysSentModal = member1Page.getByRole("dialog", { name: "Always sent" });
    await alwaysSentTrigger.click();
    await expect(alwaysSentModal).toBeVisible();
    await expect(alwaysSentModal).toContainText("Organizer actions:");
    await member1Page.keyboard.press("Escape");
    await expect(alwaysSentModal).toBeHidden();
    await expect(alwaysSentTrigger).toBeFocused();

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
        restoreNotificationPreference({
          category,
          enabled: originalPreference,
          userId: TEST_USER_IDS.member1,
        });
      }
    }
  });

  test("user can mute and unmute a group from the combobox", async ({ member1Page }) => {
    const groupId = TEST_GROUP_IDS.community1.alpha;
    const groupName = TEST_GROUP_NAMES.alpha;

    try {
      // Load the notifications tab with no muted groups for this scenario.
      cleanupGroupMute({ groupId, userId: TEST_USER_IDS.member1 });
      await navigateToPath(member1Page, NOTIFICATIONS_PATH);
      await expectMutedGroupEmptyState(member1Page);

      // Mute the primary group through the combobox and verify it appears in the list.
      await muteGroupThroughCombobox(member1Page, { groupId, groupName });
      await expectMutedGroup(member1Page, groupId, groupName);

      // Verify closing the success alert returns focus without reopening the picker.
      const search = getGroupSearch(member1Page);
      await expect(search).toBeFocused();
      await expect(search).toHaveAttribute("aria-expanded", "false");

      // Unmute the group and verify the empty state returns.
      await unmuteGroup(member1Page, { groupId, groupName });
      await expectMutedGroupEmptyState(member1Page);
    } finally {
      cleanupGroupMute({ groupId, userId: TEST_USER_IDS.member1 });
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
        cleanupGroupMute({ groupId: group.groupId, userId: TEST_USER_IDS.member1 });
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
        cleanupGroupMute({ groupId: group.groupId, userId: TEST_USER_IDS.member1 });
      }
    }
  });

  test("muted unavailable groups are marked as not available and can be unmuted", async ({ member1Page }) => {
    const groupId = TEST_GROUP_IDS.community1.empty;
    const groupName = "Empty Coverage Group";

    try {
      // Load the tab with a mute for the seeded inactive group.
      cleanupGroupMute({ groupId, userId: TEST_USER_IDS.member1 });
      setupGroupMute({ groupId, userId: TEST_USER_IDS.member1 });
      await navigateToPath(member1Page, NOTIFICATIONS_PATH);

      // Verify the muted row flags the group as not available.
      await expectMutedGroup(member1Page, groupId, groupName);
      await expect(getMutedGroupRow(member1Page, groupId)).toContainText("Not available");

      // Unmute the unavailable group and verify the empty state returns.
      await unmuteGroup(member1Page, { groupId, groupName });
      await expectMutedGroupEmptyState(member1Page);
    } finally {
      cleanupGroupMute({ groupId, userId: TEST_USER_IDS.member1 });
    }
  });

  test("group picker offers a retry when options fail to load", async ({ member1Page }) => {
    // Fail only the first group options request.
    let failedRequests = 0;
    await member1Page.route(`**${GROUP_OPTIONS_PATH}`, async (route) => {
      if (failedRequests === 0) {
        failedRequests += 1;
        await route.fulfill({ body: "Unavailable", status: 500 });
        return;
      }

      await route.continue();
    });

    try {
      // Open the picker and verify the load error.
      await navigateToPath(member1Page, NOTIFICATIONS_PATH);
      const picker = member1Page.locator("notification-group-mutes");
      await getGroupSearch(member1Page).click();
      const loadError = picker.getByRole("alert");
      await expect(loadError).toContainText("Groups could not be loaded. Try again.");

      // Retry and verify the options load.
      await loadError.getByRole("button", { name: "Retry" }).click();
      await expect(
        picker.getByRole("option", { name: new RegExp(escapeRegExp(TEST_GROUP_NAMES.alpha), "u") }),
      ).toBeVisible();
      expect(failedRequests).toBe(1);
    } finally {
      await member1Page.unroute(`**${GROUP_OPTIONS_PATH}`);
    }
  });

  test("failed mutes show the server message and keep the group unmuted", async ({ member1Page }) => {
    const groupId = TEST_GROUP_IDS.community1.alpha;
    const groupName = TEST_GROUP_NAMES.alpha;
    const serverMessage = "group not available to mute";

    // Reject the mute request with a user-facing server message.
    await member1Page.route(`**${MUTED_GROUPS_PATH}/${groupId}`, async (route) => {
      if (route.request().method() !== "PUT") {
        await route.continue();
        return;
      }

      await route.fulfill({ body: serverMessage, status: 422 });
    });

    try {
      // Load the tab without muted groups and select the group in the picker.
      cleanupGroupMute({ groupId, userId: TEST_USER_IDS.member1 });
      await navigateToPath(member1Page, NOTIFICATIONS_PATH);
      const search = getGroupSearch(member1Page);
      await search.fill(groupName);
      const muteResponse = member1Page.waitForResponse(
        (response) =>
          response.request().method() === "PUT" && response.url().endsWith(`${MUTED_GROUPS_PATH}/${groupId}`),
      );
      await member1Page
        .locator("notification-group-mutes")
        .getByRole("option", { name: new RegExp(escapeRegExp(groupName), "u") })
        .click();
      expect((await muteResponse).status()).toBe(422);

      // Verify the error alert shows the server message and focus returns to the closed picker.
      await dismissAlert(member1Page, serverMessage);
      await expect(search).toBeFocused();
      await expect(search).toHaveAttribute("aria-expanded", "false");

      // Verify the group was not muted.
      await expectMutedGroupEmptyState(member1Page);
    } finally {
      await member1Page.unroute(`**${MUTED_GROUPS_PATH}/${groupId}`);
      cleanupGroupMute({ groupId, userId: TEST_USER_IDS.member1 });
    }
  });
});

/** Waits for an alert with the expected text and closes it. */
const dismissAlert = async (page, text) => {
  const dialog = page.locator(".swal2-popup");
  await expect(dialog).toContainText(text);
  await dialog.getByRole("button", { name: "OK", exact: true }).click();
  await expect(dialog).toBeHidden();
};

/** Escapes a string for use in a regular expression. */
const escapeRegExp = (value) => value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");

/** Verifies a muted group row is present. */
const expectMutedGroup = async (page, groupId, groupName) => {
  const row = getMutedGroupRow(page, groupId);
  await expect(row).toBeVisible();
  await expect(row).toContainText(groupName);
};

/** Verifies the muted groups empty state is rendered. */
const expectMutedGroupEmptyState = async (page) => {
  await expect(page.locator("#muted-groups")).toContainText("You haven't muted any groups.");
};

/** Verifies a muted group row is absent. */
const expectNoMutedGroup = async (page, groupId) => {
  await expect(getMutedGroupRow(page, groupId)).toHaveCount(0);
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

/** Returns the group mute picker search input. */
const getGroupSearch = (page) => page.locator("notification-group-mutes #notification-group-mute-search");

/** Returns one muted group row. */
const getMutedGroupRow = (page, groupId) => page.locator(`#muted-groups [data-muted-group-id="${groupId}"]`);

/** Returns one notification preference hidden input. */
const getPreferenceInput = (page, category) => page.locator(`#preference-${category}`);

/** Returns one notification preference checkbox. */
const getPreferenceToggle = (page, category) => page.locator(`#toggle-preference-${category}`);

/** Mutes one group through the dashboard combobox. */
const muteGroupThroughCombobox = async (page, { groupId, groupName }) => {
  const picker = page.locator("notification-group-mutes");
  const search = getGroupSearch(page);

  await expect(search).toBeEnabled();
  await search.fill(groupName);
  const option = picker.getByRole("option", { name: new RegExp(escapeRegExp(groupName), "u") });
  await expect(option).toBeVisible();

  const muteResponse = page.waitForResponse(
    (response) =>
      response.request().method() === "PUT" && response.url().endsWith(`${MUTED_GROUPS_PATH}/${groupId}`),
  );
  const refreshResponse = page.waitForResponse(
    (response) =>
      response.request().method() === "GET" && response.url().includes(MUTED_GROUPS_PATH) && response.ok(),
  );

  await option.click();
  expect((await muteResponse).ok()).toBeTruthy();
  await refreshResponse;
  await waitForHtmxSettle(page);
  await dismissAlert(page, `${groupName} muted.`);
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

  await dismissAlert(page, "Notification preferences updated.");
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
      response.request().method() === "GET" && response.url().includes(MUTED_GROUPS_PATH) && response.ok(),
  );

  await waitForActionResponse(page, () => page.getByRole("button", { name: `Unmute ${groupName}` }).click(), {
    method: "DELETE",
    urlEndsWith: `${MUTED_GROUPS_PATH}/${groupId}`,
  });
  await refreshResponse;
  await waitForHtmxSettle(page);
  await dismissAlert(page, `${groupName} unmuted.`);
};
