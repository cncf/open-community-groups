import { expect, test } from "../../../fixtures.js";
import { queryE2eDatabase } from "../../../database.js";
import {
  deleteNotifications,
  expectNewNotifications,
  snapshotNotifications,
} from "../../../notifications.js";
import {
  TEST_COMMUNITY_NAME,
  TEST_GROUP_SLUGS,
  TEST_REGISTRATION_WINDOW_EVENTS,
  TEST_TICKETING_EVENTS,
  TEST_USER_IDS,
} from "../../../seed.js";
import { getAttendButton, waitForAttendanceState } from "../../../site/event/helpers.js";
import {
  buildE2eUrl,
  expectCurrentPaginationNavigation,
  navigateToEvent,
  navigateToPath,
  routeNextRequestWithQuery,
  uniqueName,
  waitForActionResponse,
} from "../../../utils.js";
import { getVisibleStatusBadge, openAttendeesTab, openInvitationRequestsTab } from "./attendees-helpers.js";
import {
  createApprovalRequiredEvent,
  deleteEventFromList,
  openCurrentEventEditorSection,
} from "./helpers.js";
import { expectUserColumnHasRoom, expectUserProfileModalFromRow } from "./user-profile-modal-helpers.js";

const CLOSED_APPROVAL_OFFER_ID = "59555555-5555-5555-5555-555555555905";

test.describe("group dashboard attendees tab — invitations", () => {
  test("organizer can invite and cancel an attendee invitation", async ({ organizerGroupPage }) => {
    // Give the invite and cancel flow enough time on slower deep runs.
    test.setTimeout(60_000);

    // Create a temporary event for the invitation lifecycle.
    const eventName = uniqueName("attendee invitation");
    const { eventId } = await createApprovalRequiredEvent(organizerGroupPage, eventName);
    let notificationIds = [];

    try {
      // Load the attendees tab for the temporary event.
      const attendeesContent = await openCurrentEventEditorSection(
        organizerGroupPage,
        eventId,
        "attendees",
        "#attendees-content",
        { tableName: "Attendees list" },
      );

      // Open the manual invitation modal for an event without RSVPs.
      const actionsButton = attendeesContent.getByRole("button", {
        name: "Open attendee actions menu",
      });
      await expect(actionsButton).toBeVisible();
      await actionsButton.click();

      // Open the invitation action for the attendee modal.
      const inviteAttendeeButton = attendeesContent.getByRole("menuitem", {
        name: "Invite attendee",
      });
      await expect(inviteAttendeeButton).toBeVisible();
      await inviteAttendeeButton.click();

      // Find the modal.
      const modal = organizerGroupPage.locator("#attendee-invitation-modal");
      const searchField = modal.locator("user-search-field[data-attendee-invitation-search]");
      const searchInput = searchField.locator("#attendee-invitation-search-input");
      const ticketTypeSelect = modal.getByLabel("Ticket type");

      // Assert the expected content is visible.
      await expect(modal).toBeVisible();
      await expect(modal.getByRole("heading", { name: "Invite attendee" })).toBeVisible();
      await expect(ticketTypeSelect).toBeVisible();
      await expect(ticketTypeSelect).toHaveValue(/.+/);
      await expect(modal.locator("#submit-attendee-invitation")).toBeDisabled();

      // Keep invalid free-form input from enabling the invitation form.
      await searchInput.fill("not-an-email");
      await expect(modal.locator("#submit-attendee-invitation")).toBeDisabled();

      // Select a seeded user and submit the invitation.
      await searchInput.fill("e2e-pending-2");
      await expect(searchField.getByText("E2E Pending Two")).toBeVisible();
      await searchField.getByText("E2E Pending Two").click();
      await expect(modal.locator("#attendee-invitation-selected-user")).toContainText("E2E Pending Two");
      await expect(modal.locator("#submit-attendee-invitation")).toBeEnabled();

      // Submit and wait for the server response.
      const invitationSnapshot = snapshotNotifications();
      await waitForActionResponse(
        organizerGroupPage,
        () => modal.locator("#submit-attendee-invitation").click(),
        {
          method: "POST",
          urlIncludes: `/dashboard/group/events/${eventId}/attendees/invite`,
        },
      );
      notificationIds = expectNewNotifications(invitationSnapshot, [
        { kind: "event-admission-offer-created", userIds: [TEST_USER_IDS.pending2] },
      ]);
      deleteNotifications(notificationIds);
      notificationIds = [];

      // Assert that the content is hidden.
      await expect(modal).toBeHidden();
      await expect(organizerGroupPage.locator(".swal2-popup")).toContainText("Invitation sent.");

      // Verify the invitation appears in the attendees table.
      const attendeeRow = attendeesContent.locator("tr", {
        hasText: "E2E Pending Two",
      });
      await expect(attendeeRow).toBeVisible();
      await expect(getVisibleStatusBadge(attendeeRow, "Offer pending")).toBeVisible();

      // Cancel the temporary invitation and wait for the table to refresh.
      const rowActionsMenu = attendeeRow.locator("[data-actions-menu]");
      await rowActionsMenu.locator("summary").click();
      await rowActionsMenu.getByRole("menuitem", { name: "Cancel invitation" }).click();
      await expect(organizerGroupPage.getByRole("button", { name: "Yes" })).toBeVisible();

      // Click Yes.
      const cancellationSnapshot = snapshotNotifications();
      await waitForActionResponse(
        organizerGroupPage,
        () => organizerGroupPage.getByRole("button", { name: "Yes" }).click(),
        {
          method: "PUT",
          urlIncludes: "/dashboard/group/admission-offers/",
          urlEndsWith: "/cancel",
        },
      );
      deleteNotificationsSince(cancellationSnapshot, "event-admission-offer-canceled", [
        TEST_USER_IDS.pending2,
      ]);

      // Dismiss the success alert before opening enrollment history.
      await expect(organizerGroupPage.locator(".swal2-popup")).toContainText("Invitation canceled.");
      await organizerGroupPage.getByRole("button", { name: "OK" }).click();

      // Switch from current enrollments to history and find the canceled offer.
      const statusFilter = attendeesContent.getByLabel("Status", {
        exact: true,
      });
      await Promise.all([
        organizerGroupPage.waitForResponse(
          (response) =>
            response.request().method() === "GET" &&
            response.url().includes(`/dashboard/group/events/${eventId}/attendees`) &&
            response.url().includes("status=history") &&
            response.ok(),
        ),
        statusFilter.selectOption("history"),
      ]);

      // Canceled offers remain visible as enrollment history.
      await expect(getVisibleStatusBadge(attendeeRow, "Offer canceled")).toBeVisible();
    } finally {
      // Remove invitation notifications and the temporary event.
      deleteNotifications(notificationIds);
      await deleteEventFromList(organizerGroupPage, eventId);
    }
  });

  test("organizer can accept and reject attendee invitation requests", async ({
    organizerGroupPage,
    pending1Page,
    pending2Page,
  }) => {
    // Give the invitation request flow enough time on slower deep runs.
    test.setTimeout(120_000);

    // Create a temporary approval-required event.
    const eventName = uniqueName("invitation requests");
    const { eventId } = await createApprovalRequiredEvent(organizerGroupPage, eventName);
    let notificationIds = [];

    try {
      // Request invitations from two users. The attend endpoint expects a
      // form-encoded body, so send an empty form payload with each request.
      for (const requesterPage of [pending1Page, pending2Page]) {
        const requestResponse = await requesterPage.request.post(
          buildE2eUrl(`/${TEST_COMMUNITY_NAME}/event/${eventId}/attend`),
          { form: {} },
        );
        expect(requestResponse.ok()).toBeTruthy();
      }

      // Open the organizer Requests tab for the temporary event.
      await routeNextRequestWithQuery(
        organizerGroupPage,
        `/dashboard/group/events/${eventId}/invitation-requests`,
        "?limit=1&offset=0",
      );
      await waitForActionResponse(
        organizerGroupPage,
        () => organizerGroupPage.locator('button[data-section="invitation-requests"]').click(),
        {
          method: "GET",
          urlIncludes: `/dashboard/group/events/${eventId}/invitation-requests`,
        },
      );

      // Verify the requests table is ready for organizer review.
      const requestsContent = organizerGroupPage.locator("#invitation-requests-content");
      const invitationRequestsTable = requestsContent.getByRole("table", {
        name: "Invitation requests",
      });
      await expect(invitationRequestsTable).toBeVisible();
      await expectUserColumnHasRoom(invitationRequestsTable, "Requester");

      // Verify both request pages and restore the full list for filter coverage.
      await expectCurrentPaginationNavigation(organizerGroupPage, "#invitation-requests-content tbody tr");
      const searchForm = requestsContent.locator("#invitation-requests-search-form");
      const paginationLimit = searchForm.locator('input[name="limit"]');
      await paginationLimit.evaluate((input) => {
        input.value = "50";
      });
      await Promise.all([
        organizerGroupPage.waitForResponse(
          (response) =>
            response.request().method() === "GET" &&
            response.url().includes(`/dashboard/group/events/${eventId}/invitation-requests`) &&
            new URL(response.url()).searchParams.get("limit") === "50" &&
            response.ok(),
        ),
        searchForm.evaluate((form) => {
          if (form instanceof HTMLFormElement) {
            form.requestSubmit();
          }
        }),
      ]);

      // Target the search controls used to submit request filters.
      const searchInput = requestsContent.getByRole("textbox", {
        name: "Search invitation requests",
      });

      // Enter a query expected to match one seeded requester.
      await searchInput.fill("Two");

      // Submit the matching search and wait for filtered results.
      await searchForm.evaluate((form) => {
        if (form instanceof HTMLFormElement) {
          form.requestSubmit();
        }
      });

      // Verify the matching result is shown and non-matching requests are hidden.
      await expect(requestsContent.locator("tr", { hasText: "E2E Pending Two" })).toBeVisible();
      await expect(requestsContent.locator("tr", { hasText: "E2E Pending One" })).toHaveCount(0);
      await expect(searchInput).toHaveValue("Two");

      // Enter a query expected to return no requests.
      await searchInput.fill("");
      await searchInput.fill("zzzzzzzzzzzz");

      // Submit the empty-result search and wait for the empty state.
      await searchForm.evaluate((form) => {
        if (form instanceof HTMLFormElement) {
          form.requestSubmit();
        }
      });

      const noResultsMessage = requestsContent.locator("div.text-xl.lg\\:text-2xl.mb-4:visible").filter({
        hasText: "No invitation requests found matching your search.",
      });

      // Verify the filtered empty result message is shown.
      await expect(noResultsMessage.first()).toBeVisible();

      // Clear the invitation request search filter.
      await requestsContent.getByRole("button", { name: "Clear invitation request search" }).click();

      // Verify clearing removes the empty state and restores request rows.
      await expect(noResultsMessage).toHaveCount(0);
      await expect(requestsContent.locator("tr", { hasText: "E2E Pending One" })).toBeVisible();
      await expect(requestsContent.locator("tr", { hasText: "E2E Pending Two" })).toBeVisible();
      await expect(searchInput).toHaveValue("");

      // Sort requesters by name before applying a status filter.
      await Promise.all([
        organizerGroupPage.waitForResponse(
          (response) =>
            response.request().method() === "GET" &&
            response.url().includes(`/dashboard/group/events/${eventId}/invitation-requests`) &&
            response.url().includes("sort=name-desc") &&
            response.ok(),
        ),
        requestsContent.getByLabel("Sort by").selectOption("name-desc"),
      ]);

      // Verify the sorted request table keeps both pending requesters visible.
      await expect(requestsContent.locator("tr", { hasText: "E2E Pending One" })).toBeVisible();
      await expect(requestsContent.locator("tr", { hasText: "E2E Pending Two" })).toBeVisible();

      // Switch the table to all statuses while preserving the active sort.
      await requestsContent.getByLabel("Status filters").click();
      await Promise.all([
        organizerGroupPage.waitForResponse(
          (response) =>
            response.request().method() === "GET" &&
            response.url().includes(`/dashboard/group/events/${eventId}/invitation-requests`) &&
            response.url().includes("sort=name-desc") &&
            response.url().includes("status=all") &&
            response.ok(),
        ),
        requestsContent
          .locator("#invitation-requests-status-filter")
          .getByRole("button", { name: "All", exact: true })
          .click(),
      ]);

      // Verify resetting status removes the previous badge while keeping sort.
      await expect(requestsContent.getByText("Active filters")).toHaveCount(0);

      const pendingOneRow = requestsContent.locator("tr", {
        hasText: "E2E Pending One",
      });

      // Verify profile modals still open from rows after the filtered refresh.
      await expectUserProfileModalFromRow(
        organizerGroupPage,
        pendingOneRow,
        "View profile for E2E Pending One",
        "E2E Pending One",
        [
          "Community Applicant at Approval Queue",
          "Pending One profile for invitation request modal coverage.",
          "openprofile.dev",
        ],
      );

      // Reject one invitation request.
      await expect(pendingOneRow).toContainText("Pending");
      await pendingOneRow
        .getByRole("button", {
          name: "Open actions for E2E Pending One",
          exact: true,
        })
        .click();
      await pendingOneRow.getByRole("button", { name: "Reject", exact: true }).click();
      await expect(organizerGroupPage.locator(".swal2-popup")).toContainText(
        "Are you sure you want to reject this invitation request?",
      );
      await waitForActionResponse(
        organizerGroupPage,
        () => organizerGroupPage.getByRole("button", { name: "Yes" }).click(),
        {
          method: "PUT",
          urlIncludes: `/dashboard/group/events/${eventId}/attendees/${TEST_USER_IDS.pending1}/invitation-request/reject`,
        },
      );
      await expect(pendingOneRow).toContainText("Rejected");

      // Accept the other invitation request.
      const pendingTwoRow = requestsContent.locator("tr", {
        hasText: "E2E Pending Two",
      });
      await expect(pendingTwoRow).toContainText("Pending");
      await pendingTwoRow
        .getByRole("button", {
          name: "Open actions for E2E Pending Two",
          exact: true,
        })
        .click();
      const approvalSnapshot = snapshotNotifications();
      await waitForActionResponse(
        organizerGroupPage,
        () => pendingTwoRow.getByRole("button", { name: "Accept", exact: true }).click(),
        {
          method: "PUT",
          urlIncludes: `/dashboard/group/events/${eventId}/attendees/${TEST_USER_IDS.pending2}/invitation-request/accept`,
        },
      );
      notificationIds = expectNewNotifications(approvalSnapshot, [
        { kind: "event-ticket-request-approved", userIds: [TEST_USER_IDS.pending2] },
      ]);
      await expectTicketOfferStatus(pendingTwoRow, "Accepted", "Pending");
    } finally {
      // Remove request notifications and the temporary event.
      deleteNotifications(notificationIds);
      await deleteEventFromList(organizerGroupPage, eventId);
    }
  });

  test("organizer accepts and rejects requests after registration closes", async ({ organizerGroupPage }) => {
    const event = TEST_REGISTRATION_WINDOW_EVENTS.approvalClosed;

    // Restore the closed-window requests before organizer review.
    resetClosedRegistrationWindowRequests();

    try {
      // Load the closed event's pending Requests tab.
      const requestsContent = await openInvitationRequestsTab(organizerGroupPage, event.name, event.id);

      // Public registration is closed, but organizer review remains available.
      await expect(requestsContent).toContainText("Public registration is not currently open.");
      await expect(requestsContent).toContainText("Pending requests can still be accepted or rejected");

      // Keep terminal requests visible while both organizer actions complete.
      await requestsContent.getByLabel("Status filters").click();
      await waitForActionResponse(
        organizerGroupPage,
        () =>
          requestsContent
            .locator("#invitation-requests-status-filter")
            .getByRole("button", { name: "All", exact: true })
            .click(),
        {
          method: "GET",
          urlIncludes: `/dashboard/group/events/${event.id}/invitation-requests`,
        },
      );

      // Reject one pending request and verify its updated state.
      const rejectedRow = requestsContent.locator("tr", {
        hasText: "E2E Pending One",
      });
      await rejectedRow.getByRole("button", { name: "Open actions for E2E Pending One" }).click();
      const rejectButton = rejectedRow.getByRole("button", {
        name: "Reject",
        exact: true,
      });
      await expect(rejectButton).toBeEnabled();
      await rejectButton.click();
      await waitForActionResponse(
        organizerGroupPage,
        () => organizerGroupPage.getByRole("button", { name: "Yes" }).click(),
        {
          method: "PUT",
          urlIncludes: `/dashboard/group/events/${event.id}/attendees/${TEST_USER_IDS.pending1}/invitation-request/reject`,
        },
      );
      await expect(rejectedRow).toContainText("Rejected");

      // Accept the other request and verify its pending offer.
      const acceptedRow = requestsContent.locator("tr", {
        hasText: "E2E Pending Two",
      });
      await acceptedRow.getByRole("button", { name: "Open actions for E2E Pending Two" }).click();
      const acceptButton = acceptedRow.getByRole("button", {
        name: "Accept",
        exact: true,
      });
      await expect(acceptButton).toBeEnabled();
      await waitForActionResponse(organizerGroupPage, () => acceptButton.click(), {
        method: "PUT",
        urlIncludes: `/dashboard/group/events/${event.id}/attendees/${TEST_USER_IDS.pending2}/invitation-request/accept`,
      });
      await expectTicketOfferStatus(acceptedRow, "Accepted", "Pending");
    } finally {
      // Restore the shared request fixtures for later tests.
      resetClosedRegistrationWindowRequests();
    }
  });

  test("organizer accepts a request before public registration opens", async ({
    member1Page,
    member2Page,
    organizerGroupPage,
  }) => {
    const event = TEST_REGISTRATION_WINDOW_EVENTS.approvalFuture;

    // Restore the pending request used by this cross-surface flow.
    resetFutureRegistrationWindowRequest();

    try {
      // Public invitation requests remain unavailable before registration opens.
      await navigateToEvent(member2Page, TEST_COMMUNITY_NAME, TEST_GROUP_SLUGS.community1.alpha, event.slug);
      await waitForAttendanceState(member2Page);
      await expect(getAttendButton(member2Page)).toContainText("Request invitation");
      await expect(getAttendButton(member2Page)).toBeDisabled();

      // Accept the seeded request from the organizer dashboard.
      const requestsContent = await openInvitationRequestsTab(organizerGroupPage, event.name, event.id);
      await expect(requestsContent).toContainText("Public registration is not currently open.");

      // Accept the existing request and remove it from the pending queue.
      const requestRow = requestsContent.locator("tr", {
        hasText: "E2E Member One",
      });
      await requestRow.getByRole("button", { name: "Open actions for E2E Member One" }).click();
      const acceptButton = requestRow.getByRole("button", {
        name: "Accept",
        exact: true,
      });
      await expect(acceptButton).toBeEnabled();
      await waitForActionResponse(organizerGroupPage, () => acceptButton.click(), {
        method: "PUT",
        urlIncludes: `/dashboard/group/events/${event.id}/attendees/${TEST_USER_IDS.member1}/invitation-request/accept`,
      });
      await expect(requestRow).toHaveCount(0);

      // The accepted request appears as a claimable offer for the requester.
      await navigateToPath(member1Page, "/dashboard/user?tab=invitations");
      const offerRow = member1Page.locator("#dashboard-content tr", {
        hasText: event.name,
      });
      await expect(offerRow).toContainText("RSVP request approved");
      await offerRow.getByLabel(/Open offer actions/).click();
      await expect(offerRow.getByRole("menuitem", { name: "Claim offer" })).toBeEnabled();
    } finally {
      // Restore the shared request fixture for later tests.
      resetFutureRegistrationWindowRequest();
    }
  });

  test("organizer reissues an expired approval offer after registration closes", async ({
    organizerGroupPage,
  }) => {
    const event = TEST_REGISTRATION_WINDOW_EVENTS.approvalClosed;

    // Restore the expired approval offer before organizer review.
    resetClosedRegistrationWindowRequests();

    try {
      // Load the closed event's Requests tab.
      const requestsContent = await openInvitationRequestsTab(organizerGroupPage, event.name, event.id);

      // Include accepted requests so the expired approval offer is visible.
      await requestsContent.getByLabel("Status filters").click();
      await waitForActionResponse(
        organizerGroupPage,
        () =>
          requestsContent
            .locator("#invitation-requests-status-filter")
            .getByRole("button", { name: "All", exact: true })
            .click(),
        {
          method: "GET",
          urlIncludes: `/dashboard/group/events/${event.id}/invitation-requests`,
        },
      );

      // Reissue the expired offer and verify its pending lifecycle state.
      const requestRow = requestsContent.locator("tr", {
        hasText: "E2E Member One",
      });
      await expectTicketOfferStatus(requestRow, "Accepted", "Expired");
      await requestRow.getByRole("button", { name: "Open actions for E2E Member One" }).click();
      const reissueButton = requestRow.getByRole("button", {
        name: "Reissue offer",
        exact: true,
      });
      await expect(reissueButton).toBeEnabled();
      await waitForActionResponse(organizerGroupPage, () => reissueButton.click(), {
        method: "PUT",
        urlIncludes: `/dashboard/group/events/${event.id}/attendees/${TEST_USER_IDS.member1}/invitation-request/reissue`,
      });
      await expect(organizerGroupPage.locator(".swal2-popup")).toContainText("Ticket offer reissued.");
      await organizerGroupPage.getByRole("button", { name: "OK" }).click();
      await expectTicketOfferStatus(requestRow, "Accepted", "Pending");
    } finally {
      // Restore the shared request fixtures for later tests.
      resetClosedRegistrationWindowRequests();
    }
  });

  test("organizer manages tiered invitation request offers across lifecycle states", async ({
    organizerGroupPage,
  }) => {
    test.setTimeout(90_000);

    // Expand the viewport for the wide lifecycle table.
    await organizerGroupPage.setViewportSize({ width: 1600, height: 900 });

    // Load the lifecycle requests tab with the ticketing fixture.
    const lifecycleEvent = TEST_TICKETING_EVENTS.invitationRequests;
    const requestsContent = await openInvitationRequestsTab(
      organizerGroupPage,
      lifecycleEvent.name,
      lifecycleEvent.id,
    );

    // Include accepted requests so expired and checkout-started offers are visible.
    await requestsContent.getByLabel("Status filters").click();
    await Promise.all([
      organizerGroupPage.waitForResponse(
        (response) =>
          response.request().method() === "GET" &&
          response.url().includes(`/dashboard/group/events/${lifecycleEvent.id}/invitation-requests`) &&
          response.url().includes("status=all") &&
          response.ok(),
      ),
      requestsContent
        .locator("#invitation-requests-status-filter")
        .getByRole("button", { name: "All", exact: true })
        .click(),
    ]);

    // Verify the requested tier remains a first-class table column.
    await expect(
      requestsContent.getByRole("columnheader", {
        name: "Ticket type",
        exact: true,
      }),
    ).toBeVisible();
    const scopedRequestRow = requestsContent.locator("tr", {
      hasText: "E2E Pending Two",
    });
    await expect(scopedRequestRow).toContainText("General Admission");

    // Approve an unscoped request by choosing one assignable private tier.
    const unscopedRequestRow = requestsContent.locator("tr", {
      hasText: "E2E Pending One",
    });
    await unscopedRequestRow.getByRole("button", { name: "Open actions for E2E Pending One" }).click();
    const ticketTypeSelect = unscopedRequestRow.getByLabel("Invitation-only ticket");
    await expect(ticketTypeSelect).toContainText("Sponsor allocation");
    await expect(ticketTypeSelect).toContainText("VIP allocation");
    await ticketTypeSelect.selectOption("56555555-5555-5555-5555-655555555914");
    const approvalRequest = organizerGroupPage.waitForRequest(
      (request) =>
        request.method() === "PUT" &&
        request
          .url()
          .includes(
            `/events/${lifecycleEvent.id}/attendees/${TEST_USER_IDS.pending1}/invitation-request/accept`,
          ),
    );
    await waitForActionResponse(
      organizerGroupPage,
      () => unscopedRequestRow.getByRole("button", { name: "Accept", exact: true }).click(),
      {
        method: "PUT",
        urlIncludes: `/events/${lifecycleEvent.id}/attendees/${TEST_USER_IDS.pending1}/invitation-request/accept`,
      },
    );
    expect(new URLSearchParams((await approvalRequest).postData() ?? "").get("event_ticket_type_id")).toBe(
      "56555555-5555-5555-5555-655555555914",
    );
    await expectTicketOfferStatus(unscopedRequestRow, "Accepted", "Pending");

    // Reissue an expired offer while preserving its assigned private tier.
    const expiredOfferRow = requestsContent.locator("tr", {
      hasText: "E2E Admin Two",
    });
    await expect(expiredOfferRow).toContainText("Accepted");
    await expiredOfferRow.getByRole("button", { name: "Open actions for E2E Admin Two" }).click();
    await expect(expiredOfferRow.getByLabel("Invitation-only ticket")).toHaveValue(
      "56555555-5555-5555-5555-655555555914",
    );
    await waitForActionResponse(
      organizerGroupPage,
      () => expiredOfferRow.getByRole("button", { name: "Reissue offer", exact: true }).click(),
      {
        method: "PUT",
        urlIncludes: "/invitation-request/reissue",
      },
    );
    await expect(organizerGroupPage.locator(".swal2-popup")).toContainText("Ticket offer reissued.");
    await organizerGroupPage.getByRole("button", { name: "OK" }).click();

    // Cancel an offer whose attendee has already started provider checkout.
    const checkoutOfferRow = requestsContent.locator("tr", {
      hasText: "E2E Organizer Two",
    });
    await checkoutOfferRow.getByRole("button", { name: "Open actions for E2E Organizer Two" }).click();
    await checkoutOfferRow.getByRole("button", { name: "Cancel offer", exact: true }).click();
    await expect(organizerGroupPage.locator(".swal2-popup")).toContainText(
      "Are you sure you want to cancel this ticket offer?",
    );
    await waitForActionResponse(
      organizerGroupPage,
      () => organizerGroupPage.getByRole("button", { name: "Yes" }).click(),
      {
        method: "PUT",
        urlIncludes: "/dashboard/group/admission-offers/",
        urlEndsWith: "/cancel",
      },
    );
    await expect(organizerGroupPage.locator(".swal2-popup")).toContainText("Ticket offer canceled.");

    // Open a request on an event whose only private tier is inactive.
    const unavailableEvent = TEST_TICKETING_EVENTS.noAssignableTier;
    const unavailableRequests = await openInvitationRequestsTab(
      organizerGroupPage,
      unavailableEvent.name,
      unavailableEvent.id,
    );
    const unavailableRow = unavailableRequests.locator("tr", {
      hasText: "E2E Community Viewer One",
    });
    await unavailableRow
      .getByRole("button", {
        name: "Open actions for E2E Community Viewer One",
      })
      .click();
    await expect(unavailableRow.locator("[data-invitation-request-ticket-empty]")).toBeVisible();
    await expect(
      unavailableRow.getByText("No invitation-only ticket types can be assigned.", { exact: false }),
    ).toBeVisible();
    await expect(unavailableRow.getByRole("button", { name: "Accept", exact: true })).toBeDisabled();
  });
});

/** Deletes matching notifications from the notification table after a snapshot. */
const deleteNotificationsSince = (snapshot, kind, userIds) => {
  queryE2eDatabase(`
    delete from notification
    where created_at >= '${snapshot.createdAfter}'::timestamptz
    and kind = '${kind}'
    and user_id in (${userIds.map((userId) => `'${userId}'::uuid`).join(", ")});
  `);
};

/** Verifies an accepted or rejected request exposes its ticket offer details. */
const expectTicketOfferStatus = async (requestRow, requestStatus, offerStatus) => {
  const requestStatusButton = requestRow.getByRole("button", {
    name: requestStatus,
    exact: true,
  });
  const offerDetails = requestRow.getByRole("tooltip");
  const offerStatusDetails = offerDetails.getByText("Offer status", { exact: true }).locator("..");

  await requestStatusButton.focus();
  await expect(offerDetails).toBeVisible();
  await expect(offerStatusDetails.getByText(offerStatus, { exact: true })).toBeVisible();
};

/** Restores invitation review fixtures whose public registration window is closed. */
const resetClosedRegistrationWindowRequests = () => {
  const eventId = TEST_REGISTRATION_WINDOW_EVENTS.approvalClosed.id;

  queryE2eDatabase(`
    delete from event_purchase
    where event_id = '${eventId}'
    and user_id in (
      '${TEST_USER_IDS.member1}',
      '${TEST_USER_IDS.pending1}',
      '${TEST_USER_IDS.pending2}'
    );

    delete from event_attendee
    where event_id = '${eventId}'
    and user_id in (
      '${TEST_USER_IDS.member1}',
      '${TEST_USER_IDS.pending1}',
      '${TEST_USER_IDS.pending2}'
    );

    delete from admission_offer
    where event_id = '${eventId}'
    and user_id in (
      '${TEST_USER_IDS.member1}',
      '${TEST_USER_IDS.pending1}',
      '${TEST_USER_IDS.pending2}'
    );

    update event_invitation_request
    set
      status = case
        when user_id = '${TEST_USER_IDS.member1}' then 'accepted'
        else 'pending'
      end,
      reviewed_at = case
        when user_id = '${TEST_USER_IDS.member1}' then current_timestamp - interval '2 days'
        else null
      end,
      reviewed_by = case
        when user_id = '${TEST_USER_IDS.member1}' then '${TEST_USER_IDS.organizer1}'::uuid
        else null
      end
    where event_id = '${eventId}'
    and user_id in (
      '${TEST_USER_IDS.member1}',
      '${TEST_USER_IDS.pending1}',
      '${TEST_USER_IDS.pending2}'
    );

    insert into admission_offer (
      admission_offer_id,
      created_at,
      amount_minor,
      currency_code,
      discount_amount_minor,
      event_id,
      event_ticket_type_id,
      expires_at,
      source,
      status,
      ticket_title,
      user_id
    ) values (
      '${CLOSED_APPROVAL_OFFER_ID}',
      current_timestamp - interval '2 days',
      null,
      null,
      null,
      '${eventId}',
      (
        select event_ticket_type_id
        from event_ticket_type
        where event_id = '${eventId}'
        order by "order"
        limit 1
      ),
      current_timestamp - interval '1 day',
      'approval',
      'expired',
      null,
      '${TEST_USER_IDS.member1}'
    );
  `);
};

/** Restores the pending approval request whose registration window opens later. */
const resetFutureRegistrationWindowRequest = () => {
  const eventId = TEST_REGISTRATION_WINDOW_EVENTS.approvalFuture.id;

  queryE2eDatabase(`
    delete from event_purchase
    where event_id = '${eventId}'
    and user_id = '${TEST_USER_IDS.member1}';

    delete from event_attendee
    where event_id = '${eventId}'
    and user_id = '${TEST_USER_IDS.member1}';

    delete from admission_offer
    where event_id = '${eventId}'
    and user_id = '${TEST_USER_IDS.member1}';

    update event_invitation_request
    set
      status = 'pending',
      reviewed_at = null,
      reviewed_by = null
    where event_id = '${eventId}'
    and user_id = '${TEST_USER_IDS.member1}';
  `);
};
