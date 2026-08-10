import { expect, test } from "../../fixtures.js";

import {
  TEST_COMMUNITY_NAME,
  TEST_EVENT_IDS,
  TEST_GROUP_SLUGS,
  getAttendButton,
  getLeaveButton,
  navigateToEvent,
  restoreSeededWaitlistEvent,
  waitForActionResponse,
  waitForAttendanceState,
} from "../../utils.js";

const WAITLIST_EVENT_NAME = "Full Event With Waitlist";
const WAITLIST_EVENT_SLUG = "alpha-waitlist-lab";

test.describe("event waitlist", () => {
  test.beforeEach(async ({ member2Page, organizerGroupPage }) => {
    await restoreSeededWaitlistEvent(member2Page, organizerGroupPage);
  });

  test.afterEach(async ({ member2Page, organizerGroupPage }) => {
    await restoreSeededWaitlistEvent(member2Page, organizerGroupPage);
  });

  test("member can join and leave the waitlist from the public event page", async ({ member2Page }) => {
    // Load the full event where members can join the waitlist.
    await navigateToEvent(
      member2Page,
      TEST_COMMUNITY_NAME,
      TEST_GROUP_SLUGS.community1.alpha,
      WAITLIST_EVENT_SLUG,
    );

    // Verify the event offers the waitlist join action.
    await expect(member2Page.getByRole("heading", { level: 1, name: WAITLIST_EVENT_NAME })).toBeVisible();

    // Wait for the current attendance state before checking the join action.
    await waitForAttendanceState(member2Page);
    await expect(getAttendButton(member2Page)).toContainText("Join waiting list");

    // Join the waitlist and wait for the attendance record to be created.
    await waitForActionResponse(member2Page, () => getAttendButton(member2Page).click(), {
      method: "POST",
      urlIncludes: `/event/${TEST_EVENT_IDS.alpha.waitlistLab}/attend`,
    });

    // Verify the member is now waitlisted.
    await expect(getLeaveButton(member2Page)).toContainText("Leave waiting list");

    // Request waitlist removal and verify the confirmation appears.
    await getLeaveButton(member2Page).click();
    await expect(member2Page.getByRole("button", { name: "Yes" })).toBeVisible();

    // Confirm waitlist removal and wait for the leave response.
    await waitForActionResponse(
      member2Page,
      () => member2Page.getByRole("button", { name: "Yes" }).click(),
      {
        method: "DELETE",
        urlIncludes: `/event/${TEST_EVENT_IDS.alpha.waitlistLab}/leave`,
      },
    );

    // Assert the expected text is rendered.
    await expect(getAttendButton(member2Page)).toContainText("Join waiting list");
  });

  test("failed waitlist join restores the same action for retry", async ({
    member2Page,
  }) => {
    // Load the full event and wait for its waitlist action.
    await navigateToEvent(
      member2Page,
      TEST_COMMUNITY_NAME,
      TEST_GROUP_SLUGS.community1.alpha,
      WAITLIST_EVENT_SLUG,
    );
    await waitForAttendanceState(member2Page);
    const attendButton = getAttendButton(member2Page);
    await expect(attendButton).toContainText("Join waiting list");

    const attendPath =
      `**/${TEST_COMMUNITY_NAME}/event/${TEST_EVENT_IDS.alpha.waitlistLab}/attend`;
    try {
      // Return a local server failure without creating a waitlist record.
      await member2Page.route(attendPath, (route) =>
        route.fulfill({
          body: "Temporary waitlist failure",
          contentType: "text/plain",
          status: 500,
        }),
      );
      await waitForActionResponse(member2Page, () => attendButton.click(), {
        method: "POST",
        status: 500,
        urlIncludes: `/event/${TEST_EVENT_IDS.alpha.waitlistLab}/attend`,
      });

      // Verify the failure keeps the waitlist-specific state available.
      await expect(member2Page.locator(".swal2-popup")).toContainText(
        "Something went wrong registering for this event. Please try again later.",
      );
      await expect(attendButton).toContainText("Join waiting list");
      await expect(attendButton).toBeEnabled();
      await expect(getLeaveButton(member2Page)).toBeHidden();
    } finally {
      await member2Page.unroute(attendPath);
      const errorConfirmation = member2Page.getByRole("button", {
        name: "OK",
      });
      if (await errorConfirmation.isVisible()) {
        await errorConfirmation.click();
      }
    }
  });
});
