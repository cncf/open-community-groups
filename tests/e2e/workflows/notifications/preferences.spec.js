import { expect, test } from "../../fixtures.js";

import { cleanupCohostEvents, setupCohostEvent } from "../../data-graphs/cohosts.js";
import { cleanupEventsByIds, setupNotificationEvent } from "../../data-graphs/events.js";
import { cleanupGroupTeamInvitation } from "../../data-graphs/invitations.js";
import { queryE2eDatabase } from "../../database.js";
import { deleteNotifications, expectNewNotifications, snapshotNotifications } from "../../notifications.js";
import { TEST_GROUP_IDS, TEST_USER_IDS } from "../../seed.js";
import { buildE2eUrl, navigateToPath, waitForActionResponse } from "../../utils.js";

const NOTIFICATIONS_PATH = "/dashboard/user?tab=notifications";

const GROUP_CUSTOM_RECIPIENT_IDS_WITH_MEMBER1_SUPPRESSED = [
  TEST_USER_IDS.organizer1,
  "77777777-7777-7777-7777-777777777711",
  "77777777-7777-7777-7777-777777777712",
  "77777777-7777-7777-7777-777777777714",
  TEST_USER_IDS.checkInManager1,
];

const ALPHA_EVENT_PUBLISHED_RECIPIENT_IDS = [
  TEST_USER_IDS.organizer1,
  TEST_USER_IDS.member1,
  "77777777-7777-7777-7777-777777777711",
  "77777777-7777-7777-7777-777777777712",
  "77777777-7777-7777-7777-777777777714",
  TEST_USER_IDS.checkInManager1,
];

const COHOST_AUDIENCE_RECIPIENT_IDS_WITH_MEMBER2_SUPPRESSED = [
  TEST_USER_IDS.organizer2,
  TEST_USER_IDS.pending1,
];

const COHOST_GROUP_ID = TEST_GROUP_IDS.community2.delta;
const COHOST_GROUP_NAME = "E2E Second Group Delta";
const GROUP_ANNOUNCEMENTS_CATEGORY = "group-announcements";
const GROUP_NOTIFICATION_BODY = "Preference suppression check from the e2e suite.";
const GROUP_NOTIFICATION_SUBJECT = "E2E preference suppression";
const OWNER_GROUP_ID = TEST_GROUP_IDS.community1.alpha;
const UNRELATED_GROUP_ID = TEST_GROUP_IDS.community2.epsilon;

test.describe("notification preferences workflow", () => {
  test("group announcements preference suppresses custom group notifications", async ({
    member1Page,
    organizerGroupPage,
  }) => {
    let notificationIds = [];
    let originalPreference;

    try {
      // Disable group announcement emails from the member's notification settings.
      await navigateToPath(member1Page, NOTIFICATIONS_PATH);
      originalPreference = await getNotificationPreference(member1Page, GROUP_ANNOUNCEMENTS_CATEGORY);
      await saveGroupAnnouncementsPreference(member1Page, false);

      // Send a group notification and assert Member One is omitted exactly.
      const optionalSnapshot = snapshotNotifications();
      const groupNotificationResponse = await organizerGroupPage.request.post(
        buildE2eUrl("/dashboard/group/notifications"),
        {
          form: {
            body: GROUP_NOTIFICATION_BODY,
            subject: GROUP_NOTIFICATION_SUBJECT,
          },
        },
      );
      expect(groupNotificationResponse.ok()).toBeTruthy();
      notificationIds = notificationIds.concat(
        expectNewNotifications(optionalSnapshot, [
          {
            kind: "group-custom",
            templateDataContains: {
              body: GROUP_NOTIFICATION_BODY,
              subject: GROUP_NOTIFICATION_SUBJECT,
            },
            userIds: GROUP_CUSTOM_RECIPIENT_IDS_WITH_MEMBER1_SUPPRESSED,
          },
        ]),
      );
    } finally {
      // Remove generated notifications and preference changes.
      deleteNotifications(notificationIds);
      if (typeof originalPreference === "boolean") {
        restoreNotificationPreference(
          TEST_USER_IDS.member1,
          GROUP_ANNOUNCEMENTS_CATEGORY,
          originalPreference,
        );
      }
    }
  });

  test("group mute suppresses custom group notifications but not mandatory invitations", async ({
    member1Page,
    organizerGroupPage,
  }) => {
    let notificationIds = [];

    try {
      // Clear invitation and mute state before preference checks.
      cleanupGroupTeamInvitation({
        groupId: OWNER_GROUP_ID,
        userId: TEST_USER_IDS.member1,
      });
      clearGroupMute(TEST_USER_IDS.member1, OWNER_GROUP_ID);
      await muteGroupForUser(member1Page, OWNER_GROUP_ID);

      // Send a group notification and assert Member One is omitted exactly.
      const groupNotificationSnapshot = snapshotNotifications();
      const groupNotificationResponse = await organizerGroupPage.request.post(
        buildE2eUrl("/dashboard/group/notifications"),
        {
          form: {
            body: GROUP_NOTIFICATION_BODY,
            subject: GROUP_NOTIFICATION_SUBJECT,
          },
        },
      );
      expect(groupNotificationResponse.ok()).toBeTruthy();
      notificationIds = notificationIds.concat(
        expectNewNotifications(groupNotificationSnapshot, [
          {
            kind: "group-custom",
            templateDataContains: {
              body: GROUP_NOTIFICATION_BODY,
              subject: GROUP_NOTIFICATION_SUBJECT,
            },
            userIds: GROUP_CUSTOM_RECIPIENT_IDS_WITH_MEMBER1_SUPPRESSED,
          },
        ]),
      );

      // Add the muted user to the group team and assert the mandatory invitation is still sent.
      const mandatorySnapshot = snapshotNotifications();
      const invitationResponse = await organizerGroupPage.request.post(
        buildE2eUrl("/dashboard/group/team/add"),
        {
          form: {
            role: "viewer",
            user_id: TEST_USER_IDS.member1,
          },
        },
      );
      expect(invitationResponse.ok()).toBeTruthy();
      notificationIds = notificationIds.concat(
        expectNewNotifications(mandatorySnapshot, [
          {
            kind: "group-team-invitation",
            templateDataContains: { group: { group_id: OWNER_GROUP_ID } },
            userIds: [TEST_USER_IDS.member1],
          },
        ]),
      );
    } finally {
      // Remove generated notifications, invitation, and mute changes.
      deleteNotifications(notificationIds);
      cleanupGroupTeamInvitation({
        groupId: OWNER_GROUP_ID,
        userId: TEST_USER_IDS.member1,
      });
      clearGroupMute(TEST_USER_IDS.member1, OWNER_GROUP_ID);
    }
  });

  test("owner group mute suppresses co-host publish notifications but unrelated mutes do not", async ({
    organizerGroupPage,
  }) => {
    const scenario = setupCohostEvent({
      cohosts: [{ groupId: COHOST_GROUP_ID, status: "approved" }],
      ownerGroupId: OWNER_GROUP_ID,
    });
    let notificationIds = [];

    try {
      // Add one temporary co-host group member, then set up two different mute states.
      cleanupGroupMember(COHOST_GROUP_ID, TEST_USER_IDS.pending1);
      setupGroupMember(COHOST_GROUP_ID, TEST_USER_IDS.pending1);
      clearGroupMute(TEST_USER_IDS.member2, OWNER_GROUP_ID);
      clearGroupMute(TEST_USER_IDS.pending1, UNRELATED_GROUP_ID);
      muteGroupInDatabase(TEST_USER_IDS.member2, OWNER_GROUP_ID);
      muteGroupInDatabase(TEST_USER_IDS.pending1, UNRELATED_GROUP_ID);

      // Publish the approved co-hosted event and assert actual notification rows.
      const publishSnapshot = snapshotNotifications();
      const publishResponse = await organizerGroupPage.request.put(
        buildE2eUrl(`/dashboard/group/events/${scenario.eventId}/publish`),
      );
      expect(publishResponse.ok()).toBeTruthy();
      notificationIds = notificationIds.concat(
        expectNewNotifications(publishSnapshot, [
          {
            kind: "event-published",
            templateDataContains: { event: { event_id: scenario.eventId } },
            userIds: ALPHA_EVENT_PUBLISHED_RECIPIENT_IDS,
          },
          {
            kind: "event-published",
            templateDataContains: { cohost_group_name: COHOST_GROUP_NAME },
            userIds: COHOST_AUDIENCE_RECIPIENT_IDS_WITH_MEMBER2_SUPPRESSED,
          },
        ]),
      );
    } finally {
      // Remove generated notifications, mutes, membership, and the temporary event.
      deleteNotifications(notificationIds);
      clearGroupMute(TEST_USER_IDS.member2, OWNER_GROUP_ID);
      clearGroupMute(TEST_USER_IDS.pending1, UNRELATED_GROUP_ID);
      cleanupGroupMember(COHOST_GROUP_ID, TEST_USER_IDS.pending1);
      cleanupCohostEvents([scenario.eventId]);
    }
  });

  test("test events suppress publish and cancellation notifications", async ({ organizerGroupPage }) => {
    // Create an owned test event with an attendee that would otherwise receive cancellation.
    const scenario = setupNotificationEvent({
      attendeeUserIds: [TEST_USER_IDS.member1],
      groupId: OWNER_GROUP_ID,
      testEvent: true,
    });
    let notificationIds = [];

    try {
      // Publish the test event and assert it creates no event publication notifications.
      const publishSnapshot = snapshotNotifications();
      const publishResponse = await organizerGroupPage.request.put(
        buildE2eUrl(`/dashboard/group/events/${scenario.eventId}/publish`),
      );
      expect(publishResponse.ok()).toBeTruthy();
      notificationIds = notificationIds.concat(expectNewNotifications(publishSnapshot, []));

      // Cancel the test event and assert it creates no cancellation notifications.
      const cancelSnapshot = snapshotNotifications();
      const cancelResponse = await organizerGroupPage.request.put(
        buildE2eUrl(`/dashboard/group/events/${scenario.eventId}/cancel`),
      );
      expect(cancelResponse.ok()).toBeTruthy();
      notificationIds = notificationIds.concat(expectNewNotifications(cancelSnapshot, []));
    } finally {
      // Remove generated notifications and the temporary test event.
      deleteNotifications(notificationIds);
      cleanupEventsByIds([scenario.eventId]);
    }
  });
});

/** Removes a user's mute for one group. */
const clearGroupMute = (userId, groupId) => {
  queryE2eDatabase(`
    delete from user_group_notification_mute
    where user_id = '${userId}'::uuid
    and group_id = '${groupId}'::uuid;
  `);
};

/** Removes a temporary group membership. */
const cleanupGroupMember = (groupId, userId) => {
  queryE2eDatabase(`
    delete from group_member
    where group_id = '${groupId}'::uuid
    and user_id = '${userId}'::uuid;
  `);
};

/** Returns one notification preference toggle's checked state. */
const getNotificationPreference = async (page, category) =>
  page.locator(`#toggle-preference-${category}`).isChecked();

/** Creates a mute row for notification fan-out scenarios. */
const muteGroupInDatabase = (userId, groupId) => {
  queryE2eDatabase(`
    insert into user_group_notification_mute (user_id, group_id)
    values ('${userId}'::uuid, '${groupId}'::uuid)
    on conflict do nothing;
  `);
};

/** Mutes one group through the authenticated user endpoint. */
const muteGroupForUser = async (page, groupId) => {
  const response = await page.request.put(
    buildE2eUrl(`/dashboard/user/notifications/muted-groups/${groupId}`),
  );

  expect(response.ok()).toBeTruthy();
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

/** Saves the group announcements preference through the notifications form. */
const saveGroupAnnouncementsPreference = async (page, enabled) => {
  await navigateToPath(page, NOTIFICATIONS_PATH);

  const toggle = page.locator(`#toggle-preference-${GROUP_ANNOUNCEMENTS_CATEGORY}`);
  if ((await toggle.isChecked()) !== enabled) {
    await page.locator(`label[for="toggle-preference-${GROUP_ANNOUNCEMENTS_CATEGORY}"]`).click();
  }

  await expect(toggle).toBeChecked({ checked: enabled });
  await expect(page.locator(`#preference-${GROUP_ANNOUNCEMENTS_CATEGORY}`)).toHaveValue(String(enabled));
  await waitForActionResponse(
    page,
    () => page.locator("#notification-preferences-form").getByRole("button", { name: "Save" }).click(),
    {
      method: "PUT",
      urlIncludes: "/dashboard/user/notifications/preferences",
    },
  );
};

/** Adds one temporary group membership. */
const setupGroupMember = (groupId, userId) => {
  queryE2eDatabase(`
    insert into group_member (group_id, user_id)
    values ('${groupId}'::uuid, '${userId}'::uuid)
    on conflict do nothing;
  `);
};
