import { expect, test } from "../../../fixtures.js";

import { cleanupEventsByIds, setupCancelableEvent } from "../../../data-graphs/events.js";
import {
  TEST_EVENT_IDS,
  TEST_EVENT_NAMES,
  TEST_REGISTRATION_WINDOW_EVENTS,
  TEST_TICKETING_EVENTS,
} from "../../../seed.js";
import {
  deleteNotifications,
  expectNewNotifications,
  snapshotNotifications,
} from "../../../notifications.js";
import {
  expectPaginationNavigation,
  expectTableColumnsAtViewport,
  expectTableHeaders,
  navigateToPath,
  waitForActionResponse,
} from "../../../utils.js";
import { openGroupEventsTabWithEvent } from "./helpers.js";

test.describe("group dashboard Events tab", () => {
  test("empty state covers both event list tabs", async ({ organizerEmptyGroupPage }) => {
    // Load events for the dedicated group without event records.
    await navigateToPath(organizerEmptyGroupPage, "/dashboard/group?tab=events");
    const dashboardContent = organizerEmptyGroupPage.locator("#dashboard-content");

    // Verify the upcoming tab keeps its creation action and empty guidance.
    await expect(dashboardContent.locator("#upcoming-content")).toContainText(
      "It looks like you don't have any upcoming events.",
    );
    await expect(dashboardContent.getByRole("button", { name: "Add Event" })).toBeVisible();

    // Switch to past events and verify its independent empty state.
    await dashboardContent.locator("#past-tab").click();
    await expect(dashboardContent.locator("#past-content")).toContainText(
      "It looks like you don't have any past events.",
    );
  });

  test("events tables expose every column at its responsive breakpoint", async ({ organizerGroupPage }) => {
    // Load the group events dashboard before checking table structure.
    await navigateToPath(organizerGroupPage, "/dashboard/group?tab=events");

    // Find the upcoming events table and its complete ordered header set.
    const eventsTable = organizerGroupPage.getByRole("table", {
      name: "Upcoming events list",
    });
    const headers = ["Name", "Location", "Date", "Type", "Status", "Attendees", "Actions"];

    // Verify header order and column visibility across dashboard breakpoints.
    await expectTableColumnsAtViewport(
      organizerGroupPage,
      eventsTable,
      1024,
      ["Name", "Status", "Actions"],
      ["Location", "Date", "Type", "Attendees"],
    );
    await expectTableColumnsAtViewport(
      organizerGroupPage,
      eventsTable,
      1280,
      ["Name", "Date", "Type", "Status", "Actions"],
      ["Location", "Attendees"],
    );
    await expectTableColumnsAtViewport(organizerGroupPage, eventsTable, 1536, headers, []);
    await expectTableHeaders(eventsTable, headers);
  });

  test("organizer can move between event result pages", async ({ organizerGroupPage }) => {
    // Paginate the seeded upcoming-event rows with one result per page.
    await expectPaginationNavigation(
      organizerGroupPage,
      "/dashboard/group?tab=events&limit=1&offset=0",
      "#upcoming-content tbody tr",
    );
  });

  test("organizer can move between past event result pages", async ({ organizerGroupPage }) => {
    // Paginate the seeded past-event rows with one result per page.
    await expectPaginationNavigation(
      organizerGroupPage,
      "/dashboard/group?tab=events&events_tab=past&limit=1&past_offset=0",
      "#past-content tbody tr",
    );
  });

  test("organizer can switch between upcoming and past events tabs", async ({ organizerGroupPage }) => {
    // Load the events list before switching tab state.
    await navigateToPath(organizerGroupPage, "/dashboard/group?tab=events");

    // Target tab controls and content regions inside dashboard content.
    const dashboardContent = organizerGroupPage.locator("#dashboard-content");
    const upcomingTab = dashboardContent.locator("#upcoming-tab");
    const pastTab = dashboardContent.locator("#past-tab");
    const upcomingContent = dashboardContent.locator("#upcoming-content");
    const pastContent = dashboardContent.locator("#past-content");

    // Verify the upcoming tab starts active with seeded event rows.
    await expect(upcomingTab).toHaveAttribute("data-active", "true");
    await expect(pastTab).toHaveAttribute("data-active", "false");
    await expect(upcomingContent).toBeVisible();
    await expect(pastContent).toBeHidden();
    await expect(upcomingContent.locator("tr", { hasText: TEST_EVENT_NAMES.alpha[0] })).toBeVisible();

    // Switch to past events and verify historical rows render.
    await pastTab.click();

    // Verify the past tab becomes active with historical rows.
    await expect(pastTab).toHaveAttribute("data-active", "true");
    await expect(upcomingTab).toHaveAttribute("data-active", "false");
    await expect(pastContent).toBeVisible();
    await expect(upcomingContent).toBeHidden();
    await expect(pastContent.locator("tr", { hasText: "Past Event For Filtering" })).toBeVisible();

    // Return to upcoming events and verify the original tab state.
    await upcomingTab.click();

    // Verify the upcoming tab returns to active state.
    await expect(upcomingTab).toHaveAttribute("data-active", "true");
    await expect(pastTab).toHaveAttribute("data-active", "false");
    await expect(upcomingContent).toBeVisible();
    await expect(pastContent).toBeHidden();
    await expect(upcomingContent.locator("tr", { hasText: TEST_EVENT_NAMES.alpha[0] })).toBeVisible();
  });

  test("organizer sees attendee count and capacity for capped events", async ({ organizerGroupPage }) => {
    // Load the events list at the width where the attendees column is visible.
    await organizerGroupPage.setViewportSize({ width: 1600, height: 900 });
    await navigateToPath(organizerGroupPage, "/dashboard/group?tab=events");

    // Find the seeded event with two occupied seats and a capacity of 100.
    const upcomingEventsTable = organizerGroupPage.getByRole("table", {
      name: "Upcoming events list",
    });
    const cappedEventRow = upcomingEventsTable.getByRole("row", {
      name: new RegExp(TEST_EVENT_NAMES.alpha[0], "u"),
    });

    // Verify the attendee count is displayed alongside the event capacity.
    await expect(cappedEventRow.getByRole("cell", { name: "2 / 100", exact: true })).toBeVisible();
  });

  test("organizer sees the 500-seat fallback for a migrated unlimited event", async ({
    organizerGroupPage,
  }) => {
    // Load the events list at the width where the attendees column is visible.
    await organizerGroupPage.setViewportSize({ width: 1600, height: 900 });
    await navigateToPath(organizerGroupPage, "/dashboard/group?tab=events");

    // Find the fixture shaped like an unlimited event after migration.
    const upcomingEventsTable = organizerGroupPage.getByRole("table", {
      name: "Upcoming events list",
    });
    const defaultCapacityEventRow = upcomingEventsTable.getByRole("row", {
      name: new RegExp(TEST_TICKETING_EVENTS.migratedCapacity.name, "u"),
    });

    // Verify the migration fallback is represented by the generated 500-seat tier.
    await expect(
      defaultCapacityEventRow.getByRole("cell", {
        name: "0 / 500",
        exact: true,
      }),
    ).toBeVisible();
  });

  test("organizer sees why active events cannot be deleted", async ({ organizerGroupPage }) => {
    // Load the event list and inspect an active published event.
    await navigateToPath(organizerGroupPage, "/dashboard/group?tab=events");
    const activeEventRow = organizerGroupPage.locator("tr", {
      hasText: TEST_EVENT_NAMES.alpha[1],
    });
    await expect(activeEventRow).toBeVisible();
    await activeEventRow.locator(".btn-actions").click();

    // Verify published events must be canceled before deletion.
    const cancelFirstDeleteButton = activeEventRow.locator(`#delete-event-${TEST_EVENT_IDS.alpha.two}`);
    await expect(cancelFirstDeleteButton).toBeDisabled();
    await expect(cancelFirstDeleteButton).toHaveAttribute("title", "Cancel this event before deleting it.");

    // Inspect an event with an active payment hold.
    await activeEventRow.locator(".btn-actions").click();
    const pendingCheckoutEvent = TEST_REGISTRATION_WINDOW_EVENTS.pendingPaymentClosed;
    const pendingCheckoutRow = organizerGroupPage.locator("tr", {
      hasText: pendingCheckoutEvent.name,
    });
    await expect(pendingCheckoutRow).toBeVisible();
    await pendingCheckoutRow.locator(".btn-actions").click();

    // Verify pending checkouts and refunds explain why deletion is blocked.
    const refundsPendingDeleteButton = pendingCheckoutRow.locator(`#delete-event-${pendingCheckoutEvent.id}`);
    await expect(refundsPendingDeleteButton).toBeDisabled();
    await expect(refundsPendingDeleteButton).toHaveAttribute(
      "title",
      "Resolve pending checkouts and refunds before deleting this event.",
    );
  });

  test("organizer can cancel an event from the list", async ({ organizerGroupPage }) => {
    // Create an owned event graph with attendees, waitlist, and speaker recipients.
    const scenario = setupCancelableEvent({ groupId: "44444444-4444-4444-4444-444444444441" });
    let notificationIds = [];

    try {
      // Load the events list with the owned event available for cancellation.
      const dashboardContent = organizerGroupPage.locator("#dashboard-content");
      const eventRow = await openGroupEventsTabWithEvent(organizerGroupPage, scenario.name);
      await expect(dashboardContent.getByText("Events", { exact: true })).toBeVisible();

      // Open the actions menu and cancel the owned event.
      await eventRow.locator(".btn-actions").click();
      const cancelButton = eventRow.locator('button[id^="cancel-event-"]');
      await expect(cancelButton).toBeVisible();
      await cancelButton.click();
      await expect(organizerGroupPage.locator(".swal2-popup")).toContainText(
        "Cancel this event? This cannot be undone. All attendee registrations will be canceled immediately. Full refunds for eligible paid purchases will be queued and may take time to process.",
      );

      // Confirm cancellation and assert the exact cancellation recipients.
      const snapshot = snapshotNotifications();
      await waitForActionResponse(
        organizerGroupPage,
        () => organizerGroupPage.getByRole("button", { name: "Cancel event" }).click(),
        {
          method: "PUT",
          urlIncludes: `/dashboard/group/events/${scenario.eventId}/cancel`,
        },
      );
      notificationIds = expectNewNotifications(snapshot, [
        {
          kind: "event-canceled",
          templateDataContains: { event: { event_id: scenario.eventId } },
          userIds: scenario.recipientUserIds,
        },
      ]);

      // Reopen the events page after cancellation so the row reflects deletion eligibility.
      const canceledEventRow = await openGroupEventsTabWithEvent(organizerGroupPage, scenario.name);

      // Verify the row reflects canceled state and no longer offers cancellation.
      await expect(canceledEventRow).toContainText("Canceled");
      await expect(canceledEventRow.locator('button[id^="cancel-event-"]')).toHaveCount(0);
      const eventActionsButton = canceledEventRow.locator(".btn-actions");
      const eventActionsDropdown = canceledEventRow.locator("[data-event-actions-dropdown]");
      await eventActionsButton.click();
      await expect(eventActionsDropdown).toBeVisible();

      // Delete the owned canceled event to keep the list reusable.
      const deleteButton = canceledEventRow.locator('button[id^="delete-event-"]');
      await expect(deleteButton).toBeEnabled();
      await deleteButton.click();
      await expect(organizerGroupPage.locator(".swal2-popup")).toContainText(
        "Delete this event? This removes it from the dashboard and cannot be undone.",
      );

      // Confirm deletion and wait for the server response.
      await waitForActionResponse(
        organizerGroupPage,
        () => organizerGroupPage.getByRole("button", { name: "Yes" }).click(),
        {
          method: "DELETE",
          urlIncludes: `/dashboard/group/events/${scenario.eventId}/delete`,
        },
      );

      // Verify the deleted event is removed from the list.
      await expect(dashboardContent.locator("tr", { hasText: scenario.name })).toHaveCount(0);
    } finally {
      // Remove generated notifications and any remaining copied event.
      deleteNotifications(notificationIds);
      cleanupEventsByIds([scenario.eventId]);
    }
  });

  test("organizer can unpublish and publish an event from the list", async ({ organizerGroupPage }) => {
    // Load the events list before changing publish status.
    await navigateToPath(organizerGroupPage, "/dashboard/group?tab=events");

    // Target the seeded published event in the list.
    const dashboardContent = organizerGroupPage.locator("#dashboard-content");
    const eventRow = dashboardContent.locator("tr", {
      hasText: "Upcoming In-Person Event",
    });
    await expect(eventRow).toBeVisible();
    await expect(eventRow).toContainText("Published");

    // Unpublish the seeded event from the actions menu.
    const actionsButton = eventRow.locator(`.btn-actions[data-event-id="${TEST_EVENT_IDS.alpha.one}"]`);
    await actionsButton.click();

    // Target the unpublish action after opening the menu.
    const unpublishButton = organizerGroupPage.locator(`#unpublish-event-${TEST_EVENT_IDS.alpha.one}`);
    await expect(unpublishButton).toBeVisible();

    // Confirm unpublish and wait for the server response.
    await Promise.all([
      organizerGroupPage.waitForResponse(
        (response) =>
          response.request().method() === "PUT" &&
          response.url().includes(`/dashboard/group/events/${TEST_EVENT_IDS.alpha.one}/unpublish`) &&
          response.ok(),
      ),
      unpublishButton.click(),
      organizerGroupPage.getByRole("button", { name: "Yes" }).click(),
    ]);

    // Verify the event row reflects draft state.
    await expect(eventRow).toContainText("Draft");

    // Publish the seeded event again to restore the original state.
    await eventRow.locator(`.btn-actions[data-event-id="${TEST_EVENT_IDS.alpha.one}"]`).click();

    // Target the publish action after opening the menu.
    const publishButton = organizerGroupPage.locator(`#publish-event-${TEST_EVENT_IDS.alpha.one}`);
    await expect(publishButton).toBeVisible();

    // Confirm publish and wait for the server response.
    await Promise.all([
      organizerGroupPage.waitForResponse(
        (response) =>
          response.request().method() === "PUT" &&
          response.url().includes(`/dashboard/group/events/${TEST_EVENT_IDS.alpha.one}/publish`) &&
          response.ok(),
      ),
      publishButton.click(),
      organizerGroupPage.getByRole("button", { name: "Yes" }).click(),
    ]);

    // Verify the event row returns to published state.
    await expect(eventRow).toContainText("Published");
  });
});
