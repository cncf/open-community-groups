import type { Page } from "@playwright/test";

import { expect, test } from "../../fixtures";

import {
  TEST_COMMUNITY_NAME,
  TEST_EVENT_IDS,
  TEST_GROUP_SLUGS,
  getAttendButton,
  getLeaveButton,
  navigateToEvent,
  waitForAttendanceState,
} from "../../utils";

const WAITLIST_EVENT_NAME = "Alpha Waitlist Lab";
const WAITLIST_EVENT_SLUG = "alpha-waitlist-lab";

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
          response.url().includes(`/event/${TEST_EVENT_IDS.alpha.waitlistLab}/attend`) &&
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
          response.url().includes(`/event/${TEST_EVENT_IDS.alpha.waitlistLab}/leave`) &&
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
          response.url().includes(`/event/${TEST_EVENT_IDS.alpha.waitlistLab}/attend`) &&
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
          response.url().includes(`/event/${TEST_EVENT_IDS.alpha.waitlistLab}/leave`) &&
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
          response.url().includes(`/event/${TEST_EVENT_IDS.alpha.waitlistLab}/leave`) &&
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
          response.url().includes(`/event/${TEST_EVENT_IDS.alpha.waitlistLab}/attend`) &&
          response.ok(),
      ),
      getAttendButton(organizerGroupPage).click(),
    ]);

    await expect(getLeaveButton(organizerGroupPage)).toContainText("Cancel attendance");
  });
});
