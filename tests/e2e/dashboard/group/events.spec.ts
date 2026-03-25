import type { Locator } from "@playwright/test";

import { expect, test } from "../../fixtures";

import {
  TEST_COMMUNITY_NAME,
  TEST_EVENT_IDS,
  TEST_EVENT_SLUGS,
  TEST_GROUP_SLUGS,
  navigateToPath,
  selectTimezone,
} from "../../utils";
import {
  TEST_UPLOAD_ASSET_PATHS,
  fillEventVenue,
  fillMarkdownEditor,
  fillMultipleInputs,
  uploadGalleryImages,
  uploadImageField,
} from "../form-helpers";

test.describe("group dashboard events views", () => {
  test("organizer can create and delete an event", async ({ organizerGroupPage }) => {
    const eventName = `E2E Group Event ${Date.now()}`;

    await navigateToPath(organizerGroupPage, "/dashboard/group?tab=events");

    const dashboardContent = organizerGroupPage.locator("#dashboard-content");
    await expect(dashboardContent.getByText("Events", { exact: true })).toBeVisible();

    await dashboardContent.getByRole("button", { name: "Add Event" }).click();
    await expect(organizerGroupPage.locator("#name")).toBeVisible();

    await organizerGroupPage.locator("#name").fill(eventName);
    await organizerGroupPage.locator("#kind_id").selectOption("virtual");
    await organizerGroupPage
      .locator("#category_id")
      .selectOption("33333333-3333-3333-3333-333333333331");
    await organizerGroupPage.locator("#description_short").fill(
      "A dashboard-created event from the e2e suite.",
    );
    await organizerGroupPage
      .locator('markdown-editor#description .CodeMirror textarea')
      .fill("A dashboard event created and removed by the e2e suite.");
    await organizerGroupPage.locator('button[data-section="date-venue"]').click();
    await selectTimezone(organizerGroupPage, "UTC");
    await expect(organizerGroupPage.locator("#starts_at")).toBeVisible();
    await organizerGroupPage.locator("#starts_at").fill("2030-05-10T10:00");
    await organizerGroupPage.locator("#ends_at").fill("2030-05-10T12:00");
    await organizerGroupPage.locator("#meeting_join_url").fill(
      "https://meet.example.com/e2e-created-event",
    );
    const visibleAddEventButton = organizerGroupPage.locator(
      "#pending-changes-alert:not(.hidden) #add-event-button",
    );
    await expect(organizerGroupPage.locator("#pending-changes-alert")).not.toHaveClass(
      /hidden/,
    );
    await expect(visibleAddEventButton).toBeVisible();

    await Promise.all([
      organizerGroupPage.waitForResponse(
        (response) =>
          response.request().method() === "POST" &&
          response.url().includes("/dashboard/group/events/add") &&
          response.status() === 201,
      ),
      visibleAddEventButton.click(),
    ]);

    const eventRow = dashboardContent.locator("tr", { hasText: eventName });
    await expect(eventRow).toBeVisible();

    await eventRow.locator(".btn-actions").click();

    const deleteButton = eventRow.locator('button[id^="delete-event-"]');
    await expect(deleteButton).toBeVisible();

    await Promise.all([
      organizerGroupPage.waitForResponse(
        (response) =>
          response.request().method() === "DELETE" &&
          response.url().includes("/dashboard/group/events/") &&
          response.url().includes("/delete") &&
          response.ok(),
      ),
      deleteButton.click(),
      organizerGroupPage.getByRole("button", { name: "Yes" }).click(),
    ]);

    await expect(dashboardContent.locator("tr", { hasText: eventName })).toHaveCount(0);
  });

  test("organizer can create, update, and delete an event with images and rich fields", async ({
    organizerGroupPage,
  }) => {
    const initialValues = {
      bannerMobilePath: TEST_UPLOAD_ASSET_PATHS.bannerMobile,
      bannerPath: TEST_UPLOAD_ASSET_PATHS.banner,
      capacity: "120",
      categoryId: "33333333-3333-3333-3333-333333333331",
      cfsDescription:
        "Initial speaker program details for a temporary event.",
      cfsEndsAt: "2030-09-20T17:00",
      cfsLabels: ["track / platform"],
      cfsStartsAt: "2030-09-01T09:00",
      description:
        "Initial full description for a temporary event with rich form coverage.",
      descriptionShort: "Initial temporary event for rich update coverage.",
      endsAt: "2030-10-05T13:30",
      eventReminderEnabled: true,
      galleryPaths: [TEST_UPLOAD_ASSET_PATHS.galleryOne],
      kindId: "hybrid",
      logoPath: TEST_UPLOAD_ASSET_PATHS.logo,
      meetupUrl: "https://meetup.com/e2e-rich-event-initial",
      meetingJoinUrl: "https://meet.example.com/e2e-rich-event-initial",
      meetingRecordingUrl: "https://video.example.com/e2e-rich-event-initial",
      name: `E2E Rich Event ${Date.now()}`,
      registrationRequired: true,
      startsAt: "2030-10-05T10:00",
      tags: ["meetup", "platform"],
      timezone: "UTC",
      venueAddress: "123 Platform Street",
      venueCity: "Barcelona",
      venueLatitude: "41.3874",
      venueLongitude: "2.1686",
      venueName: "Platform Hall",
      venueZipCode: "08001",
      waitlistEnabled: true,
    };
    const updatedValues = {
      bannerMobilePath: TEST_UPLOAD_ASSET_PATHS.bannerMobile,
      bannerPath: TEST_UPLOAD_ASSET_PATHS.banner,
      capacity: "180",
      categoryId: "33333333-3333-3333-3333-333333333333",
      cfsDescription:
        "Updated speaker program details for a temporary event.",
      cfsEndsAt: "2030-09-24T18:00",
      cfsLabels: ["track / devex", "track / cloud"],
      cfsStartsAt: "2030-09-03T10:30",
      description:
        "Updated full description for a temporary event with rich form coverage.",
      descriptionShort: "Updated temporary event for rich update coverage.",
      endsAt: "2030-10-08T18:00",
      eventReminderEnabled: false,
      galleryPaths: [TEST_UPLOAD_ASSET_PATHS.galleryTwo],
      kindId: "hybrid",
      logoPath: TEST_UPLOAD_ASSET_PATHS.logo,
      meetupUrl: "https://meetup.com/e2e-rich-event-updated",
      meetingJoinUrl: "https://meet.example.com/e2e-rich-event-updated",
      meetingRecordingUrl: "https://video.example.com/e2e-rich-event-updated",
      name: `E2E Rich Event Updated ${Date.now()}`,
      registrationRequired: false,
      startsAt: "2030-10-08T14:00",
      tags: ["conference", "cloud"],
      timezone: "Europe/Madrid",
      venueAddress: "456 Cloud Avenue",
      venueCity: "Madrid",
      venueLatitude: "40.4168",
      venueLongitude: "-3.7038",
      venueName: "Cloud Forum",
      venueZipCode: "28001",
      waitlistEnabled: false,
    };

    const fillEventForm = async (values: typeof initialValues) => {
      await organizerGroupPage.locator("#name").fill(values.name);
      await organizerGroupPage.locator("#kind_id").selectOption(values.kindId);
      await organizerGroupPage.locator("#category_id").selectOption(values.categoryId);
      await uploadImageField(organizerGroupPage, "logo_url", values.logoPath);
      await uploadImageField(organizerGroupPage, "banner_url", values.bannerPath);
      await uploadImageField(
        organizerGroupPage,
        "banner_mobile_url",
        values.bannerMobilePath,
      );
      await organizerGroupPage.locator("#description_short").fill(values.descriptionShort);
      await fillMarkdownEditor(organizerGroupPage, "description", values.description);
      await organizerGroupPage.locator("#capacity").fill(values.capacity);
      if (values.registrationRequired) {
        await organizerGroupPage
          .locator("#toggle_registration_required")
          .check({ force: true });
      } else {
        await organizerGroupPage
          .locator("#toggle_registration_required")
          .uncheck({ force: true });
      }
      if (values.waitlistEnabled) {
        await organizerGroupPage.locator("#toggle_waitlist_enabled").check({ force: true });
      } else {
        await organizerGroupPage.locator("#toggle_waitlist_enabled").uncheck({ force: true });
      }
      await organizerGroupPage.locator("#meetup_url").fill(values.meetupUrl);
      await fillMultipleInputs(
        organizerGroupPage.locator('multiple-inputs[field-name="tags"]'),
        values.tags,
      );
      await uploadGalleryImages(organizerGroupPage, "photos_urls", values.galleryPaths);

      await organizerGroupPage.locator('button[data-section="date-venue"]').click({
        force: true,
      });
      await selectTimezone(organizerGroupPage, values.timezone);
      await organizerGroupPage.locator("#starts_at").fill(values.startsAt);
      await organizerGroupPage.locator("#ends_at").fill(values.endsAt);
      if (values.eventReminderEnabled) {
        await organizerGroupPage
          .locator("#toggle_event_reminder_enabled")
          .check({ force: true });
      } else {
        await organizerGroupPage
          .locator("#toggle_event_reminder_enabled")
          .uncheck({ force: true });
      }
      await fillEventVenue(organizerGroupPage, {
        address: values.venueAddress,
        city: values.venueCity,
        latitude: values.venueLatitude,
        longitude: values.venueLongitude,
        name: values.venueName,
        zipCode: values.venueZipCode,
      });
      await organizerGroupPage.locator("#meeting_join_url").fill(values.meetingJoinUrl);
      await organizerGroupPage
        .locator("#meeting_recording_url")
        .fill(values.meetingRecordingUrl);

      await organizerGroupPage.locator('button[data-section="cfs"]').click({ force: true });
      await organizerGroupPage.locator("#toggle_cfs_enabled").check({ force: true });
      await organizerGroupPage.locator("#cfs_starts_at").fill(values.cfsStartsAt);
      await organizerGroupPage.locator("#cfs_ends_at").fill(values.cfsEndsAt);
      await fillMarkdownEditor(
        organizerGroupPage,
        "cfs_description",
        values.cfsDescription,
      );
      await fillMultipleInputs(
        organizerGroupPage.locator("cfs-labels-editor"),
        values.cfsLabels,
        "label",
      );
    };

    const openEventUpdateForm = async (eventRow: Locator) => {
      await Promise.all([
        organizerGroupPage.waitForResponse(
          (response) =>
            response.request().method() === "GET" &&
            response.url().includes("/dashboard/group/events/") &&
            response.url().includes("/update") &&
            response.ok(),
        ),
        eventRow.locator('td button[aria-label^="Edit event:"]').click(),
      ]);
    };

    await navigateToPath(organizerGroupPage, "/dashboard/group?tab=events");

    const dashboardContent = organizerGroupPage.locator("#dashboard-content");
    await expect(dashboardContent.getByText("Events", { exact: true })).toBeVisible();

    await dashboardContent.getByRole("button", { name: "Add Event" }).click();
    await expect(organizerGroupPage.locator("#name")).toBeVisible();

    await fillEventForm(initialValues);

    const addEventButton = organizerGroupPage.locator(
      "#pending-changes-alert:not(.hidden) #add-event-button",
    );
    await expect(addEventButton).toBeVisible();

    await Promise.all([
      organizerGroupPage.waitForResponse(
        (response) =>
          response.request().method() === "POST" &&
          response.url().includes("/dashboard/group/events/add") &&
          response.status() === 201,
      ),
      addEventButton.click(),
    ]);

    let eventRow = dashboardContent.locator("tr", { hasText: initialValues.name });
    await expect(eventRow).toBeVisible();

    await openEventUpdateForm(eventRow);
    await fillEventForm(updatedValues);

    await Promise.all([
      organizerGroupPage.waitForResponse(
        (response) =>
          response.request().method() === "PUT" &&
          response.url().includes("/dashboard/group/events/") &&
          response.url().includes("/update") &&
          response.ok(),
      ),
      organizerGroupPage.locator("#update-event-button").click(),
    ]);

    eventRow = dashboardContent.locator("tr", { hasText: updatedValues.name });
    await expect(eventRow).toBeVisible();

    await openEventUpdateForm(eventRow);
    await expect(organizerGroupPage.locator("#name")).toHaveValue(updatedValues.name);
    await expect(organizerGroupPage.locator("#kind_id")).toHaveValue(updatedValues.kindId);
    await expect(organizerGroupPage.locator("#category_id")).toHaveValue(updatedValues.categoryId);
    await expect
      .poll(async () => (await organizerGroupPage.locator("#description_short").inputValue()).trim())
      .toBe(updatedValues.descriptionShort);
    await expect(organizerGroupPage.locator("#capacity")).toHaveValue(updatedValues.capacity);
    await expect(organizerGroupPage.locator("#registration_required")).toHaveValue(
      String(updatedValues.registrationRequired),
    );
    await expect(organizerGroupPage.locator("#waitlist_enabled")).toHaveValue(
      String(updatedValues.waitlistEnabled),
    );
    await expect(organizerGroupPage.locator("#meetup_url")).toHaveValue(updatedValues.meetupUrl);
    await expect(
      organizerGroupPage.locator('image-field[name="logo_url"] input[name="logo_url"]'),
    ).toHaveValue(/\/images\//);
    await expect(
      organizerGroupPage.locator('image-field[name="banner_url"] input[name="banner_url"]'),
    ).toHaveValue(/\/images\//);
    await expect(
      organizerGroupPage.locator(
        'image-field[name="banner_mobile_url"] input[name="banner_mobile_url"]',
      ),
    ).toHaveValue(/\/images\//);
    await expect(
      organizerGroupPage.locator('multiple-inputs[field-name="tags"] input[name="tags[]"]'),
    ).toHaveCount(updatedValues.tags.length);
    await organizerGroupPage.locator('button[data-section="date-venue"]').click();
    await expect(organizerGroupPage.locator('input[name="timezone"]')).toHaveValue(
      updatedValues.timezone,
    );
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
    await expect(organizerGroupPage.locator("#meeting_join_url")).toHaveValue(
      updatedValues.meetingJoinUrl,
    );
    await expect(organizerGroupPage.locator("#meeting_recording_url")).toHaveValue(
      updatedValues.meetingRecordingUrl,
    );
    await organizerGroupPage.locator('button[data-section="cfs"]').click();
    await expect(organizerGroupPage.locator("#cfs_enabled")).toHaveValue("true");
    await expect(organizerGroupPage.locator("#cfs_starts_at")).toHaveValue(
      updatedValues.cfsStartsAt,
    );
    await expect(organizerGroupPage.locator("#cfs_ends_at")).toHaveValue(
      updatedValues.cfsEndsAt,
    );
    await expect(
      organizerGroupPage.locator('cfs-labels-editor input[name$="[name]"]'),
    ).toHaveCount(updatedValues.cfsLabels.length);
    await expect(
      organizerGroupPage.locator('gallery-field[field-name="photos_urls"] input[name="photos_urls[]"]'),
    ).toHaveCount(
      initialValues.galleryPaths.length + updatedValues.galleryPaths.length,
    );

    await navigateToPath(organizerGroupPage, "/dashboard/group?tab=events");
    eventRow = dashboardContent.locator("tr", { hasText: updatedValues.name });
    await expect(eventRow).toBeVisible();

    await eventRow.locator(".btn-actions").click();

    const deleteButton = eventRow.locator('button[id^="delete-event-"]');
    await expect(deleteButton).toBeVisible();

    await Promise.all([
      organizerGroupPage.waitForResponse(
        (response) =>
          response.request().method() === "DELETE" &&
          response.url().includes("/dashboard/group/events/") &&
          response.url().includes("/delete") &&
          response.ok(),
      ),
      deleteButton.click(),
      organizerGroupPage.getByRole("button", { name: "Yes" }).click(),
    ]);

    await expect(dashboardContent.locator("tr", { hasText: updatedValues.name })).toHaveCount(0);
  });

  test("organizer can unpublish and publish an event from the list", async ({
    organizerGroupPage,
  }) => {
    await navigateToPath(organizerGroupPage, "/dashboard/group?tab=events");

    const dashboardContent = organizerGroupPage.locator("#dashboard-content");
    const eventRow = dashboardContent.locator("tr", {
      hasText: "Upcoming In-Person Event",
    });
    await expect(eventRow).toBeVisible();
    await expect(eventRow).toContainText("Published");

    const actionsButton = eventRow.locator(
      `.btn-actions[data-event-id="${TEST_EVENT_IDS.alpha.one}"]`,
    );
    await actionsButton.click();

    const unpublishButton = organizerGroupPage.locator(
      `#unpublish-event-${TEST_EVENT_IDS.alpha.one}`,
    );
    await expect(unpublishButton).toBeVisible();

    await Promise.all([
      organizerGroupPage.waitForResponse(
        (response) =>
          response.request().method() === "PUT" &&
          response.url().includes(`/dashboard/group/events/${TEST_EVENT_IDS.alpha.one}/unpublish`) &&
          response.ok(),
      ),
      unpublishButton.click(),
      organizerGroupPage.getByRole("button", { name: "Yes" }).click(),
    ]);

    await expect(eventRow).toContainText("Draft");

    await eventRow
      .locator(`.btn-actions[data-event-id="${TEST_EVENT_IDS.alpha.one}"]`)
      .click();

    const publishButton = organizerGroupPage.locator(
      `#publish-event-${TEST_EVENT_IDS.alpha.one}`,
    );
    await expect(publishButton).toBeVisible();

    await Promise.all([
      organizerGroupPage.waitForResponse(
        (response) =>
          response.request().method() === "PUT" &&
          response.url().includes(`/dashboard/group/events/${TEST_EVENT_IDS.alpha.one}/publish`) &&
          response.ok(),
      ),
      publishButton.click(),
      organizerGroupPage.getByRole("button", { name: "Yes" }).click(),
    ]);

    await expect(eventRow).toContainText("Published");
  });

  test("organizer can update and restore event fields across multiple tabs", async ({
    organizerGroupPage,
  }) => {
    const cfsSummitPath =
      `/${TEST_COMMUNITY_NAME}/group/${TEST_GROUP_SLUGS.community1.alpha}/event/${TEST_EVENT_SLUGS.alphaDashboard[0]}`;
    const shiftDateTimeLocalMinutes = (value: string, minutes: number) => {
      const shiftedDate = new Date(`${value}:00Z`);
      shiftedDate.setUTCMinutes(shiftedDate.getUTCMinutes() + minutes);

      return shiftedDate.toISOString().slice(0, 16);
    };

    const openCfsSummitEditor = async () => {
      await navigateToPath(organizerGroupPage, "/dashboard/group?tab=events");

      const eventRow = organizerGroupPage.locator("tr").filter({
        has: organizerGroupPage.locator(`a[href="${cfsSummitPath}"]`),
      });
      await expect(eventRow).toBeVisible();

      await Promise.all([
        organizerGroupPage.waitForResponse(
          (response) =>
            response.request().method() === "GET" &&
            response.url().includes(`/dashboard/group/events/${TEST_EVENT_IDS.alpha.cfsSummit}/update`) &&
            response.ok(),
        ),
        eventRow
          .locator(
            `td button[hx-get="/dashboard/group/events/${TEST_EVENT_IDS.alpha.cfsSummit}/update"]`,
          )
          .click(),
      ]);
    };

    const readEventValues = async () => {
      await openCfsSummitEditor();

      return {
        cfsEndsAt: await organizerGroupPage.locator("#cfs_ends_at").inputValue(),
        cfsStartsAt: await organizerGroupPage.locator("#cfs_starts_at").inputValue(),
        endsAt: await organizerGroupPage.locator("#ends_at").inputValue(),
        meetupUrl: await organizerGroupPage.locator("#meetup_url").inputValue(),
        name: await organizerGroupPage.locator("#name").inputValue(),
        startsAt: await organizerGroupPage.locator("#starts_at").inputValue(),
      };
    };

    const saveUpdatedValues = async (values: {
      cfsEndsAt: string;
      cfsStartsAt: string;
      endsAt: string;
      meetupUrl: string;
      name: string;
      startsAt: string;
    }) => {
      await openCfsSummitEditor();

      await organizerGroupPage.locator("#name").fill(values.name);
      await organizerGroupPage.locator("#meetup_url").fill(values.meetupUrl);

      await organizerGroupPage.locator('button[data-section="date-venue"]').click();
      await expect(organizerGroupPage.locator("#starts_at")).toBeVisible();
      await organizerGroupPage.locator("#starts_at").fill(values.startsAt);
      await organizerGroupPage.locator("#ends_at").fill(values.endsAt);

      await organizerGroupPage.locator('button[data-section="cfs"]').click();
      await expect(organizerGroupPage.locator("#cfs_starts_at")).toBeVisible();
      await organizerGroupPage.locator("#cfs_starts_at").fill(values.cfsStartsAt);
      await organizerGroupPage.locator("#cfs_ends_at").fill(values.cfsEndsAt);
      await expect(organizerGroupPage.locator("#pending-changes-alert")).not.toHaveClass(
        /hidden/,
      );

      await Promise.all([
        organizerGroupPage.waitForResponse(
          (response) =>
            response.request().method() === "PUT" &&
            response
              .url()
              .includes(`/dashboard/group/events/${TEST_EVENT_IDS.alpha.cfsSummit}/update`) &&
            response.ok(),
        ),
        organizerGroupPage.locator("#update-event-button").click(),
      ]);
    };

    const originalValues = await readEventValues();
    const updatedValues = {
      cfsEndsAt: shiftDateTimeLocalMinutes(originalValues.cfsEndsAt, 60),
      cfsStartsAt: shiftDateTimeLocalMinutes(originalValues.cfsStartsAt, 60),
      endsAt: shiftDateTimeLocalMinutes(originalValues.endsAt, -30),
      meetupUrl: "https://meetup.com/e2e-alpha-cfs-summit",
      name: `Event With Active CFS ${Date.now()}`,
      startsAt: shiftDateTimeLocalMinutes(originalValues.startsAt, 30),
    };

    await saveUpdatedValues(updatedValues);

    await openCfsSummitEditor();
    await expect(organizerGroupPage.locator("#name")).toHaveValue(updatedValues.name);
    await expect(organizerGroupPage.locator("#meetup_url")).toHaveValue(
      updatedValues.meetupUrl,
    );
    await organizerGroupPage.locator('button[data-section="date-venue"]').click();
    await expect(organizerGroupPage.locator("#starts_at")).toHaveValue(updatedValues.startsAt);
    await expect(organizerGroupPage.locator("#ends_at")).toHaveValue(updatedValues.endsAt);
    await organizerGroupPage.locator('button[data-section="cfs"]').click();
    await expect(organizerGroupPage.locator("#cfs_starts_at")).toHaveValue(
      updatedValues.cfsStartsAt,
    );
    await expect(organizerGroupPage.locator("#cfs_ends_at")).toHaveValue(
      updatedValues.cfsEndsAt,
    );

    await saveUpdatedValues(originalValues);
  });

  test("organizer is warned before removing dates from an event with sessions", async ({
    organizerGroupPage,
  }) => {
    const alphaEventPath =
      `/${TEST_COMMUNITY_NAME}/group/${TEST_GROUP_SLUGS.community1.alpha}/event/${TEST_EVENT_SLUGS.alpha[0]}`;

    await navigateToPath(organizerGroupPage, "/dashboard/group?tab=events");

    const eventRow = organizerGroupPage.locator("tr").filter({
      has: organizerGroupPage.locator(`a[href="${alphaEventPath}"]`),
    });
    await expect(eventRow).toBeVisible();

    await Promise.all([
      organizerGroupPage.waitForResponse(
        (response) =>
          response.request().method() === "GET" &&
          response.url().includes(`/dashboard/group/events/${TEST_EVENT_IDS.alpha.one}/update`) &&
          response.ok(),
      ),
      eventRow
        .locator(`td button[hx-get="/dashboard/group/events/${TEST_EVENT_IDS.alpha.one}/update"]`)
        .click(),
    ]);

    await organizerGroupPage.locator('button[data-section="date-venue"]').click();
    await expect(organizerGroupPage.locator("#starts_at")).toBeVisible();
    await organizerGroupPage.locator("#starts_at").fill("");
    await organizerGroupPage.locator("#ends_at").fill("");

    await expect(organizerGroupPage.locator("#pending-changes-alert")).not.toHaveClass(/hidden/);

    await organizerGroupPage.locator("#update-event-button").click();

    const confirmationDialog = organizerGroupPage.locator(".swal2-popup");
    await expect(confirmationDialog).toContainText(
      "Saving this event without start and end dates will remove all sessions.",
    );

    await confirmationDialog.getByRole("button", { name: "No" }).click();
  });
});
