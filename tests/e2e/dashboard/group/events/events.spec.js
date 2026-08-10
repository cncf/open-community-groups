import { expect, test } from "../../../fixtures.js";

import {
  E2E_MEETINGS_ENABLED,
  E2E_PAYMENTS_ENABLED,
  TEST_APPROVAL_REQUIRED_EVENT,
  TEST_COMMUNITY_NAME,
  TEST_EVENT_IDS,
  TEST_EVENT_NAMES,
  TEST_EVENT_SLUGS,
  TEST_GROUP_SLUGS,
  TEST_PAYMENT_EVENT_IDS,
  TEST_PAYMENT_EVENT_NAMES,
  TEST_REGISTRATION_WINDOW_EVENTS,
  TEST_TICKETING_EVENTS,
  TEST_USER_IDS,
  expectPaginationNavigation,
  expectTableColumnsAtViewport,
  expectTableHeaders,
  navigateToPath,
  selectTimezone,
  waitForActionResponse,
} from "../../../utils.js";
import {
  TEST_UPLOAD_ASSET_PATHS,
  fillEventVenue,
  fillMarkdownEditor,
  fillMultipleInputs,
  uploadGalleryImages,
  uploadImageField,
} from "../../form-helpers.js";
import {
  addDiscountCode,
  openEventUpdateFormByName,
  openPaymentsSection,
} from "./helpers.js";

import {
  addTicketType,
  editTicketType,
  enableAutomaticMeetingCreation,
  expectAutomaticMeetingControls,
  expectManualMeetingFields,
  openDetailsSection,
  removeDiscountCode,
  setAutomaticMeetingCapacity,
  setCfsLabels,
  setEventPeople,
  setRegistrationQuestions,
} from "./event-form-helpers.js";

test.describe("group dashboard Events tab", () => {
  test("empty state covers both event list tabs", async ({
    organizerEmptyGroupPage,
  }) => {
    // Load events for the dedicated group without event records.
    await navigateToPath(
      organizerEmptyGroupPage,
      "/dashboard/group?tab=events",
    );
    const dashboardContent =
      organizerEmptyGroupPage.locator("#dashboard-content");

    // Verify the upcoming tab keeps its creation action and empty guidance.
    await expect(dashboardContent.locator("#upcoming-content")).toContainText(
      "It looks like you don't have any upcoming events.",
    );
    await expect(
      dashboardContent.getByRole("button", { name: "Add Event" }),
    ).toBeVisible();

    // Switch to past events and verify its independent empty state.
    await dashboardContent.locator("#past-tab").click();
    await expect(dashboardContent.locator("#past-content")).toContainText(
      "It looks like you don't have any past events.",
    );
  });

  test("events tables expose every column at its responsive breakpoint", async ({
    organizerGroupPage,
  }) => {
    // Load the group events dashboard before checking table structure.
    await navigateToPath(organizerGroupPage, "/dashboard/group?tab=events");

    // Find the upcoming events table and its complete ordered header set.
    const eventsTable = organizerGroupPage.getByRole("table", {
      name: "Upcoming events list",
    });
    const headers = [
      "Name",
      "Location",
      "Date",
      "Type",
      "Status",
      "Attendees",
      "Actions",
    ];

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
    await expectTableColumnsAtViewport(
      organizerGroupPage,
      eventsTable,
      1536,
      headers,
      [],
    );
    await expectTableHeaders(eventsTable, headers);
  });

  test("organizer can move between event result pages", async ({
    organizerGroupPage,
  }) => {
    // Paginate the seeded upcoming-event rows with one result per page.
    await expectPaginationNavigation(
      organizerGroupPage,
      "/dashboard/group?tab=events&limit=1&offset=0",
      "#upcoming-content tbody tr",
    );
  });

  test("organizer can move between past event result pages", async ({
    organizerGroupPage,
  }) => {
    // Paginate the seeded past-event rows with one result per page.
    await expectPaginationNavigation(
      organizerGroupPage,
      "/dashboard/group?tab=events&events_tab=past&limit=1&past_offset=0",
      "#past-content tbody tr",
    );
  });

  test("organizer can switch between upcoming and past events tabs", async ({
    organizerGroupPage,
  }) => {
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
    await expect(
      upcomingContent.locator("tr", { hasText: TEST_EVENT_NAMES.alpha[0] }),
    ).toBeVisible();

    // Switch to past events and verify historical rows render.
    await pastTab.click();

    // Verify the past tab becomes active with historical rows.
    await expect(pastTab).toHaveAttribute("data-active", "true");
    await expect(upcomingTab).toHaveAttribute("data-active", "false");
    await expect(pastContent).toBeVisible();
    await expect(upcomingContent).toBeHidden();
    await expect(
      pastContent.locator("tr", { hasText: "Past Event For Filtering" }),
    ).toBeVisible();

    // Return to upcoming events and verify the original tab state.
    await upcomingTab.click();

    // Verify the upcoming tab returns to active state.
    await expect(upcomingTab).toHaveAttribute("data-active", "true");
    await expect(pastTab).toHaveAttribute("data-active", "false");
    await expect(upcomingContent).toBeVisible();
    await expect(pastContent).toBeHidden();
    await expect(
      upcomingContent.locator("tr", { hasText: TEST_EVENT_NAMES.alpha[0] }),
    ).toBeVisible();
  });

  test("organizer sees attendee count and capacity for capped events", async ({
    organizerGroupPage,
  }) => {
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
    await expect(
      cappedEventRow.getByRole("cell", { name: "2 / 100", exact: true }),
    ).toBeVisible();
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

  test("organizer sees why active events cannot be deleted", async ({
    organizerGroupPage,
  }) => {
    // Load the event list and inspect an active published event.
    await navigateToPath(organizerGroupPage, "/dashboard/group?tab=events");
    const activeEventRow = organizerGroupPage.locator("tr", {
      hasText: TEST_EVENT_NAMES.alpha[1],
    });
    await expect(activeEventRow).toBeVisible();
    await activeEventRow.locator(".btn-actions").click();

    // Verify published events must be canceled before deletion.
    const cancelFirstDeleteButton = activeEventRow.locator(
      `#delete-event-${TEST_EVENT_IDS.alpha.two}`,
    );
    await expect(cancelFirstDeleteButton).toBeDisabled();
    await expect(cancelFirstDeleteButton).toHaveAttribute(
      "title",
      "Cancel this event before deleting it.",
    );

    // Inspect an event with an active payment hold.
    await activeEventRow.locator(".btn-actions").click();
    const pendingCheckoutEvent =
      TEST_REGISTRATION_WINDOW_EVENTS.pendingPaymentClosed;
    const pendingCheckoutRow = organizerGroupPage.locator("tr", {
      hasText: pendingCheckoutEvent.name,
    });
    await expect(pendingCheckoutRow).toBeVisible();
    await pendingCheckoutRow.locator(".btn-actions").click();

    // Verify pending checkouts and refunds explain why deletion is blocked.
    const refundsPendingDeleteButton = pendingCheckoutRow.locator(
      `#delete-event-${pendingCheckoutEvent.id}`,
    );
    await expect(refundsPendingDeleteButton).toBeDisabled();
    await expect(refundsPendingDeleteButton).toHaveAttribute(
      "title",
      "Resolve pending checkouts and refunds before deleting this event.",
    );
  });

  test("organizer can cancel an event from the list", async ({
    organizerGroupPage,
  }) => {
    // Create a unique event name for the temporary cancellation flow.
    const eventName = `E2E Canceled Group Event ${Date.now()}`;

    // Load the events list before creating a temporary event.
    await navigateToPath(organizerGroupPage, "/dashboard/group?tab=events");

    // Target dashboard content after the events tab loads.
    const dashboardContent = organizerGroupPage.locator("#dashboard-content");
    await expect(
      dashboardContent.getByText("Events", { exact: true }),
    ).toBeVisible();

    // Open the event form from the dashboard list.
    await dashboardContent.getByRole("button", { name: "Add Event" }).click();
    await expect(organizerGroupPage.locator("#name")).toBeVisible();

    // Fill the core event details required for creation.
    await organizerGroupPage.locator("#name").fill(eventName);
    await organizerGroupPage.locator("#kind_id").selectOption("virtual");
    await organizerGroupPage
      .locator("#category_id")
      .selectOption("33333333-3333-3333-3333-333333333331");
    await organizerGroupPage
      .locator("#description_short")
      .fill("A dashboard-created event for cancellation coverage.");
    await fillMarkdownEditor(
      organizerGroupPage,
      "description",
      "A dashboard event created and canceled by the e2e suite.",
    );

    // Configure a meeting-safe capacity before automatic meeting selection.
    if (E2E_MEETINGS_ENABLED) {
      await setAutomaticMeetingCapacity(organizerGroupPage);
    }

    // Fill schedule and online meeting details.
    await organizerGroupPage.locator("button[data-section-next]").click();
    await expect(
      organizerGroupPage.locator('button[data-section="date-venue"]'),
    ).toHaveAttribute("data-active", "true");
    await selectTimezone(organizerGroupPage, "UTC");
    await expect(organizerGroupPage.locator("#starts_at")).toBeVisible();
    await organizerGroupPage.locator("#starts_at").fill("2030-05-12T10:00");
    await organizerGroupPage.locator("#ends_at").fill("2030-05-12T12:00");
    if (E2E_MEETINGS_ENABLED) {
      await enableAutomaticMeetingCreation(organizerGroupPage);
    } else {
      await organizerGroupPage
        .locator("#meeting_join_url")
        .fill("https://meet.example.com/e2e-canceled-event");
    }

    // Target the visible submit button after pending changes appear.
    const visibleAddEventButton = organizerGroupPage.locator(
      "#pending-changes-alert:not(.hidden) #add-event-button",
    );
    await expect(
      organizerGroupPage.locator("#pending-changes-alert"),
    ).not.toHaveClass(/hidden/);
    await expect(visibleAddEventButton).toBeVisible();

    // Create the event and wait for the POST response.
    await waitForActionResponse(
      organizerGroupPage,
      () => visibleAddEventButton.click(),
      {
        method: "POST",
        urlIncludes: "/dashboard/group/events/add",
        status: 201,
      },
    );

    // Verify the temporary event appears in the events list.
    const eventRow = dashboardContent.locator("tr", { hasText: eventName });
    await expect(eventRow).toBeVisible();

    // Open the actions menu and cancel the temporary event.
    await eventRow.locator(".btn-actions").click();
    const cancelButton = eventRow.locator('button[id^="cancel-event-"]');
    await expect(cancelButton).toBeVisible();
    await cancelButton.click();
    await expect(organizerGroupPage.locator(".swal2-popup")).toContainText(
      "Cancel this event? This cannot be undone. All attendees will have their attendance canceled and eligible ticket purchases will be refunded automatically.",
    );

    // Confirm cancellation and wait for the server response.
    await Promise.all([
      organizerGroupPage.waitForResponse(
        (response) =>
          response.request().method() === "PUT" &&
          response.url().includes("/dashboard/group/events/") &&
          response.url().includes("/cancel") &&
          response.ok(),
      ),
      organizerGroupPage.getByRole("button", { name: "Yes" }).click(),
    ]);

    // Open past events after cancellation moves the event out of the upcoming list.
    await waitForActionResponse(
      organizerGroupPage,
      () =>
        dashboardContent.getByRole("button", { name: "Past events" }).click(),
      {
        method: "GET",
        urlIncludes: "/dashboard/group/events?events_tab=past",
      },
    );

    // Verify the row reflects canceled state and no longer offers cancellation.
    await expect(eventRow).toBeVisible();
    await expect(eventRow).toContainText("Canceled");
    await expect(eventRow.locator('button[id^="cancel-event-"]')).toHaveCount(
      0,
    );
    const eventActionsButton = eventRow.locator(".btn-actions");
    const eventActionsDropdown = eventRow.locator(
      "[data-event-actions-dropdown]",
    );
    await eventActionsButton.click();
    await expect(eventActionsDropdown).toBeVisible();

    // Delete the temporary canceled event to keep the list reusable.
    const deleteButton = eventRow.locator('button[id^="delete-event-"]');
    await expect(deleteButton).toBeVisible();
    await deleteButton.click();
    await expect(organizerGroupPage.locator(".swal2-popup")).toContainText(
      "Delete this event? This removes it from the dashboard and cannot be undone.",
    );

    // Confirm deletion and wait for the server response.
    await Promise.all([
      organizerGroupPage.waitForResponse(
        (response) =>
          response.request().method() === "DELETE" &&
          response.url().includes("/dashboard/group/events/") &&
          response.url().includes("/delete") &&
          response.ok(),
      ),
      organizerGroupPage.getByRole("button", { name: "Yes" }).click(),
    ]);

    // Verify the deleted event is removed from the list.
    await expect(
      dashboardContent.locator("tr", { hasText: eventName }),
    ).toHaveCount(0);
  });

  test("organizer can unpublish and publish an event from the list", async ({
    organizerGroupPage,
  }) => {
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
    const actionsButton = eventRow.locator(
      `.btn-actions[data-event-id="${TEST_EVENT_IDS.alpha.one}"]`,
    );
    await actionsButton.click();

    // Target the unpublish action after opening the menu.
    const unpublishButton = organizerGroupPage.locator(
      `#unpublish-event-${TEST_EVENT_IDS.alpha.one}`,
    );
    await expect(unpublishButton).toBeVisible();

    // Confirm unpublish and wait for the server response.
    await Promise.all([
      organizerGroupPage.waitForResponse(
        (response) =>
          response.request().method() === "PUT" &&
          response
            .url()
            .includes(
              `/dashboard/group/events/${TEST_EVENT_IDS.alpha.one}/unpublish`,
            ) &&
          response.ok(),
      ),
      unpublishButton.click(),
      organizerGroupPage.getByRole("button", { name: "Yes" }).click(),
    ]);

    // Verify the event row reflects draft state.
    await expect(eventRow).toContainText("Draft");

    // Publish the seeded event again to restore the original state.
    await eventRow
      .locator(`.btn-actions[data-event-id="${TEST_EVENT_IDS.alpha.one}"]`)
      .click();

    // Target the publish action after opening the menu.
    const publishButton = organizerGroupPage.locator(
      `#publish-event-${TEST_EVENT_IDS.alpha.one}`,
    );
    await expect(publishButton).toBeVisible();

    // Confirm publish and wait for the server response.
    await Promise.all([
      organizerGroupPage.waitForResponse(
        (response) =>
          response.request().method() === "PUT" &&
          response
            .url()
            .includes(
              `/dashboard/group/events/${TEST_EVENT_IDS.alpha.one}/publish`,
            ) &&
          response.ok(),
      ),
      publishButton.click(),
      organizerGroupPage.getByRole("button", { name: "Yes" }).click(),
    ]);

    // Verify the event row returns to published state.
    await expect(eventRow).toContainText("Published");
  });
});
