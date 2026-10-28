import { expect, test } from "../../fixtures.js";
import { cleanupEventEnrollment } from "../../data-graphs/invitations.js";
import {
  TEST_COMMUNITY_NAME,
  TEST_EVENT_IDS,
  TEST_EVENT_SLUGS,
  TEST_GROUP_SLUGS,
  TEST_USER_IDS,
} from "../../seed.js";
import { getAttendButton, getLeaveButton } from "../../site/event/helpers.js";
import { navigateToEvent, navigateToPath, waitForActionResponse } from "../../utils.js";

test.describe("event attendance workflow", () => {
  test("organizer can check in an attendee from the attendees tab @smoke", async ({
    member2Page,
    notifications,
    organizerGroupPage,
    owned,
  }) => {
    // Remove the attendance the member creates.
    owned.defer(() =>
      cleanupEventEnrollment({ eventId: TEST_EVENT_IDS.alpha.one, userId: TEST_USER_IDS.member2 }),
    );

    // Load the public event page before creating attendance.
    await navigateToEvent(
      member2Page,
      TEST_COMMUNITY_NAME,
      TEST_GROUP_SLUGS.community1.alpha,
      TEST_EVENT_SLUGS.alpha[0],
    );

    // Find the attend button.
    const attendButton = getAttendButton(member2Page);
    const leaveButton = getLeaveButton(member2Page);

    // Attend the event as a member.
    await expect(attendButton).toContainText("Attend event");

    // Attend and verify only the welcome notification is enqueued.
    const attendCheckpoint = notifications.checkpoint();
    await waitForActionResponse(member2Page, () => attendButton.click(), {
      method: "POST",
      urlIncludes: `/event/${TEST_EVENT_IDS.alpha.one}/attend`,
    });
    notifications.expectNew([{ kind: "event-welcome", userIds: [TEST_USER_IDS.member2] }], {
      since: attendCheckpoint,
    });

    // Assert the expected text is rendered.
    await expect(leaveButton).toContainText("Cancel attendance");

    // Load the group events dashboard as the organizer.
    await navigateToPath(organizerGroupPage, "/dashboard/group?tab=events");

    // Find the event row.
    const eventRow = organizerGroupPage.locator("tr", {
      hasText: "Upcoming In-Person Event",
    });
    await expect(eventRow).toBeVisible();

    // Open the event update form before switching to attendees.
    await waitForActionResponse(
      organizerGroupPage,
      () => eventRow.locator('td button[aria-label="Edit event: Upcoming In-Person Event"]').click(),
      {
        method: "GET",
        urlIncludes: `/dashboard/group/events/${TEST_EVENT_IDS.alpha.one}/update`,
      },
    );

    // Load the attendees tab for the event.
    await waitForActionResponse(
      organizerGroupPage,
      () => organizerGroupPage.locator('button[data-section="attendees"]').click(),
      {
        method: "GET",
        urlIncludes: `/dashboard/group/events/${TEST_EVENT_IDS.alpha.one}/attendees`,
      },
    );

    // Target the attendee check-in toggle.
    const attendeesContent = organizerGroupPage.locator("#attendees-content");
    const attendeeRow = attendeesContent.locator("tr", {
      hasText: "E2E Member Two",
    });
    const checkInToggle = attendeeRow.locator(".check-in-toggle");

    // Assert the attendees table lists the public attendee.
    await expect(attendeesContent.getByRole("table", { name: "Attendees list" })).toBeVisible();
    await expect(attendeeRow).toBeVisible();
    await expect(checkInToggle).toBeEnabled();

    // Check in the attendee from the attendees tab.
    await waitForActionResponse(organizerGroupPage, () => attendeeRow.locator("label").click(), {
      method: "POST",
      urlIncludes: `/dashboard/group/events/${TEST_EVENT_IDS.alpha.one}/attendees/${TEST_USER_IDS.member2}/check-in`,
    });

    // The attendee row reflects the saved interaction and check-in sends no notification.
    await expect(checkInToggle).toBeChecked();
    await expect(checkInToggle).toBeDisabled();
    notifications.expectNew([{ kind: "event-welcome", userIds: [TEST_USER_IDS.member2] }], {
      since: attendCheckpoint,
    });

    // Verify the attendee dashboard removes the event from pending check-in.
    await navigateToPath(member2Page, "/dashboard/user?tab=check-in");
    const attendeeEvent = member2Page.locator("[data-user-check-in-open]", {
      hasText: "Upcoming In-Person Event",
    });
    await expect(attendeeEvent).toHaveCount(0);
  });
});
