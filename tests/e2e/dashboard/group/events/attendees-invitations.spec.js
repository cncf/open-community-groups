import { expect, test } from "../../../fixtures.js";
import { queryE2eDatabase } from "../../../database.js";
import {
  deleteNotifications,
  deleteNotificationsSince,
  expectNewNotifications,
  snapshotNotifications,
} from "../../../notifications.js";
import { TEST_USER_IDS } from "../../../seed.js";
import { uniqueName, waitForActionResponse } from "../../../utils.js";
import { getVisibleStatusBadge, submitAttendeeInvitation } from "./attendees-helpers.js";
import {
  createApprovalRequiredEvent,
  deleteEventFromList,
  openCurrentEventEditorSection,
} from "./helpers.js";

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
      await organizerGroupPage.getByRole("button", { name: "OK" }).click();

      // Verify the invitation appears in the attendees table.
      const attendeeRow = attendeesContent.locator("tr", {
        hasText: "E2E Pending Two",
      });
      await expect(attendeeRow).toBeVisible();
      await expect(getVisibleStatusBadge(attendeeRow, "Offer pending")).toBeVisible();

      // Retry the invitation and verify the pending offer rejects the duplicate.
      const duplicateModal = await submitAttendeeInvitation(
        organizerGroupPage,
        attendeesContent,
        eventId,
        { name: "E2E Pending Two", username: "e2e-pending-2" },
        422,
      );
      await expect(organizerGroupPage.locator(".swal2-popup")).toContainText(
        "user already has a pending event invitation",
      );
      await organizerGroupPage.getByRole("button", { name: "OK" }).click();
      expect(
        queryE2eDatabase(`
          select count(*)
          from admission_offer
          where event_id = '${eventId}'
          and user_id = '${TEST_USER_IDS.pending2}'
        `),
      ).toBe("1");

      // Verify the failed submission keeps the selection until the organizer closes the modal.
      await expect(duplicateModal).toBeVisible();
      await expect(duplicateModal.locator("#attendee-invitation-selected-user")).toContainText(
        "E2E Pending Two",
      );
      await duplicateModal.locator("#cancel-attendee-invitation").click();
      await expect(duplicateModal).toBeHidden();

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
});
