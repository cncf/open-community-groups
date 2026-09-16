import { expect, test } from "../../fixtures.js";
import { deleteNotifications, expectNewNotifications, snapshotNotifications } from "../../notifications.js";
import { cleanupEventsByIds, setupNotificationEvent } from "../../data-graphs/events.js";
import { cleanupGroupTeamInvitation } from "../../data-graphs/invitations.js";
import { TEST_GROUP_IDS, TEST_USER_IDS } from "../../seed.js";
import { buildE2eUrl, navigateToPath, waitForActionResponse } from "../../utils.js";

const ACCOUNT_PATH = "/dashboard/user?tab=account";

const GROUP_CUSTOM_RECIPIENT_IDS_WITH_MEMBER1_OPTED_OUT = [
  TEST_USER_IDS.organizer1,
  "77777777-7777-7777-7777-777777777711",
  "77777777-7777-7777-7777-777777777712",
  "77777777-7777-7777-7777-777777777714",
  TEST_USER_IDS.checkInManager1,
];

const GROUP_NOTIFICATION_BODY = "Preference suppression check from the e2e suite.";

const GROUP_NOTIFICATION_SUBJECT = "E2E preference suppression";

test.describe("notification preferences workflow", () => {
  test("optional preference suppresses custom group notifications but not mandatory invitations", async ({
    member1Page,
    organizerGroupPage,
  }) => {
    let notificationIds = [];
    let originalPreference;

    try {
      // Clear existing invitation state before preference checks.
      cleanupGroupTeamInvitation({
        groupId: TEST_GROUP_IDS.community1.alpha,
        userId: TEST_USER_IDS.member1,
      });

      // Disable optional notifications from the member's account settings.
      await navigateToPath(member1Page, ACCOUNT_PATH);
      originalPreference = await member1Page.locator("#toggle_optional_notifications_enabled").isChecked();
      await saveOptionalNotificationPreference(member1Page, false);

      // Send an optional group notification and assert Member One is omitted exactly.
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
            userIds: GROUP_CUSTOM_RECIPIENT_IDS_WITH_MEMBER1_OPTED_OUT,
          },
        ]),
      );

      // Add the opted-out user to the group team and assert the mandatory invitation is still sent.
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
            templateDataContains: { group: { group_id: TEST_GROUP_IDS.community1.alpha } },
            userIds: [TEST_USER_IDS.member1],
          },
        ]),
      );
    } finally {
      // Remove generated notifications, invitation, and preference changes.
      deleteNotifications(notificationIds);
      cleanupGroupTeamInvitation({
        groupId: TEST_GROUP_IDS.community1.alpha,
        userId: TEST_USER_IDS.member1,
      });
      if (typeof originalPreference === "boolean") {
        await saveOptionalNotificationPreference(member1Page, originalPreference);
      }
    }
  });

  test("test events suppress publish and cancellation notifications", async ({ organizerGroupPage }) => {
    // Create an owned test event with an attendee that would otherwise receive cancellation.
    const scenario = setupNotificationEvent({
      attendeeUserIds: [TEST_USER_IDS.member1],
      groupId: TEST_GROUP_IDS.community1.alpha,
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

/** Saves the optional notification preference through the account form. */
const saveOptionalNotificationPreference = async (page, enabled) => {
  await navigateToPath(page, ACCOUNT_PATH);

  const detailsForm = page.locator("#user-details-form");
  const toggle = detailsForm.locator("#toggle_optional_notifications_enabled");

  await toggle.setChecked(enabled, { force: true });
  await expect(detailsForm.locator("#optional_notifications_enabled")).toHaveValue(String(enabled));
  await waitForActionResponse(page, () => detailsForm.getByRole("button", { name: "Save" }).click(), {
    method: "PUT",
    urlIncludes: "/dashboard/account/update/details",
  });
};
