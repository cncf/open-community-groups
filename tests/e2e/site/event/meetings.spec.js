import { expect, test } from "../../fixtures.js";
import { TEST_COMMUNITY_NAME, TEST_GROUP_SLUG, TEST_MEETING_EVENTS, TEST_MEETINGS } from "../../seed.js";
import { navigateToEvent } from "../../utils.js";
import { getAttendanceContainer } from "./helpers.js";

const RECORDING_VISIBILITY_CASES = [
  {
    event: TEST_MEETING_EVENTS.publicRecording,
    href: TEST_MEETINGS.publicRecording.finalRecordingUrl,
    name: "published",
    visible: true,
  },
  {
    event: TEST_MEETING_EVENTS.unpublishedRecording,
    href: TEST_MEETINGS.unpublishedRecording.finalRecordingUrl,
    name: "unpublished",
    visible: false,
  },
];

test.describe("event page meeting details", () => {
  test("attendee sees the live meeting join link", async ({ member1Page }) => {
    // Load the live seeded event as a confirmed attendee.
    await navigateToMeetingEvent(member1Page, TEST_MEETING_EVENTS.live);
    await waitForAttendanceControls(member1Page);

    // Verify attendee-only meeting access reveals the join link during the live window.
    await expect(member1Page.locator("[data-meeting-details]").first()).toBeVisible();
    await expect(member1Page.getByRole("link", { name: "Meeting link" })).toHaveAttribute(
      "href",
      TEST_MEETINGS.live.joinUrl,
    );
    const joinMeetingButton = getAttendanceContainer(member1Page).locator(
      '[data-attendance-role="join-meeting-btn"]',
    );
    await expect(joinMeetingButton).toBeVisible();
    await expect(joinMeetingButton).toHaveAttribute("href", TEST_MEETINGS.live.joinUrl);
  });

  test("non-attendees and anonymous visitors cannot see the live meeting join link", async ({
    emptyUserPage,
    page,
  }) => {
    // Load the live seeded event as a signed-in user without attendance.
    await navigateToMeetingEvent(emptyUserPage, TEST_MEETING_EVENTS.live);
    await waitForAttendanceControls(emptyUserPage);

    // Verify signed-in non-attendees do not receive meeting access.
    await expect(emptyUserPage.locator("[data-meeting-details]").first()).toBeHidden();
    await expect(
      getAttendanceContainer(emptyUserPage).locator('[data-attendance-role="join-meeting-btn"]'),
    ).toBeHidden();

    // Load the same event anonymously and verify the join link remains hidden.
    await navigateToMeetingEvent(page, TEST_MEETING_EVENTS.live);
    await waitForAttendanceControls(page);
    await expect(page.locator("[data-meeting-details]").first()).toBeHidden();
    await expect(
      getAttendanceContainer(page).locator('[data-attendance-role="join-meeting-btn"]'),
    ).toBeHidden();
  });

  for (const recordingCase of RECORDING_VISIBILITY_CASES) {
    test(`${recordingCase.name} meeting recording visibility is enforced`, async ({ page }) => {
      // Load the past event with a final recording URL configured by the organizer.
      await navigateToMeetingEvent(page, recordingCase.event);

      // Verify the public recording link follows the organizer publication flag.
      const recordingLink = page.getByRole("link", { name: "View recording" });
      if (recordingCase.visible) {
        await expect(recordingLink).toHaveAttribute("href", recordingCase.href);
      } else {
        await expect(recordingLink).toHaveCount(0);
        await expect(page.getByText(recordingCase.href, { exact: true })).toHaveCount(0);
      }
    });
  }
});

/** Opens the public meeting event page for the supplied fixture. */
const navigateToMeetingEvent = async (page, event) => {
  await navigateToEvent(page, TEST_COMMUNITY_NAME, TEST_GROUP_SLUG, event.slug);
};

/** Waits for the attendance controls to finish hydrating. */
const waitForAttendanceControls = async (page) => {
  const attendanceContainer = getAttendanceContainer(page);

  await expect(attendanceContainer).toHaveAttribute("data-attendance-ready", "true");
  await expect(attendanceContainer).toHaveAttribute("data-availability-hydrated", "true");
};
