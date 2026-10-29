import { expect, test } from "../../fixtures.js";
import { queryE2eDatabase, queryE2eDatabaseRows, sqlUuid, sqlUuidArray } from "../../database.js";
import { cleanupEventsByIds } from "../../data-graphs/events.js";
import { TEST_EVENT_CATEGORY_IDS, TEST_GROUP_AUDIENCE_IDS, TEST_USER_IDS } from "../../seed.js";
import {
  futureDate,
  navigateToPath,
  selectTimezone,
  uniqueName,
  waitForActionResponse,
} from "../../utils.js";
import { fillMarkdownEditor } from "../../dashboard/form-helpers.js";
import {
  listEventLabels,
  listSessionLabels,
  waitForEventEditorAfterSave,
} from "../../dashboard/group/events/helpers.js";
import {
  addSession,
  expectSessionCardLabels,
  openSessionsSection,
  setLabels,
} from "../../dashboard/group/events/event-form-helpers.js";

const ALPHA_GROUP_EVENT_SERIES_PUBLISHED_RECIPIENT_IDS = TEST_GROUP_AUDIENCE_IDS.alpha;

test.describe("recurring event workflows", () => {
  test("each recurring occurrence gets its own labels used by its sessions", async ({
    organizerGroupPage,
    owned,
  }) => {
    // Create unique names for the recurring labeled series, resolving its events at cleanup.
    const eventName = uniqueName("recurring labeled event");
    const sessionName = uniqueName("recurring labeled session");
    owned.defer(() => cleanupEventsByIds(listEventIdsByName(eventName)));

    // Open the event form from the dashboard list.
    await navigateToPath(organizerGroupPage, "/dashboard/group?tab=events");
    const dashboardContent = organizerGroupPage.locator("#dashboard-content");
    await dashboardContent.getByRole("button", { name: "Add Event" }).click();
    await expect(organizerGroupPage.locator("#name")).toBeVisible();

    // Fill the core event details for the recurring series.
    await organizerGroupPage.locator("#name").fill(eventName);
    await organizerGroupPage.locator("#kind_id").selectOption("virtual");
    await organizerGroupPage.locator("#category_id").selectOption(TEST_EVENT_CATEGORY_IDS.general);
    await organizerGroupPage
      .locator("#description_short")
      .fill("A recurring dashboard event with labeled sessions.");
    await fillMarkdownEditor(
      organizerGroupPage,
      "description",
      "A recurring dashboard event used by session label e2e coverage.",
    );

    // Fill the recurring schedule and occurrence count.
    await organizerGroupPage.locator('button[data-section="date-venue"]').click();
    await selectTimezone(organizerGroupPage, "UTC");
    await organizerGroupPage.locator("#starts_at").fill(futureDate({ days: 89, hour: 10 }));
    await organizerGroupPage.locator("#ends_at").fill(futureDate({ days: 89, hour: 12 }));
    await organizerGroupPage
      .locator("#meeting_join_url")
      .fill("https://meet.example.com/e2e-recurring-labeled-event");
    await organizerGroupPage.locator("#recurrence_pattern").selectOption("weekly");
    await expect(organizerGroupPage.locator("#recurrence-additional-occurrences-container")).toBeVisible();
    await organizerGroupPage.locator("#recurrence_additional_occurrences").fill("2");

    // Add labels and a session that uses one of them.
    await setLabels(organizerGroupPage, ["track / alpha", "track / beta"]);
    await addSession(organizerGroupPage, {
      endTime: "11:00",
      labels: ["track / beta"],
      name: sessionName,
      startTime: "10:30",
    });

    // Create the recurring series and wait for the first occurrence editor.
    const visibleAddEventButton = organizerGroupPage.locator(
      "#pending-changes-alert:not(.hidden) #add-event-button",
    );
    await expect(visibleAddEventButton).toBeVisible();
    await waitForActionResponse(organizerGroupPage, () => visibleAddEventButton.click(), {
      method: "POST",
      urlIncludes: "/dashboard/group/events/add",
      status: 201,
    });
    await waitForEventEditorAfterSave(organizerGroupPage);
    const eventIds = listEventIdsByName(eventName);
    expect(eventIds).toHaveLength(3);

    // Verify the first occurrence editor shows the session label.
    await openSessionsSection(organizerGroupPage);
    await expectSessionCardLabels(organizerGroupPage, sessionName, ["track / beta"]);

    // Verify every occurrence owns a separate copy of the labels.
    const occurrenceLabels = eventIds.map((eventId) => listEventLabels(eventId));
    for (const labels of occurrenceLabels) {
      expect(labels.map((label) => label.name)).toEqual(["track / alpha", "track / beta"]);
    }
    const labelIds = occurrenceLabels.flat().map((label) => label.id);
    expect(new Set(labelIds).size).toBe(labelIds.length);

    // Verify every occurrence session uses the labels of its own occurrence.
    for (const eventId of eventIds) {
      expect(listSessionLabels(eventId)).toEqual([{ labels: ["track / beta"], name: sessionName }]);
    }
    expect(listSessionLabelEventIds(eventIds)).toEqual(eventIds.map((eventId) => [eventId, eventId]));
  });

  test("organizer can scope recurring publish, unpublish, and cancel actions", async ({
    notifications,
    organizerGroupPage,
    owned,
  }) => {
    // Create a unique event name for the recurring scoped actions flow, resolving its events at
    // cleanup.
    const eventName = uniqueName("recurring scoped event");
    owned.defer(() => cleanupEventsByIds(listEventIdsByName(eventName)));

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
    await organizerGroupPage.locator("#category_id").selectOption(TEST_EVENT_CATEGORY_IDS.general);
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
    const eventIds = listEventIdsByName(eventName);

    // Make Pending Two a speaker on every occurrence so the first publish welcomes them once.
    addSeriesSpeakers(eventIds, TEST_USER_IDS.pending2);

    // Publish the full series and assert member/team fan-out plus the speaker welcome.
    const firstPublishCheckpoint = notifications.checkpoint();
    await selectScopedAction(organizerGroupPage, eventRows.first(), "publish", "All in series");
    notifications.expectNew(
      [
        {
          kind: "event-series-published",
          templateDataContains: { event_count: 3 },
          userIds: ALPHA_GROUP_EVENT_SERIES_PUBLISHED_RECIPIENT_IDS,
        },
        {
          kind: "speaker-series-welcome",
          templateDataContains: { event_count: 3 },
          userIds: [TEST_USER_IDS.pending2],
        },
      ],
      { since: firstPublishCheckpoint },
    );

    // Remove the speakers again: the republish and cancellation expectations below exclude them.
    removeSeriesSpeakers(eventIds);
    await expect(eventRows.first()).toContainText("Published");
    await expect(eventRows.nth(1)).toContainText("Published");
    await expect(eventRows.nth(2)).toContainText("Published");

    // Unpublish the whole series.
    await selectScopedAction(organizerGroupPage, eventRows.first(), "unpublish", "All in series");
    await expect(eventRows.first()).toContainText("Draft");
    await expect(eventRows.nth(1)).toContainText("Draft");
    await expect(eventRows.nth(2)).toContainText("Draft");

    // Republish the full series so the cancellation broadcast covers all occurrences.
    const secondPublishCheckpoint = notifications.checkpoint();
    await selectScopedAction(organizerGroupPage, eventRows.first(), "publish", "All in series");
    notifications.expectNew(
      [
        {
          kind: "event-series-published",
          templateDataContains: { event_count: 3 },
          userIds: ALPHA_GROUP_EVENT_SERIES_PUBLISHED_RECIPIENT_IDS,
        },
      ],
      { since: secondPublishCheckpoint },
    );
    await expect(eventRows.first()).toContainText("Published");
    await expect(eventRows.nth(1)).toContainText("Published");
    await expect(eventRows.nth(2)).toContainText("Published");

    // Attach one attendee to each occurrence so series cancellation has exact recipients.
    addSeriesCancellationAttendees(eventIds, TEST_USER_IDS.member2);

    // Cancel the full series and assert occurrence attendee fan-out.
    const cancelCheckpoint = notifications.checkpoint();
    await selectScopedAction(
      organizerGroupPage,
      eventRows.first(),
      "cancel",
      "Non-completed events in series",
    );
    notifications.expectNew(
      [
        {
          kind: "event-series-canceled",
          templateDataContains: { event_count: 3 },
          userIds: [TEST_USER_IDS.member2],
        },
      ],
      { since: cancelCheckpoint },
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
    await waitForActionResponse(
      organizerGroupPage,
      () => seriesConfirmationDialog.getByRole("button", { name: "All in series" }).click(),
      {
        method: "DELETE",
        params: { scope: "series" },
        pathname: /^\/dashboard\/group\/events\/[^/]+\/delete$/u,
        status: 204,
      },
    );

    // Verify every recurring series row is removed from the list.
    await expect(dashboardContent.locator("tr", { hasText: eventName })).toHaveCount(0);
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

/** Adds the user as a speaker on every given event. */
const addSeriesSpeakers = (eventIds, userId) => {
  queryE2eDatabase(`
    insert into event_speaker (event_id, user_id, featured)
    select event_id, ${sqlUuid(userId)}, false
    from unnest(${sqlUuidArray(eventIds)}) as event_id;
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

/** Returns the event of each session and of its label for the session labels of the events. */
const listSessionLabelEventIds = (eventIds) =>
  queryE2eDatabaseRows(`
    select s.event_id, el.event_id
    from session s
    join session_label sl on sl.session_id = s.session_id
    join event_label el on el.event_label_id = sl.event_label_id
    where s.event_id = any(array[${eventIds.map((eventId) => `'${eventId}'::uuid`).join(", ")}])
    order by s.starts_at, s.event_id
  `);

/** Removes every speaker from the given events. */
const removeSeriesSpeakers = (eventIds) => {
  queryE2eDatabase(`delete from event_speaker where event_id = any(${sqlUuidArray(eventIds)});`);
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

  await waitForActionResponse(
    page,
    () => seriesConfirmationDialog.getByRole("button", { name: scopeButtonName }).click(),
    {
      method: "PUT",
      params: { scope: "series" },
      pathname: new RegExp(`^/dashboard/group/events/[^/]+/${action}$`, "u"),
      status: 204,
    },
  );
};
