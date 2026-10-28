import { expect, test } from "../../fixtures.js";

import { cleanupEventsByIds, setupNotificationEvent } from "../../data-graphs/events.js";
import { cleanupGroupTeamInvitation } from "../../data-graphs/invitations.js";
import {
  cleanupEventSurveys,
  readSurveyOpenNotification,
  setupOwnedEventSurvey,
} from "../../data-graphs/surveys.js";
import {
  cleanupGroupMute,
  restoreNotificationPreference,
  setupGroupMute,
} from "../../data-graphs/notification-preferences.js";
import { queryE2eDatabase } from "../../database.js";
import { TEST_GROUP_AUDIENCE_IDS, TEST_GROUP_IDS, TEST_GROUP_NAMES, TEST_USER_IDS } from "../../seed.js";
import { buildE2eUrl, navigateToPath, waitForActionResponse } from "../../utils.js";

const NOTIFICATIONS_PATH = "/dashboard/user?tab=notifications";

const GROUP_CUSTOM_RECIPIENT_IDS_WITH_MEMBER1_SUPPRESSED = TEST_GROUP_AUDIENCE_IDS.alpha.filter(
  (userId) => userId !== TEST_USER_IDS.member1,
);

const ALPHA_EVENT_PUBLISHED_RECIPIENT_IDS = TEST_GROUP_AUDIENCE_IDS.alpha;

const COHOST_AUDIENCE_RECIPIENT_IDS_WITH_MEMBER2_SUPPRESSED = [
  TEST_USER_IDS.organizer2,
  TEST_USER_IDS.pending1,
];

const COHOST_GROUP_ID = TEST_GROUP_IDS.community2.delta;
const COHOST_GROUP_NAME = TEST_GROUP_NAMES.delta;
const EVENT_REMINDERS_CATEGORY = "event-reminders";
const EVENT_SURVEYS_CATEGORY = "event-surveys";
const GROUP_ANNOUNCEMENTS_CATEGORY = "group-announcements";
const GROUP_NOTIFICATION_BODY = "Preference suppression check from the e2e suite.";
const GROUP_NOTIFICATION_SUBJECT = "E2E preference suppression";
const ORGANIZER_MESSAGE_BODY = "Organizer message preference check from the e2e suite.";
const ORGANIZER_MESSAGE_SUBJECT = "E2E organizer message preferences";
const OWNER_GROUP_ID = TEST_GROUP_IDS.community1.alpha;
const UNRELATED_GROUP_ID = TEST_GROUP_IDS.community2.epsilon;

test.describe("notification preferences workflow", () => {
  test("group announcements preference suppresses custom group notifications", async ({
    member1Page,
    notifications,
    organizerGroupPage,
    owned,
  }) => {
    // Disable group announcement emails from the member's notification settings.
    await navigateToPath(member1Page, NOTIFICATIONS_PATH);
    const originalPreference = await getNotificationPreference(member1Page, GROUP_ANNOUNCEMENTS_CATEGORY);
    owned.defer(() =>
      restoreNotificationPreference({
        category: GROUP_ANNOUNCEMENTS_CATEGORY,
        enabled: originalPreference,
        userId: TEST_USER_IDS.member1,
      }),
    );
    await saveGroupAnnouncementsPreference(member1Page, false);

    // Send a group notification and assert Member One is omitted exactly.
    const optionalCheckpoint = notifications.checkpoint();
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
    notifications.expectNew(
      [
        {
          kind: "group-custom",
          templateDataContains: {
            body: GROUP_NOTIFICATION_BODY,
            subject: GROUP_NOTIFICATION_SUBJECT,
          },
          userIds: GROUP_CUSTOM_RECIPIENT_IDS_WITH_MEMBER1_SUPPRESSED,
        },
      ],
      { since: optionalCheckpoint },
    );
  });

  test("group mute suppresses custom group notifications but not mandatory invitations", async ({
    member1Page,
    notifications,
    organizerGroupPage,
    owned,
  }) => {
    // Clear invitation state, then mute the group through the user endpoint.
    const invitation = { groupId: OWNER_GROUP_ID, userId: TEST_USER_IDS.member1 };
    cleanupGroupTeamInvitation(invitation);
    owned.track(invitation, cleanupGroupTeamInvitation);
    owned.track({ groupId: OWNER_GROUP_ID, userId: TEST_USER_IDS.member1 }, cleanupGroupMute);
    await muteGroupForUser(member1Page, OWNER_GROUP_ID);

    // Send a group notification and assert Member One is omitted exactly.
    const groupNotificationCheckpoint = notifications.checkpoint();
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
    notifications.expectNew(
      [
        {
          kind: "group-custom",
          templateDataContains: {
            body: GROUP_NOTIFICATION_BODY,
            subject: GROUP_NOTIFICATION_SUBJECT,
          },
          userIds: GROUP_CUSTOM_RECIPIENT_IDS_WITH_MEMBER1_SUPPRESSED,
        },
      ],
      { since: groupNotificationCheckpoint },
    );

    // Add the muted user to the group team and assert the mandatory invitation is still sent.
    const mandatoryCheckpoint = notifications.checkpoint();
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
    notifications.expectNew(
      [
        {
          kind: "group-team-invitation",
          templateDataContains: { group: { group_id: OWNER_GROUP_ID } },
          userIds: [TEST_USER_IDS.member1],
        },
      ],
      { since: mandatoryCheckpoint },
    );
  });

  test("owner group mute suppresses co-host publish notifications but unrelated mutes do not", async ({
    notifications,
    organizerGroupPage,
    owned,
  }) => {
    const scenario = owned.cohostEvent({
      cohosts: [{ groupId: COHOST_GROUP_ID, status: "approved" }],
      ownerGroupId: OWNER_GROUP_ID,
    });

    // Add one temporary co-host group member, then set up two different mute states.
    setupOwnedGroupMember(owned, COHOST_GROUP_ID, TEST_USER_IDS.pending1);
    setupOwnedGroupMute(owned, { groupId: OWNER_GROUP_ID, userId: TEST_USER_IDS.member2 });
    setupOwnedGroupMute(owned, { groupId: UNRELATED_GROUP_ID, userId: TEST_USER_IDS.pending1 });

    // Publish the approved co-hosted event and assert actual notification rows.
    const publishCheckpoint = notifications.checkpoint();
    const publishResponse = await organizerGroupPage.request.put(
      buildE2eUrl(`/dashboard/group/events/${scenario.eventId}/publish`),
    );
    expect(publishResponse.ok()).toBeTruthy();
    notifications.expectNew(
      [
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
      ],
      { since: publishCheckpoint },
    );
  });

  test("owner group mute suppresses organizer messages but co-host group mutes do not", async ({
    notifications,
    organizerGroupPage,
    owned,
  }) => {
    const scenario = owned.cohostEvent({
      attendeeUserIds: [TEST_USER_IDS.member1, TEST_USER_IDS.member2],
      cohosts: [{ groupId: COHOST_GROUP_ID, status: "approved" }],
      ownerGroupId: OWNER_GROUP_ID,
      published: true,
    });

    // Mute the co-host group for Member One and the owner group for Member Two.
    setupOwnedGroupMute(owned, { groupId: COHOST_GROUP_ID, userId: TEST_USER_IDS.member1 });
    setupOwnedGroupMute(owned, { groupId: OWNER_GROUP_ID, userId: TEST_USER_IDS.member2 });

    // Email every attendee and assert only Member One receives the organizer message.
    const messageCheckpoint = notifications.checkpoint();
    const messageResponse = await organizerGroupPage.request.post(
      buildE2eUrl(`/dashboard/group/notifications/${scenario.eventId}`),
      {
        form: {
          body: ORGANIZER_MESSAGE_BODY,
          subject: ORGANIZER_MESSAGE_SUBJECT,
        },
      },
    );
    expect(messageResponse.ok()).toBeTruthy();
    notifications.expectNew(
      [
        {
          kind: "event-custom",
          templateDataContains: {
            body: ORGANIZER_MESSAGE_BODY,
            event: { event_id: scenario.eventId },
            subject: ORGANIZER_MESSAGE_SUBJECT,
          },
          userIds: [TEST_USER_IDS.member1],
        },
      ],
      { since: messageCheckpoint },
    );
  });

  test("event reminders respect category opt-outs and owner group mutes but not co-host group mutes", async ({
    notifications,
    owned,
  }) => {
    // Opt Member One out of reminders, mute the owner for Member Two, and the co-host for Pending One.
    setupOwnedCategoryOptOut(owned, EVENT_REMINDERS_CATEGORY, TEST_USER_IDS.member1);
    setupOwnedGroupMute(owned, { groupId: OWNER_GROUP_ID, userId: TEST_USER_IDS.member2 });
    setupOwnedGroupMute(owned, { groupId: COHOST_GROUP_ID, userId: TEST_USER_IDS.pending1 });

    // Checkpoint before creating the due event because the server reminder worker may enqueue it first.
    const reminderCheckpoint = notifications.checkpoint();
    const scenario = owned.cohostEvent({
      attendeeUserIds: [TEST_USER_IDS.member1, TEST_USER_IDS.member2, TEST_USER_IDS.pending1],
      cohosts: [{ groupId: COHOST_GROUP_ID, status: "approved" }],
      days: 0.5,
      ownerGroupId: OWNER_GROUP_ID,
      published: true,
    });

    // Run the reminder enqueue step the server worker runs on its schedule.
    queryE2eDatabase("select enqueue_due_event_reminders();");

    // Assert only Pending One receives the reminder.
    notifications.expectNew(
      [
        {
          kind: "event-reminder",
          templateDataContains: { event: { event_id: scenario.eventId } },
          userIds: [TEST_USER_IDS.pending1],
        },
      ],
      { since: reminderCheckpoint },
    );
  });

  test("event survey opening emails respect category opt-outs and owner group mutes", async ({
    notifications,
    owned,
  }) => {
    // Opt Member One out of survey emails and mute the owner group for Member Two.
    setupOwnedCategoryOptOut(owned, EVENT_SURVEYS_CATEGORY, TEST_USER_IDS.member1);
    setupOwnedGroupMute(owned, { groupId: OWNER_GROUP_ID, userId: TEST_USER_IDS.member2 });

    // Checkpoint before opening the survey because the server worker may enqueue it first.
    const surveyCheckpoint = notifications.checkpoint();
    const scenario = owned.cohostEvent({
      attendeeUserIds: [TEST_USER_IDS.member1, TEST_USER_IDS.member2, TEST_USER_IDS.pending1],
      days: -2,
      ownerGroupId: OWNER_GROUP_ID,
      published: true,
    });
    const survey = owned.track(
      setupOwnedEventSurvey({ eventId: scenario.eventId, status: "ready" }),
      ({ id }) => cleanupEventSurveys([id]),
    );

    // Run the survey email enqueue step the server worker runs on its schedule.
    queryE2eDatabase("select enqueue_due_event_survey_notifications();");

    // Assert only Pending One receives the opening email with a site-relative dashboard survey link.
    notifications.expectNew(
      [
        {
          kind: "event-survey-opened",
          templateDataContains: {
            anonymous: true,
            event: { event_id: scenario.eventId },
            link: `/dashboard/user?tab=surveys&event_survey_id=${survey.id}`,
            survey_title: survey.title,
          },
          userIds: [TEST_USER_IDS.pending1],
        },
      ],
      { since: surveyCheckpoint },
    );

    // Assert the survey is marked handled so it never emails again.
    expect(readSurveyOpenNotification(survey.id)).toEqual({ processed: true, recipients: 1 });
    queryE2eDatabase("select enqueue_due_event_survey_notifications();");
    expect(readSurveyOpenNotification(survey.id)).toEqual({ processed: true, recipients: 1 });
  });

  test("test events suppress publish and cancellation notifications", async ({
    notifications,
    organizerGroupPage,
    owned,
  }) => {
    // Create an owned test event with an attendee that would otherwise receive cancellation.
    const scenario = owned.track(
      setupNotificationEvent({
        attendeeUserIds: [TEST_USER_IDS.member1],
        groupId: OWNER_GROUP_ID,
        testEvent: true,
      }),
      ({ eventId }) => cleanupEventsByIds([eventId]),
    );

    // Publish the test event and assert it creates no event publication notifications.
    const publishCheckpoint = notifications.checkpoint();
    const publishResponse = await organizerGroupPage.request.put(
      buildE2eUrl(`/dashboard/group/events/${scenario.eventId}/publish`),
    );
    expect(publishResponse.ok()).toBeTruthy();
    notifications.expectNew([], { since: publishCheckpoint });

    // Cancel the test event and assert it creates no cancellation notifications.
    const cancelCheckpoint = notifications.checkpoint();
    const cancelResponse = await organizerGroupPage.request.put(
      buildE2eUrl(`/dashboard/group/events/${scenario.eventId}/cancel`),
    );
    expect(cancelResponse.ok()).toBeTruthy();
    notifications.expectNew([], { since: cancelCheckpoint });
  });
});

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

/** Mutes one group through the authenticated user endpoint. */
const muteGroupForUser = async (page, groupId) => {
  const response = await page.request.put(
    buildE2eUrl(`/dashboard/user/notifications/muted-groups/${groupId}`),
  );

  expect(response.ok()).toBeTruthy();
};

/** Opts a user out of one notification category and defers opting them back in. */
const setupOwnedCategoryOptOut = (owned, category, userId) => {
  owned.defer(() => restoreNotificationPreference({ category, enabled: true, userId }));
  restoreNotificationPreference({ category, enabled: false, userId });
};

/** Adds one temporary group membership and defers its removal. */
const setupOwnedGroupMember = (owned, groupId, userId) => {
  owned.defer(() => cleanupGroupMember(groupId, userId));
  setupGroupMember(groupId, userId);
};

/** Mutes one group for a user and defers removing the mute. */
const setupOwnedGroupMute = (owned, mute) => {
  setupGroupMute(owned.track(mute, cleanupGroupMute));
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
