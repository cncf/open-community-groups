import type { Page } from "@playwright/test";

import { expect, test } from "../fixtures";

import {
  buildE2eUrl,
  TEST_COMMUNITY_NAME,
  TEST_EVENT_NAMES,
  TEST_EVENT_SLUGS,
  TEST_GROUP_SLUGS,
  navigateToEvent,
  navigateToPath,
} from "../utils";

const eventId = "55555555-5555-5555-5555-555555555501";
const member2Id = "77777777-7777-7777-7777-777777777706";

/**
 * Returns the public attendance container for the current event page.
 */
const getAttendanceContainer = (page: Page) => page.locator("[data-attendance-container]").first();

/**
 * Returns the attend button within the public attendance controls.
 */
const getAttendButton = (page: Page) =>
  getAttendanceContainer(page).locator('[data-attendance-role="attend-btn"]');

/**
 * Returns the cancel attendance button within the public attendance controls.
 */
const getLeaveButton = (page: Page) =>
  getAttendanceContainer(page).locator('[data-attendance-role="leave-btn"]');

/**
 * Waits until the attendance widget resolves to either attend or cancel state.
 */
const waitForAttendanceState = async (page: Page) => {
  await Promise.race([
    getAttendButton(page).waitFor({ state: "visible" }),
    getLeaveButton(page).waitFor({ state: "visible" }),
  ]);
};

/**
 * Navigates to the public attendee check-in page.
 */
const navigateToCheckInPage = async (page: Page) => {
  await navigateToPath(page, `/${TEST_COMMUNITY_NAME}/check-in/${eventId}`);
};

/**
 * Registers the current user as an attendee for the test event.
 */
const attendEvent = async (page: Page) => {
  const attendButton = getAttendButton(page);
  await expect(attendButton).toBeVisible();

  await Promise.all([
    page.waitForResponse(
      (response) =>
        response.request().method() === "POST" &&
        response.url().includes(`/event/${eventId}/attend`) &&
        response.ok(),
    ),
    attendButton.click(),
  ]);

  await expect(getLeaveButton(page)).toBeVisible();
};

/**
 * Cancels attendance to return the event to a reusable test state.
 */
const leaveEvent = async (page: Page) => {
  const leaveButton = getLeaveButton(page);
  await expect(leaveButton).toBeVisible();

  await leaveButton.click();
  const confirmButton = page.getByRole("button", { name: "Yes" });
  await expect(confirmButton).toBeVisible();

  await Promise.all([
    page.waitForResponse(
      (response) =>
        response.request().method() === "DELETE" &&
        response.url().includes(`/event/${eventId}/leave`) &&
        response.ok(),
    ),
    confirmButton.click(),
  ]);

  await expect(getAttendButton(page)).toBeVisible();
};

test.describe("event check-in", () => {
  test("organizer check-in is reflected on the attendee page", async ({
    organizerGroupPage,
    member2Page,
  }) => {
    await navigateToEvent(
      member2Page,
      TEST_COMMUNITY_NAME,
      TEST_GROUP_SLUGS.community1.alpha,
      TEST_EVENT_SLUGS.alpha[0],
    );

    await expect(
      member2Page.getByRole("heading", { level: 1, name: TEST_EVENT_NAMES.alpha[0] }),
    ).toBeVisible();

    await waitForAttendanceState(member2Page);

    if (await getLeaveButton(member2Page).isVisible()) {
      await leaveEvent(member2Page);
    }

    await attendEvent(member2Page);

    await navigateToCheckInPage(member2Page);
    await expect(member2Page.getByText("Check-in opens closer to the event")).toBeVisible();

    const checkInResponse = await organizerGroupPage.request.post(
      buildE2eUrl(`/dashboard/group/events/${eventId}/attendees/${member2Id}/check-in`),
    );
    expect(checkInResponse.ok()).toBeTruthy();

    await navigateToCheckInPage(member2Page);
    await expect(member2Page.getByText("You're checked in")).toBeVisible();
    await expect(member2Page.getByRole("link", { name: "View event details" })).toBeVisible();

    await navigateToEvent(
      member2Page,
      TEST_COMMUNITY_NAME,
      TEST_GROUP_SLUGS.community1.alpha,
      TEST_EVENT_SLUGS.alpha[0],
    );

    await waitForAttendanceState(member2Page);
    if (await getLeaveButton(member2Page).isVisible()) {
      await leaveEvent(member2Page);
    }
  });
});
