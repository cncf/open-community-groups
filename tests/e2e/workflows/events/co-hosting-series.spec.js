import { expect, test } from "../../fixtures.js";

import { cleanupCohostEvents, readCohostStatus } from "../../data-graphs/cohosts.js";
import { queryE2eDatabaseRows } from "../../database.js";
import {
  addCohostThroughEditor,
  fillVirtualEventDraft,
  getCohostDashboardRows,
  respondToCohostInvitation,
} from "../../dashboard/group/cohosts/helpers.js";
import { waitForEventEditorAfterSave } from "../../dashboard/group/events/helpers.js";
import { deleteNotifications, expectNewNotifications, snapshotNotifications } from "../../notifications.js";
import { TEST_GROUP_IDS, TEST_GROUP_NAMES, TEST_USER_IDS } from "../../seed.js";
import { navigateToPath, uniqueName, waitForActionResponse } from "../../utils.js";

// Owner group members and team who receive publish notifications.
const ALPHA_EVENT_PUBLISHED_RECIPIENT_IDS = [
  TEST_USER_IDS.organizer1,
  TEST_USER_IDS.member1,
  "77777777-7777-7777-7777-777777777711",
  "77777777-7777-7777-7777-777777777712",
  "77777777-7777-7777-7777-777777777714",
  TEST_USER_IDS.checkInManager1,
];
// Cross-community group invited to co-host every occurrence.
const COHOST_GROUP_ID = TEST_GROUP_IDS.community2.delta;
const COHOST_GROUP_NAME = "E2E Second Group Delta";
// Co-host group members and team who receive publish notifications.
const COHOST_AUDIENCE_RECIPIENT_IDS = [TEST_USER_IDS.organizer2, TEST_USER_IDS.member2];
// Owner events list page that keeps every occurrence visible.
const OWNER_EVENTS_PATH = "/dashboard/group?tab=events&events_tab=upcoming&limit=100";

test.describe("event series co-hosting workflows", () => {
  test("series invitations are answered per occurrence and gate series publishing", async ({
    organizerGroupPage,
    organizerGroupWithoutPaymentsPage,
  }) => {
    const eventName = uniqueName("co-hosted series");
    let eventIds = [];
    let notificationIds = [];

    try {
      // Create a weekly series with one co-host from the add-event form.
      await navigateToPath(organizerGroupPage, "/dashboard/group?tab=events");
      const dashboardContent = organizerGroupPage.locator("#dashboard-content");
      await dashboardContent.getByRole("button", { name: "Add Event" }).click();
      await fillVirtualEventDraft(organizerGroupPage, eventName, { additionalOccurrences: 2, days: 260 });
      await addCohostThroughEditor(organizerGroupPage, {
        groupId: COHOST_GROUP_ID,
        groupName: COHOST_GROUP_NAME,
        search: "Delta",
      });
      const invitationSnapshot = snapshotNotifications();
      await waitForActionResponse(
        organizerGroupPage,
        () => organizerGroupPage.locator("#pending-changes-alert:not(.hidden) #add-event-button").click(),
        {
          method: "POST",
          status: 201,
          urlIncludes: "/dashboard/group/events/add",
        },
      );
      await waitForEventEditorAfterSave(organizerGroupPage);
      eventIds = listEventIdsByName(eventName);
      expect(eventIds).toHaveLength(3);

      // Verify the co-host admins receive one invitation covering the whole series.
      notificationIds = notificationIds.concat(
        expectNewNotifications(invitationSnapshot, [
          {
            kind: "event-cohost-invitation",
            templateDataContains: {
              cohost_group_name: COHOST_GROUP_NAME,
              events: [{ name: eventName }, { name: eventName }, { name: eventName }],
              owner_group_name: TEST_GROUP_NAMES.alpha,
            },
            userIds: [TEST_USER_IDS.organizer2],
          },
        ]),
      );

      // Verify the co-host sees one pending row per occurrence.
      await navigateToPath(organizerGroupWithoutPaymentsPage, "/dashboard/group?tab=cohosts");
      const cohostRows = getCohostDashboardRows(organizerGroupWithoutPaymentsPage, eventName);
      await expect(cohostRows).toHaveCount(3);
      for (const row of await cohostRows.all()) {
        await expect(row).toContainText("Pending");
      }

      // Verify every owner list row explains why publishing is unavailable.
      await navigateToPath(organizerGroupPage, OWNER_EVENTS_PATH);
      for (const eventId of eventIds) {
        const publishButton = organizerGroupPage.locator(`#publish-event-${eventId}`);
        await expect(publishButton).toBeDisabled();
        await expect(publishButton).toHaveAttribute("title", "Waiting for 1 co-host(s) to respond.");
      }

      // Approve only the latest occurrence, listed first on the co-host dashboard.
      await respondToCohostInvitation(organizerGroupWithoutPaymentsPage, eventName, "approve");
      const approvedEventId = eventIds[2];
      expect(readCohostStatus(approvedEventId, COHOST_GROUP_ID)).toBe("approved");
      expect(readCohostStatus(eventIds[0], COHOST_GROUP_ID)).toBe("pending");
      expect(readCohostStatus(eventIds[1], COHOST_GROUP_ID)).toBe("pending");

      // Verify publishing the whole series is rejected while other occurrences are pending.
      await navigateToPath(organizerGroupPage, OWNER_EVENTS_PATH);
      await openScopedPublishDialog(organizerGroupPage, approvedEventId);
      await waitForActionResponse(
        organizerGroupPage,
        () =>
          organizerGroupPage.locator(".swal2-popup").getByRole("button", { name: "All in series" }).click(),
        {
          method: "PUT",
          status: 422,
          urlIncludes: `/dashboard/group/events/${approvedEventId}/publish?scope=series`,
        },
      );
      await expect(organizerGroupPage.locator(".swal2-popup")).toContainText(
        "co-hosts must respond for every event in the series before publishing",
      );
      await organizerGroupPage
        .locator(".swal2-popup")
        .getByRole("button", { name: "OK", exact: true })
        .click();

      // Publish only the approved occurrence and verify both audiences are notified.
      await navigateToPath(organizerGroupPage, OWNER_EVENTS_PATH);
      await openScopedPublishDialog(organizerGroupPage, approvedEventId);
      const publishSnapshot = snapshotNotifications();
      await waitForActionResponse(
        organizerGroupPage,
        () =>
          organizerGroupPage.locator(".swal2-popup").getByRole("button", { name: "Only this event" }).click(),
        {
          method: "PUT",
          urlEndsWith: `/dashboard/group/events/${approvedEventId}/publish`,
        },
      );
      notificationIds = notificationIds.concat(
        expectNewNotifications(publishSnapshot, [
          { kind: "event-published", userIds: ALPHA_EVENT_PUBLISHED_RECIPIENT_IDS },
          {
            kind: "event-published",
            templateDataContains: { cohost_group_name: COHOST_GROUP_NAME },
            userIds: COHOST_AUDIENCE_RECIPIENT_IDS,
          },
        ]),
      );

      // Verify only the approved occurrence was published.
      expect(listPublishedEventIds(eventIds)).toEqual([approvedEventId]);
    } finally {
      // Restore seeded state.
      deleteNotifications(notificationIds);
      cleanupCohostEvents(eventIds);
    }
  });
});

/** Returns event identifiers for a unique event name ordered by start time. */
const listEventIdsByName = (eventName) =>
  queryE2eDatabaseRows(`
    select event_id
    from event
    where name = '${eventName.replaceAll("'", "''")}'
    order by starts_at, event_id
  `).map(([eventId]) => eventId);

/** Returns which of the given events are currently published. */
const listPublishedEventIds = (eventIds) =>
  queryE2eDatabaseRows(`
    select event_id
    from event
    where event_id = any(array[${eventIds.map((eventId) => `'${eventId}'::uuid`).join(", ")}])
    and published = true
    order by starts_at, event_id
  `).map(([eventId]) => eventId);

/** Opens the owner row actions for one occurrence and starts its scoped publish action. */
const openScopedPublishDialog = async (page, eventId) => {
  const publishButton = page.locator(`#publish-event-${eventId}`);
  const eventRow = page.locator("#dashboard-content tr", { has: publishButton });
  await eventRow.locator(".btn-actions").click();
  await expect(publishButton).toBeEnabled();
  await publishButton.click();
  await expect(page.locator(".swal2-popup")).toContainText(
    "This event is part of a recurring series. What would you like to publish?",
  );
};
