import type { Page } from "@playwright/test";

import { expect, test } from "../../fixtures";

import {
  TEST_COMMUNITY_NAME,
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
} from "../../utils";

/** Navigates to the public attendee check-in page. */
const navigateToCheckInPage = async (page: Page) => {
  await navigateToPath(page, `/${TEST_COMMUNITY_NAME}/check-in/${TEST_EVENT_IDS.alpha.one}`);
};

/** Registers the current user as an attendee for the test event. */
const attendEvent = async (page: Page) => {
  const attendButton = getAttendButton(page);
  await expect(attendButton).toBeVisible();

  await Promise.all([
    page.waitForResponse(
      (response) =>
        response.request().method() === "POST" &&
        response.url().includes(`/event/${TEST_EVENT_IDS.alpha.one}/attend`) &&
        response.ok(),
    ),
    attendButton.click(),
  ]);

  await expect(getLeaveButton(page)).toBeVisible();
};

/** Cancels attendance to return the event to a reusable test state. */
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
        response.url().includes(`/event/${TEST_EVENT_IDS.alpha.one}/leave`) &&
        response.ok(),
    ),
    confirmButton.click(),
  ]);

  await expect(getAttendButton(page)).toBeVisible();
};

test.describe("event check-in", () => {
  test("attendee sees the public check-in waiting state before event check-in opens", async ({
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

  test("checked-in attendee sees the public success state on the check-in page", async ({
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

    const checkInResponse = await organizerGroupPage.request.post(
      `/dashboard/group/events/${TEST_EVENT_IDS.alpha.one}/attendees/${TEST_USER_IDS.member2}/check-in`,
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
