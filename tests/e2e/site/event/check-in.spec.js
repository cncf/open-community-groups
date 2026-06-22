import { expect, test } from "../../fixtures.js";

import {
  TEST_ALLIANCE_NAME,
  TEST_EVENT_IDS,
  TEST_EVENT_NAMES,
  TEST_EVENT_SLUGS,
  TEST_GROUP_SLUGS,
  TEST_USER_IDS,
  getAttendButton,
  getLeaveButton,
  navigateToEvent,
  navigateToPath,
  waitForAttendanceState,
} from "../../utils.js";

// Navigate to the public attendee check-in page.
const navigateToCheckInPage = async (page) => {
  await navigateToPath(
    page,
    `/${TEST_ALLIANCE_NAME}/check-in/${TEST_EVENT_IDS.alpha.one}`,
  );
};

// Register the current user as an attendee for the test event.
const attendEvent = async (page) => {
  const attendButton = getAttendButton(page);
  await expect(attendButton).toBeVisible();

  // Register for the event and wait for attendance to be created.
  await Promise.all([
    page.waitForResponse(
      (response) =>
        response.request().method() === "POST" &&
        response.url().includes(`/event/${TEST_EVENT_IDS.alpha.one}/attend`) &&
        response.ok(),
    ),
    attendButton.click(),
  ]);

  // Verify the user can cancel after registering.
  await expect(getLeaveButton(page)).toBeVisible();
};

// Cancel attendance to return the event to a reusable test state.
const leaveEvent = async (page) => {
  const leaveButton = getLeaveButton(page);
  await expect(leaveButton).toBeVisible();

  // Request attendance cancellation before confirming the dialog.
  await leaveButton.click();
  const confirmButton = page.getByRole("button", { name: "Yes" });
  await expect(confirmButton).toBeVisible();

  // Confirm cancellation and wait for the attendance record to be removed.
  await Promise.all([
    page.waitForResponse(
      (response) =>
        response.request().method() === "DELETE" &&
        response.url().includes(`/event/${TEST_EVENT_IDS.alpha.one}/leave`) &&
        response.ok(),
    ),
    confirmButton.click(),
  ]);

  // Verify the user can attend again after cancellation.
  await expect(getAttendButton(page)).toBeVisible();
};

test.describe("public event check-in page", () => {
  test("attendee sees the waiting state before public check-in opens", async ({
    member2Page,
  }) => {
    // Load the event page and ensure the member starts as an attendee.
    await navigateToEvent(
      member2Page,
      TEST_ALLIANCE_NAME,
      TEST_GROUP_SLUGS.alliance1.alpha,
      TEST_EVENT_SLUGS.alpha[0],
    );

    // Verify the event page is loaded before opening check-in.
    await expect(
      member2Page.getByRole("heading", {
        level: 1,
        name: TEST_EVENT_NAMES.alpha[0],
      }),
    ).toBeVisible();

    // Resolve existing attendance before setting up the check-in state.
    await waitForAttendanceState(member2Page);

    // Clear existing attendance before registering the member.
    if (await getLeaveButton(member2Page).isVisible()) {
      await leaveEvent(member2Page);
    }

    // Register the member before opening the check-in page.
    await attendEvent(member2Page);

    // Open the check-in page and verify the waiting message.
    await navigateToCheckInPage(member2Page);
    await expect(
      member2Page.getByText("Check-in opens closer to the event"),
    ).toBeVisible();

    // Return to the event page before cleaning up attendance.
    await navigateToEvent(
      member2Page,
      TEST_ALLIANCE_NAME,
      TEST_GROUP_SLUGS.alliance1.alpha,
      TEST_EVENT_SLUGS.alpha[0],
    );

    // Restore the reusable attendance state.
    await waitForAttendanceState(member2Page);
    if (await getLeaveButton(member2Page).isVisible()) {
      await leaveEvent(member2Page);
    }
  });

  test("checked-in attendee sees the success state on the public check-in page", async ({
    organizerGroupPage,
    member2Page,
  }) => {
    // Load the event page and register the member before check-in.
    await navigateToEvent(
      member2Page,
      TEST_ALLIANCE_NAME,
      TEST_GROUP_SLUGS.alliance1.alpha,
      TEST_EVENT_SLUGS.alpha[0],
    );

    // Verify the event page is loaded before recording check-in.
    await expect(
      member2Page.getByRole("heading", {
        level: 1,
        name: TEST_EVENT_NAMES.alpha[0],
      }),
    ).toBeVisible();

    // Resolve existing attendance before recording check-in.
    await waitForAttendanceState(member2Page);

    // Leave any existing attendance before continuing.
    if (await getLeaveButton(member2Page).isVisible()) {
      await leaveEvent(member2Page);
    }

    // Register the member before recording check-in.
    await attendEvent(member2Page);

    // Record check-in through the organizer dashboard API.
    const checkInResponse = await organizerGroupPage.request.post(
      `/dashboard/group/events/${TEST_EVENT_IDS.alpha.one}/attendees/${TEST_USER_IDS.member2}/check-in`,
    );
    expect(checkInResponse.ok()).toBeTruthy();

    // Open the check-in page and verify the success state.
    await navigateToCheckInPage(member2Page);
    await expect(member2Page.getByText("You're checked in")).toBeVisible();
    await expect(
      member2Page.getByRole("link", { name: "View event details" }),
    ).toBeVisible();

    // Return to the event page before cleaning up attendance.
    await navigateToEvent(
      member2Page,
      TEST_ALLIANCE_NAME,
      TEST_GROUP_SLUGS.alliance1.alpha,
      TEST_EVENT_SLUGS.alpha[0],
    );

    // Restore the reusable attendance state.
    await waitForAttendanceState(member2Page);
    if (await getLeaveButton(member2Page).isVisible()) {
      await leaveEvent(member2Page);
    }
  });
});
