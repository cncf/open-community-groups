import { expect, test } from "../../../fixtures.js";
import { TEST_MEETING_EVENTS, TEST_MEETINGS } from "../../../seed.js";
import {
  futureDate,
  navigateToPath,
  selectTimezone,
  uniqueName,
  waitForActionResponse,
} from "../../../utils.js";
import { fillMarkdownEditor } from "../../form-helpers.js";
import { setAutomaticMeetingCapacity } from "./event-form-helpers.js";
import { deleteEventFromList, openEventUpdateFormByName, waitForEventEditorAfterSave } from "./helpers.js";

const MEETING_STATE_CASES = [
  {
    event: TEST_MEETING_EVENTS.error,
    expectedText: TEST_MEETINGS.errorMessage,
    name: "error",
    statusText: "Meeting not synced",
  },
  {
    event: TEST_MEETING_EVENTS.pending,
    expectedText: "We've requested a meeting for this event.",
    name: "in-flight",
    statusText: "Meeting not synced yet",
  },
  {
    event: TEST_MEETING_EVENTS.live,
    expectedText: TEST_MEETINGS.live.joinUrl,
    name: "synced",
    statusText: "Meeting synced",
  },
];

test.describe("group dashboard event meetings", () => {
  test("organizer can override recording urls for automatic event and session meetings", async ({
    organizerGroupPage,
  }) => {
    const eventName = uniqueName("automatic recording override");
    const sessionName = uniqueName("automatic recording session");
    const urlToken = eventName
      .replace(/[^a-z0-9]+/giu, "-")
      .replace(/^-|-$/gu, "")
      .toLowerCase();
    const eventRecordingUrl = `https://youtube.com/watch?v=event-${urlToken}`;
    const sessionRecordingUrl = `https://youtube.com/watch?v=session-${urlToken}`;
    let eventId = "";

    try {
      // Load the events list before configuring recording overrides.
      await navigateToPath(organizerGroupPage, "/dashboard/group?tab=events");

      // Target dashboard content after the events tab loads.
      const dashboardContent = organizerGroupPage.locator("#dashboard-content");
      await expect(dashboardContent.getByText("Events", { exact: true })).toBeVisible();

      // Open the event form from the dashboard list.
      await dashboardContent.getByRole("button", { name: "Add Event" }).click();
      await expect(organizerGroupPage.locator("#name")).toBeVisible();

      // Fill the core event details for the automatic meeting flow.
      await organizerGroupPage.locator("#name").fill(eventName);
      await organizerGroupPage.locator("#kind_id").selectOption("virtual");
      await organizerGroupPage.locator("#category_id").selectOption("33333333-3333-3333-3333-333333333331");
      await organizerGroupPage.locator("#description_short").fill("Automatic recording override coverage.");
      await fillMarkdownEditor(
        organizerGroupPage,
        "description",
        "Coverage for automatic event and session recording overrides.",
      );
      // Configure a meeting-safe capacity before selecting automatic recording.
      await setAutomaticMeetingCapacity(organizerGroupPage);

      // Fill the event schedule before configuring online recording.
      await organizerGroupPage.locator('button[data-section="date-venue"]').click();
      await selectTimezone(organizerGroupPage, "UTC");
      await organizerGroupPage.locator("#starts_at").fill(futureDate({ days: 300, hour: 10 }));
      await organizerGroupPage.locator("#ends_at").fill(futureDate({ days: 300, hour: 12 }));

      // Configure automatic meeting recording for the event.
      const eventOnlineDetails = organizerGroupPage.locator("#online-event-details");
      await eventOnlineDetails.locator('input[type="radio"][value="automatic"]').check({
        force: true,
      });
      const recordMeetingLabel = eventOnlineDetails.getByText("Record meeting", {
        exact: true,
      });
      const publishRecordingLabel = eventOnlineDetails.getByText("Publish recording publicly", {
        exact: true,
      });
      await expect(recordMeetingLabel).toBeVisible();
      await expect(publishRecordingLabel).toBeVisible();
      const [recordMeetingLabelBox, publishRecordingLabelBox] = await Promise.all([
        recordMeetingLabel.boundingBox(),
        publishRecordingLabel.boundingBox(),
      ]);
      if (!recordMeetingLabelBox || !publishRecordingLabelBox) {
        throw new Error("Recording visibility controls should be visible.");
      }
      expect(publishRecordingLabelBox.y).toBeGreaterThan(recordMeetingLabelBox.y);

      // Toggle public recording publication for the event.
      const eventRecordingPublishedInput = eventOnlineDetails.locator(
        'input[type="hidden"][name="meeting_recording_published"]',
      );
      const eventRecordingPublishedControl = eventOnlineDetails.locator("label", {
        hasText: "Publish recording publicly",
      });
      const eventRecordingPublishedToggle = eventOnlineDetails.getByLabel("Publish recording publicly");
      await expect(eventRecordingPublishedInput).toHaveValue("false");
      await expect(eventRecordingPublishedToggle).not.toBeChecked();
      await eventRecordingPublishedControl.click();
      await expect(eventRecordingPublishedToggle).toBeChecked();
      await expect(eventRecordingPublishedInput).toHaveValue("true");

      // Fill the event recording override URL.
      await eventOnlineDetails
        .locator('input[type="url"][placeholder="https://youtube.com/watch?v=..."]')
        .fill(eventRecordingUrl);

      // Add a session with its own automatic recording override.
      await organizerGroupPage.locator('button[data-section="sessions"]').click();
      const sessionsSection = organizerGroupPage.locator("sessions-section");
      const addSessionButton = sessionsSection.getByRole("button", {
        name: "Add session",
      });
      await expect(addSessionButton).toBeVisible();
      await addSessionButton.click();

      // Fill the session details inside the session modal.
      const sessionModal = organizerGroupPage.locator("session-form-modal");
      const sessionDialog = sessionModal.locator('[role="dialog"]');
      await expect(sessionDialog).toBeVisible();
      await sessionModal.locator('input[data-name="name"]').fill(sessionName);
      await sessionModal.locator('select[data-name="kind"]').selectOption("virtual");
      await sessionModal.locator('input[type="time"]').nth(0).fill("10:30");
      await sessionModal.locator('input[type="time"]').nth(1).fill("11:30");

      // Configure automatic meeting recording for the session.
      const sessionOnlineDetails = sessionModal.locator("online-event-details");
      await expect(sessionOnlineDetails).toHaveAttribute("kind", "virtual");
      await expect(sessionOnlineDetails).toHaveAttribute(
        "starts-at",
        `${futureDate({ days: 300, hour: 10 }).slice(0, 11)}10:30`,
      );
      await expect(sessionOnlineDetails).toHaveAttribute(
        "ends-at",
        `${futureDate({ days: 300, hour: 12 }).slice(0, 11)}11:30`,
      );
      await sessionOnlineDetails.getByText("Create meeting automatically", { exact: true }).click();
      await expect(sessionOnlineDetails.getByText("Meeting provider", { exact: true })).toBeVisible();
      const sessionRecordingPublishedInput = sessionOnlineDetails.locator(
        'input[type="hidden"][name="sessions[0][meeting_recording_published]"]',
      );
      const sessionRecordingPublishedControl = sessionOnlineDetails.locator("label", {
        hasText: "Publish recording publicly",
      });
      const sessionRecordingPublishedToggle = sessionOnlineDetails.getByLabel("Publish recording publicly");
      await expect(sessionRecordingPublishedInput).toHaveValue("false");
      await expect(sessionRecordingPublishedToggle).not.toBeChecked();
      await sessionRecordingPublishedControl.click();
      await expect(sessionRecordingPublishedToggle).toBeChecked();
      await expect(sessionRecordingPublishedInput).toHaveValue("true");

      // Fill the session recording override and save the session.
      await sessionOnlineDetails
        .locator('input[type="url"][placeholder="https://youtube.com/watch?v=..."]')
        .fill(sessionRecordingUrl);
      await sessionModal.getByRole("button", { name: "Add session" }).click();
      await expect(sessionDialog).toBeHidden();
      await expect(
        sessionsSection.locator('input[name="sessions[0][meeting_recording_published]"]'),
      ).toHaveValue("true");

      // Target the visible submit button after pending changes appear.
      const visibleAddEventButton = organizerGroupPage.locator(
        "#pending-changes-alert:not(.hidden) #add-event-button",
      );
      await expect(visibleAddEventButton).toBeVisible();

      // Create the event and wait for the POST response.
      await waitForActionResponse(organizerGroupPage, () => visibleAddEventButton.click(), {
        method: "POST",
        urlIncludes: "/dashboard/group/events/add",
        status: 201,
      });

      // Verify event recording values persisted on the update page.
      eventId = await waitForEventEditorAfterSave(organizerGroupPage);

      // Open date and venue details before checking event recording fields.
      await organizerGroupPage.locator('button[data-section="date-venue"]').click();
      await expect(
        eventOnlineDetails.locator('input[type="url"][placeholder="https://youtube.com/watch?v=..."]'),
      ).toHaveValue(eventRecordingUrl);
      await expect(eventOnlineDetails.getByLabel("Publish recording publicly")).toBeChecked();
      await expect(eventRecordingPublishedInput).toHaveValue("true");

      // Reopen the session and verify session recording values persisted.
      await organizerGroupPage.locator('button[data-section="sessions"]').click();
      const sessionCard = organizerGroupPage.locator("session-card").filter({
        hasText: sessionName,
      });
      await expect(sessionCard).toBeVisible();
      await sessionCard.locator('button[title="Edit"]').click();

      // Verify the reopened session keeps recording override values.
      await expect(sessionDialog).toBeVisible();
      const reopenedSessionOnlineDetails = sessionModal.locator("online-event-details");
      await expect(
        reopenedSessionOnlineDetails.locator(
          'input[type="url"][placeholder="https://youtube.com/watch?v=..."]',
        ),
      ).toHaveValue(sessionRecordingUrl);
      await expect(reopenedSessionOnlineDetails.getByLabel("Publish recording publicly")).toBeChecked();
      await expect(
        reopenedSessionOnlineDetails.locator(
          'input[type="hidden"][name="sessions[0][meeting_recording_published]"]',
        ),
      ).toHaveValue("true");
      await sessionModal.getByRole("button", { name: "Cancel" }).click();
      await expect(sessionDialog).toBeHidden();
    } finally {
      // Delete the temporary meeting event if it was created.
      if (eventId) {
        await deleteEventFromList(organizerGroupPage, eventId);
      }
    }
  });

  for (const meetingState of MEETING_STATE_CASES) {
    test(`organizer sees ${meetingState.name} automatic meeting state`, async ({ organizerGroupPage }) => {
      // Open the seeded event editor on the section that owns online meeting state.
      const onlineEventDetails = await openMeetingEventEditor(organizerGroupPage, meetingState.event);

      // Verify the automatic meeting status and details match the persisted sync state.
      await expect(onlineEventDetails.getByText(meetingState.statusText, { exact: true })).toBeVisible();
      await expect(onlineEventDetails.getByText(meetingState.expectedText, { exact: false })).toBeVisible();

      // Verify live meetings expose their join link.
      if (meetingState.event === TEST_MEETING_EVENTS.live) {
        await expect(
          onlineEventDetails.getByRole("link", { name: TEST_MEETINGS.live.joinUrl }),
        ).toHaveAttribute("href", TEST_MEETINGS.live.joinUrl);
      }
    });
  }
});

/** Opens the meeting event editor and returns the online details section. */
const openMeetingEventEditor = async (page, event) => {
  await navigateToPath(page, "/dashboard/group?tab=events&events_tab=upcoming&limit=100");
  await expect(page.locator("#upcoming-content")).toBeVisible();
  await openEventUpdateFormByName(page, event.name, event.id);

  const dateVenueSectionButton = page.locator('button[data-section="date-venue"]');
  await dateVenueSectionButton.click();
  await expect(dateVenueSectionButton).toHaveAttribute("data-active", "true");

  const onlineEventDetails = page.locator("#online-event-details");
  await expect(onlineEventDetails).toBeVisible();
  await expect(onlineEventDetails.locator('input[type="radio"][value="automatic"]')).toBeChecked();
  return onlineEventDetails;
};
