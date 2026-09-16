import { expect, test } from "../../fixtures.js";
import { queryE2eDatabase, queryE2eDatabaseRows } from "../../database.js";
import { deleteNotifications, expectNewNotifications, snapshotNotifications } from "../../notifications.js";
import { cleanupEventsByIds } from "../../data-graphs/events.js";
import { TEST_USER_IDS } from "../../seed.js";
import {
  futureDate,
  navigateToPath,
  selectTimezone,
  uniqueName,
  waitForActionResponse,
} from "../../utils.js";
import { fillMarkdownEditor } from "../../dashboard/form-helpers.js";
import { waitForEventEditorAfterSave } from "../../dashboard/group/events/helpers.js";

const ALPHA_GROUP_EVENT_SERIES_PUBLISHED_RECIPIENT_IDS = [
  TEST_USER_IDS.organizer1,
  TEST_USER_IDS.member1,
  "77777777-7777-7777-7777-777777777711",
  "77777777-7777-7777-7777-777777777712",
  "77777777-7777-7777-7777-777777777714",
  TEST_USER_IDS.checkInManager1,
];

test.describe("recurring event workflows", () => {
  test("organizer can create and delete a recurring event series", async ({ organizerGroupPage }) => {
    // Create a unique event name for the recurring series flow.
    const eventName = uniqueName("recurring group event");
    let eventIds = [];

    try {
      // Load the events list before creating a recurring series.
      await navigateToPath(organizerGroupPage, "/dashboard/group?tab=events");

      // Target dashboard content after the events tab loads.
      const dashboardContent = organizerGroupPage.locator("#dashboard-content");
      await expect(dashboardContent.getByText("Events", { exact: true })).toBeVisible();

      // Open the event form from the dashboard list.
      await dashboardContent.getByRole("button", { name: "Add Event" }).click();
      await expect(organizerGroupPage.locator("#name")).toBeVisible();

      // Fill the core event details for the recurring series.
      await organizerGroupPage.locator("#name").fill(eventName);
      await organizerGroupPage.locator("#kind_id").selectOption("virtual");
      await organizerGroupPage.locator("#category_id").selectOption("33333333-3333-3333-3333-333333333331");
      await organizerGroupPage
        .locator("#description_short")
        .fill("A recurring dashboard-created event from the e2e suite.");
      await fillMarkdownEditor(
        organizerGroupPage,
        "description",
        "A recurring dashboard event created and removed by the e2e suite.",
      );

      // Fill the recurring schedule and occurrence count.
      await organizerGroupPage.locator('button[data-section="date-venue"]').click();
      await selectTimezone(organizerGroupPage, "UTC");
      await expect(organizerGroupPage.locator("#starts_at")).toBeVisible();
      await organizerGroupPage.locator("#starts_at").fill(futureDate({ days: 75, hour: 10 }));
      await organizerGroupPage.locator("#ends_at").fill(futureDate({ days: 75, hour: 12 }));
      await organizerGroupPage
        .locator("#meeting_join_url")
        .fill("https://meet.example.com/e2e-recurring-event");
      await organizerGroupPage.locator("#recurrence_pattern").selectOption("weekly");
      await expect(organizerGroupPage.locator("#recurrence-additional-occurrences-container")).toBeVisible();
      await organizerGroupPage.locator("#recurrence_additional_occurrences").fill("2");

      // Target the visible submit button after pending changes appear.
      const visibleAddEventButton = organizerGroupPage.locator(
        "#pending-changes-alert:not(.hidden) #add-event-button",
      );
      await expect(organizerGroupPage.locator("#pending-changes-alert")).not.toHaveClass(/hidden/);
      await expect(visibleAddEventButton).toBeVisible();

      // Create the recurring series and wait for the POST response.
      await waitForActionResponse(organizerGroupPage, () => visibleAddEventButton.click(), {
        method: "POST",
        urlIncludes: "/dashboard/group/events/add",
        status: 201,
      });

      // The first occurrence opens in the event editor after create.
      await waitForEventEditorAfterSave(organizerGroupPage);
      // Request the largest page so all occurrences stay visible beyond the default 50-row page.
      await navigateToPath(organizerGroupPage, "/dashboard/group?tab=events&events_tab=upcoming&limit=100");

      // Verify the recurring series creates the expected number of rows.
      const eventRows = dashboardContent.locator("tr", { hasText: eventName });
      await expect(eventRows).toHaveCount(3);
      eventIds = listEventIdsByName(eventName);

      // Delete the full series to keep the seeded list reusable.
      const eventRow = eventRows.first();
      await eventRow.locator(".btn-actions").click();

      // Open the delete confirmation for the first series occurrence.
      const deleteButton = eventRow.locator('button[id^="delete-event-"]');
      await expect(deleteButton).toBeVisible();
      await deleteButton.click();

      // Verify the recurring-series delete dialog is shown.
      const seriesConfirmationDialog = organizerGroupPage.locator(".swal2-popup");
      await expect(seriesConfirmationDialog).toContainText(
        "This event is part of a recurring series. What would you like to delete?",
      );

      // Confirm full-series deletion and wait for the server response.
      await Promise.all([
        organizerGroupPage.waitForResponse(
          (response) =>
            response.request().method() === "DELETE" &&
            response.url().includes("/dashboard/group/events/") &&
            response.url().includes("/delete") &&
            response.url().includes("scope=series") &&
            response.ok(),
        ),
        seriesConfirmationDialog.getByRole("button", { name: "All in series" }).click(),
      ]);

      // Verify every recurring series row is removed from the list.
      await expect(dashboardContent.locator("tr", { hasText: eventName })).toHaveCount(0);
    } finally {
      // Remove any remaining recurring event rows.
      cleanupEventsByIds(eventIds);
    }
  });

  test("organizer can scope recurring publish, unpublish, and cancel actions", async ({
    organizerGroupPage,
  }) => {
    // Create a unique event name for the recurring scoped actions flow.
    const eventName = uniqueName("recurring scoped event");
    let eventIds = [];
    let notificationIds = [];

    try {
      // Load the events list before creating a recurring series.
      await navigateToPath(organizerGroupPage, "/dashboard/group?tab=events");

      // Target dashboard content after the events tab loads.
      const dashboardContent = organizerGroupPage.locator("#dashboard-content");
      await expect(dashboardContent.getByText("Events", { exact: true })).toBeVisible();

      // Open the event form from the dashboard list.
      await dashboardContent.getByRole("button", { name: "Add Event" }).click();
      await expect(organizerGroupPage.locator("#name")).toBeVisible();

      // Fill the core event details for the recurring series.
      await organizerGroupPage.locator("#name").fill(eventName);
      await organizerGroupPage.locator("#kind_id").selectOption("virtual");
      await organizerGroupPage.locator("#category_id").selectOption("33333333-3333-3333-3333-333333333331");
      await organizerGroupPage
        .locator("#description_short")
        .fill("A recurring dashboard event for scoped action coverage.");
      await fillMarkdownEditor(
        organizerGroupPage,
        "description",
        "A recurring dashboard event used by scoped action e2e coverage.",
      );

      // Fill the recurring schedule and occurrence count.
      await organizerGroupPage.locator('button[data-section="date-venue"]').click();
      await selectTimezone(organizerGroupPage, "UTC");
      await expect(organizerGroupPage.locator("#starts_at")).toBeVisible();
      await organizerGroupPage.locator("#starts_at").fill(futureDate({ days: 82, hour: 10 }));
      await organizerGroupPage.locator("#ends_at").fill(futureDate({ days: 82, hour: 12 }));
      await organizerGroupPage
        .locator("#meeting_join_url")
        .fill("https://meet.example.com/e2e-recurring-scoped-event");
      await organizerGroupPage.locator("#recurrence_pattern").selectOption("weekly");
      await expect(organizerGroupPage.locator("#recurrence-additional-occurrences-container")).toBeVisible();
      await organizerGroupPage.locator("#recurrence_additional_occurrences").fill("2");

      // Target the visible submit button after pending changes appear.
      const visibleAddEventButton = organizerGroupPage.locator(
        "#pending-changes-alert:not(.hidden) #add-event-button",
      );
      await expect(organizerGroupPage.locator("#pending-changes-alert")).not.toHaveClass(/hidden/);
      await expect(visibleAddEventButton).toBeVisible();

      // Create the recurring series and wait for the POST response.
      await waitForActionResponse(organizerGroupPage, () => visibleAddEventButton.click(), {
        method: "POST",
        urlIncludes: "/dashboard/group/events/add",
        status: 201,
      });

      // The first occurrence opens in the event editor after create.
      await waitForEventEditorAfterSave(organizerGroupPage);
      // Request the largest page so all occurrences stay visible beyond the default 50-row page.
      await navigateToPath(organizerGroupPage, "/dashboard/group?tab=events&events_tab=upcoming&limit=100");

      // Verify the recurring series creates the expected number of rows.
      const eventRows = dashboardContent.locator("tr", { hasText: eventName });
      await expect(eventRows).toHaveCount(3);
      eventIds = listEventIdsByName(eventName);

      // Publish the full series and assert member/team fan-out.
      const firstPublishSnapshot = snapshotNotifications();
      await selectScopedAction(organizerGroupPage, eventRows.first(), "publish", "All in series");
      notificationIds = notificationIds.concat(
        expectNewNotifications(firstPublishSnapshot, [
          {
            kind: "event-series-published",
            templateDataContains: { event_count: 3 },
            userIds: ALPHA_GROUP_EVENT_SERIES_PUBLISHED_RECIPIENT_IDS,
          },
        ]),
      );
      await expect(eventRows.first()).toContainText("Published");
      await expect(eventRows.nth(1)).toContainText("Published");
      await expect(eventRows.nth(2)).toContainText("Published");

      // Unpublish the whole series.
      await selectScopedAction(organizerGroupPage, eventRows.first(), "unpublish", "All in series");
      await expect(eventRows.first()).toContainText("Draft");
      await expect(eventRows.nth(1)).toContainText("Draft");
      await expect(eventRows.nth(2)).toContainText("Draft");

      // Republish the full series so the cancellation broadcast covers all occurrences.
      const secondPublishSnapshot = snapshotNotifications();
      await selectScopedAction(organizerGroupPage, eventRows.first(), "publish", "All in series");
      notificationIds = notificationIds.concat(
        expectNewNotifications(secondPublishSnapshot, [
          {
            kind: "event-series-published",
            templateDataContains: { event_count: 3 },
            userIds: ALPHA_GROUP_EVENT_SERIES_PUBLISHED_RECIPIENT_IDS,
          },
        ]),
      );
      await expect(eventRows.first()).toContainText("Published");
      await expect(eventRows.nth(1)).toContainText("Published");
      await expect(eventRows.nth(2)).toContainText("Published");

      // Attach one attendee to each occurrence so series cancellation has exact recipients.
      addSeriesCancellationAttendees(eventIds, TEST_USER_IDS.member2);

      // Cancel the full series and assert occurrence attendee fan-out.
      const cancelSnapshot = snapshotNotifications();
      await selectScopedAction(
        organizerGroupPage,
        eventRows.first(),
        "cancel",
        "Non-completed events in series",
      );
      notificationIds = notificationIds.concat(
        expectNewNotifications(cancelSnapshot, [
          {
            kind: "event-series-canceled",
            templateDataContains: { event_count: 3 },
            userIds: [TEST_USER_IDS.member2],
          },
        ]),
      );
      await expect(eventRows.first()).toContainText("Canceled");
      await expect(eventRows.nth(1)).toContainText("Canceled");
      await expect(eventRows.nth(2)).toContainText("Canceled");

      // Delete the full series to keep the seeded list reusable.
      await eventRows.first().locator(".btn-actions").click();
      const deleteButton = eventRows.first().locator('button[id^="delete-event-"]');
      await expect(deleteButton).toBeVisible();
      await deleteButton.click();

      // Verify the recurring-series delete dialog is shown.
      const seriesConfirmationDialog = organizerGroupPage.locator(".swal2-popup");
      await expect(seriesConfirmationDialog).toContainText(
        "This event is part of a recurring series. What would you like to delete?",
      );

      // Confirm full-series deletion and wait for the server response.
      await Promise.all([
        organizerGroupPage.waitForResponse(
          (response) =>
            response.request().method() === "DELETE" &&
            response.url().includes("/dashboard/group/events/") &&
            response.url().includes("/delete") &&
            response.url().includes("scope=series") &&
            response.ok(),
        ),
        seriesConfirmationDialog.getByRole("button", { name: "All in series" }).click(),
      ]);

      // Verify every recurring series row is removed from the list.
      await expect(dashboardContent.locator("tr", { hasText: eventName })).toHaveCount(0);
    } finally {
      // Remove notifications and any remaining recurring event rows.
      deleteNotifications(notificationIds);
      cleanupEventsByIds(eventIds);
    }
  });
});

/** Inserts event_attendee rows for seeded series cancellation coverage. */
const addSeriesCancellationAttendees = (eventIds, userId) => {
  if (eventIds.length === 0) {
    return;
  }

  queryE2eDatabase(`
    insert into event_attendee (event_id, user_id, status)
    select owned_event.event_id, '${userId}', 'confirmed'
    from unnest(array[${eventIds.map((eventId) => `'${eventId}'::uuid`).join(", ")}]) as owned_event(event_id)
    on conflict (event_id, user_id) do nothing;
  `);
};

/** Returns event identifiers from the event table for a matching name. */
const listEventIdsByName = (eventName) => {
  const escapedName = eventName.replace(/'/g, "''");

  return queryE2eDatabaseRows(`
    select event_id
    from event
    where name = '${escapedName}'
    order by starts_at, event_id
  `).map(([eventId]) => eventId);
};

/** Selects a scoped recurring-event action and waits for the series request. */
const selectScopedAction = async (page, row, action, scopeButtonName) => {
  await row.locator(".btn-actions").click();
  const actionButton = row.locator(`button[id^="${action}-event-"]`);
  await expect(actionButton).toBeVisible();
  await actionButton.click();

  const seriesConfirmationDialog = page.locator(".swal2-popup");
  const expectedConfirmationMessage =
    action === "cancel"
      ? "Canceling is permanent. Attendee registrations are canceled immediately, and full refunds for eligible paid purchases are queued and may take time to process. Which events would you like to cancel?"
      : `This event is part of a recurring series. What would you like to ${action}?`;
  await expect(seriesConfirmationDialog).toContainText(expectedConfirmationMessage);

  await Promise.all([
    page.waitForResponse(
      (response) =>
        response.request().method() === "PUT" &&
        response.url().includes("/dashboard/group/events/") &&
        response.url().includes(`/${action}`) &&
        response.url().includes("scope=series") &&
        response.ok(),
    ),
    seriesConfirmationDialog.getByRole("button", { name: scopeButtonName }).click(),
  ]);
};
