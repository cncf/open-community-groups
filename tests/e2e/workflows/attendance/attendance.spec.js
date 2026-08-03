import { expect, test } from "../../fixtures.js";

import {
  TEST_COMMUNITY_NAME,
  TEST_EVENT_IDS,
  TEST_EVENT_SLUGS,
  TEST_GROUP_SLUGS,
  TEST_USER_IDS,
  navigateToEvent,
  navigateToPath,
  waitForActionResponse,
} from "../../utils.js";
import { expectUserProfileModalFromRow } from "../../dashboard/group/events/user-profile-modal-helpers.js";

test.describe("event attendance workflow", () => {
  test("organizer can see a public attendee on the attendees tab", async ({
    member2Page,
    organizerGroupPage,
  }) => {
    // Load the public event page before creating attendance.
    await navigateToEvent(
      member2Page,
      TEST_COMMUNITY_NAME,
      TEST_GROUP_SLUGS.community1.alpha,
      TEST_EVENT_SLUGS.alpha[0],
    );

    // Find the attend button.
    const attendButton = member2Page.locator(
      '[data-attendance-role="attend-btn"]',
    );
    const leaveButton = member2Page.locator(
      '[data-attendance-role="leave-btn"]',
    );

    // Attend the event as a member.
    await expect(attendButton).toContainText("Attend event");

    // Click the attend button.
    await waitForActionResponse(member2Page, () => attendButton.click(), {
      method: "POST",
      urlIncludes: `/event/${TEST_EVENT_IDS.alpha.one}/attend`,
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
      () =>
        eventRow
          .locator('td button[aria-label="Edit event: Upcoming In-Person Event"]')
          .click(),
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

    // Verify the organizer sees the public attendee.
    const attendeesContent = organizerGroupPage.locator("#attendees-content");
    const attendeeRow = attendeesContent.locator("tr", {
      hasText: "E2E Member Two",
    });

    // Assert that Attendees list is visible.
    await expect(
      attendeesContent.getByRole("table", { name: "Attendees list" }),
    ).toBeVisible();
    await expect(attendeeRow).toBeVisible();
    await expect(attendeeRow).toContainText("e2e-member-2");
    await expect(
      attendeesContent.getByRole("button", { name: "Send email" }),
    ).toBeEnabled();
    await expectUserProfileModalFromRow(
      organizerGroupPage,
      attendeeRow,
      "View profile for E2E Member Two",
      "E2E Member Two",
      [
        "Member Experience Engineer at Platform Ops Lab",
        "Member Two profile for dashboard modal coverage.",
        "openprofile.dev",
      ],
    );

    // Return to the public event page to restore attendance state.
    await navigateToEvent(
      member2Page,
      TEST_COMMUNITY_NAME,
      TEST_GROUP_SLUGS.community1.alpha,
      TEST_EVENT_SLUGS.alpha[0],
    );

    // Cancel the temporary attendance record.
    await leaveButton.click();
    await expect(
      member2Page.getByRole("button", { name: "Yes" }),
    ).toBeVisible();

    // Click Yes.
    await waitForActionResponse(member2Page, () => member2Page.getByRole("button", { name: "Yes" }).click(), {
      method: "DELETE",
      urlIncludes: `/event/${TEST_EVENT_IDS.alpha.one}/leave`,
    });

    // Assert the expected text is rendered.
    await expect(attendButton).toContainText("Attend event");
  });

  test("organizer can check in an attendee from the attendees tab", async ({
    member2Page,
    organizerGroupPage,
  }) => {
    // Load the public event page before creating attendance.
    await navigateToEvent(
      member2Page,
      TEST_COMMUNITY_NAME,
      TEST_GROUP_SLUGS.community1.alpha,
      TEST_EVENT_SLUGS.alpha[0],
    );

    // Find the attend button.
    const attendButton = member2Page.locator(
      '[data-attendance-role="attend-btn"]',
    );
    const leaveButton = member2Page.locator(
      '[data-attendance-role="leave-btn"]',
    );

    // Attend the event as a member.
    await expect(attendButton).toContainText("Attend event");

    // Click the attend button.
    await waitForActionResponse(member2Page, () => attendButton.click(), {
      method: "POST",
      urlIncludes: `/event/${TEST_EVENT_IDS.alpha.one}/attend`,
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
      () =>
        eventRow
          .locator('td button[aria-label="Edit event: Upcoming In-Person Event"]')
          .click(),
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

    // Assert the expected content is visible.
    await expect(attendeeRow).toBeVisible();
    await expect(checkInToggle).toBeEnabled();

    // Check in the attendee from the attendees tab.
    await waitForActionResponse(organizerGroupPage, () => attendeeRow.locator("label").click(), {
      method: "POST",
      urlIncludes:
        `/dashboard/group/events/${TEST_EVENT_IDS.alpha.one}/attendees/${TEST_USER_IDS.member2}/check-in`,
    });

    // The attendee row reflects the saved interaction.
    await expect(checkInToggle).toBeChecked();
    await expect(checkInToggle).toBeDisabled();

    // Verify the checked-in attendee can access the check-in page.
    await navigateToPath(
      member2Page,
      `/${TEST_COMMUNITY_NAME}/check-in/${TEST_EVENT_IDS.alpha.one}`,
    );
    await expect(member2Page.getByText("You're checked in")).toBeVisible();

    // Return to the public event page to restore attendance state.
    await navigateToEvent(
      member2Page,
      TEST_COMMUNITY_NAME,
      TEST_GROUP_SLUGS.community1.alpha,
      TEST_EVENT_SLUGS.alpha[0],
    );

    // Cancel the temporary attendance record.
    await leaveButton.click();
    await expect(
      member2Page.getByRole("button", { name: "Yes" }),
    ).toBeVisible();

    // Click Yes.
    await waitForActionResponse(member2Page, () => member2Page.getByRole("button", { name: "Yes" }).click(), {
      method: "DELETE",
      urlIncludes: `/event/${TEST_EVENT_IDS.alpha.one}/leave`,
    });

    // Assert the expected text is rendered.
    await expect(attendButton).toContainText("Attend event");
  });
});
