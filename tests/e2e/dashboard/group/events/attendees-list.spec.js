import { expect, test } from "../../../fixtures.js";
import { readFile } from "node:fs/promises";
import { queryE2eDatabase } from "../../../database.js";
import { setupOwnedTicketedAttendee } from "../../../data-graphs/attendance.js";
import { cleanupEventsByIds, setupApprovalRequiredEvent } from "../../../data-graphs/events.js";
import {
  TEST_EVENT_CANCELLATION,
  TEST_EVENT_IDS,
  TEST_EVENT_NAMES,
  TEST_GROUP_IDS,
  TEST_INVITATION_CANCELLATION,
  TEST_USER_IDS,
} from "../../../seed.js";
import {
  confirmAlert,
  dismissAlert,
  expectCurrentPaginationNavigation,
  navigateToPath,
  uniqueName,
  waitForActionResponse,
} from "../../../utils.js";
import { installFakeQrScanner } from "../check-in/helpers.js";
import { getVisibleStatusBadge, openAttendeesTab } from "./attendees-helpers.js";
import { expectUserColumnHasRoom } from "./user-profile-modal-helpers.js";

const EVENT_CANCELLATION_CONFIRMED_USER_ID = TEST_USER_IDS.admin1;

const FRESH_CANCELLATION_USER_ID = TEST_USER_IDS.empty;

test.describe("group dashboard attendees tab", () => {
  test("organizer scans and refreshes attendees from a published current event", async ({
    organizerGroupPage,
  }) => {
    // Replace the browser scanner with a deterministic camera implementation.
    await installFakeQrScanner(organizerGroupPage);

    // Return a deterministic successful scan without mutating seeded attendee state.
    await organizerGroupPage.route(
      `**/dashboard/group/events/${TEST_EVENT_IDS.alpha.one}/check-ins/scan`,
      (route) =>
        route.fulfill({
          body: JSON.stringify({
            attendee: { name: "E2E Scanned Attendee" },
            outcome: "checked-in",
            ticket_title: "General admission",
          }),
          contentType: "application/json",
          status: 200,
        }),
    );

    // Open the published event's attendees tab and launch its scanner.
    const attendeesContent = await openAttendeesTab(
      organizerGroupPage,
      TEST_EVENT_NAMES.alpha[0],
      TEST_EVENT_IDS.alpha.one,
    );
    const scannerButton = attendeesContent.getByRole("button", {
      name: "Scan Attendee Codes",
    });
    await expect(scannerButton).toBeEnabled();
    await scannerButton.click();

    // Verify the shared scanner opens with the selected event.
    const scannerModal = attendeesContent.locator("#group-check-in-scanner-modal");
    await expect(scannerModal).toBeVisible();
    await expect(scannerModal.getByText(TEST_EVENT_NAMES.alpha[0], { exact: true })).toBeVisible();
    await expect(scannerModal.getByText("Hold an attendee QR code inside the frame.")).toBeVisible();

    // Submit a successful credential through the simulated camera.
    await waitForActionResponse(
      organizerGroupPage,
      () =>
        organizerGroupPage.evaluate(
          (eventId) =>
            window.__OCG_E2E_QR_SCANNER__.last.onDecode({
              data: `ocg-check-in:v1:${eventId}:e2e-scanner-credential`,
            }),
          TEST_EVENT_IDS.alpha.one,
        ),
      {
        method: "POST",
        pathname: `/dashboard/group/events/${TEST_EVENT_IDS.alpha.one}/check-ins/scan`,
        status: 200,
      },
    );
    await expect(scannerModal.getByText("Checked in", { exact: true })).toBeVisible();

    // Closing the scanner refreshes the attendees region once.
    await waitForActionResponse(
      organizerGroupPage,
      () => scannerModal.getByRole("button", { name: "Close", exact: true }).click(),
      {
        method: "GET",
        pathname: `/dashboard/group/events/${TEST_EVENT_IDS.alpha.one}/attendees`,
        status: 200,
      },
    );
    await expect(scannerModal).toBeHidden();
    await expect(attendeesContent.getByRole("button", { name: "Scan Attendee Codes" })).toBeEnabled();
  });

  test("check-in manager launches the desktop scanner without event write access", async ({
    checkInManagerGroupPage,
  }) => {
    // Open the published event's attendees tab with check-in-only permissions.
    const attendeesContent = await openAttendeesTab(
      checkInManagerGroupPage,
      TEST_EVENT_NAMES.alpha[0],
      TEST_EVENT_IDS.alpha.one,
    );

    // Verify the desktop scan action stays discoverable for this role.
    const scannerButton = attendeesContent.getByRole("button", {
      name: "Scan Attendee Codes",
    });
    await expect(scannerButton).toBeVisible();
    await expect(scannerButton).toBeEnabled();
    await scannerButton.click();

    // Verify the shared scanner opens for the selected event.
    const scannerModal = attendeesContent.locator("#group-check-in-scanner-modal");
    await expect(scannerModal).toBeVisible();
    await expect(scannerModal.getByText(TEST_EVENT_NAMES.alpha[0], { exact: true })).toBeVisible();
    await scannerModal.getByRole("button", { name: "Close", exact: true }).click();
    await expect(scannerModal).toBeHidden();
  });

  test("organizer can move between attendee result pages", async ({ organizerGroupPage }) => {
    // Open seeded attendees with one result per page.
    await openAttendeesTab(
      organizerGroupPage,
      "Upcoming In-Person Event",
      TEST_EVENT_IDS.alpha.one,
      "?limit=1&offset=0",
    );

    // Verify pagination swaps attendee rows in both directions.
    await expectCurrentPaginationNavigation(organizerGroupPage, "#attendees-content tbody tr");
  });

  test("pre-canceled event preserves attendee history and clears check-in", async ({
    organizerGroupPage,
  }) => {
    // Pin the retained history state without exercising the cancellation endpoint.
    prepareCanceledEventHistoryFixture();

    try {
      // Open retained attendee history after the pre-canceled state is prepared.
      const attendeesContent = await openAttendeesTab(
        organizerGroupPage,
        TEST_EVENT_CANCELLATION.name,
        TEST_EVENT_CANCELLATION.id,
        "?status=history",
      );
      const canceledAttendeeRow = attendeesContent.locator("tr", {
        hasText: "E2E Admin One",
      });
      const canceledOfferRow = attendeesContent.locator("tr", {
        hasText: "E2E Admin Two",
      });

      // Verify canceled attendance history is retained and check-in is cleared.
      await expect(getVisibleStatusBadge(canceledAttendeeRow, "Attendance canceled")).toBeVisible();
      await expect(canceledAttendeeRow.locator(".check-in-toggle")).not.toBeChecked();
      await expect(canceledAttendeeRow.locator(".check-in-toggle")).toBeDisabled();
      await expect(getVisibleStatusBadge(canceledOfferRow, "Offer canceled")).toBeVisible();
    } finally {
      // Restore the canceled event history fixture.
      restoreCanceledEventHistoryFixture();
    }
  });

  test("organizer cancels a fresh owned attendee and retains history", async ({
    notifications,
    organizerGroupPage,
    owned,
  }) => {
    // Create an owned attendee row that is independent of shared seed enrollments.
    owned.attendee({
      checkedIn: true,
      eventId: TEST_EVENT_IDS.alpha.one,
      userId: FRESH_CANCELLATION_USER_ID,
    });

    // Open the active attendee row before canceling it through the organizer action.
    const attendeesContent = await openAttendeesTab(
      organizerGroupPage,
      TEST_EVENT_NAMES.alpha[0],
      TEST_EVENT_IDS.alpha.one,
    );
    const attendeeRow = attendeesContent.locator("tr", {
      hasText: "E2E Empty User",
    });
    const rowActionsMenu = attendeeRow.locator("[data-actions-menu]");
    await expect(attendeeRow).toBeVisible();
    await expect(attendeeRow.locator(".check-in-toggle")).toBeChecked();
    await rowActionsMenu.locator("summary").click();
    await rowActionsMenu.getByRole("menuitem", { name: "Cancel attendance" }).click();

    // Confirm cancellation and require the exact success status.
    await waitForActionResponse(
      organizerGroupPage,
      () => confirmAlert(organizerGroupPage, { message: "Are you sure you want to cancel this attendance?" }),
      {
        method: "DELETE",
        status: 204,
        urlIncludes: `/dashboard/group/events/${TEST_EVENT_IDS.alpha.one}/attendees/${FRESH_CANCELLATION_USER_ID}`,
        urlEndsWith: "/attendance",
      },
    );
    notifications.expectNew([{ kind: "event-attendance-canceled", userIds: [FRESH_CANCELLATION_USER_ID] }]);
    await dismissAlert(organizerGroupPage, { message: "Attendance canceled." });

    // Verify the canceled attendee remains in history with check-in cleared.
    const historyContent = await openAttendeesTab(
      organizerGroupPage,
      TEST_EVENT_NAMES.alpha[0],
      TEST_EVENT_IDS.alpha.one,
      "?status=history",
    );
    const historyRow = historyContent.locator("tr", {
      hasText: "E2E Empty User",
    });
    await expect(getVisibleStatusBadge(historyRow, "Attendance canceled")).toBeVisible();
    await expect(historyRow.locator(".check-in-toggle")).not.toBeChecked();
    await expect(historyRow.locator(".check-in-toggle")).toBeDisabled();
    expect(
      queryE2eDatabase(`
        select status || '|' || checked_in::text
        from event_attendee
        where event_id = '${TEST_EVENT_IDS.alpha.one}'
        and user_id = '${FRESH_CANCELLATION_USER_ID}';
      `),
    ).toBe("attendance-canceled|false");
  });

  test("canceled invitations remain visible in attendee history", async ({ organizerGroupPage }) => {
    // Open the pre-canceled event and inspect its retained invitation.
    const attendeesContent = await openAttendeesTab(
      organizerGroupPage,
      TEST_INVITATION_CANCELLATION.name,
      TEST_INVITATION_CANCELLATION.id,
    );
    const canceledInvitationRow = attendeesContent.locator("tr", {
      hasText: "E2E Admin Two",
    });

    // Verify canceled invitations remain discoverable with explicit status.
    await expect(canceledInvitationRow).toBeVisible();
    await expect(canceledInvitationRow).toContainText("Invitation canceled");
  });

  test("viewer sees read-only attendee controls on the attendees tab", async ({ groupViewerPage }) => {
    // Load the group events dashboard as a read-only viewer.
    await navigateToPath(groupViewerPage, "/dashboard/group?tab=events");

    // Target the seeded event used for attendee permission checks.
    const eventRow = groupViewerPage.locator("tr", {
      hasText: "Full Event With Waitlist",
    });
    await expect(eventRow).toBeVisible();

    // Open the event update form before switching to attendees.
    await waitForActionResponse(
      groupViewerPage,
      () => eventRow.locator('td button[aria-label="Edit event: Full Event With Waitlist"]').click(),
      {
        method: "GET",
        urlIncludes: `/dashboard/group/events/${TEST_EVENT_IDS.alpha.waitlistLab}/update`,
      },
    );

    // Load the attendees tab for the seeded event.
    await waitForActionResponse(
      groupViewerPage,
      () => groupViewerPage.locator('button[data-section="attendees"]').click(),
      {
        method: "GET",
        urlIncludes: `/dashboard/group/events/${TEST_EVENT_IDS.alpha.waitlistLab}/attendees`,
      },
    );

    // Target the attendee row and verify controls remain read-only.
    const attendeesContent = groupViewerPage.locator("#attendees-content");
    const attendeeRow = attendeesContent.locator("tr", {
      hasText: "E2E Organizer One",
    });

    // Assert that Attendees list is visible.
    const attendeesTable = attendeesContent.getByRole("table", {
      name: "Attendees list",
    });
    await expect(attendeesTable).toBeVisible();
    await expectUserColumnHasRoom(attendeesTable, "Attendee");
    await expect(attendeeRow).toBeVisible();
    await expect(attendeesContent.locator("#attendee-email-actions-button")).toBeHidden();
    await expect(attendeeRow.locator(".check-in-toggle")).toBeDisabled();
  });

  test("organizer sees the empty state on the attendees tab for an event without RSVPs", async ({
    organizerGroupPage,
    owned,
  }) => {
    // Create a temporary event without attendees.
    const { eventId, name: eventName } = owned.track(
      setupApprovalRequiredEvent({
        groupId: TEST_GROUP_IDS.community1.alpha,
        name: uniqueName("Empty Attendees"),
      }),
      (event) => cleanupEventsByIds([event.eventId]),
    );

    // Load the attendees tab for the temporary event.
    const attendeesContent = await openAttendeesTab(organizerGroupPage, eventName, eventId);

    // Assert that Attendees list is visible.
    await expect(attendeesContent.getByRole("table", { name: "Attendees list" })).toBeVisible();
    await expect(attendeesContent).toContainText("No attendees found for this event.");
    await expect(attendeesContent.getByRole("button", { name: "Send email" })).toBeDisabled();
    await expect(attendeesContent.getByRole("button", { name: "Send email" })).toHaveAttribute(
      "title",
      "No attendees with verified email addresses who accept messages from event organizers.",
    );
  });

  test("organizer can search attendees and clear the filter", async ({ organizerGroupPage }) => {
    // Load the attendees tab for the seeded event.
    const attendeesContent = await openAttendeesTab(
      organizerGroupPage,
      "Upcoming In-Person Event",
      TEST_EVENT_IDS.alpha.one,
    );

    // Target the search controls used to submit attendee filters.
    const searchInput = attendeesContent.getByRole("textbox", {
      name: "Search attendees",
    });

    // Enter a query expected to match a seeded attendee.
    await searchInput.fill("member");

    // Submit the matching search and wait for filtered results.
    await waitForActionResponse(organizerGroupPage, () => searchInput.press("Enter"), {
      method: "GET",
      params: { ts_query: "member" },
      pathname: `/dashboard/group/events/${TEST_EVENT_IDS.alpha.one}/attendees`,
      status: 200,
    });

    // Verify the matching result is shown and non-matching attendees are hidden.
    await expect(attendeesContent.locator("tr", { hasText: "E2E Member One" })).toBeVisible();
    await expect(attendeesContent.locator("tr", { hasText: "E2E Organizer One" })).toHaveCount(0);
    await expect(searchInput).toHaveValue("member");

    // Enter a query expected to return no attendees.
    await searchInput.fill("");
    await searchInput.fill("zzzzzzzzzzzz");

    // Submit the empty-result search and wait for the empty state.
    await waitForActionResponse(organizerGroupPage, () => searchInput.press("Enter"), {
      method: "GET",
      params: { ts_query: "zzzzzzzzzzzz" },
      pathname: `/dashboard/group/events/${TEST_EVENT_IDS.alpha.one}/attendees`,
      status: 200,
    });

    const noResultsMessage = attendeesContent
      .locator("div.text-xl.lg\\:text-2xl.mb-4:visible")
      .filter({ hasText: "No attendees found matching your filters." });

    // Verify the filtered empty result message is shown.
    await expect(noResultsMessage.first()).toBeVisible();

    // Clear the attendee search filter.
    await attendeesContent.getByRole("button", { name: "Clear attendee search" }).click();

    // Verify clearing removes the empty state and restores seeded attendees.
    await expect(noResultsMessage).toHaveCount(0);
    await expect(attendeesContent.locator("tr", { hasText: "E2E Member One" })).toBeVisible();
    await expect(attendeesContent.locator("tr", { hasText: "E2E Organizer One" })).toBeVisible();
    await expect(searchInput).toHaveValue("");

    // Sort attendees by name.
    await waitForActionResponse(
      organizerGroupPage,
      () => attendeesContent.getByLabel("Sort by").selectOption("name-desc"),
      {
        method: "GET",
        params: { sort: "name-desc" },
        pathname: `/dashboard/group/events/${TEST_EVENT_IDS.alpha.one}/attendees`,
        status: 200,
      },
    );

    // Verify the sorted table keeps both seeded attendees visible.
    await expect(attendeesContent.locator("tr", { hasText: "E2E Member One" })).toBeVisible();
    await expect(attendeesContent.locator("tr", { hasText: "E2E Organizer One" })).toBeVisible();
  });

  test("organizer retains focus while filtering enrollment status", async ({ organizerGroupPage }) => {
    // Load the attendees tab for the seeded event.
    const attendeesContent = await openAttendeesTab(
      organizerGroupPage,
      "Upcoming In-Person Event",
      TEST_EVENT_IDS.alpha.one,
    );
    const statusFilter = attendeesContent.getByLabel("Status", {
      exact: true,
    });

    // Select enrollment history and verify the replacement control keeps focus.
    await statusFilter.focus();
    await waitForActionResponse(organizerGroupPage, () => statusFilter.selectOption("history"), {
      method: "GET",
      params: { status: "history" },
      pathname: `/dashboard/group/events/${TEST_EVENT_IDS.alpha.one}/attendees`,
      status: 200,
    });
    await expect(statusFilter).toBeFocused();
    await expect(statusFilter).toHaveValue("history");

    // Return to current enrollments and preserve the same focus contract.
    await waitForActionResponse(organizerGroupPage, () => statusFilter.selectOption("current"), {
      method: "GET",
      params: { status: "current" },
      pathname: `/dashboard/group/events/${TEST_EVENT_IDS.alpha.one}/attendees`,
      status: 200,
    });
    await expect(statusFilter).toBeFocused();
    await expect(statusFilter).toHaveValue("current");
  });

  test("organizer combines ticket type and check-in filters through the browser form", async ({
    organizerGroupPage,
    owned,
  }) => {
    // Create a two-tier event with VIP and general ticket holders in both check-in states.
    const event = owned.event({
      groupId: TEST_GROUP_IDS.community1.alpha,
      tiers: [
        { key: "general", seats: 10, title: "General admission" },
        { key: "vip", seats: 10, title: "VIP" },
      ],
    });
    const attendeesPath = `/dashboard/group/events/${event.eventId}/attendees`;
    const vipTicketTypeId = event.ticketTypeIds.vip;
    setupOwnedTicketedAttendee({
      checkedIn: true,
      eventId: event.eventId,
      ticketTypeId: vipTicketTypeId,
      userId: TEST_USER_IDS.member1,
    });
    setupOwnedTicketedAttendee({
      eventId: event.eventId,
      ticketTypeId: vipTicketTypeId,
      userId: TEST_USER_IDS.member2,
    });
    setupOwnedTicketedAttendee({
      checkedIn: true,
      eventId: event.eventId,
      ticketTypeId: event.ticketTypeIds.general,
      userId: TEST_USER_IDS.member3,
    });

    // Load the attendees tab with every ticket holder listed.
    const attendeesContent = await openAttendeesTab(organizerGroupPage, event.name, event.eventId);
    const vipCheckedInRow = attendeesContent.locator("tr", { hasText: "E2E Member One" });
    const vipPendingRow = attendeesContent.locator("tr", { hasText: "E2E Member Two" });
    const generalCheckedInRow = attendeesContent.locator("tr", { hasText: "E2E Member Three" });
    const activeFilters = attendeesContent.getByText("Active filters", { exact: true }).locator("xpath=..");
    // The closed filter menu hides its checkboxes from the accessibility tree.
    const vipFilterCheckbox = attendeesContent.locator(
      `#attendees-ticket-filter input[name="event_ticket_type_ids[]"][value="${vipTicketTypeId}"]`,
    );
    await expect(vipCheckedInRow).toContainText("VIP");
    await expect(vipPendingRow).toContainText("VIP");
    await expect(generalCheckedInRow).toContainText("General admission");
    await expect(activeFilters).toHaveCount(0);

    // Select the VIP tier in the ticket type filter menu. Click instead of check: the change swaps
    // the table and closes the menu, so check() could not find the checkbox to verify its state.
    await attendeesContent.getByLabel("Ticket type filters", { exact: true }).click();
    await waitForActionResponse(
      organizerGroupPage,
      () =>
        attendeesContent
          .locator("#attendees-ticket-filter")
          .getByRole("checkbox", { exact: true, name: "VIP" })
          .click(),
      {
        method: "GET",
        params: { "event_ticket_type_ids[]": vipTicketTypeId },
        pathname: attendeesPath,
        status: 200,
      },
    );

    // Verify only VIP holders remain and the ticket type chip is shown.
    await expect(vipCheckedInRow).toBeVisible();
    await expect(vipPendingRow).toBeVisible();
    await expect(generalCheckedInRow).toHaveCount(0);
    await expect(vipFilterCheckbox).toBeChecked();
    await expect(activeFilters.locator(".custom-badge")).toHaveText(["Ticket type: Selected"]);

    // Add the checked-in filter while keeping the selected tier.
    await attendeesContent.getByLabel("Checked In filters", { exact: true }).click();
    await waitForActionResponse(
      organizerGroupPage,
      () =>
        attendeesContent
          .locator("#attendees-check-in-filter")
          .getByRole("button", { name: "Checked in", exact: true })
          .click(),
      {
        method: "GET",
        params: { checked_in: "true", "event_ticket_type_ids[]": vipTicketTypeId },
        pathname: attendeesPath,
        status: 200,
      },
    );

    // Verify both chips and the checked-in VIP holder.
    await expect(vipCheckedInRow).toBeVisible();
    await expect(vipPendingRow).toHaveCount(0);
    await expect(generalCheckedInRow).toHaveCount(0);
    await expect(activeFilters.locator(".custom-badge")).toHaveText([
      "Checked In: Yes",
      "Ticket type: Selected",
    ]);

    // Remove the ticket type chip and keep the check-in filter.
    await waitForActionResponse(
      organizerGroupPage,
      () => activeFilters.getByRole("button", { name: "Remove ticket type filter" }).click(),
      {
        method: "GET",
        params: { checked_in: "true", "event_ticket_type_ids[]": null },
        pathname: attendeesPath,
        status: 200,
      },
    );

    // Verify checked-in holders of every tier are listed under the remaining chip.
    await expect(vipCheckedInRow).toBeVisible();
    await expect(generalCheckedInRow).toBeVisible();
    await expect(vipPendingRow).toHaveCount(0);
    await expect(vipFilterCheckbox).not.toBeChecked();
    await expect(activeFilters.locator(".custom-badge")).toHaveText(["Checked In: Yes"]);

    // Reset all filters.
    await waitForActionResponse(
      organizerGroupPage,
      () => activeFilters.getByRole("button", { name: "Reset all" }).click(),
      {
        method: "GET",
        params: { checked_in: null, "event_ticket_type_ids[]": null },
        pathname: attendeesPath,
        status: 200,
      },
    );

    // Verify every ticket holder is listed again without active filters.
    await expect(vipCheckedInRow).toBeVisible();
    await expect(vipPendingRow).toBeVisible();
    await expect(generalCheckedInRow).toBeVisible();
    await expect(activeFilters).toHaveCount(0);
  });

  test("organizer can download attendees as CSV from the attendees tab", async ({ organizerGroupPage }) => {
    // Load the attendees tab for the seeded waitlist event.
    const attendeesContent = await openAttendeesTab(
      organizerGroupPage,
      "Full Event With Waitlist",
      TEST_EVENT_IDS.alpha.waitlistLab,
    );

    // Open attendee actions before selecting the CSV download.
    const actionsButton = attendeesContent.getByRole("button", {
      name: "Open attendee actions menu",
    });
    await expect(actionsButton).toBeVisible();
    await actionsButton.click();

    // Find the Download CSV control.
    const downloadCsvLink = attendeesContent.getByRole("menuitem", {
      name: "Download CSV",
    });
    await expect(downloadCsvLink).toBeVisible();
    await expect(downloadCsvLink).toHaveAttribute(
      "href",
      `/dashboard/group/events/${TEST_EVENT_IDS.alpha.waitlistLab}/attendees.csv`,
    );

    // Download the CSV and verify the seeded attendee row.
    const [download] = await Promise.all([
      organizerGroupPage.waitForEvent("download"),
      downloadCsvLink.click(),
    ]);
    const downloadPath = await download.path();

    // Fail clearly if the CSV download was not captured.
    if (!downloadPath) {
      throw new Error("Expected attendee CSV download to have a local file path.");
    }

    // Assert the downloaded filename.
    expect(download.suggestedFilename()).toBe("event-alpha-waitlist-lab-attendees.csv");
    const csvContents = await readFile(downloadPath, "utf8");
    expect(csvContents).toMatch(
      new RegExp(
        "Name,Company,Title,Invited,Enrollment date,Payment method,Amount,Payment deadline,Paid at,Marked by,Payment details\\n" +
          "E2E Organizer One,,,No,\\d{4}-\\d{2}-\\d{2} \\d{2}:\\d{2} UTC,Free,Free,,,,\\n",
      ),
    );
  });
});

/** Prepares event, attendee, and offer rows for canceled event history. */
const prepareCanceledEventHistoryFixture = () => {
  queryE2eDatabase(`
    update event
    set canceled = true
    where event_id = '${TEST_EVENT_CANCELLATION.id}';

    update event_attendee
    set
      attendance_canceled_at = current_timestamp,
      attendance_canceled_by_user_id = '${TEST_USER_IDS.organizer1}',
      checked_in = false,
      checked_in_at = null,
      status = 'attendance-canceled'
    where event_id = '${TEST_EVENT_CANCELLATION.id}'
    and user_id = '${EVENT_CANCELLATION_CONFIRMED_USER_ID}';

    update admission_offer
    set status = 'canceled', updated_at = current_timestamp
    where event_id = '${TEST_EVENT_CANCELLATION.id}'
    and status in ('checkout_pending', 'pending');
  `);
};

/** Restores event, attendee, and offer rows for canceled event history. */
const restoreCanceledEventHistoryFixture = () => {
  queryE2eDatabase(`
    update event
    set canceled = false
    where event_id = '${TEST_EVENT_CANCELLATION.id}';

    update event_attendee
    set
      attendance_canceled_at = null,
      attendance_canceled_by_user_id = null,
      checked_in = true,
      checked_in_at = current_timestamp - interval '1 hour',
      status = 'confirmed'
    where event_id = '${TEST_EVENT_CANCELLATION.id}'
    and user_id = '${EVENT_CANCELLATION_CONFIRMED_USER_ID}';

    delete from admission_offer
    where event_id = '${TEST_EVENT_CANCELLATION.id}'
    and user_id in (
      '${TEST_USER_IDS.admin2}',
      '${TEST_USER_IDS.organizer2}'
    );

    insert into admission_offer (
      event_id,
      event_ticket_type_id,
      expires_at,
      source,
      status,
      user_id
    ) values (
      '${TEST_EVENT_CANCELLATION.id}',
      (select event_ticket_type_id from event_ticket_type where event_id = '${TEST_EVENT_CANCELLATION.id}' order by "order" limit 1),
      '2099-12-31 00:00:00+00',
      'organizer_invitation',
      'pending',
      '${TEST_USER_IDS.admin2}'
    ), (
      '${TEST_EVENT_CANCELLATION.id}',
      (select event_ticket_type_id from event_ticket_type where event_id = '${TEST_EVENT_CANCELLATION.id}' order by "order" limit 1),
      '2099-12-31 00:00:00+00',
      'waitlist',
      'pending',
      '${TEST_USER_IDS.organizer2}'
    );
  `);
};
