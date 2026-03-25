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

    await navigateToPath(organizerGroupPage, "/dashboard/group?tab=events");

    const eventRow = organizerGroupPage.locator("tr", {
      hasText: TEST_EVENT_NAMES.alpha[0],
    });
    await expect(eventRow).toBeVisible();

    await Promise.all([
      organizerGroupPage.waitForResponse(
        (response) =>
          response.request().method() === "GET" &&
          response.url().includes(`/dashboard/group/events/${TEST_EVENT_IDS.alpha.one}/update`) &&
          response.ok(),
      ),
      eventRow
        .locator(`td button[aria-label="Edit event: ${TEST_EVENT_NAMES.alpha[0]}"]`)
        .click(),
    ]);

    await Promise.all([
      organizerGroupPage.waitForResponse(
        (response) =>
          response.request().method() === "GET" &&
          response.url().includes(`/dashboard/group/events/${TEST_EVENT_IDS.alpha.one}/attendees`) &&
          response.ok(),
      ),
      organizerGroupPage.locator('button[data-section="attendees"]').click(),
    ]);

    const attendeeRow = organizerGroupPage.locator("#attendees-content").locator("tr", {
      hasText: "E2E Member Two",
    });
    const checkInToggle = attendeeRow.locator(".check-in-toggle");

    await expect(attendeeRow).toBeVisible();
    await expect(checkInToggle).toBeEnabled();

    await Promise.all([
      organizerGroupPage.waitForResponse(
        (response) =>
          response.request().method() === "POST" &&
          response
            .url()
            .includes(
              `/dashboard/group/events/${TEST_EVENT_IDS.alpha.one}/attendees/${TEST_USER_IDS.member2}/check-in`,
            ) &&
          response.ok(),
      ),
      attendeeRow.locator("label").click(),
    ]);

    await expect(checkInToggle).toBeChecked();
    await expect(checkInToggle).toBeDisabled();

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
