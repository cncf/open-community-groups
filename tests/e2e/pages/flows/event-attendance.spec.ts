import type { Page } from "@playwright/test";

import { expect, test } from "../../fixtures";

import {
  TEST_COMMUNITY_NAME,
  TEST_EVENT_NAMES,
  TEST_EVENT_SLUGS,
  TEST_GROUP_SLUGS,
  navigateToEvent,
} from "../../utils";

const eventId = "55555555-5555-5555-5555-555555555501";

/** Returns the public attendance container for the current event page. */
const getAttendanceContainer = (page: Page) => page.locator("[data-attendance-container]").first();

/** Returns the attend button within the public attendance controls. */
const getAttendButton = (page: Page) =>
  getAttendanceContainer(page).locator('[data-attendance-role="attend-btn"]');

/** Returns the cancel attendance button within the public attendance controls. */
const getLeaveButton = (page: Page) =>
  getAttendanceContainer(page).locator('[data-attendance-role="leave-btn"]');

/** Waits until the attendance widget resolves to either attend or cancel state. */
const waitForAttendanceState = async (page: Page) => {
  await Promise.race([
    getAttendButton(page).waitFor({ state: "visible" }),
    getLeaveButton(page).waitFor({ state: "visible" }),
  ]);
};

/** Cancels attendance when the current user is already registered. */
const cancelAttendance = async (page: Page) => {
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

test.describe("event attendance", () => {
  test("member can attend and cancel from the public event page", async ({
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
      await cancelAttendance(member2Page);
    }

    const attendButton = getAttendButton(member2Page);
    await expect(attendButton).toBeVisible();

    await Promise.all([
      member2Page.waitForResponse(
        (response) =>
          response.request().method() === "POST" &&
          response.url().includes(`/event/${eventId}/attend`) &&
          response.ok(),
      ),
      attendButton.click(),
    ]);

    await expect(getLeaveButton(member2Page)).toBeVisible();

    await cancelAttendance(member2Page);
  });
});
