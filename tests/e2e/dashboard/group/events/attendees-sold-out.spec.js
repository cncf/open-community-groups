import { expect, test } from "../../../fixtures.js";
import { queryE2eDatabase } from "../../../database.js";
import {
  cleanupEventsByIds,
  setupTicketAllocationEvent,
  setupTicketOffer,
} from "../../../data-graphs/events.js";
import {
  deleteNotifications,
  expectNewNotifications,
  snapshotNotifications,
} from "../../../notifications.js";
import { TEST_GROUP_IDS, TEST_USER_IDS } from "../../../seed.js";
import { waitForActionResponse } from "../../../utils.js";
import {
  expectErrorAlert,
  holdSeat,
  openAttendeesTab,
  waitForEventSectionRefresh,
} from "./attendees-helpers.js";

const ATTENDEE_REISSUE_SOLD_OUT_TITLE =
  "This ticket type is sold out. Add seats or cancel a pending offer before reissuing this invitation.";

const SOLD_OUT_CONFLICT_MESSAGE =
  "This ticket type is sold out. Add seats or cancel a pending offer before allocating another ticket.";

const TICKET_TYPES = [
  { key: "full", seats: 1, title: "Full tier" },
  { key: "open", seats: 1, title: "Open tier" },
];

test.describe("group dashboard attendees tab — sold-out tickets", () => {
  test("organizer can only reissue attendee invitations for tiers with seats left", async ({
    organizerGroupPage,
  }) => {
    const event = setupTicketAllocationEvent({
      groupId: TEST_GROUP_IDS.community1.alpha,
      ticketTypes: TICKET_TYPES,
    });
    let notificationIds = [];

    try {
      // Record expired invitations for the full tier and for the open tier.
      holdSeat(event, "full", TEST_USER_IDS.admin1);
      setupTicketOffer({
        eventId: event.eventId,
        source: "organizer_invitation",
        status: "expired",
        ticketTypeId: event.ticketTypeIds.full,
        userId: TEST_USER_IDS.pending1,
      });
      setupTicketOffer({
        eventId: event.eventId,
        source: "organizer_invitation",
        status: "expired",
        ticketTypeId: event.ticketTypeIds.open,
        userId: TEST_USER_IDS.pending2,
      });
      const attendeesContent = await openAttendeesTab(
        organizerGroupPage,
        event.name,
        event.eventId,
        "status=invitation-expired",
      );

      // The full tier disables Reissue and explains why.
      const soldOutRow = attendeesContent.locator("tr", { hasText: "E2E Pending One" });
      const soldOutReissueButton = await openAttendeeReissueAction(soldOutRow);
      await expect(soldOutReissueButton).toBeDisabled();
      await expect(soldOutReissueButton).toHaveAttribute("title", ATTENDEE_REISSUE_SOLD_OUT_TITLE);
      await closeAttendeeActions(soldOutRow);

      // The open tier keeps Reissue available and confirms the new offer once.
      const openRow = attendeesContent.locator("tr", { hasText: "E2E Pending Two" });
      const openReissueButton = await openAttendeeReissueAction(openRow);
      await expect(openReissueButton).toBeEnabled();
      const snapshot = snapshotNotifications();
      await waitForActionResponse(organizerGroupPage, () => openReissueButton.click(), {
        method: "POST",
        urlIncludes: `/dashboard/group/events/${event.eventId}/attendees/invite`,
        status: 201,
      });
      await expect(organizerGroupPage.locator(".swal2-popup")).toHaveCount(1);
      await expect(organizerGroupPage.locator(".swal2-popup")).toContainText("Invitation reissued.");
      await organizerGroupPage.getByRole("button", { name: "OK" }).click();
      notificationIds = expectNewNotifications(snapshot, [
        { kind: "event-admission-offer-created", userIds: [TEST_USER_IDS.pending2] },
      ]);
    } finally {
      deleteNotifications(notificationIds);
      cleanupEventsByIds([event.eventId]);
    }
  });

  test("organizer gets sold-out guidance when reissuing an invitation into a filled tier", async ({
    organizerGroupPage,
  }) => {
    const event = setupTicketAllocationEvent({
      groupId: TEST_GROUP_IDS.community1.alpha,
      ticketTypes: TICKET_TYPES,
    });

    try {
      // Render an expired invitation while its tier still has one seat left.
      setupTicketOffer({
        eventId: event.eventId,
        source: "organizer_invitation",
        status: "expired",
        ticketTypeId: event.ticketTypeIds.open,
        userId: TEST_USER_IDS.pending2,
      });
      const attendeesContent = await openAttendeesTab(
        organizerGroupPage,
        event.name,
        event.eventId,
        "status=invitation-expired",
      );
      const attendeeRow = attendeesContent.locator("tr", { hasText: "E2E Pending Two" });
      const reissueButton = await openAttendeeReissueAction(attendeeRow);
      await expect(reissueButton).toBeEnabled();

      // Take the last seat after the list rendered, then reissue the stale invitation.
      holdSeat(event, "open", TEST_USER_IDS.admin2);
      const refresh = waitForEventSectionRefresh(organizerGroupPage, event.eventId, "attendees");
      await waitForActionResponse(organizerGroupPage, () => reissueButton.click(), {
        method: "POST",
        urlIncludes: `/dashboard/group/events/${event.eventId}/attendees/invite`,
        status: 409,
      });
      await refresh;

      // The conflict explains the capacity problem and the refreshed row blocks another retry.
      await expectErrorAlert(organizerGroupPage, SOLD_OUT_CONFLICT_MESSAGE);
      const refreshedReissueButton = await openAttendeeReissueAction(
        attendeesContent.locator("tr", { hasText: "E2E Pending Two" }),
      );
      await expect(refreshedReissueButton).toBeDisabled();
      await expect(refreshedReissueButton).toHaveAttribute("title", ATTENDEE_REISSUE_SOLD_OUT_TITLE);
    } finally {
      cleanupEventsByIds([event.eventId]);
    }
  });

  test("organizer gets sold-out guidance when inviting into a tier that filled", async ({
    organizerGroupPage,
  }) => {
    const event = setupTicketAllocationEvent({
      groupId: TEST_GROUP_IDS.community1.alpha,
      ticketTypes: TICKET_TYPES,
    });

    try {
      // Open the invitation modal while the open tier still has one seat left.
      holdSeat(event, "full", TEST_USER_IDS.admin1);
      const attendeesContent = await openAttendeesTab(organizerGroupPage, event.name, event.eventId);
      await attendeesContent.getByRole("button", { name: "Open attendee actions menu" }).click();
      await attendeesContent.getByRole("menuitem", { name: "Invite attendee" }).click();
      const modal = organizerGroupPage.locator("#attendee-invitation-modal");
      await expect(modal).toBeVisible();

      // Sold-out tiers are not offered, so choose the open tier for a registered member.
      const ticketTypeSelect = modal.getByLabel("Ticket type");
      await expect(ticketTypeSelect.locator("option", { hasText: "Full tier" })).toHaveCount(0);
      await ticketTypeSelect.selectOption(event.ticketTypeIds.open);
      const searchField = modal.locator("user-search-field[data-attendee-invitation-search]");
      await searchField.locator("#attendee-invitation-search-input").fill("e2e-member-1");
      await searchField.getByText("E2E Member One").click();
      await expect(modal.locator("#submit-attendee-invitation")).toBeEnabled();

      // Take the last seat after the modal rendered, then submit the stale invitation.
      holdSeat(event, "open", TEST_USER_IDS.admin2);
      const refresh = waitForEventSectionRefresh(organizerGroupPage, event.eventId, "attendees");
      await waitForActionResponse(
        organizerGroupPage,
        () => modal.locator("#submit-attendee-invitation").click(),
        {
          method: "POST",
          urlIncludes: `/dashboard/group/events/${event.eventId}/attendees/invite`,
          status: 409,
        },
      );
      await refresh;

      // The conflict explains the capacity problem and closes the stale modal.
      await expectErrorAlert(organizerGroupPage, SOLD_OUT_CONFLICT_MESSAGE);
      await expect(modal).toBeHidden();
      expect(
        queryE2eDatabase(`
          select count(*)
          from admission_offer
          where event_id = '${event.eventId}'
          and user_id = '${TEST_USER_IDS.member1}'
        `),
      ).toBe("0");

      // Reopening the modal shows the refreshed tiers without the filled tier.
      await attendeesContent.getByRole("button", { name: "Open attendee actions menu" }).click();
      await attendeesContent.getByRole("menuitem", { name: "Invite attendee" }).click();
      await expect(modal).toBeVisible();
      await expect(modal.getByLabel("Ticket type").locator("option", { hasText: "Open tier" })).toHaveCount(
        0,
      );
      await expect(modal.locator("#attendee-invitation-selected-user")).not.toContainText("E2E Member One");
    } finally {
      cleanupEventsByIds([event.eventId]);
    }
  });
});

/** Closes the open actions menu in one attendee row. */
const closeAttendeeActions = async (attendeeRow) => {
  await attendeeRow.locator("[data-actions-menu] summary").click();
  await expect(attendeeRow.getByRole("menuitem", { name: "Reissue invitation" })).toBeHidden();
};

/** Opens one attendee row menu and returns its reissue action. */
const openAttendeeReissueAction = async (attendeeRow) => {
  await expect(attendeeRow).toBeVisible();
  await attendeeRow.locator("[data-actions-menu] summary").click();
  const reissueButton = attendeeRow.getByRole("menuitem", { name: "Reissue invitation" });
  await expect(reissueButton).toBeVisible();

  return reissueButton;
};
