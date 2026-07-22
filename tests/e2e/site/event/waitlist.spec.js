import { expect, test } from "../../fixtures.js";

import {
  TEST_ALLIANCE_NAME,
  TEST_EVENT_IDS,
  TEST_GROUP_SLUGS,
  getAttendButton,
  getLeaveButton,
  navigateToEvent,
  restoreSeededWaitlistEvent,
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

  test("member can join and leave the waitlist from the public event page", async ({
    member2Page,
  }) => {
    // Load the full event where members can join the waitlist.
    await navigateToEvent(
      member2Page,
      TEST_ALLIANCE_NAME,
      TEST_GROUP_SLUGS.alliance1.alpha,
      WAITLIST_EVENT_SLUG,
    );

    // Verify the event offers the waitlist join action.
    await expect(
      member2Page.getByRole("heading", { level: 1, name: WAITLIST_EVENT_NAME }),
    ).toBeVisible();

    // Wait for the current attendance state before checking the join action.
    await waitForAttendanceState(member2Page);
    await expect(getAttendButton(member2Page)).toContainText(
      "Join waiting list",
    );

    // Join the waitlist and wait for the attendance record to be created.
    await Promise.all([
      member2Page.waitForResponse(
        (response) =>
          response.request().method() === "POST" &&
          response
            .url()
            .includes(`/event/${TEST_EVENT_IDS.alpha.waitlistLab}/attend`) &&
          response.ok(),
      ),
      getAttendButton(member2Page).click(),
    ]);

    // Verify the member is now waitlisted.
    await expect(getLeaveButton(member2Page)).toContainText(
      "Leave waiting list",
    );

    // Request waitlist removal and verify the confirmation appears.
    await getLeaveButton(member2Page).click();
    await expect(
      member2Page.getByRole("button", { name: "Yes" }),
    ).toBeVisible();

    // Confirm waitlist removal and wait for the leave response.
    await Promise.all([
      member2Page.waitForResponse(
        (response) =>
          response.request().method() === "DELETE" &&
          response
            .url()
            .includes(`/event/${TEST_EVENT_IDS.alpha.waitlistLab}/leave`) &&
          response.ok(),
      ),
      member2Page.getByRole("button", { name: "Yes" }).click(),
    ]);

    // Assert the expected text is rendered.
    await expect(getAttendButton(member2Page)).toContainText(
      "Join waiting list",
    );
  });

  test("a waitlisted user is promoted when the attendee leaves", async ({
    member2Page,
    organizerGroupPage,
  }) => {
    // Load the waitlist event before creating a waitlisted member.
    await navigateToEvent(
      member2Page,
      TEST_ALLIANCE_NAME,
      TEST_GROUP_SLUGS.alliance1.alpha,
      WAITLIST_EVENT_SLUG,
    );

    // Wait for the member attendance controls before joining the waitlist.
    await waitForAttendanceState(member2Page);

    // Join the waitlist and wait for the attendance record to be created.
    await Promise.all([
      member2Page.waitForResponse(
        (response) =>
          response.request().method() === "POST" &&
          response
            .url()
            .includes(`/event/${TEST_EVENT_IDS.alpha.waitlistLab}/attend`) &&
          response.ok(),
      ),
      getAttendButton(member2Page).click(),
    ]);

    // Verify the member is waiting before the attendee leaves.
    await expect(getLeaveButton(member2Page)).toContainText(
      "Leave waiting list",
    );

    // Load the attendee account that can free the event capacity.
    await navigateToEvent(
      organizerGroupPage,
      TEST_ALLIANCE_NAME,
      TEST_GROUP_SLUGS.alliance1.alpha,
      WAITLIST_EVENT_SLUG,
    );

    // Verify the attendee can cancel attendance.
    await waitForAttendanceState(organizerGroupPage);
    await expect(getLeaveButton(organizerGroupPage)).toContainText(
      "Cancel attendance",
    );

    // Request attendee cancellation and verify the confirmation appears.
    await getLeaveButton(organizerGroupPage).click();
    await expect(
      organizerGroupPage.getByRole("button", { name: "Yes" }),
    ).toBeVisible();

    // Cancel the organizer attendance to promote the waitlisted member.
    await Promise.all([
      organizerGroupPage.waitForResponse(
        (response) =>
          response.request().method() === "DELETE" &&
          response
            .url()
            .includes(`/event/${TEST_EVENT_IDS.alpha.waitlistLab}/leave`) &&
          response.ok(),
      ),
      organizerGroupPage.getByRole("button", { name: "Yes" }).click(),
    ]);

    // Reload the waitlisted member after promotion.
    await navigateToEvent(
      member2Page,
      TEST_ALLIANCE_NAME,
      TEST_GROUP_SLUGS.alliance1.alpha,
      WAITLIST_EVENT_SLUG,
    );

    // Verify the promoted member can now cancel attendance.
    await waitForAttendanceState(member2Page);
    await expect(getLeaveButton(member2Page)).toContainText(
      "Cancel attendance",
    );

    // Request promoted member cancellation and verify confirmation appears.
    await getLeaveButton(member2Page).click();
    await expect(
      member2Page.getByRole("button", { name: "Yes" }),
    ).toBeVisible();

    // Cancel the promoted member attendance before restoring the organizer.
    await Promise.all([
      member2Page.waitForResponse(
        (response) =>
          response.request().method() === "DELETE" &&
          response
            .url()
            .includes(`/event/${TEST_EVENT_IDS.alpha.waitlistLab}/leave`) &&
          response.ok(),
      ),
      member2Page.getByRole("button", { name: "Yes" }).click(),
    ]);

    // Reload the organizer event page before restoring attendance.
    await navigateToEvent(
      organizerGroupPage,
      TEST_ALLIANCE_NAME,
      TEST_GROUP_SLUGS.alliance1.alpha,
      WAITLIST_EVENT_SLUG,
    );

    // Run wait for attendance state.
    await waitForAttendanceState(organizerGroupPage);
    await expect(getAttendButton(organizerGroupPage)).toContainText(
      "Attend event",
    );

    // Restore the organizer attendance for the waitlist event.
    await Promise.all([
      organizerGroupPage.waitForResponse(
        (response) =>
          response.request().method() === "POST" &&
          response
            .url()
            .includes(`/event/${TEST_EVENT_IDS.alpha.waitlistLab}/attend`) &&
          response.ok(),
      ),
      getAttendButton(organizerGroupPage).click(),
    ]);

    // Verify organizer attendance is restored.
    await expect(getLeaveButton(organizerGroupPage)).toContainText(
      "Cancel attendance",
    );
  });
});
