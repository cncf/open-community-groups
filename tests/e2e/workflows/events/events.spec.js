import { expect, test } from "../../fixtures.js";

import { cleanupEventsByIds } from "../../data-graphs/events.js";
import {
  TEST_COMMUNITY_NAME,
  TEST_EVENT_IDS,
  TEST_EVENT_SLUGS,
  TEST_GROUP_SLUGS,
  TEST_USER_IDS,
} from "../../seed.js";
import { deleteNotifications, expectNewNotifications, snapshotNotifications } from "../../notifications.js";

import {
  futureDate,
  navigateToPath,
  selectTimezone,
  uniqueName,
  waitForActionResponse,
} from "../../utils.js";

import {
  TEST_UPLOAD_ASSET_PATHS,
  fillEventVenue,
  fillMarkdownEditor,
  fillMultipleInputs,
  uploadGalleryImages,
  uploadImageField,
} from "../../dashboard/form-helpers.js";

import {
  openGroupEventsTabWithEvent,
  openPaymentsSection,
  waitForEventEditorAfterSave,
} from "../../dashboard/group/events/helpers.js";

import {
  editTicketType,
  enableAutomaticMeetingCreation,
  expectAutomaticMeetingControls,
  openDetailsSection,
  setAutomaticMeetingCapacity,
  setCfsLabels,
  setEventPeople,
  setRegistrationQuestions,
} from "../../dashboard/group/events/event-form-helpers.js";

const ALPHA_GROUP_EVENT_PUBLISHED_RECIPIENT_IDS = [
  TEST_USER_IDS.organizer1,
  TEST_USER_IDS.member1,
  "77777777-7777-7777-7777-777777777711",
  "77777777-7777-7777-7777-777777777712",
  "77777777-7777-7777-7777-777777777714",
  TEST_USER_IDS.checkInManager1,
];

test.describe("event management workflows", () => {
  test("organizer can create and delete an event", async ({ organizerGroupPage }) => {
    // Create a unique event name for the temporary event flow.
    const eventName = uniqueName("group event");
    let eventId;
    let notificationIds = [];

    try {
      // Load the events list before creating a temporary event.
      await navigateToPath(organizerGroupPage, "/dashboard/group?tab=events");

      // Target dashboard content after the events tab loads.
      const dashboardContent = organizerGroupPage.locator("#dashboard-content");
      await expect(dashboardContent.getByText("Events", { exact: true })).toBeVisible();

      // Open the event form from the dashboard list.
      await dashboardContent.getByRole("button", { name: "Add Event" }).click();
      await expect(organizerGroupPage.locator("#name")).toBeVisible();

      // Fill the core event details required for creation.
      await organizerGroupPage.locator("#name").fill(eventName);
      await organizerGroupPage.locator("#kind_id").selectOption("virtual");
      await organizerGroupPage.locator("#category_id").selectOption("33333333-3333-3333-3333-333333333331");
      await organizerGroupPage
        .locator("#description_short")
        .fill("A dashboard-created event from the e2e suite.");
      await fillMarkdownEditor(
        organizerGroupPage,
        "description",
        "A dashboard event created and removed by the e2e suite.",
      );

      // Configure a meeting-safe capacity before automatic meeting selection.
      await setAutomaticMeetingCapacity(organizerGroupPage);

      // Fill schedule and online meeting details.
      await organizerGroupPage.locator("button[data-section-next]").click();
      await expect(organizerGroupPage.locator('button[data-section="date-venue"]')).toHaveAttribute(
        "data-active",
        "true",
      );
      await selectTimezone(organizerGroupPage, "UTC");
      await expect(organizerGroupPage.locator("#starts_at")).toBeVisible();
      await organizerGroupPage.locator("#starts_at").fill(futureDate({ days: 70, hour: 10 }));
      await organizerGroupPage.locator("#ends_at").fill(futureDate({ days: 70, hour: 12 }));
      await enableAutomaticMeetingCreation(organizerGroupPage);

      // Target the visible submit button after pending changes appear.
      const visibleAddEventButton = organizerGroupPage.locator(
        "#pending-changes-alert:not(.hidden) #add-event-button",
      );
      await expect(organizerGroupPage.locator("#pending-changes-alert")).not.toHaveClass(/hidden/);
      await expect(visibleAddEventButton).toBeVisible();

      // Create the event and wait for the POST response.
      await waitForActionResponse(organizerGroupPage, () => visibleAddEventButton.click(), {
        method: "POST",
        urlIncludes: "/dashboard/group/events/add",
        status: 201,
      });

      // Verify the first save opens the new draft's update page.
      eventId = await waitForEventEditorAfterSave(organizerGroupPage);
      await expect(organizerGroupPage.locator(".swal2-popup")).toContainText(
        "You have successfully created the event.",
      );

      // Verify online details persisted on the update page.
      await organizerGroupPage.locator('button[data-section="date-venue"]').click();

      // Verify the correct online meeting state persisted.
      await expectAutomaticMeetingControls(organizerGroupPage);
      await expect(
        organizerGroupPage.locator('online-event-details input[name="meeting_requested"]'),
      ).toHaveValue("true");

      // Publish the draft and assert group member/team fan-out before deleting it.
      let eventRow = await openGroupEventsTabWithEvent(organizerGroupPage, eventName);
      await eventRow.locator(".btn-actions").click();
      const publishButton = eventRow.locator('button[id^="publish-event-"]');
      await expect(publishButton).toBeVisible();
      const snapshot = snapshotNotifications();
      await publishButton.click();
      await waitForActionResponse(
        organizerGroupPage,
        () => organizerGroupPage.getByRole("button", { name: "Yes" }).click(),
        {
          method: "PUT",
          urlIncludes: `/dashboard/group/events/${eventId}/publish`,
        },
      );
      notificationIds = expectNewNotifications(snapshot, [
        {
          kind: "event-published",
          templateDataContains: { event: { event_id: eventId } },
          userIds: ALPHA_GROUP_EVENT_PUBLISHED_RECIPIENT_IDS,
        },
      ]);
      await expect(eventRow).toContainText("Published");

      // Unpublishing keeps the event editable, but published history still requires cancellation before deletion.
      await eventRow.locator(".btn-actions").click();
      const unpublishButton = eventRow.locator('button[id^="unpublish-event-"]');
      await expect(unpublishButton).toBeVisible();
      await unpublishButton.click();
      await waitForActionResponse(
        organizerGroupPage,
        () => organizerGroupPage.getByRole("button", { name: "Yes" }).click(),
        {
          method: "PUT",
          urlIncludes: `/dashboard/group/events/${eventId}/unpublish`,
        },
      );

      // Cancel the previously published event so its delete action is enabled.
      eventRow = await openGroupEventsTabWithEvent(organizerGroupPage, eventName);
      await eventRow.locator(".btn-actions").click();
      const cancelButton = eventRow.locator('button[id^="cancel-event-"]');
      await expect(cancelButton).toBeVisible();
      await cancelButton.click();
      await waitForActionResponse(
        organizerGroupPage,
        () => organizerGroupPage.getByRole("button", { name: "Cancel event" }).click(),
        {
          method: "PUT",
          urlIncludes: `/dashboard/group/events/${eventId}/cancel`,
        },
      );

      // Open the delete confirmation for the temporary event.
      eventRow = await openGroupEventsTabWithEvent(organizerGroupPage, eventName);
      await eventRow.locator(".btn-actions").click();
      const deleteButton = eventRow.locator('button[id^="delete-event-"]');
      await expect(deleteButton).toBeEnabled();
      await deleteButton.click();
      await expect(organizerGroupPage.locator(".swal2-popup")).toContainText(
        "Delete this event? This removes it from the dashboard and cannot be undone.",
      );

      // Confirm deletion and wait for the server response.
      await waitForActionResponse(
        organizerGroupPage,
        () => organizerGroupPage.getByRole("button", { name: "Yes" }).click(),
        {
          method: "DELETE",
          urlIncludes: `/dashboard/group/events/${eventId}/delete`,
        },
      );

      // Verify the deleted event is removed from the list.
      await expect(dashboardContent.locator("tr", { hasText: eventName })).toHaveCount(0);
    } finally {
      // Remove publish notifications and any remaining temporary event.
      deleteNotifications(notificationIds);
      if (eventId) {
        cleanupEventsByIds([eventId]);
      }
    }
  });

  test("organizer can create, update, and delete an event with images and rich fields", async ({
    organizerGroupPage,
  }) => {
    const initialEventName = uniqueName("rich event");
    const updatedEventName = uniqueName("rich event updated");
    let eventId;

    // Define rich event values for the create and update flow.
    const initialValues = {
      bannerMobilePath: TEST_UPLOAD_ASSET_PATHS.bannerMobile,
      bannerPath: TEST_UPLOAD_ASSET_PATHS.banner,
      seatsTotal: "120",
      categoryId: "33333333-3333-3333-3333-333333333331",
      cfsDescription: "Initial speaker program details for a temporary event.",
      cfsEndsAt: "2030-09-20T17:00",
      cfsLabels: ["track / platform"],
      cfsStartsAt: "2030-09-01T09:00",
      description: "Initial full description for a temporary event with rich form coverage.",
      descriptionShort: "Initial temporary event for rich update coverage.",
      endsAt: "2030-10-05T13:30",
      eventReminderEnabled: true,
      galleryPaths: [TEST_UPLOAD_ASSET_PATHS.galleryOne],
      hosts: [
        {
          name: "E2E Member Two",
          user_id: TEST_USER_IDS.member2,
          username: "e2e-member-2",
        },
      ],
      kindId: "hybrid",
      logoPath: TEST_UPLOAD_ASSET_PATHS.logo,
      lumaUrl: "https://luma.com/e2e-rich-event-initial",
      meetupUrl: "https://meetup.com/e2e-rich-event-initial",
      meetingJoinUrl: "https://meet.example.com/e2e-rich-event-initial",
      meetingRecordingUrl: "https://video.example.com/e2e-rich-event-initial",
      name: initialEventName,
      registrationQuestions: [
        {
          id: "99999999-0000-4000-8000-000000000001",
          kind: "free-text",
          options: [],
          prompt: "What do you want to learn?",
          required: true,
        },
      ],
      startsAt: "2030-10-05T10:00",
      speakers: [
        {
          featured: true,
          name: "E2E Pending One",
          user_id: TEST_USER_IDS.pending1,
          username: "e2e-pending-1",
        },
      ],
      tags: ["meetup", "platform"],
      testEvent: true,
      timezone: "UTC",
      venueAddress: "123 Platform Street",
      venueCity: "Barcelona",
      venueCountryCode: "ES",
      venueCountryName: "Spain",
      venueLatitude: "41.3874",
      venueLongitude: "2.1686",
      venueName: "Platform Hall",
      venueState: "Catalonia",
      venueStateCode: "CT",
      venueZipCode: "08001",
      attendeeApprovalRequired: false,
      waitlistEnabled: true,
    };
    const updatedValues = {
      bannerMobilePath: TEST_UPLOAD_ASSET_PATHS.bannerMobile,
      bannerPath: TEST_UPLOAD_ASSET_PATHS.banner,
      seatsTotal: "180",
      categoryId: "33333333-3333-3333-3333-333333333331",
      cfsDescription: "Updated speaker program details for a temporary event.",
      cfsEndsAt: "2030-09-24T18:00",
      cfsLabels: ["track / devex", "track / cloud"],
      cfsStartsAt: "2030-09-03T10:30",
      description: "Updated full description for a temporary event with rich form coverage.",
      descriptionShort: "Updated temporary event for rich update coverage.",
      endsAt: "2030-10-08T18:00",
      eventReminderEnabled: false,
      galleryPaths: [TEST_UPLOAD_ASSET_PATHS.galleryTwo],
      hosts: [
        {
          name: "E2E Pending Two",
          user_id: TEST_USER_IDS.pending2,
          username: "e2e-pending-2",
        },
      ],
      kindId: "hybrid",
      logoPath: TEST_UPLOAD_ASSET_PATHS.logo,
      lumaUrl: "https://luma.com/e2e-rich-event-updated",
      meetupUrl: "https://meetup.com/e2e-rich-event-updated",
      meetingJoinUrl: "https://meet.example.com/e2e-rich-event-updated",
      meetingRecordingUrl: "https://video.example.com/e2e-rich-event-updated",
      name: updatedEventName,
      registrationQuestions: [
        {
          id: "99999999-0000-4000-8000-000000000002",
          kind: "single-select",
          options: [
            {
              id: "99999999-0000-4000-8000-000000000003",
              label: "Platform engineering",
            },
            {
              id: "99999999-0000-4000-8000-000000000004",
              label: "Developer experience",
            },
          ],
          prompt: "Which track are you most interested in?",
          required: true,
        },
      ],
      startsAt: "2030-10-08T14:00",
      speakers: [
        {
          featured: false,
          name: "E2E Member Two",
          user_id: TEST_USER_IDS.member2,
          username: "e2e-member-2",
        },
      ],
      tags: ["conference", "cloud"],
      testEvent: false,
      timezone: "Europe/Madrid",
      venueAddress: "456 Cloud Avenue",
      venueCity: "Madrid",
      venueCountryCode: "ES",
      venueCountryName: "Spain",
      venueLatitude: "40.4168",
      venueLongitude: "-3.7038",
      venueName: "Cloud Forum",
      venueState: "Community of Madrid",
      venueStateCode: "MD",
      venueZipCode: "28001",
      attendeeApprovalRequired: true,
      waitlistEnabled: false,
    };

    // Fill every rich event field used by create and update flows.
    const fillEventForm = async (values) => {
      await openDetailsSection(organizerGroupPage);
      await organizerGroupPage.locator("#name").fill(values.name);
      await organizerGroupPage.locator("#kind_id").selectOption(values.kindId);
      await organizerGroupPage.locator("#category_id").selectOption(values.categoryId);
      await uploadImageField(organizerGroupPage, "logo_url", values.logoPath);
      await uploadImageField(organizerGroupPage, "banner_url", values.bannerPath);
      await uploadImageField(organizerGroupPage, "banner_mobile_url", values.bannerMobilePath);
      await organizerGroupPage.locator("#description_short").fill(values.descriptionShort);
      await fillMarkdownEditor(organizerGroupPage, "description", values.description);
      await openPaymentsSection(organizerGroupPage);
      await editTicketType(organizerGroupPage, "General Admission", {
        description: "Default free admission tier.",
        seatsTotal: values.seatsTotal,
        title: "General Admission",
      });
      await openDetailsSection(organizerGroupPage);
      if (values.testEvent) {
        await organizerGroupPage.locator("#toggle_test_event").check({ force: true });
      } else {
        await organizerGroupPage.locator("#toggle_test_event").uncheck({ force: true });
      }
      if (values.waitlistEnabled) {
        await organizerGroupPage.locator("#toggle_waitlist_enabled").check({ force: true });
      } else {
        await organizerGroupPage.locator("#toggle_waitlist_enabled").uncheck({ force: true });
      }
      if (values.attendeeApprovalRequired) {
        await organizerGroupPage.locator("#toggle_attendee_approval_required").check({ force: true });
      } else {
        await organizerGroupPage.locator("#toggle_attendee_approval_required").uncheck({ force: true });
      }
      await organizerGroupPage.locator("#meetup_url").fill(values.meetupUrl);
      await organizerGroupPage.locator("#luma_url").fill(values.lumaUrl);
      await fillMultipleInputs(organizerGroupPage.locator('multiple-inputs[field-name="tags"]'), values.tags);
      await uploadGalleryImages(organizerGroupPage, "photos_urls", values.galleryPaths);

      // Fill registration questions for this values set.
      await organizerGroupPage.locator('button[data-section="questions"]').click({ force: true });
      await setRegistrationQuestions(organizerGroupPage, values.registrationQuestions);

      // Fill hosts and speakers for this values set.
      await organizerGroupPage.locator('button[data-section="hosts-sponsors"]').click({ force: true });
      await setEventPeople(organizerGroupPage, values);

      // Fill date, venue, and meeting details for this values set.
      await organizerGroupPage.locator('button[data-section="date-venue"]').click({
        force: true,
      });
      await selectTimezone(organizerGroupPage, values.timezone);
      await organizerGroupPage.locator("#starts_at").fill(values.startsAt);
      await organizerGroupPage.locator("#ends_at").fill(values.endsAt);
      if (values.eventReminderEnabled) {
        await organizerGroupPage.locator("#toggle_event_reminder_enabled").check({ force: true });
      } else {
        await organizerGroupPage.locator("#toggle_event_reminder_enabled").uncheck({ force: true });
      }
      await fillEventVenue(organizerGroupPage, {
        address: values.venueAddress,
        city: values.venueCity,
        countryCode: values.venueCountryCode,
        countryName: values.venueCountryName,
        latitude: values.venueLatitude,
        longitude: values.venueLongitude,
        name: values.venueName,
        state: values.venueState,
        stateCode: values.venueStateCode,
        zipCode: values.venueZipCode,
      });
      await organizerGroupPage.locator("#meeting_join_url").fill(values.meetingJoinUrl);
      await organizerGroupPage.locator("#meeting_recording_url").fill(values.meetingRecordingUrl);

      // Fill CFS fields for this values set.
      const cfsSectionButton = organizerGroupPage.locator('button[data-section="cfs"]');
      await cfsSectionButton.scrollIntoViewIfNeeded();
      await cfsSectionButton.click({ force: true });
      await organizerGroupPage.locator("#toggle_cfs_enabled").check({ force: true });
      await organizerGroupPage.locator("#cfs_starts_at").fill(values.cfsStartsAt, {
        force: true,
      });
      await organizerGroupPage.locator("#cfs_ends_at").fill(values.cfsEndsAt, {
        force: true,
      });
      await fillMarkdownEditor(organizerGroupPage, "cfs_description", values.cfsDescription);
      await setCfsLabels(organizerGroupPage, values.cfsLabels);
    };

    try {
      // Load the events list before opening the rich event form.
      await navigateToPath(organizerGroupPage, "/dashboard/group?tab=events");

      // Target dashboard content after the events tab loads.
      const dashboardContent = organizerGroupPage.locator("#dashboard-content");
      await expect(dashboardContent.getByText("Events", { exact: true })).toBeVisible();

      // Open the event form from the dashboard list.
      await dashboardContent.getByRole("button", { name: "Add Event" }).click();
      await expect(organizerGroupPage.locator("#name")).toBeVisible();

      // Create the temporary event with the initial rich values.
      await fillEventForm(initialValues);

      // Target the visible submit button after pending changes appear.
      const addEventButton = organizerGroupPage.locator(
        "#pending-changes-alert:not(.hidden) #add-event-button",
      );
      await expect(addEventButton).toBeVisible();

      // Submit the rich event and wait for the created response.
      await waitForActionResponse(organizerGroupPage, () => addEventButton.click(), {
        method: "POST",
        urlIncludes: "/dashboard/group/events/add",
        status: 201,
      });

      // The first save opens the new draft so later edits stay on the editor.
      eventId = await waitForEventEditorAfterSave(organizerGroupPage);

      // Update the event with the second set of rich values.
      await fillEventForm(updatedValues);

      // Submit the update and wait for the editor to reload from the follow-up GET.
      await waitForEventEditorAfterSave(
        organizerGroupPage,
        () => organizerGroupPage.locator("#update-event-button").click(),
        {
          eventId,
          method: "PUT",
          urlIncludes: `/dashboard/group/events/${eventId}/update`,
        },
      );

      // Verify the rich values persisted on the same update page.
      await expect(organizerGroupPage.locator("#name")).toHaveValue(updatedValues.name);
      await expect(organizerGroupPage.locator("#kind_id")).toHaveValue(updatedValues.kindId);
      await expect(organizerGroupPage.locator("#category_id")).toHaveValue(updatedValues.categoryId);
      await expect
        .poll(async () => (await organizerGroupPage.locator("#description_short").inputValue()).trim())
        .toBe(updatedValues.descriptionShort);
      await openPaymentsSection(organizerGroupPage);
      const generalAdmissionRow = organizerGroupPage
        .locator('#ticket-types-ui [data-ticketing-role="table-body"] tr')
        .filter({ hasText: "General Admission" });
      await expect(generalAdmissionRow).toContainText(updatedValues.seatsTotal);
      await expect(organizerGroupPage.locator("#test_event")).toHaveValue(String(updatedValues.testEvent));
      await expect(organizerGroupPage.locator("#attendee_approval_required")).toHaveValue(
        String(updatedValues.attendeeApprovalRequired),
      );
      await expect(organizerGroupPage.locator("#waitlist_enabled")).toHaveValue(
        String(updatedValues.waitlistEnabled),
      );
      await expect(organizerGroupPage.locator("#meetup_url")).toHaveValue(updatedValues.meetupUrl);
      await expect(organizerGroupPage.locator("#luma_url")).toHaveValue(updatedValues.lumaUrl);
      await expect(
        organizerGroupPage.locator('image-field[name="logo_url"] input[name="logo_url"]'),
      ).toHaveValue(/\/images\//);
      await expect(
        organizerGroupPage.locator('image-field[name="banner_url"] input[name="banner_url"]'),
      ).toHaveValue(/\/images\//);
      await expect(
        organizerGroupPage.locator('image-field[name="banner_mobile_url"] input[name="banner_mobile_url"]'),
      ).toHaveValue(/\/images\//);
      await expect(
        organizerGroupPage.locator('multiple-inputs[field-name="tags"] input[name="tags[]"]'),
      ).toHaveCount(updatedValues.tags.length);
      await organizerGroupPage.locator('button[data-section="questions"]').click();
      await expect(
        organizerGroupPage.locator('questions-editor input[name="registration_questions[0][prompt]"]'),
      ).toHaveValue(updatedValues.registrationQuestions[0].prompt);
      await expect(
        organizerGroupPage.locator(
          'questions-editor input[name="registration_questions[0][options][0][label]"]',
        ),
      ).toHaveValue(updatedValues.registrationQuestions[0].options[0].label);
      await organizerGroupPage.locator('button[data-section="hosts-sponsors"]').click();
      await expect(
        organizerGroupPage.locator('user-search-selector[field-name="hosts"] input[name="hosts[]"]'),
      ).toHaveValue(updatedValues.hosts[0].user_id);
      await expect(
        organizerGroupPage.locator(
          'speakers-selector[field-name-prefix="speakers"] input[name="speakers[0][user_id]"]',
        ),
      ).toHaveValue(updatedValues.speakers[0].user_id);
      await expect(
        organizerGroupPage.locator(
          'speakers-selector[field-name-prefix="speakers"] input[name="speakers[0][featured]"]',
        ),
      ).toHaveValue(String(updatedValues.speakers[0].featured));
      await organizerGroupPage.locator('button[data-section="date-venue"]').click();
      await expect(organizerGroupPage.locator('input[name="timezone"]')).toHaveValue(updatedValues.timezone);
      await expect(organizerGroupPage.locator("#starts_at")).toHaveValue(updatedValues.startsAt);
      await expect(organizerGroupPage.locator("#ends_at")).toHaveValue(updatedValues.endsAt);
      await expect(organizerGroupPage.locator("#event_reminder_enabled")).toHaveValue(
        String(updatedValues.eventReminderEnabled),
      );
      await expect(organizerGroupPage.locator("#location-search-venue_name")).toHaveValue(
        updatedValues.venueName,
      );
      await expect(organizerGroupPage.locator("#location-search-venue_address")).toHaveValue(
        updatedValues.venueAddress,
      );
      await expect(organizerGroupPage.locator("#location-search-venue_city")).toHaveValue(
        updatedValues.venueCity,
      );
      await expect(organizerGroupPage.locator("#location-search-venue_state_name")).toHaveValue(
        updatedValues.venueState,
      );
      await expect(organizerGroupPage.locator("#location-search-venue_state_code")).toHaveValue(
        updatedValues.venueStateCode,
      );
      await expect(organizerGroupPage.locator("#location-search-venue_country_name")).toHaveValue(
        updatedValues.venueCountryName,
      );
      await expect(organizerGroupPage.locator("#location-search-venue_country_code")).toHaveValue(
        updatedValues.venueCountryCode,
      );
      await expect(organizerGroupPage.locator("#meeting_join_url")).toHaveValue(updatedValues.meetingJoinUrl);
      await expect(organizerGroupPage.locator("#meeting_recording_url")).toHaveValue(
        updatedValues.meetingRecordingUrl,
      );
      await organizerGroupPage.locator('button[data-section="cfs"]').click();
      await expect(organizerGroupPage.locator("#cfs_enabled")).toHaveValue("true");
      await expect(organizerGroupPage.locator("#cfs_starts_at")).toHaveValue(updatedValues.cfsStartsAt);
      await expect(organizerGroupPage.locator("#cfs_ends_at")).toHaveValue(updatedValues.cfsEndsAt);
      await expect(organizerGroupPage.locator('cfs-labels-editor input[name$="[name]"]')).toHaveCount(
        updatedValues.cfsLabels.length,
      );
      await expect(
        organizerGroupPage.locator('gallery-field[field-name="photos_urls"] input[name="photos_urls[]"]'),
      ).toHaveCount(initialValues.galleryPaths.length + updatedValues.galleryPaths.length);

      // Delete the temporary event to keep the seeded list reusable.
      const eventRow = await openGroupEventsTabWithEvent(organizerGroupPage, updatedValues.name);

      // Open the actions menu for the updated temporary event.
      await eventRow.locator(".btn-actions").click();

      // Target the delete action for the temporary event.
      const deleteButton = eventRow.locator('button[id^="delete-event-"]');
      await expect(deleteButton).toBeEnabled();
      await deleteButton.click();
      await expect(organizerGroupPage.locator(".swal2-popup")).toContainText(
        "Delete this event? This removes it from the dashboard and cannot be undone.",
      );

      // Confirm deletion and wait for the server response.
      await waitForActionResponse(
        organizerGroupPage,
        () => organizerGroupPage.getByRole("button", { name: "Yes" }).click(),
        {
          method: "DELETE",
          urlIncludes: "/dashboard/group/events/",
          urlEndsWith: "/delete",
        },
      );

      // Verify the deleted event is removed from the list.
      await expect(dashboardContent.locator("tr", { hasText: updatedValues.name })).toHaveCount(0);
    } finally {
      // Remove any remaining temporary rich event.
      if (eventId) {
        cleanupEventsByIds([eventId]);
      }
    }
  });

  test("organizer can update and restore event fields across multiple tabs", async ({
    organizerGroupPage,
  }) => {
    // Target the seeded CFS event that can be restored after updates.
    const cfsSummitPath = `/${TEST_COMMUNITY_NAME}/group/${TEST_GROUP_SLUGS.community1.alpha}/event/${TEST_EVENT_SLUGS.alphaDashboard[0]}`;

    // Shift date-time fixture values while preserving input field format.
    const shiftDateTimeLocalMinutes = (value, minutes) => {
      const shiftedDate = new Date(`${value}:00Z`);
      shiftedDate.setUTCMinutes(shiftedDate.getUTCMinutes() + minutes);

      // Return the shifted value in datetime-local format.
      return shiftedDate.toISOString().slice(0, 16);
    };

    // Open the seeded CFS summit editor from the events list.
    const openCfsSummitEditor = async () => {
      await navigateToPath(organizerGroupPage, "/dashboard/group?tab=events");

      // Locate the seeded CFS summit row in the events list.
      const eventRow = organizerGroupPage.locator("tr").filter({
        has: organizerGroupPage.locator(`a[href="${cfsSummitPath}"]`),
      });
      await expect(eventRow).toBeVisible();

      // Open the seeded CFS summit editor and wait for update content.
      await waitForActionResponse(
        organizerGroupPage,
        () =>
          eventRow
            .locator(`td button[hx-get="/dashboard/group/events/${TEST_EVENT_IDS.alpha.cfsSummit}/update"]`)
            .click(),
        {
          method: "GET",
          urlIncludes: `/dashboard/group/events/${TEST_EVENT_IDS.alpha.cfsSummit}/update`,
        },
      );
    };

    // Read editable values from the seeded CFS summit form.
    const readEventValues = async () => {
      await openCfsSummitEditor();

      // Return the editable values needed for update and restore.
      return {
        cfsEndsAt: await organizerGroupPage.locator("#cfs_ends_at").inputValue(),
        cfsStartsAt: await organizerGroupPage.locator("#cfs_starts_at").inputValue(),
        endsAt: await organizerGroupPage.locator("#ends_at").inputValue(),
        meetupUrl: await organizerGroupPage.locator("#meetup_url").inputValue(),
        name: await organizerGroupPage.locator("#name").inputValue(),
        startsAt: await organizerGroupPage.locator("#starts_at").inputValue(),
      };
    };

    // Save editable values across the details, date, and CFS tabs.
    const saveUpdatedValues = async (values) => {
      await openCfsSummitEditor();

      // Fill detail values in the first form tab.
      await organizerGroupPage.locator("#name").fill(values.name);
      await organizerGroupPage.locator("#meetup_url").fill(values.meetupUrl);

      // Fill date values in the date and venue tab.
      await organizerGroupPage.locator("button[data-section-next]").click();
      await expect(organizerGroupPage.locator('button[data-section="date-venue"]')).toHaveAttribute(
        "data-active",
        "true",
      );
      await expect(organizerGroupPage.locator("#starts_at")).toBeVisible();
      await organizerGroupPage.locator("#starts_at").fill(values.startsAt);
      await organizerGroupPage.locator("#ends_at").fill(values.endsAt);

      // Fill CFS values in the CFS tab.
      await organizerGroupPage.locator('button[data-section="cfs"]').click();
      await expect(organizerGroupPage.locator("#cfs_starts_at")).toBeVisible();
      await organizerGroupPage.locator("#cfs_starts_at").fill(values.cfsStartsAt);
      await organizerGroupPage.locator("#cfs_ends_at").fill(values.cfsEndsAt);
      await expect(organizerGroupPage.locator("#pending-changes-alert")).not.toHaveClass(/hidden/);

      // Submit the seeded event update and wait for the server response.
      await waitForActionResponse(
        organizerGroupPage,
        () => organizerGroupPage.locator("#update-event-button").click(),
        {
          method: "PUT",
          urlIncludes: `/dashboard/group/events/${TEST_EVENT_IDS.alpha.cfsSummit}/update`,
        },
      );
    };

    // Read the original seeded values before mutating the event.
    const originalValues = await readEventValues();

    // Build updated values relative to the original seeded values.
    const updatedValues = {
      cfsEndsAt: shiftDateTimeLocalMinutes(originalValues.cfsEndsAt, 60),
      cfsStartsAt: shiftDateTimeLocalMinutes(originalValues.cfsStartsAt, 60),
      endsAt: shiftDateTimeLocalMinutes(originalValues.endsAt, -30),
      meetupUrl: "https://meetup.com/e2e-alpha-cfs-summit",
      name: uniqueName("event with active cfs"),
      startsAt: shiftDateTimeLocalMinutes(originalValues.startsAt, 30),
    };

    try {
      // Update the seeded event across the details, date, and CFS tabs.
      await saveUpdatedValues(updatedValues);

      // Reopen the event and verify updated values persisted.
      await openCfsSummitEditor();
      await expect(organizerGroupPage.locator("#name")).toHaveValue(updatedValues.name);
      await expect(organizerGroupPage.locator("#meetup_url")).toHaveValue(updatedValues.meetupUrl);
      await organizerGroupPage.locator('button[data-section="date-venue"]').click();
      await expect(organizerGroupPage.locator("#starts_at")).toHaveValue(updatedValues.startsAt);
      await expect(organizerGroupPage.locator("#ends_at")).toHaveValue(updatedValues.endsAt);
      await organizerGroupPage.locator('button[data-section="cfs"]').click();
      await expect(organizerGroupPage.locator("#cfs_starts_at")).toHaveValue(updatedValues.cfsStartsAt);
      await expect(organizerGroupPage.locator("#cfs_ends_at")).toHaveValue(updatedValues.cfsEndsAt);
    } finally {
      // Restore the seeded event to its original values.
      await saveUpdatedValues(originalValues);
    }
  });

  test("organizer is warned before removing dates from an event with sessions", async ({
    organizerGroupPage,
  }) => {
    // Target the seeded event with sessions before removing its dates.
    const alphaEventPath = `/${TEST_COMMUNITY_NAME}/group/${TEST_GROUP_SLUGS.community1.alpha}/event/${TEST_EVENT_SLUGS.alpha[0]}`;

    // Load the seeded event with sessions before removing dates.
    await navigateToPath(organizerGroupPage, "/dashboard/group?tab=events");

    // Target the seeded event row with sessions.
    const eventRow = organizerGroupPage.locator("tr").filter({
      has: organizerGroupPage.locator(`a[href="${alphaEventPath}"]`),
    });
    await expect(eventRow).toBeVisible();

    // Open the seeded event editor and wait for update content.
    await waitForActionResponse(
      organizerGroupPage,
      () =>
        eventRow
          .locator(`td button[hx-get="/dashboard/group/events/${TEST_EVENT_IDS.alpha.one}/update"]`)
          .click(),
      {
        method: "GET",
        urlIncludes: `/dashboard/group/events/${TEST_EVENT_IDS.alpha.one}/update`,
      },
    );

    // Remove dates from the event to trigger the sessions warning.
    await organizerGroupPage.locator('button[data-section="date-venue"]').click();
    await expect(organizerGroupPage.locator("#starts_at")).toBeVisible();
    await organizerGroupPage.locator("#starts_at").fill("");
    await organizerGroupPage.locator("#ends_at").fill("");

    // Verify pending changes are visible before submitting.
    await expect(organizerGroupPage.locator("#pending-changes-alert")).not.toHaveClass(/hidden/);

    // Submit the update to trigger the sessions warning.
    await organizerGroupPage.locator("#update-event-button").click();

    // Verify the session removal warning is shown before saving.
    const confirmationDialog = organizerGroupPage.locator(".swal2-popup");
    await expect(confirmationDialog).toContainText(
      "Saving this event without start and end dates will remove all sessions.",
    );

    // Cancel the warning so the seeded event remains unchanged.
    await confirmationDialog.getByRole("button", { name: "No" }).click();
  });
});
