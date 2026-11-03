import { expect, test } from "../../fixtures.js";

import { resetWaitlistLab } from "../../data-graphs/waitlist.js";
import { TEST_COMMUNITY_NAME, TEST_EVENT_IDS, TEST_GROUP_SLUGS, TEST_USER_IDS } from "../../seed.js";
import { getAttendButton, getLeaveButton, waitForAttendanceState } from "./helpers.js";
import { confirmAlert, navigateToEvent, waitForActionResponse } from "../../utils.js";

const WAITLIST_EVENT_NAME = "Full Event With Waitlist";
const WAITLIST_EVENT_SLUG = "alpha-waitlist-lab";

test.describe("event waitlist", () => {
  test.afterEach(() => {
    resetWaitlistLab();
  });

  test("member can join and leave the waitlist from the public event page", async ({
    member2Page,
    notifications,
  }) => {
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

    // Join the waitlist and verify its notification.
    await waitForActionResponse(member2Page, () => getAttendButton(member2Page).click(), {
      method: "POST",
      urlIncludes: `/event/${TEST_EVENT_IDS.alpha.waitlistLab}/attend`,
    });
    notifications.expectNew([{ kind: "event-waitlist-joined", userIds: [TEST_USER_IDS.member2] }]);

    // Verify the member is now waitlisted.
    await expect(getLeaveButton(member2Page)).toContainText("Leave waiting list");

    // Request waitlist removal and verify the confirmation appears.
    await getLeaveButton(member2Page).click();
    await expect(member2Page.getByRole("button", { name: "Yes" })).toBeVisible();

    // Confirm waitlist removal and verify its notification.
    const leftCheckpoint = notifications.checkpoint();
    await waitForActionResponse(
      member2Page,
      () => confirmAlert(member2Page, { message: "Are you sure you want to leave the waiting list?" }),
      {
        method: "DELETE",
        urlIncludes: `/event/${TEST_EVENT_IDS.alpha.waitlistLab}/leave`,
      },
    );
    notifications.expectNew([{ kind: "event-waitlist-left", userIds: [TEST_USER_IDS.member2] }], {
      since: leftCheckpoint,
    });

    // Assert the expected text is rendered.
    await expect(getAttendButton(member2Page)).toContainText("Join waiting list");
  });

  test("failed waitlist join restores the same action for retry", async ({ member2Page }) => {
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

    // Prepare the failed waitlist join route.
    const attendPath = `**/${TEST_COMMUNITY_NAME}/event/${TEST_EVENT_IDS.alpha.waitlistLab}/attend`;
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
      // Restore the real waitlist join endpoint and dismiss any error.
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
