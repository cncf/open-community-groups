import type { Page } from "@playwright/test";

import { expect, test } from "../../fixtures";

import {
  TEST_COMMUNITY_NAME,
  TEST_EVENT_IDS,
  TEST_EVENT_NAMES,
  TEST_EVENT_SLUGS,
  TEST_GROUP_SLUGS,
  getAttendButton,
  getLeaveButton,
  navigateToEvent,
  waitForAttendanceState,
} from "../../utils";

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
        response.url().includes(`/event/${TEST_EVENT_IDS.alpha.one}/leave`) &&
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
          response.url().includes(`/event/${TEST_EVENT_IDS.alpha.one}/attend`) &&
          response.ok(),
      ),
      attendButton.click(),
    ]);

    await expect(getLeaveButton(member2Page)).toBeVisible();

    await cancelAttendance(member2Page);
  });
});
