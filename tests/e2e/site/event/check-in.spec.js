import { expect, test } from "../../fixtures.js";

import {
  TEST_COMMUNITY_NAME,
  TEST_EVENT_IDS,
  TEST_EVENT_NAMES,
  TEST_EVENT_SLUGS,
  TEST_GROUP_SLUGS,
  TEST_OPEN_CHECK_IN_EVENT,
  TEST_USER_IDS,
  getAttendButton,
  getLeaveButton,
  navigateToEvent,
  navigateToPath,
  waitForActionResponse,
  waitForAttendanceState,
} from "../../utils.js";

// Navigate to the public attendee check-in page.
const navigateToCheckInPage = async (page) => {
  await navigateToPath(page, `/${TEST_COMMUNITY_NAME}/check-in/${TEST_EVENT_IDS.alpha.one}`);
};

// Register the current user as an attendee for the test event.
const attendEvent = async (page, eventId = TEST_EVENT_IDS.alpha.one) => {
  const attendButton = getAttendButton(page);
  await expect(attendButton).toBeVisible();

  // Register for the event and wait for attendance to be created.
  await waitForActionResponse(page, () => attendButton.click(), {
    method: "POST",
    urlIncludes: `/event/${eventId}/attend`,
  });

  // Verify the user can cancel after registering.
  await expect(getLeaveButton(page)).toBeVisible();
};

// Cancel attendance to return the event to a reusable test state.
const leaveEvent = async (page, eventId = TEST_EVENT_IDS.alpha.one) => {
  const leaveButton = getLeaveButton(page);
  await expect(leaveButton).toBeVisible();

  // Request attendance cancellation before confirming the dialog.
  await leaveButton.click();
  const confirmButton = page.getByRole("button", { name: "Yes" });
  await expect(confirmButton).toBeVisible();

  // Confirm cancellation and wait for the attendance record to be removed.
  await waitForActionResponse(page, () => confirmButton.click(), {
    method: "DELETE",
    urlIncludes: `/event/${eventId}/leave`,
  });

  // Verify the user can attend again after cancellation.
  await expect(getAttendButton(page)).toBeVisible();
};

// Restore the live check-in attendee to a confirmed and unchecked state.
const resetOpenCheckInAttendance = async (page) => {
  await navigateToEvent(
    page,
    TEST_COMMUNITY_NAME,
    TEST_GROUP_SLUGS.community1.alpha,
    TEST_OPEN_CHECK_IN_EVENT.slug,
  );
  await waitForAttendanceState(page);

  // Clear any checked-in or confirmed state left by an interrupted retry.
  if (await getLeaveButton(page).isVisible()) {
    await leaveEvent(page, TEST_OPEN_CHECK_IN_EVENT.id);
  }

  // Recreate confirmed attendance without a checked-in timestamp.
  await attendEvent(page, TEST_OPEN_CHECK_IN_EVENT.id);
};

// Navigate to the seeded event whose public check-in window is open.
const navigateToOpenCheckInPage = async (page) => {
  await navigateToPath(page, `/${TEST_COMMUNITY_NAME}/check-in/${TEST_OPEN_CHECK_IN_EVENT.id}`);
};

test.describe("public event check-in page", () => {
  test("unregistered visitors see the event recovery path", async ({ pending1Page }) => {
    // Load public check-in without an attendance record for this event.
    await navigateToCheckInPage(pending1Page);

    // Verify the recovery copy and event destination are available.
    await expect(
      pending1Page.getByRole("heading", { level: 1, name: TEST_EVENT_NAMES.alpha[0] }),
    ).toBeVisible();
    await expect(
      pending1Page.getByText("You're not registered for this event", { exact: true }),
    ).toBeVisible();
    await expect(
      pending1Page.getByText(
        "Only registered attendees can check in. Reserve a spot on the event page and come back once you're confirmed.",
        { exact: true },
      ),
    ).toBeVisible();
    await expect(
      pending1Page.getByRole("link", { name: "View event details" }),
    ).toHaveAttribute(
      "href",
      `/${TEST_COMMUNITY_NAME}/group/${TEST_GROUP_SLUGS.community1.alpha}/event/${TEST_EVENT_SLUGS.alpha[0]}`,
    );
  });

  test("check-in recovery content remains usable on mobile @mobile", async ({ pending1Page }) => {
    // Load public check-in using the mobile project viewport.
    await navigateToCheckInPage(pending1Page);

    // Find the recovery link and verify its content remains visible.
    const detailsLink = pending1Page.getByRole("link", { name: "View event details" });
    await expect(
      pending1Page.getByText("You're not registered for this event", { exact: true }),
    ).toBeVisible();
    await expect(detailsLink).toBeVisible();
    // Verify the recovery link fits within the mobile viewport.
    const linkBounds = await detailsLink.boundingBox();
    expect(linkBounds).not.toBeNull();
    expect(linkBounds.x).toBeGreaterThanOrEqual(0);
    expect(linkBounds.x + linkBounds.width).toBeLessThanOrEqual(390);
  });

  test("attendee sees the waiting state before public check-in opens", async ({ member2Page }) => {
    // Load the event page and ensure the member starts as an attendee.
    await navigateToEvent(
      member2Page,
      TEST_COMMUNITY_NAME,
      TEST_GROUP_SLUGS.community1.alpha,
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
    await expect(member2Page.getByText("Check-in opens closer to the event")).toBeVisible();

    // Return to the event page before cleaning up attendance.
    await navigateToEvent(
      member2Page,
      TEST_COMMUNITY_NAME,
      TEST_GROUP_SLUGS.community1.alpha,
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
      TEST_COMMUNITY_NAME,
      TEST_GROUP_SLUGS.community1.alpha,
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
    await expect(member2Page.getByRole("link", { name: "View event details" })).toBeVisible();

    // Return to the event page before cleaning up attendance.
    await navigateToEvent(
      member2Page,
      TEST_COMMUNITY_NAME,
      TEST_GROUP_SLUGS.community1.alpha,
      TEST_EVENT_SLUGS.alpha[0],
    );

    // Restore the reusable attendance state.
    await waitForAttendanceState(member2Page);
    if (await getLeaveButton(member2Page).isVisible()) {
      await leaveEvent(member2Page);
    }
  });

  test("attendee can submit the public check-in form", async ({ pending2Page }) => {
    // Prepare a confirmed attendee in an open check-in window.
    await resetOpenCheckInAttendance(pending2Page);
    await navigateToOpenCheckInPage(pending2Page);

    // Verify the live event exposes the public check-in form.
    await expect(
      pending2Page.getByRole("heading", {
        level: 1,
        name: TEST_OPEN_CHECK_IN_EVENT.name,
      }),
    ).toBeVisible();
    const checkInButton = pending2Page.getByRole("button", {
      name: "Check in now",
    });
    await expect(checkInButton).toBeVisible();

    // Submit check-in and capture the form contract sent to the server.
    const checkInRequest = pending2Page.waitForRequest(
      (request) =>
        request.method() === "POST" && request.url().includes(`/check-in/${TEST_OPEN_CHECK_IN_EVENT.id}`),
    );
    await waitForActionResponse(pending2Page, () => checkInButton.click(), {
      method: "POST",
      urlIncludes: `/check-in/${TEST_OPEN_CHECK_IN_EVENT.id}`,
    });

    // Verify the request and visible success state reflect durable check-in.
    expect((await checkInRequest).postData()).toContain(`event_id=${TEST_OPEN_CHECK_IN_EVENT.id}`);
    await expect(pending2Page.getByText("You're checked in", { exact: true })).toBeVisible();
    await expect(pending2Page.getByRole("link", { name: "View event details" })).toBeVisible();

    // Restore the reusable attendee fixture after the successful mutation.
    await resetOpenCheckInAttendance(pending2Page);
  });

  test("failed public check-in keeps the form available for retry", async ({ pending2Page }) => {
    // Prepare a confirmed attendee before intercepting the check-in request.
    await resetOpenCheckInAttendance(pending2Page);
    await pending2Page.route(`**/${TEST_COMMUNITY_NAME}/check-in/${TEST_OPEN_CHECK_IN_EVENT.id}`, (route) => {
      if (route.request().method() !== "POST") {
        return route.continue();
      }

      return route.fulfill({
        body: "Temporary check-in failure",
        contentType: "text/plain",
        status: 500,
      });
    });
    await navigateToOpenCheckInPage(pending2Page);

    // Submit the form and wait for the simulated server failure.
    const checkInButton = pending2Page.getByRole("button", {
      name: "Check in now",
    });
    await waitForActionResponse(pending2Page, () => checkInButton.click(), {
      method: "POST",
      status: 500,
      urlIncludes: `/check-in/${TEST_OPEN_CHECK_IN_EVENT.id}`,
    });

    // Verify the error is explicit and the attendee can retry safely.
    await expect(
      pending2Page.getByText("Check-in failed. Please try again later.", {
        exact: true,
      }),
    ).toBeVisible();
    await expect(checkInButton).toBeVisible();
    await expect(checkInButton).toBeEnabled();
    // The success card stays in the DOM but must remain hidden on failure.
    await expect(pending2Page.getByText("You're checked in", { exact: true })).toBeHidden();
  });
});
