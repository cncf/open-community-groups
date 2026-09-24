import { expect, test } from "../../../fixtures.js";
import { queryE2eDatabase } from "../../../database.js";
import {
  cleanupEventsByIds,
  setupTicketAllocationEvent,
  setupTicketInvitationRequest,
  setupTicketOffer,
} from "../../../data-graphs/events.js";
import {
  deleteNotifications,
  deleteNotificationsSince,
  expectNewNotifications,
  snapshotNotifications,
} from "../../../notifications.js";
import {
  TEST_APPROVAL_REQUIRED_EVENT,
  TEST_COMMUNITY_NAME,
  TEST_EVENT_IDS,
  TEST_GROUP_IDS,
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
  waitForHtmxSettle,
} from "../../../utils.js";
import {
  expectErrorAlert,
  holdSeat,
  openInvitationRequestsTab,
  submitAttendeeInvitation,
  waitForEventSectionRefresh,
} from "./attendees-helpers.js";
import {
  createApprovalRequiredEvent,
  deleteEventFromList,
  openCurrentEventEditorSection,
  openEventUpdateFormByName,
} from "./helpers.js";
import { expectUserColumnHasRoom, expectUserProfileModalFromRow } from "./user-profile-modal-helpers.js";

const APPROVAL_DISABLED_REISSUE_TITLE = "Turn on invitation approval to reissue ticket offers.";

const CLOSED_APPROVAL_OFFER_ID = "59555555-5555-5555-5555-555555555905";

const DISABLED_APPROVAL_EVENT_NAME = "Upcoming In-Person Event";

const SOLD_OUT_CONFLICT_MESSAGE =
  "This ticket type is sold out. Add seats or cancel a pending offer before allocating another ticket.";

const TICKET_TYPES = [
  { key: "full", seats: 1, title: "Full tier" },
  { key: "open", seats: 1, title: "Open tier" },
];

test.describe("group dashboard requests tab", () => {
  test("requests tab is offered for approval-required events and hidden for events without requests", async ({
    organizerGroupPage,
  }) => {
    // Open the seeded approval-required event form first.
    await navigateToPath(organizerGroupPage, "/dashboard/group?tab=events");
    await openEventUpdateFormByName(
      organizerGroupPage,
      TEST_APPROVAL_REQUIRED_EVENT.name,
      TEST_APPROVAL_REQUIRED_EVENT.id,
    );

    // Verify the requests tab is present in both section pickers.
    const sectionSelect = organizerGroupPage.locator('select[aria-label="Event form section"]');
    await expect(organizerGroupPage.locator('button[data-section="invitation-requests"]')).toBeVisible();
    await expect(sectionSelect.locator('option[value="invitation-requests"]')).toHaveCount(1);

    // Open an event without attendee approval or requests and verify the tab is absent.
    await navigateToPath(organizerGroupPage, "/dashboard/group?tab=events");
    await openEventUpdateFormByName(
      organizerGroupPage,
      "Full Event With Waitlist",
      TEST_EVENT_IDS.alpha.waitlistLab,
    );
    await expect(organizerGroupPage.locator('button[data-section="invitation-requests"]')).toHaveCount(0);
    await expect(sectionSelect.locator('option[value="invitation-requests"]')).toHaveCount(0);
  });

  test("requests tab stays while reviewed requests remain after approval is disabled", async ({
    organizerGroupPage,
  }) => {
    try {
      // Record a reviewed request on the Alpha event while approval stays disabled.
      setupReviewedInvitationRequest();

      // Open the Alpha event editor.
      await openEventUpdateFormByName(
        organizerGroupPage,
        DISABLED_APPROVAL_EVENT_NAME,
        TEST_EVENT_IDS.alpha.one,
      );
      await expect(organizerGroupPage.locator("#attendee_approval_required")).toHaveValue("false");

      // Verify both section pickers still offer the requests tab.
      const sectionSelect = organizerGroupPage.locator('select[aria-label="Event form section"]');
      await expect(organizerGroupPage.locator('button[data-section="invitation-requests"]')).toHaveCount(1);
      await expect(sectionSelect.locator('option[value="invitation-requests"]')).toHaveCount(1);

      // Open the requests tab.
      const requestsContent = await openCurrentEventEditorSection(
        organizerGroupPage,
        TEST_EVENT_IDS.alpha.one,
        "invitation-requests",
        "#invitation-requests-content",
        { tableName: "Invitation requests" },
      );
      const requestRow = requestsContent.locator("tr", { hasText: "E2E Member Two" });

      // Verify the default pending filter hides reviewed requests.
      await expect(requestsContent.getByRole("row", { name: "No invitation requests found." })).toBeVisible();
      await expect(requestRow).toHaveCount(0);

      // Reset the status filter and verify the reviewed request is listed.
      await waitForActionResponse(
        organizerGroupPage,
        () => requestsContent.getByRole("button", { name: "Reset status filter" }).click(),
        {
          method: "GET",
          urlIncludes: `/dashboard/group/events/${TEST_EVENT_IDS.alpha.one}/invitation-requests`,
        },
      );
      await expect(requestRow).toBeVisible();
      await expect(requestRow).toContainText("Rejected");

      // Remove the request and verify the reopened editor hides the tab.
      cleanupReviewedInvitationRequest();
      await openEventUpdateFormByName(
        organizerGroupPage,
        DISABLED_APPROVAL_EVENT_NAME,
        TEST_EVENT_IDS.alpha.one,
      );
      await expect(organizerGroupPage.locator('button[data-section="invitation-requests"]')).toHaveCount(0);
      await expect(sectionSelect.locator('option[value="invitation-requests"]')).toHaveCount(0);
      await expect(organizerGroupPage.locator('[data-content="invitation-requests"]')).toHaveCount(0);
    } finally {
      // Remove the temporary invitation request.
      cleanupReviewedInvitationRequest();
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

  test("organizer invitations hide superseded reviewed requests without a reload", async ({
    organizerGroupPage,
    pending1Page,
    pending2Page,
  }) => {
    // Give the review and invitation flow enough time on slower deep runs.
    test.setTimeout(120_000);

    // Create a temporary approval-required event.
    const eventName = uniqueName("superseded requests");
    const { eventId } = await createApprovalRequiredEvent(organizerGroupPage, eventName);
    const notificationSnapshot = snapshotNotifications();

    try {
      // Request invitations from two users with an empty form payload.
      for (const requesterPage of [pending1Page, pending2Page]) {
        const requestResponse = await requesterPage.request.post(
          buildE2eUrl(`/${TEST_COMMUNITY_NAME}/event/${eventId}/attend`),
          { form: {} },
        );
        expect(requestResponse.ok()).toBeTruthy();
      }

      // Open the Requests tab with every request status visible.
      const requestsContent = await openCurrentEventEditorSection(
        organizerGroupPage,
        eventId,
        "invitation-requests",
        "#invitation-requests-content",
        { query: "?status=all", tableName: "Invitation requests" },
      );
      const rejectedRow = requestsContent.locator("tr", { hasText: "E2E Pending One" });
      const acceptedRow = requestsContent.locator("tr", { hasText: "E2E Pending Two" });

      // Reject the first request.
      await rejectedRow
        .getByRole("button", { name: "Open actions for E2E Pending One", exact: true })
        .click();
      await rejectedRow.getByRole("button", { name: "Reject", exact: true }).click();
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
      await expect(rejectedRow).toContainText("Rejected");

      // Accept the second request.
      await acceptedRow
        .getByRole("button", { name: "Open actions for E2E Pending Two", exact: true })
        .click();
      await waitForActionResponse(
        organizerGroupPage,
        () => acceptedRow.getByRole("button", { name: "Accept", exact: true }).click(),
        {
          method: "PUT",
          urlIncludes: `/dashboard/group/events/${eventId}/attendees/${TEST_USER_IDS.pending2}/invitation-request/accept`,
        },
      );
      await expect(organizerGroupPage.locator(".swal2-popup")).toContainText("Ticket request accepted.");
      await organizerGroupPage.getByRole("button", { name: "OK" }).click();

      // Cancel the approval offer so the accepted request holds a lapsed offer.
      await acceptedRow
        .getByRole("button", { name: "Open actions for E2E Pending Two", exact: true })
        .click();
      await acceptedRow.getByRole("button", { name: "Cancel offer", exact: true }).click();
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
      await organizerGroupPage.getByRole("button", { name: "OK" }).click();
      await expectTicketOfferStatus(acceptedRow, "Accepted", "Canceled");

      // Invite both reviewed requesters from the Attendees tab.
      const attendeesContent = await openCurrentEventEditorSection(
        organizerGroupPage,
        eventId,
        "attendees",
        "#attendees-content",
        { tableName: "Attendees list" },
      );
      for (const requester of [
        { name: "E2E Pending One", username: "e2e-pending-1" },
        { name: "E2E Pending Two", username: "e2e-pending-2" },
      ]) {
        const requestsRefresh = waitForEventSectionRefresh(
          organizerGroupPage,
          eventId,
          "invitation-requests",
        );
        await submitAttendeeInvitation(organizerGroupPage, attendeesContent, eventId, requester);
        await expect(organizerGroupPage.locator(".swal2-popup")).toContainText("Invitation sent.");
        await organizerGroupPage.getByRole("button", { name: "OK" }).click();

        // Verify the hidden Requests tab refreshes with its active status filter.
        const refreshResponse = await requestsRefresh;
        expect(new URL(refreshResponse.url()).searchParams.get("status")).toBe("all");
        await waitForHtmxSettle(organizerGroupPage);
      }

      // Return to the already loaded Requests tab and verify both reviews are hidden.
      await organizerGroupPage.locator('button[data-section="invitation-requests"]').click();
      await expect(rejectedRow).toHaveCount(0);
      await expect(acceptedRow).toHaveCount(0);

      // Verify the rejected filter no longer lists the superseded rejection.
      await requestsContent.getByLabel("Status filters").click();
      await Promise.all([
        organizerGroupPage.waitForResponse(
          (response) =>
            response.request().method() === "GET" &&
            response.url().includes(`/dashboard/group/events/${eventId}/invitation-requests`) &&
            response.url().includes("status=rejected") &&
            response.ok(),
        ),
        requestsContent
          .locator("#invitation-requests-status-filter")
          .getByRole("button", { name: "Rejected", exact: true })
          .click(),
      ]);
      await expect(rejectedRow).toHaveCount(0);

      // Verify the reviews persist next to the organizer offers that replaced them.
      expect(
        queryE2eDatabase(`
          select string_agg(u.username || ':' || eir.status, ',' order by u.username)
          from event_invitation_request eir
          join "user" u using (user_id)
          where eir.event_id = '${eventId}'
        `),
      ).toBe("e2e-pending-1:rejected,e2e-pending-2:accepted");
      expect(
        queryE2eDatabase(`
          select string_agg(
            u.username || ':' || ao.source || ':' || ao.status,
            ','
            order by u.username, ao.created_at
          )
          from admission_offer ao
          join "user" u using (user_id)
          where ao.event_id = '${eventId}'
        `),
      ).toBe(
        [
          "e2e-pending-1:organizer_invitation:pending",
          "e2e-pending-2:approval:canceled",
          "e2e-pending-2:organizer_invitation:pending",
        ].join(","),
      );
    } finally {
      // Remove the temporary event and the requester notifications it produced.
      await deleteEventFromList(organizerGroupPage, eventId);
      for (const kind of [
        "event-admission-offer-canceled",
        "event-admission-offer-created",
        "event-canceled",
        "event-ticket-request-approved",
      ]) {
        deleteNotificationsSince(notificationSnapshot, kind, [
          TEST_USER_IDS.pending1,
          TEST_USER_IDS.pending2,
        ]);
      }
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
      await showAllInvitationRequests(organizerGroupPage, requestsContent, event.id);

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
      await showAllInvitationRequests(organizerGroupPage, requestsContent, event.id);

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

  test("organizer cannot reissue an expired approval offer after approval is disabled", async ({
    organizerGroupPage,
  }) => {
    try {
      // Record an accepted request with an expired offer while approval stays disabled.
      setupDisabledApprovalExpiredOffer();

      // Load the Alpha event's Requests tab.
      const requestsContent = await openInvitationRequestsTab(
        organizerGroupPage,
        DISABLED_APPROVAL_EVENT_NAME,
        TEST_EVENT_IDS.alpha.one,
      );

      // Include accepted requests so the expired approval offer is visible.
      await showAllInvitationRequests(organizerGroupPage, requestsContent, TEST_EVENT_IDS.alpha.one);

      // Verify the reissue action is disabled with the approval reason.
      const requestRow = requestsContent.locator("tr", {
        hasText: "E2E Member Two",
      });
      await expectTicketOfferStatus(requestRow, "Accepted", "Expired");
      await requestRow.getByRole("button", { name: "Open actions for E2E Member Two" }).click();
      const reissueButton = requestRow.getByRole("button", {
        name: "Reissue offer",
        exact: true,
      });
      await expect(reissueButton).toBeDisabled();
      await expect(reissueButton).toHaveAttribute(
        "title",
        "Turn on invitation approval to reissue ticket offers.",
      );
    } finally {
      // Remove the temporary request and offer.
      cleanupDisabledApprovalExpiredOffer();
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

  test("organizer can review invitation request registration answers", async ({ organizerGroupPage }) => {
    // Load Requests for the seeded approval-required registration event.
    const requestEvent = TEST_TICKETING_EVENTS.ticketRequest;
    const requestsContent = await openInvitationRequestsTab(
      organizerGroupPage,
      requestEvent.name,
      requestEvent.id,
    );
    const requestRow = requestsContent.locator("tr", {
      hasText: "E2E Pending One",
    });
    const actionsButton = requestRow.getByRole("button", {
      name: "Open actions for E2E Pending One",
    });
    const actionsDropdown = requestRow.locator("[data-event-actions-dropdown]");

    // Open the request actions and select its answer review action.
    await expect(requestRow).toBeVisible();
    await actionsButton.click();
    await expect(actionsDropdown).toBeVisible();
    await requestRow.getByRole("button", { name: "View answers" }).click();

    // Verify the dropdown closes and the request answers fill the modal.
    const answersModal = organizerGroupPage.locator("#invitation-request-answers-modal");
    await expect(actionsDropdown).toBeHidden();
    await expect(actionsButton).toHaveAttribute("aria-expanded", "false");
    await expect(answersModal).toBeVisible();
    await expect(answersModal.getByRole("heading", { name: "Registration answers" })).toBeVisible();
    await expect(answersModal.locator("#invitation-request-answers-name")).toHaveText("E2E Pending One");
    await expect(answersModal).toContainText("Why would you like this ticket?");
    await expect(answersModal).toContainText("community programs can make technical events more welcoming");
    await expect
      .poll(() => answersModal.evaluate((modal) => modal.contains(document.activeElement)))
      .toBe(true);

    // Close the modal and return focus to the visible actions disclosure.
    await answersModal.locator("#cancel-invitation-request-answers-modal").click();
    await expect(answersModal).toBeHidden();
    await expect(actionsButton).toBeFocused();
  });

  test("viewer can review invitation request answers without managing the request", async ({
    groupViewerPage,
  }) => {
    // Load Requests with read-only group permissions.
    const requestEvent = TEST_TICKETING_EVENTS.ticketRequest;
    const requestsContent = await openInvitationRequestsTab(
      groupViewerPage,
      requestEvent.name,
      requestEvent.id,
    );
    const requestRow = requestsContent.locator("tr", {
      hasText: "E2E Pending One",
    });
    const actionsButton = requestRow.getByRole("button", {
      name: "Open actions for E2E Pending One",
    });

    // Open the read-only actions and review the submitted answer.
    await expect(actionsButton).toBeEnabled();
    await actionsButton.click();
    await expect(requestRow.getByRole("button", { name: "Accept", exact: true })).toBeDisabled();
    await expect(requestRow.getByRole("button", { name: "Reject", exact: true })).toBeDisabled();
    await requestRow.getByRole("button", { name: "View answers" }).click();

    // Verify answers remain available, then dismiss with the keyboard.
    const answersModal = groupViewerPage.locator("#invitation-request-answers-modal");
    await expect(answersModal).toBeVisible();
    await expect(answersModal).toContainText("community programs can make technical events more welcoming");
    await groupViewerPage.keyboard.press("Escape");
    await expect(answersModal).toBeHidden();
    await expect(actionsButton).toBeFocused();
  });

  test("organizer sees sold-out guidance before accepting or reissuing requests", async ({
    groupViewerPage,
    organizerGroupPage,
  }) => {
    const event = setupTicketAllocationEvent({
      approvalRequired: true,
      groupId: TEST_GROUP_IDS.community1.alpha,
      ticketTypes: TICKET_TYPES,
    });

    try {
      // Fill the full tier and record requests against both tiers.
      holdSeat(event, "full", TEST_USER_IDS.admin1);
      setupTicketInvitationRequest({
        eventId: event.eventId,
        ticketTypeId: event.ticketTypeIds.full,
        userId: TEST_USER_IDS.pending1,
      });
      setupTicketInvitationRequest({
        eventId: event.eventId,
        ticketTypeId: event.ticketTypeIds.open,
        userId: TEST_USER_IDS.member1,
      });
      setupTicketInvitationRequest({
        eventId: event.eventId,
        status: "accepted",
        ticketTypeId: event.ticketTypeIds.full,
        userId: TEST_USER_IDS.pending2,
      });
      setupTicketOffer({
        eventId: event.eventId,
        source: "approval",
        status: "expired",
        ticketTypeId: event.ticketTypeIds.full,
        userId: TEST_USER_IDS.pending2,
      });

      // Include accepted requests so the expired offer is listed.
      const requestsContent = await openInvitationRequestsTab(organizerGroupPage, event.name, event.eventId);
      await showAllInvitationRequests(organizerGroupPage, requestsContent, event.eventId);

      // Pending requests for the full tier explain why Accept is unavailable.
      const soldOutRequestRow = await openRequestActions(requestsContent, "E2E Pending One");
      const soldOutAcceptButton = soldOutRequestRow.getByRole("button", { name: "Accept", exact: true });
      const soldOutAcceptNote = soldOutRequestRow.locator(
        `#invitation-request-ticket-sold-out-${TEST_USER_IDS.pending1}`,
      );
      await expect(soldOutAcceptButton).toBeDisabled();
      await expect(soldOutAcceptButton).toHaveAttribute("title", "This ticket type is sold out.");
      await expect(soldOutAcceptButton).toHaveAttribute(
        "aria-describedby",
        `invitation-request-ticket-sold-out-${TEST_USER_IDS.pending1}`,
      );
      await expect(soldOutAcceptNote).toBeVisible();
      await expect(soldOutAcceptNote).toHaveText(
        "This ticket type is sold out. Add seats or cancel a pending offer before accepting this request.",
      );

      // Expired offers for the full tier explain why Reissue is unavailable.
      const soldOutReissueRow = await openRequestActions(requestsContent, "E2E Pending Two");
      const soldOutReissueButton = soldOutReissueRow.getByRole("button", {
        name: "Reissue offer",
        exact: true,
      });
      await expect(soldOutReissueButton).toBeDisabled();
      await expect(
        soldOutReissueRow.locator(`#invitation-request-ticket-sold-out-${TEST_USER_IDS.pending2}`),
      ).toHaveText(
        "This ticket type is sold out. Add seats or cancel a pending offer before reissuing this offer.",
      );

      // Requests for a tier with seats left keep Accept available without guidance.
      const openRequestRow = await openRequestActions(requestsContent, "E2E Member One");
      await expect(openRequestRow.getByRole("button", { name: "Accept", exact: true })).toBeEnabled();
      await expect(
        openRequestRow.locator(`#invitation-request-ticket-sold-out-${TEST_USER_IDS.member1}`),
      ).toHaveCount(0);

      // Viewers cannot act on requests, so the sold-out guidance is not rendered.
      const viewerRequestsContent = await openInvitationRequestsTab(
        groupViewerPage,
        event.name,
        event.eventId,
      );
      await expect(viewerRequestsContent.locator("tr", { hasText: "E2E Pending One" })).toBeVisible();
      await expect(viewerRequestsContent.locator("[id^='invitation-request-ticket-sold-out-']")).toHaveCount(
        0,
      );
    } finally {
      cleanupEventsByIds([event.eventId]);
    }
  });

  test("organizer gets sold-out guidance when a requested tier fills before accepting", async ({
    organizerGroupPage,
  }) => {
    const event = setupTicketAllocationEvent({
      approvalRequired: true,
      groupId: TEST_GROUP_IDS.community1.alpha,
      ticketTypes: TICKET_TYPES,
    });

    try {
      // Request the open tier while it still has one seat left.
      setupTicketInvitationRequest({
        eventId: event.eventId,
        ticketTypeId: event.ticketTypeIds.open,
        userId: TEST_USER_IDS.member1,
      });
      const requestsContent = await openInvitationRequestsTab(organizerGroupPage, event.name, event.eventId);
      const requestRow = await openRequestActions(requestsContent, "E2E Member One");
      const acceptButton = requestRow.getByRole("button", { name: "Accept", exact: true });
      await expect(acceptButton).toBeEnabled();

      // Take the last seat after the list rendered, then accept the stale request.
      holdSeat(event, "open", TEST_USER_IDS.admin2);
      const refresh = waitForEventSectionRefresh(organizerGroupPage, event.eventId, "invitation-requests");
      await waitForActionResponse(organizerGroupPage, () => acceptButton.click(), {
        method: "PUT",
        urlIncludes: `/dashboard/group/events/${event.eventId}/attendees/${TEST_USER_IDS.member1}/invitation-request/accept`,
        status: 409,
      });
      await refresh;

      // The conflict explains the capacity problem instead of a generic failure.
      await expectErrorAlert(organizerGroupPage, SOLD_OUT_CONFLICT_MESSAGE);
      expect(
        queryE2eDatabase(`
          select count(*)
          from admission_offer
          where event_id = '${event.eventId}'
          and user_id = '${TEST_USER_IDS.member1}'
        `),
      ).toBe("0");

      // The refreshed list now shows the request as blocked by the sold-out tier.
      const refreshedRow = await openRequestActions(requestsContent, "E2E Member One");
      await expect(refreshedRow.getByRole("button", { name: "Accept", exact: true })).toBeDisabled();
      await expect(
        refreshedRow.locator(`#invitation-request-ticket-sold-out-${TEST_USER_IDS.member1}`),
      ).toBeVisible();
    } finally {
      cleanupEventsByIds([event.eventId]);
    }
  });

  test("organizer gets sold-out guidance when an expired offer tier fills before reissuing", async ({
    organizerGroupPage,
  }) => {
    const event = setupTicketAllocationEvent({
      approvalRequired: true,
      groupId: TEST_GROUP_IDS.community1.alpha,
      ticketTypes: TICKET_TYPES,
    });

    try {
      // Record an expired approval offer while its tier still has one seat left.
      setupTicketInvitationRequest({
        eventId: event.eventId,
        status: "accepted",
        ticketTypeId: event.ticketTypeIds.open,
        userId: TEST_USER_IDS.pending2,
      });
      setupTicketOffer({
        eventId: event.eventId,
        source: "approval",
        status: "expired",
        ticketTypeId: event.ticketTypeIds.open,
        userId: TEST_USER_IDS.pending2,
      });
      const requestsContent = await openInvitationRequestsTab(organizerGroupPage, event.name, event.eventId);
      await showAllInvitationRequests(organizerGroupPage, requestsContent, event.eventId);
      const requestRow = await openRequestActions(requestsContent, "E2E Pending Two");
      const reissueButton = requestRow.getByRole("button", { name: "Reissue offer", exact: true });
      await expect(reissueButton).toBeEnabled();

      // Take the last seat after the list rendered, then reissue the stale offer.
      holdSeat(event, "open", TEST_USER_IDS.admin2);
      const refresh = waitForEventSectionRefresh(organizerGroupPage, event.eventId, "invitation-requests");
      await waitForActionResponse(organizerGroupPage, () => reissueButton.click(), {
        method: "PUT",
        urlIncludes: `/dashboard/group/events/${event.eventId}/attendees/${TEST_USER_IDS.pending2}/invitation-request/reissue`,
        status: 409,
      });
      await refresh;

      // The conflict explains the capacity problem and keeps the offer expired.
      await expectErrorAlert(organizerGroupPage, SOLD_OUT_CONFLICT_MESSAGE);
      expect(
        queryE2eDatabase(`
          select string_agg(status, ',')
          from admission_offer
          where event_id = '${event.eventId}'
          and user_id = '${TEST_USER_IDS.pending2}'
        `),
      ).toBe("expired");

      // The refreshed list now shows the reissue as blocked by the sold-out tier.
      const refreshedRow = await openRequestActions(requestsContent, "E2E Pending Two");
      await expect(refreshedRow.getByRole("button", { name: "Reissue offer", exact: true })).toBeDisabled();
      await expect(
        refreshedRow.locator(`#invitation-request-ticket-sold-out-${TEST_USER_IDS.pending2}`),
      ).toHaveText(
        "This ticket type is sold out. Add seats or cancel a pending offer before reissuing this offer.",
      );
    } finally {
      cleanupEventsByIds([event.eventId]);
    }
  });

  test("organizer sees approval guidance instead of sold-out guidance when approval is off", async ({
    organizerGroupPage,
  }) => {
    const event = setupTicketAllocationEvent({
      groupId: TEST_GROUP_IDS.community1.alpha,
      ticketTypes: TICKET_TYPES,
    });

    try {
      // Record an expired approval offer for the full tier after approval was turned off.
      holdSeat(event, "full", TEST_USER_IDS.admin1);
      setupTicketInvitationRequest({
        eventId: event.eventId,
        status: "accepted",
        ticketTypeId: event.ticketTypeIds.full,
        userId: TEST_USER_IDS.pending2,
      });
      setupTicketOffer({
        eventId: event.eventId,
        source: "approval",
        status: "expired",
        ticketTypeId: event.ticketTypeIds.full,
        userId: TEST_USER_IDS.pending2,
      });

      const requestsContent = await openInvitationRequestsTab(organizerGroupPage, event.name, event.eventId);
      await showAllInvitationRequests(organizerGroupPage, requestsContent, event.eventId);

      // Only the approval reason applies, so the sold-out note stays hidden.
      const requestRow = await openRequestActions(requestsContent, "E2E Pending Two");
      const reissueButton = requestRow.getByRole("button", { name: "Reissue offer", exact: true });
      await expect(reissueButton).toBeDisabled();
      await expect(reissueButton).toHaveAttribute("title", APPROVAL_DISABLED_REISSUE_TITLE);
      await expect(
        requestRow.locator(`#invitation-request-ticket-sold-out-${TEST_USER_IDS.pending2}`),
      ).toHaveCount(0);
    } finally {
      cleanupEventsByIds([event.eventId]);
    }
  });
});

/** Removes the temporary request and offer used by disabled approval reissue coverage. */
const cleanupDisabledApprovalExpiredOffer = () => {
  queryE2eDatabase(`
    delete from admission_offer
    where event_id = '${TEST_EVENT_IDS.alpha.one}'
    and user_id = '${TEST_USER_IDS.member2}';

    delete from event_invitation_request
    where event_id = '${TEST_EVENT_IDS.alpha.one}'
    and user_id = '${TEST_USER_IDS.member2}';
  `);
};

/** Removes the temporary request used by disabled approval tab coverage. */
const cleanupReviewedInvitationRequest = () => {
  queryE2eDatabase(`
    delete from event_invitation_request
    where event_id = '${TEST_EVENT_IDS.alpha.one}'
    and user_id = '${TEST_USER_IDS.member2}';
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

/** Opens one invitation request row menu and returns the row. */
const openRequestActions = async (requestsContent, name) => {
  const requestRow = requestsContent.locator("tr", { hasText: name });
  await expect(requestRow).toBeVisible();

  // Close any open row menu first so it cannot cover the next actions button.
  await requestsContent.page().keyboard.press("Escape");
  await requestRow.getByRole("button", { name: `Open actions for ${name}` }).click();
  await expect(requestRow.locator("[data-event-actions-dropdown]")).toBeVisible();

  return requestRow;
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

/** Records an accepted request with an expired approval offer on the Alpha event. */
const setupDisabledApprovalExpiredOffer = () => {
  queryE2eDatabase(`
    insert into event_invitation_request (event_id, user_id, status, reviewed_at, reviewed_by)
    values (
      '${TEST_EVENT_IDS.alpha.one}',
      '${TEST_USER_IDS.member2}',
      'accepted',
      current_timestamp - interval '3 days',
      '${TEST_USER_IDS.organizer1}'
    )
    on conflict do nothing;

    insert into admission_offer (
      created_at,
      event_id,
      event_ticket_type_id,
      expires_at,
      source,
      status,
      user_id
    ) values (
      current_timestamp - interval '2 days',
      '${TEST_EVENT_IDS.alpha.one}',
      (
        select event_ticket_type_id
        from event_ticket_type
        where event_id = '${TEST_EVENT_IDS.alpha.one}'
        order by "order"
        limit 1
      ),
      current_timestamp - interval '1 day',
      'approval',
      'expired',
      '${TEST_USER_IDS.member2}'
    );
  `);
};

/** Records a rejected request on the Alpha event without enabling approval. */
const setupReviewedInvitationRequest = () => {
  queryE2eDatabase(`
    insert into event_invitation_request (event_id, user_id, status, reviewed_at, reviewed_by)
    values (
      '${TEST_EVENT_IDS.alpha.one}',
      '${TEST_USER_IDS.member2}',
      'rejected',
      now(),
      '${TEST_USER_IDS.organizer1}'
    )
    on conflict do nothing;
  `);
};

/** Switches the Requests tab to all statuses so reviewed requests are listed. */
const showAllInvitationRequests = async (page, requestsContent, eventId) => {
  await requestsContent.getByLabel("Status filters").click();
  await waitForActionResponse(
    page,
    () =>
      requestsContent
        .locator("#invitation-requests-status-filter")
        .getByRole("button", { name: "All", exact: true })
        .click(),
    {
      method: "GET",
      urlIncludes: `/dashboard/group/events/${eventId}/invitation-requests`,
    },
  );
};
