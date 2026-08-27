import { expect, test } from "../../fixtures.js";

import {
  E2E_MEETINGS_ENABLED,
  E2E_PAYMENTS_ENABLED,
  TEST_APPROVAL_REQUIRED_EVENT,
  TEST_COMMUNITY_NAME,
  TEST_EVENT_IDS,
  TEST_EVENT_NAMES,
  TEST_EVENT_SLUGS,
  TEST_GROUP_SLUGS,
  TEST_PAYMENT_EVENT_IDS,
  TEST_PAYMENT_EVENT_NAMES,
  TEST_REGISTRATION_WINDOW_EVENTS,
  TEST_TICKETING_EVENTS,
  TEST_USER_IDS,
  expectPaginationNavigation,
  expectTableColumnsAtViewport,
  expectTableHeaders,
  navigateToPath,
  selectTimezone,
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
  addDiscountCode,
  openPaymentsSection,
  waitForEventEditorAfterSave,
} from "../../dashboard/group/events/helpers.js";

import {
  addTicketType,
  editTicketType,
  enableAutomaticMeetingCreation,
  expectAutomaticMeetingControls,
  expectManualMeetingFields,
  openDetailsSection,
  removeDiscountCode,
  setAutomaticMeetingCapacity,
  setCfsLabels,
  setEventPeople,
  setRegistrationQuestions,
} from "../../dashboard/group/events/event-form-helpers.js";

test.describe("event management workflows", () => {
  test("organizer can create and delete an event", async ({ organizerGroupPage }) => {
    // Create a unique event name for the temporary event flow.
    const eventName = `E2E Group Event ${Date.now()}`;

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
    if (E2E_MEETINGS_ENABLED) {
      await setAutomaticMeetingCapacity(organizerGroupPage);
    }

    // Fill schedule and online meeting details.
    await organizerGroupPage.locator("button[data-section-next]").click();
    await expect(organizerGroupPage.locator('button[data-section="date-venue"]')).toHaveAttribute(
      "data-active",
      "true",
    );
    await selectTimezone(organizerGroupPage, "UTC");
    await expect(organizerGroupPage.locator("#starts_at")).toBeVisible();
    await organizerGroupPage.locator("#starts_at").fill("2030-05-10T10:00");
    await organizerGroupPage.locator("#ends_at").fill("2030-05-10T12:00");
    if (E2E_MEETINGS_ENABLED) {
      await enableAutomaticMeetingCreation(organizerGroupPage);
    } else {
      await organizerGroupPage
        .locator("#meeting_join_url")
        .fill("https://meet.example.com/e2e-created-event");
    }

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
    await waitForEventEditorAfterSave(organizerGroupPage);
    await expect(organizerGroupPage.locator(".swal2-popup")).toContainText(
      "You have successfully created the event.",
    );

    // Verify online details persisted on the update page.
    await organizerGroupPage.locator('button[data-section="date-venue"]').click();

    // Verify the correct online meeting state persisted.
    if (E2E_MEETINGS_ENABLED) {
      await expectAutomaticMeetingControls(organizerGroupPage);
      await expect(
        organizerGroupPage.locator('online-event-details input[name="meeting_requested"]'),
      ).toHaveValue("true");
    } else {
      await expect(organizerGroupPage.locator("#meeting_join_url")).toHaveValue(
        "https://meet.example.com/e2e-created-event",
      );
    }

    // Delete the temporary event to keep the seeded list reusable.
    await navigateToPath(organizerGroupPage, "/dashboard/group?tab=events");
    const eventRow = dashboardContent.locator("tr", { hasText: eventName });
    await expect(eventRow).toBeVisible();
    await eventRow.locator(".btn-actions").click();

    // Open the delete confirmation for the temporary event.
    const deleteButton = eventRow.locator('button[id^="delete-event-"]');
    await expect(deleteButton).toBeVisible();
    await deleteButton.click();
    await expect(organizerGroupPage.locator(".swal2-popup")).toContainText(
      "Delete this event? This removes it from the dashboard and cannot be undone.",
    );

    // Confirm deletion and wait for the server response.
    await Promise.all([
      organizerGroupPage.waitForResponse(
        (response) =>
          response.request().method() === "DELETE" &&
          response.url().includes("/dashboard/group/events/") &&
          response.url().includes("/delete") &&
          response.ok(),
      ),
      organizerGroupPage.getByRole("button", { name: "Yes" }).click(),
    ]);

    // Verify the deleted event is removed from the list.
    await expect(dashboardContent.locator("tr", { hasText: eventName })).toHaveCount(0);
  });

  test("organizer can create and delete a recurring event series", async ({ organizerGroupPage }) => {
    // Create a unique event name for the recurring series flow.
    const eventName = `E2E Recurring Group Event ${Date.now()}`;

    // Load the events list before creating a recurring series.
    await navigateToPath(organizerGroupPage, "/dashboard/group?tab=events");

    // Target dashboard content after the events tab loads.
    const dashboardContent = organizerGroupPage.locator("#dashboard-content");
    await expect(dashboardContent.getByText("Events", { exact: true })).toBeVisible();

    // Open the event form from the dashboard list.
    await dashboardContent.getByRole("button", { name: "Add Event" }).click();
    await expect(organizerGroupPage.locator("#name")).toBeVisible();

    // Fill the core event details for the recurring series.
    await organizerGroupPage.locator("#name").fill(eventName);
    await organizerGroupPage.locator("#kind_id").selectOption("virtual");
    await organizerGroupPage.locator("#category_id").selectOption("33333333-3333-3333-3333-333333333331");
    await organizerGroupPage
      .locator("#description_short")
      .fill("A recurring dashboard-created event from the e2e suite.");
    await fillMarkdownEditor(
      organizerGroupPage,
      "description",
      "A recurring dashboard event created and removed by the e2e suite.",
    );

    // Fill the recurring schedule and occurrence count.
    await organizerGroupPage.locator('button[data-section="date-venue"]').click();
    await selectTimezone(organizerGroupPage, "UTC");
    await expect(organizerGroupPage.locator("#starts_at")).toBeVisible();
    await organizerGroupPage.locator("#starts_at").fill("2030-05-15T10:00");
    await organizerGroupPage.locator("#ends_at").fill("2030-05-15T12:00");
    await organizerGroupPage
      .locator("#meeting_join_url")
      .fill("https://meet.example.com/e2e-recurring-event");
    await organizerGroupPage.locator("#recurrence_pattern").selectOption("weekly");
    await expect(organizerGroupPage.locator("#recurrence-additional-occurrences-container")).toBeVisible();
    await organizerGroupPage.locator("#recurrence_additional_occurrences").fill("2");

    // Target the visible submit button after pending changes appear.
    const visibleAddEventButton = organizerGroupPage.locator(
      "#pending-changes-alert:not(.hidden) #add-event-button",
    );
    await expect(organizerGroupPage.locator("#pending-changes-alert")).not.toHaveClass(/hidden/);
    await expect(visibleAddEventButton).toBeVisible();

    // Create the recurring series and wait for the POST response.
    await waitForActionResponse(organizerGroupPage, () => visibleAddEventButton.click(), {
      method: "POST",
      urlIncludes: "/dashboard/group/events/add",
      status: 201,
    });

    // The first occurrence opens in the event editor after create.
    await waitForEventEditorAfterSave(organizerGroupPage);
    await navigateToPath(organizerGroupPage, "/dashboard/group?tab=events");

    // Verify the recurring series creates the expected number of rows.
    const eventRows = dashboardContent.locator("tr", { hasText: eventName });
    await expect(eventRows).toHaveCount(3);

    // Delete the full series to keep the seeded list reusable.
    const eventRow = eventRows.first();
    await eventRow.locator(".btn-actions").click();

    // Open the delete confirmation for the first series occurrence.
    const deleteButton = eventRow.locator('button[id^="delete-event-"]');
    await expect(deleteButton).toBeVisible();
    await deleteButton.click();

    // Verify the recurring-series delete dialog is shown.
    const seriesConfirmationDialog = organizerGroupPage.locator(".swal2-popup");
    await expect(seriesConfirmationDialog).toContainText(
      "This event is part of a recurring series. What would you like to delete?",
    );

    // Confirm full-series deletion and wait for the server response.
    await Promise.all([
      organizerGroupPage.waitForResponse(
        (response) =>
          response.request().method() === "DELETE" &&
          response.url().includes("/dashboard/group/events/") &&
          response.url().includes("/delete") &&
          response.url().includes("scope=series") &&
          response.ok(),
      ),
      seriesConfirmationDialog.getByRole("button", { name: "All in series" }).click(),
    ]);

    // Verify every recurring series row is removed from the list.
    await expect(dashboardContent.locator("tr", { hasText: eventName })).toHaveCount(0);
  });

  test("organizer can scope recurring publish, unpublish, and cancel actions", async ({
    organizerGroupPage,
  }) => {
    // Create a unique event name for the recurring scoped actions flow.
    const eventName = `E2E Recurring Scoped Event ${Date.now()}`;

    // Load the events list before creating a recurring series.
    await navigateToPath(organizerGroupPage, "/dashboard/group?tab=events");

    // Target dashboard content after the events tab loads.
    const dashboardContent = organizerGroupPage.locator("#dashboard-content");
    await expect(dashboardContent.getByText("Events", { exact: true })).toBeVisible();

    // Open the event form from the dashboard list.
    await dashboardContent.getByRole("button", { name: "Add Event" }).click();
    await expect(organizerGroupPage.locator("#name")).toBeVisible();

    // Fill the core event details for the recurring series.
    await organizerGroupPage.locator("#name").fill(eventName);
    await organizerGroupPage.locator("#kind_id").selectOption("virtual");
    await organizerGroupPage.locator("#category_id").selectOption("33333333-3333-3333-3333-333333333331");
    await organizerGroupPage
      .locator("#description_short")
      .fill("A recurring dashboard event for scoped action coverage.");
    await fillMarkdownEditor(
      organizerGroupPage,
      "description",
      "A recurring dashboard event used by scoped action e2e coverage.",
    );

    // Fill the recurring schedule and occurrence count.
    await organizerGroupPage.locator('button[data-section="date-venue"]').click();
    await selectTimezone(organizerGroupPage, "UTC");
    await expect(organizerGroupPage.locator("#starts_at")).toBeVisible();
    await organizerGroupPage.locator("#starts_at").fill("2030-05-22T10:00");
    await organizerGroupPage.locator("#ends_at").fill("2030-05-22T12:00");
    await organizerGroupPage
      .locator("#meeting_join_url")
      .fill("https://meet.example.com/e2e-recurring-scoped-event");
    await organizerGroupPage.locator("#recurrence_pattern").selectOption("weekly");
    await expect(organizerGroupPage.locator("#recurrence-additional-occurrences-container")).toBeVisible();
    await organizerGroupPage.locator("#recurrence_additional_occurrences").fill("2");

    // Target the visible submit button after pending changes appear.
    const visibleAddEventButton = organizerGroupPage.locator(
      "#pending-changes-alert:not(.hidden) #add-event-button",
    );
    await expect(organizerGroupPage.locator("#pending-changes-alert")).not.toHaveClass(/hidden/);
    await expect(visibleAddEventButton).toBeVisible();

    // Create the recurring series and wait for the POST response.
    await waitForActionResponse(organizerGroupPage, () => visibleAddEventButton.click(), {
      method: "POST",
      urlIncludes: "/dashboard/group/events/add",
      status: 201,
    });

    // The first occurrence opens in the event editor after create.
    await waitForEventEditorAfterSave(organizerGroupPage);
    await navigateToPath(organizerGroupPage, "/dashboard/group?tab=events");

    // Verify the recurring series creates the expected number of rows.
    const eventRows = dashboardContent.locator("tr", { hasText: eventName });
    await expect(eventRows).toHaveCount(3);

    // Select a scoped action from the row actions menu.
    const selectScopedAction = async (row, action, scopeButtonName) => {
      await row.locator(".btn-actions").click();
      const actionButton = row.locator(`button[id^="${action}-event-"]`);
      await expect(actionButton).toBeVisible();
      await actionButton.click();

      const seriesConfirmationDialog = organizerGroupPage.locator(".swal2-popup");
      const expectedConfirmationMessage =
        action === "cancel"
          ? "Canceling is permanent. Attendee registrations are canceled immediately, and full refunds for eligible paid purchases are queued and may take time to process. Which events would you like to cancel?"
          : `This event is part of a recurring series. What would you like to ${action}?`;
      await expect(seriesConfirmationDialog).toContainText(expectedConfirmationMessage);

      await Promise.all([
        organizerGroupPage.waitForResponse(
          (response) =>
            response.request().method() === "PUT" &&
            response.url().includes("/dashboard/group/events/") &&
            response.url().includes(`/${action}`) &&
            (scopeButtonName !== "Only this event"
              ? response.url().includes("scope=series")
              : !response.url().includes("scope=series")) &&
            response.ok(),
        ),
        seriesConfirmationDialog.getByRole("button", { name: scopeButtonName }).click(),
      ]);
    };

    // Publish the series first when the default created state is draft.
    await eventRows.first().locator(".btn-actions").click();
    if ((await eventRows.first().locator('button[id^="publish-event-"]').count()) > 0) {
      await eventRows.first().locator(".btn-actions").click();
      await selectScopedAction(eventRows.first(), "publish", "All in series");
      await expect(eventRows.first()).toContainText("Published");
      await expect(eventRows.nth(1)).toContainText("Published");
      await expect(eventRows.nth(2)).toContainText("Published");
    } else {
      await eventRows.first().locator(".btn-actions").click();
    }

    // Unpublish the whole series.
    await selectScopedAction(eventRows.first(), "unpublish", "All in series");
    await expect(eventRows.first()).toContainText("Draft");
    await expect(eventRows.nth(1)).toContainText("Draft");
    await expect(eventRows.nth(2)).toContainText("Draft");

    // Publish only one event in the series.
    await selectScopedAction(eventRows.first(), "publish", "Only this event");
    await expect(eventRows.first()).toContainText("Published");
    await expect(eventRows.nth(1)).toContainText("Draft");
    await expect(eventRows.nth(2)).toContainText("Draft");

    // Cancel the full series.
    await selectScopedAction(eventRows.first(), "cancel", "Non-completed events in series");
    await expect(eventRows.first()).toContainText("Canceled");
    await expect(eventRows.nth(1)).toContainText("Canceled");
    await expect(eventRows.nth(2)).toContainText("Canceled");

    // Delete the full series to keep the seeded list reusable.
    await eventRows.first().locator(".btn-actions").click();
    const deleteButton = eventRows.first().locator('button[id^="delete-event-"]');
    await expect(deleteButton).toBeVisible();
    await deleteButton.click();

    const seriesConfirmationDialog = organizerGroupPage.locator(".swal2-popup");
    await expect(seriesConfirmationDialog).toContainText(
      "This event is part of a recurring series. What would you like to delete?",
    );

    await Promise.all([
      organizerGroupPage.waitForResponse(
        (response) =>
          response.request().method() === "DELETE" &&
          response.url().includes("/dashboard/group/events/") &&
          response.url().includes("/delete") &&
          response.url().includes("scope=series") &&
          response.ok(),
      ),
      seriesConfirmationDialog.getByRole("button", { name: "All in series" }).click(),
    ]);

    // Verify every recurring series row is removed from the list.
    await expect(dashboardContent.locator("tr", { hasText: eventName })).toHaveCount(0);
  });

  test("organizer can copy event details and payment configuration", async ({ organizerGroupPage }) => {
    test.skip(!E2E_PAYMENTS_ENABLED, "Payments are disabled in this environment.");

    // Load the events list before opening the create form.
    await navigateToPath(organizerGroupPage, "/dashboard/group?tab=events");
    const dashboardContent = organizerGroupPage.locator("#dashboard-content");
    await dashboardContent.getByRole("button", { name: "Add Event" }).click();
    await expect(organizerGroupPage.locator("#name")).toBeVisible();

    // Open the copy selector and target the seeded paid event.
    await organizerGroupPage.locator("#copy-event-selector").click();
    await organizerGroupPage
      .locator("#dropdown-events #event-search-input")
      .fill(TEST_PAYMENT_EVENT_NAMES.draft);
    const eventOption = organizerGroupPage
      .locator('#dropdown-events button[id^="select-event-"]')
      .filter({ hasText: TEST_PAYMENT_EVENT_NAMES.draft });
    await expect(eventOption).toBeVisible();
    const copiedEventName = (await eventOption.locator("div").nth(1).innerText()).trim();

    // Copy the event details into the create form.
    await Promise.all([
      organizerGroupPage.waitForResponse(
        (response) =>
          response.request().method() === "GET" &&
          response.url().includes("/dashboard/group/events/") &&
          response.url().includes("/details") &&
          response.ok(),
      ),
      eventOption.click(),
    ]);

    // Verify copied details are applied and the schedule is left blank.
    await expect(organizerGroupPage.locator("#name")).toHaveValue(`${copiedEventName} (copy)`);
    await organizerGroupPage.locator('button[data-section="date-venue"]').click();
    await expect(organizerGroupPage.locator("#starts_at")).toHaveValue("");
    await expect(organizerGroupPage.locator("#ends_at")).toHaveValue("");
    await expect(organizerGroupPage.locator("#kind_id")).toHaveValue("hybrid");
    await expect(organizerGroupPage.locator("#location-search-venue_name")).toHaveValue("E2E Admission Hall");
    await expect(organizerGroupPage.locator("#location-search-venue_address")).toHaveValue("123 Payment Way");
    await expect(organizerGroupPage.locator("#location-search-venue_city")).toHaveValue("New York");
    await expect(organizerGroupPage.locator("#location-search-venue_state_name")).toHaveValue("NY");
    await expect(organizerGroupPage.locator("#location-search-venue_state_code")).toHaveValue("NY");
    await expect(organizerGroupPage.locator("#location-search-venue_country_name")).toHaveValue(
      "United States",
    );
    await expect(organizerGroupPage.locator("#location-search-venue_country_code")).toHaveValue("US");
    await expect(organizerGroupPage.locator("#location-search-venue_zip_code")).toHaveValue("10001");
    await expect(organizerGroupPage.locator(".swal2-popup")).toContainText("Event details copied.");
    await organizerGroupPage.getByRole("button", { name: "OK" }).click();

    // Copied payment configuration keeps currency, tax settings, tiers, and discounts.
    await openPaymentsSection(organizerGroupPage);
    await expect(organizerGroupPage.locator("#payment_currency_code")).toHaveValue("USD");
    await expect(organizerGroupPage.locator("#tax_behavior")).toHaveValue("inclusive");
    await expect(organizerGroupPage.locator("#tax_calculation_mode")).toHaveValue("automatic");
    await expect(
      organizerGroupPage.locator('#ticket-types-ui [data-ticketing-role="table-body"]'),
    ).toContainText("General admission");
    await expect(
      organizerGroupPage.locator('#ticket-types-ui [data-ticketing-role="table-body"]'),
    ).toContainText("Community ticket");
    await expect(
      organizerGroupPage.locator('#discount-codes-ui [data-ticketing-role="table-body"]'),
    ).toContainText("SAVE10");
    await expect(
      organizerGroupPage.locator('#discount-codes-ui [data-ticketing-role="table-body"]'),
    ).toContainText("EARLY20");
  });

  test("organizer can override recording urls for automatic event and session meetings", async ({
    organizerGroupPage,
  }) => {
    // Skip automatic meeting coverage when the environment disables it.
    test.skip(!E2E_MEETINGS_ENABLED, "Automatic meetings are disabled in this environment.");

    // Create unique event, session, and recording values for this flow.
    const eventName = `E2E Automatic Recording Override ${Date.now()}`;
    const eventRecordingUrl = `https://youtube.com/watch?v=event-${Date.now()}`;
    const sessionName = `Session ${Date.now()}`;
    const sessionRecordingUrl = `https://youtube.com/watch?v=session-${Date.now()}`;

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
    await organizerGroupPage.locator("#starts_at").fill("2030-06-10T10:00");
    await organizerGroupPage.locator("#ends_at").fill("2030-06-10T12:00");

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
    await expect(sessionOnlineDetails).toHaveAttribute("starts-at", "2030-06-10T10:30");
    await expect(sessionOnlineDetails).toHaveAttribute("ends-at", "2030-06-10T11:30");
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
    await waitForEventEditorAfterSave(organizerGroupPage);

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
  });

  test("organizer can configure paid tiers without contacting the payment provider", async ({
    organizerGroupPage,
  }) => {
    test.setTimeout(90_000);

    // Skip paid-tier coverage when the environment disables payments.
    test.skip(!E2E_PAYMENTS_ENABLED, "Payments are disabled in this environment.");

    // Create a unique event name for the tiered payment flow.
    const eventName = `E2E Paid Tier Event ${Date.now()}`;

    // Open the event form for a payment-ready group.
    await navigateToPath(organizerGroupPage, "/dashboard/group?tab=events");

    // Open the create form from the dashboard content.
    const dashboardContent = organizerGroupPage.locator("#dashboard-content");
    await dashboardContent.getByRole("button", { name: "Add Event" }).click();

    // Fill the core event details.
    await organizerGroupPage.locator("#name").fill(eventName);
    await organizerGroupPage.locator("#kind_id").selectOption("virtual");
    await organizerGroupPage.locator("#category_id").selectOption("33333333-3333-3333-3333-333333333331");
    await organizerGroupPage.locator("#description_short").fill("Paid dashboard event for payment coverage.");
    await fillMarkdownEditor(
      organizerGroupPage,
      "description",
      "Paid dashboard event used to cover admission tiers and discount codes.",
    );
    await organizerGroupPage.locator("#toggle_test_event").check({ force: true });
    await organizerGroupPage.locator("#toggle_waitlist_enabled").check({ force: true });

    // Configure a meeting-safe capacity before automatic meeting selection.
    if (E2E_MEETINGS_ENABLED) {
      await setAutomaticMeetingCapacity(organizerGroupPage);
    }

    // Fill schedule and online meeting details.
    await organizerGroupPage.locator('button[data-section="date-venue"]').click();
    await selectTimezone(organizerGroupPage, "UTC");
    await organizerGroupPage.locator("#starts_at").fill("2030-11-12T18:00");
    await organizerGroupPage.locator("#ends_at").fill("2030-11-12T20:00");
    if (E2E_MEETINGS_ENABLED) {
      await enableAutomaticMeetingCreation(organizerGroupPage);
    } else {
      await organizerGroupPage
        .locator("#meeting_join_url")
        .fill("https://meet.example.com/e2e-paid-tier-event");
    }

    // Open payments before editing the default admission tier.
    await openPaymentsSection(organizerGroupPage);

    // Reuse the default tier for the free admission option.
    await editTicketType(organizerGroupPage, "General Admission", {
      title: "Free community pass",
      description: "Free tier used for zero-price coverage.",
      seatsTotal: "12",
    });

    // Verify free-only tiers need no currency and retain the waitlist setting.
    const paymentCurrencyInput = organizerGroupPage.locator("#payment_currency_code");
    await expect(paymentCurrencyInput).toHaveJSProperty("required", false);
    await expect(organizerGroupPage.locator("#toggle_waitlist_enabled")).toBeEnabled();
    await expect(organizerGroupPage.locator("#waitlist_enabled")).toHaveValue("true");

    // Add a paid ticket type with scheduled price windows.
    await addTicketType(organizerGroupPage, {
      title: "General admission",
      description: "Paid tier with early-bird pricing.",
      seatsTotal: "30",
      priceWindows: [
        { amount: "2500", endsAt: "2030-10-01T23:59" },
        { amount: "3000", startsAt: "2030-10-02T00:00" },
      ],
    });

    // Verify positive prices require a currency before submission.
    await expect(paymentCurrencyInput).toHaveJSProperty("required", true);
    const validationMessage = await paymentCurrencyInput.evaluate((element) => element.validationMessage);
    expect(validationMessage).toBe("Paid ticket prices require an event currency.");
    await paymentCurrencyInput.selectOption("USD");

    // Add discount codes for fixed amount and percentage coverage.
    await addDiscountCode(organizerGroupPage, {
      title: "Launch savings",
      code: "SAVE10",
      kind: "fixed_amount",
      amount: "1000",
    });
    await addDiscountCode(organizerGroupPage, {
      title: "Early supporter",
      code: "EARLY20",
      kind: "percentage",
      percentage: "20",
      totalAvailable: "50",
    });

    // Verify compact redemption summaries at the default desktop width.
    const discountCodesTable = organizerGroupPage.locator("#discount-codes-ui table");
    const redemptionsHeader = discountCodesTable.locator("thead th").nth(1);
    const unlimitedDiscountRow = discountCodesTable.locator("tbody tr", {
      hasText: "Launch savings",
    });
    const limitedDiscountRow = discountCodesTable.locator("tbody tr", {
      hasText: "Early supporter",
    });
    await expect(redemptionsHeader).toBeHidden();
    await expect(redemptionsHeader).toContainText("Redemptions");
    await expect(unlimitedDiscountRow.getByText("Unlimited", { exact: true }).first()).toBeVisible();
    await expect(limitedDiscountRow.getByText("50 max", { exact: true }).first()).toBeVisible();

    // Verify the dedicated redemption column at the widest layout.
    await organizerGroupPage.setViewportSize({ width: 1600, height: 900 });
    await expect(redemptionsHeader).toBeVisible();
    await expect(unlimitedDiscountRow.locator("td").nth(1)).toHaveText("Unlimited");
    await expect(limitedDiscountRow.locator("td").nth(1)).toHaveText("50 max");

    // Target submission while tracking whether browser validation blocks it.
    const visibleAddEventButton = organizerGroupPage.locator(
      "#pending-changes-alert:not(.hidden) #add-event-button",
    );
    await expect(visibleAddEventButton).toBeVisible();
    let eventAddRequests = 0;
    const countEventAddRequests = (request) => {
      if (request.method() === "POST" && request.url().includes("/dashboard/group/events/add")) {
        eventAddRequests += 1;
      }
    };
    organizerGroupPage.on("request", countEventAddRequests);

    // Verify paid tickets require an eligible event type before submission.
    await visibleAddEventButton.click();
    const eventKindInput = organizerGroupPage.locator("#kind_id");
    await expect(eventKindInput).toBeFocused();
    await expect(eventKindInput).toHaveJSProperty(
      "validationMessage",
      "Paid tickets require an in-person or hybrid event.",
    );
    await expect(organizerGroupPage.locator('button[data-section="details"]')).toHaveAttribute(
      "data-active",
      "true",
    );

    // Make the paid event hybrid and verify its physical venue is required.
    await organizerGroupPage.locator("#kind_id").selectOption("hybrid");
    await visibleAddEventButton.click();
    const venueNameInput = organizerGroupPage.locator("#location-search-venue_name");
    await expect(venueNameInput).toBeFocused();
    await expect(venueNameInput).toHaveJSProperty("validationMessage", "Paid tickets require a venue name.");
    await expect(organizerGroupPage.locator('button[data-section="date-venue"]')).toHaveAttribute(
      "data-active",
      "true",
    );

    // Keep subdivisions optional and validate every required venue field in browser order.
    await venueNameInput.fill("Hybrid Admission Hall");
    const venueStateNameInput = organizerGroupPage.locator("#location-search-venue_state_name");
    const venueStateCodeInput = organizerGroupPage.locator("#location-search-venue_state_code");
    await expect(venueStateNameInput).toHaveJSProperty("required", false);
    await expect(venueStateNameInput).toHaveJSProperty("validationMessage", "");
    await expect(venueStateCodeInput).toHaveJSProperty("required", false);
    await expect(venueStateCodeInput).toHaveJSProperty("validationMessage", "");
    const requiredVenueFields = [
      {
        input: organizerGroupPage.locator("#location-search-venue_address"),
        message: "Paid tickets require a venue address.",
        value: "123 Hybrid Way",
      },
      {
        input: organizerGroupPage.locator("#location-search-venue_city"),
        message: "Paid tickets require a venue city.",
        value: "New York",
      },
      {
        input: organizerGroupPage.locator("#location-search-venue_zip_code"),
        message: "Paid tickets require a venue postal code.",
        value: "10001",
      },
      {
        input: organizerGroupPage.locator("#location-search-venue_country_name"),
        message: "Paid tickets require a country.",
        value: "United States",
      },
      {
        input: organizerGroupPage.locator("#location-search-venue_country_code"),
        message: "Paid tickets require a country code to calculate taxes.",
        value: "US",
      },
    ];
    for (const requirement of requiredVenueFields) {
      await visibleAddEventButton.click();
      await expect(requirement.input).toBeFocused();
      await expect(requirement.input).toHaveJSProperty("validationMessage", requirement.message);
      await requirement.input.fill(requirement.value);
    }

    // Complete the venue and verify the tax controls included in the form payload.
    await fillEventVenue(organizerGroupPage, {
      address: "123 Hybrid Way",
      city: "New York",
      countryCode: "US",
      countryName: "United States",
      latitude: "40.7128",
      longitude: "-74.006",
      name: "Hybrid Admission Hall",
      state: "NY",
      stateCode: "NY",
      zipCode: "10001",
    });
    for (const requirement of [venueNameInput, ...requiredVenueFields.map(({ input }) => input)]) {
      await expect(requirement).toHaveJSProperty("validationMessage", "");
    }
    await openPaymentsSection(organizerGroupPage);
    await expect(organizerGroupPage.locator("#tax_behavior")).toHaveValue("inclusive");
    await organizerGroupPage.locator("#tax_behavior").selectOption("exclusive");
    await expect(organizerGroupPage.locator("#tax_behavior")).toHaveValue("exclusive");
    await expect(organizerGroupPage.locator("#tax_calculation_mode")).toHaveValue("automatic");

    // Client-side validation never sent an event request or contacted the provider.
    organizerGroupPage.off("request", countEventAddRequests);
    expect(eventAddRequests).toBe(0);
  });

  test("organizer can create, update, and delete an event with images and rich fields", async ({
    organizerGroupPage,
  }) => {
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
      name: `E2E Rich Event ${Date.now()}`,
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
      name: `E2E Rich Event Updated ${Date.now()}`,
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
    const eventId = await waitForEventEditorAfterSave(organizerGroupPage);

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
    await navigateToPath(organizerGroupPage, "/dashboard/group?tab=events");
    const eventRow = dashboardContent.locator("tr", { hasText: updatedValues.name });
    await expect(eventRow).toBeVisible();

    // Open the actions menu for the updated temporary event.
    await eventRow.locator(".btn-actions").click();

    // Target the delete action for the temporary event.
    const deleteButton = eventRow.locator('button[id^="delete-event-"]');
    await expect(deleteButton).toBeVisible();

    // Confirm deletion and wait for the server response.
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

    // Verify the deleted event is removed from the list.
    await expect(dashboardContent.locator("tr", { hasText: updatedValues.name })).toHaveCount(0);
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
      name: `Event With Active CFS ${Date.now()}`,
      startsAt: shiftDateTimeLocalMinutes(originalValues.startsAt, 30),
    };

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

    // Restore the seeded event to its original values.
    await saveUpdatedValues(originalValues);
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
