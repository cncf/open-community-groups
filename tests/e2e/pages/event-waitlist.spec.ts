import type { Page } from "@playwright/test";

import { expect, test } from "../fixtures";

import {
  TEST_COMMUNITY_NAME,
  TEST_GROUP_SLUGS,
  navigateToEvent,
} from "../utils";

const WAITLIST_EVENT_ID = "55555555-5555-5555-5555-555555555521";
const WAITLIST_EVENT_NAME = "Alpha Waitlist Lab";
const WAITLIST_EVENT_SLUG = "alpha-waitlist-lab";

/** Returns the public attendance container for the current event page. */
const getAttendanceContainer = (page: Page) =>
  page.locator("[data-attendance-container]").first();

/** Returns the attend button within the public attendance controls. */
const getAttendButton = (page: Page) =>
  getAttendanceContainer(page).locator('[data-attendance-role="attend-btn"]');

/** Returns the cancel/leave button within the public attendance controls. */
const getLeaveButton = (page: Page) =>
  getAttendanceContainer(page).locator('[data-attendance-role="leave-btn"]');

/** Waits until the attendance widget resolves to either attend or leave state. */
const waitForAttendanceState = async (page: Page) => {
  await Promise.race([
    getAttendButton(page).waitFor({ state: "visible" }),
    getLeaveButton(page).waitFor({ state: "visible" }),
  ]);
};

test.describe("event waitlist", () => {
  test("member can join and leave the waitlist from the public event page", async ({
    member2Page,
    organizerGroupPage,
  }) => {
    await navigateToEvent(
      member2Page,
      TEST_COMMUNITY_NAME,
      TEST_GROUP_SLUGS.community1.alpha,
      WAITLIST_EVENT_SLUG,
    );

    await expect(
      member2Page.getByRole("heading", { level: 1, name: WAITLIST_EVENT_NAME }),
    ).toBeVisible();

    await waitForAttendanceState(member2Page);
    await expect(getAttendButton(member2Page)).toContainText("Join waiting list");

    await Promise.all([
      member2Page.waitForResponse(
        (response) =>
          response.request().method() === "POST" &&
          response.url().includes(`/event/${WAITLIST_EVENT_ID}/attend`) &&
          response.ok(),
      ),
      getAttendButton(member2Page).click(),
    ]);

    await expect(getLeaveButton(member2Page)).toContainText("Leave waiting list");

    await getLeaveButton(member2Page).click();
    await expect(member2Page.getByRole("button", { name: "Yes" })).toBeVisible();

    await Promise.all([
      member2Page.waitForResponse(
        (response) =>
          response.request().method() === "DELETE" &&
          response.url().includes(`/event/${WAITLIST_EVENT_ID}/leave`) &&
          response.ok(),
      ),
      member2Page.getByRole("button", { name: "Yes" }).click(),
    ]);

    await expect(getAttendButton(member2Page)).toContainText("Join waiting list");
  });

  test("a waitlisted user is promoted when the attendee leaves", async ({
    member2Page,
    organizerGroupPage,
  }) => {
    await navigateToEvent(
      member2Page,
      TEST_COMMUNITY_NAME,
      TEST_GROUP_SLUGS.community1.alpha,
      WAITLIST_EVENT_SLUG,
    );

    await waitForAttendanceState(member2Page);

    await Promise.all([
      member2Page.waitForResponse(
        (response) =>
          response.request().method() === "POST" &&
          response.url().includes(`/event/${WAITLIST_EVENT_ID}/attend`) &&
          response.ok(),
      ),
      getAttendButton(member2Page).click(),
    ]);

    await expect(getLeaveButton(member2Page)).toContainText("Leave waiting list");

    await navigateToEvent(
      organizerGroupPage,
      TEST_COMMUNITY_NAME,
      TEST_GROUP_SLUGS.community1.alpha,
      WAITLIST_EVENT_SLUG,
    );

    await waitForAttendanceState(organizerGroupPage);
    await expect(getLeaveButton(organizerGroupPage)).toContainText("Cancel attendance");

    await getLeaveButton(organizerGroupPage).click();
    await expect(organizerGroupPage.getByRole("button", { name: "Yes" })).toBeVisible();

    await Promise.all([
      organizerGroupPage.waitForResponse(
        (response) =>
          response.request().method() === "DELETE" &&
          response.url().includes(`/event/${WAITLIST_EVENT_ID}/leave`) &&
          response.ok(),
      ),
      organizerGroupPage.getByRole("button", { name: "Yes" }).click(),
    ]);

    await navigateToEvent(
      member2Page,
      TEST_COMMUNITY_NAME,
      TEST_GROUP_SLUGS.community1.alpha,
      WAITLIST_EVENT_SLUG,
    );

    await waitForAttendanceState(member2Page);
    await expect(getLeaveButton(member2Page)).toContainText("Cancel attendance");

    await getLeaveButton(member2Page).click();
    await expect(member2Page.getByRole("button", { name: "Yes" })).toBeVisible();

    await Promise.all([
      member2Page.waitForResponse(
        (response) =>
          response.request().method() === "DELETE" &&
          response.url().includes(`/event/${WAITLIST_EVENT_ID}/leave`) &&
          response.ok(),
      ),
      member2Page.getByRole("button", { name: "Yes" }).click(),
    ]);

    await navigateToEvent(
      organizerGroupPage,
      TEST_COMMUNITY_NAME,
      TEST_GROUP_SLUGS.community1.alpha,
      WAITLIST_EVENT_SLUG,
    );

    await waitForAttendanceState(organizerGroupPage);
    await expect(getAttendButton(organizerGroupPage)).toContainText("Attend event");

    await Promise.all([
      organizerGroupPage.waitForResponse(
        (response) =>
          response.request().method() === "POST" &&
          response.url().includes(`/event/${WAITLIST_EVENT_ID}/attend`) &&
          response.ok(),
      ),
      getAttendButton(organizerGroupPage).click(),
    ]);

    await expect(getLeaveButton(organizerGroupPage)).toContainText("Cancel attendance");
  });
});
