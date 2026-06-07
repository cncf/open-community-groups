import { expect, test } from "../../../fixtures.js";

import {
  E2E_MEETINGS_ENABLED,
  E2E_PAYMENTS_ENABLED,
  TEST_COMMUNITY_NAME,
  TEST_EVENT_IDS,
  TEST_EVENT_NAMES,
  TEST_EVENT_SLUGS,
  TEST_PAYMENT_EVENT_IDS,
  TEST_PAYMENT_EVENT_NAMES,
  TEST_GROUP_SLUGS,
  TEST_USER_IDS,
  navigateToPath,
  selectTimezone,
} from "../../../utils.js";
import {
  TEST_UPLOAD_ASSET_PATHS,
  fillEventVenue,
  fillMarkdownEditor,
  fillMultipleInputs,
  uploadGalleryImages,
  uploadImageField,
} from "../../form-helpers.js";

// Open the payments section and retry until the tab state is active.
const openPaymentsSection = async (page) => {
  const paymentsSectionButton = page.locator('button[data-section="payments"]');

  await paymentsSectionButton.scrollIntoViewIfNeeded();
  await expect(paymentsSectionButton).toBeVisible();

  if ((await paymentsSectionButton.getAttribute("data-active")) === "true") {
    return;
  }

  for (let attempt = 0; attempt < 3; attempt += 1) {
    await paymentsSectionButton.click({ force: true });

    try {
      await expect(paymentsSectionButton).toHaveAttribute(
        "data-active",
        "true",
        {
          timeout: 1000,
        },
      );
      return;
    } catch (error) {
      if (attempt === 2) {
        throw error;
      }
    }
  }
};

// Open the event update form by row action and wait for HTMX content.
const openEventUpdateFormByName = async (page, eventName, eventId) => {
  const editButton = page.locator(
    `td button[aria-label="Edit event: ${eventName}"]:visible`,
  );
  await expect(editButton).toBeVisible();

  await Promise.all([
    page.waitForResponse(
      (response) =>
        response.request().method() === "GET" &&
        response.url().includes("/dashboard/group/events/") &&
        response.url().includes("/update") &&
        (eventId ? response.url().includes(eventId) : true) &&
        response.ok(),
    ),
    editButton.click(),
  ]);
};

// Verify manual meeting URL fields are visible in the event form.
const expectManualMeetingFields = async (page) => {
  await expect(page.locator("#meeting_join_url")).toBeVisible();
  await expect(page.locator("#meeting_recording_url")).toBeVisible();
};

// Verify automatic meeting controls are visible in the online details form.
const expectAutomaticMeetingControls = async (page) => {
  const onlineEventDetails = page.locator("online-event-details");
  const automaticModeCard = onlineEventDetails.locator(
    'input[type="radio"][value="automatic"] + div',
  );

  await expect(onlineEventDetails).toBeVisible();
  await expect(automaticModeCard).toBeVisible();
  await expect(
    automaticModeCard.getByText("Create meeting automatically", {
      exact: true,
    }),
  ).toBeVisible();
};

// Select automatic meeting creation and assert the hidden request value.
const enableAutomaticMeetingCreation = async (page) => {
  const onlineEventDetails = page.locator("online-event-details");
  const automaticModeInput = onlineEventDetails.locator(
    'input[type="radio"][value="automatic"]',
  );

  await expectAutomaticMeetingControls(page);
  await expect(automaticModeInput).toBeEnabled();

  await automaticModeInput.check({ force: true });

  await expect(
    onlineEventDetails.locator(
      'input[type="hidden"][name="meeting_requested"]',
    ),
  ).toHaveValue("true");
};

// Add a ticket type through the ticketing modal and save it.
const addTicketType = async (page, values) => {
  await page.locator("#add-ticket-type-button").click();

  const modal = page.locator('[data-ticketing-role="ticket-modal"]');
  await expect(modal).toBeVisible();
  await modal.locator("#ticket-title-draft").fill(values.title);
  await modal.locator("#ticket-seats-draft").fill(values.seatsTotal);
  await modal.locator("#ticket-description-draft").fill(values.description);

  const activeCheckbox = modal.locator('[data-ticket-field="active"]');
  if (!(await activeCheckbox.isChecked())) {
    await activeCheckbox.check({ force: true });
  }

  for (let index = 0; index < values.priceWindows.length; index += 1) {
    const priceWindow = values.priceWindows[index];

    if (index > 0) {
      await modal.locator('[data-ticketing-action="add-price-window"]').click();
    }

    const amountField = modal
      .locator('[data-ticket-window-field="amount"]')
      .nth(index);
    await amountField.fill(priceWindow.amount);

    if (priceWindow.startsAt) {
      await modal
        .locator('[data-ticket-window-field="starts_at"]')
        .nth(index)
        .fill(priceWindow.startsAt);
    }

    if (priceWindow.endsAt) {
      await modal
        .locator('[data-ticket-window-field="ends_at"]')
        .nth(index)
        .fill(priceWindow.endsAt);
    }
  }

  await modal.locator('[data-ticketing-action="save-ticket"]').click();
  await expect(modal).toBeHidden();
};

// Add a discount code through the ticketing modal and save it.
const addDiscountCode = async (page, values) => {
  await page.locator("#add-discount-code-button").click();

  const modal = page.locator('[data-ticketing-role="discount-modal"]');
  await expect(modal).toBeVisible();
  await modal.locator("#discount-title-draft").fill(values.title);
  await modal.locator("#discount-code-draft").fill(values.code);

  const activeCheckbox = modal.locator('[data-discount-field="active"]');
  if (!(await activeCheckbox.isChecked())) {
    await activeCheckbox.check({ force: true });
  }

  await modal.locator("#discount-kind-draft").selectOption(values.kind);

  if (values.kind === "fixed_amount" && values.amount) {
    await modal.locator("#discount-amount-draft").fill(values.amount);
  }

  if (values.kind === "percentage" && values.percentage) {
    await modal.locator("#discount-percentage-draft").fill(values.percentage);
  }

  if (values.totalAvailable) {
    await modal.locator("#discount-total-draft").fill(values.totalAvailable);
  }

  if (values.available) {
    await modal.locator("#discount-available-draft").fill(values.available);
  }

  if (values.startsAt) {
    await modal.locator("#discount-starts-draft").fill(values.startsAt);
  }

  if (values.endsAt) {
    await modal.locator("#discount-ends-draft").fill(values.endsAt);
  }

  await modal.locator('[data-ticketing-action="save-discount"]').click();
  await expect(modal).toBeHidden();
};

// Set CFS label names through the editor component API and assert inputs.
const setCfsLabels = async (page, labels) => {
  const editor = page.locator("cfs-labels-editor");

  await editor.evaluate(async (element, nextLabels) => {
    const cfsLabelsEditor = element;

    cfsLabelsEditor.setLabels?.(
      nextLabels.map((name) => ({
        color: "",
        name,
      })),
    );
    await cfsLabelsEditor.updateComplete;
  }, labels);

  // Verify the editor rendered one submitted input for each label.
  await expect(
    editor.locator('input[name^="cfs_labels"][name$="[name]"]'),
  ).toHaveCount(labels.length);
};

// Set registration questions through the editor API and assert submitted inputs.
const setRegistrationQuestions = async (page, questions) => {
  const editor = page.locator("questions-editor");

  await editor.evaluate(async (element, nextQuestions) => {
    const questionsEditor = element;

    questionsEditor.questions = nextQuestions;
    await questionsEditor.updateComplete;
  }, questions);

  await expect(
    editor.locator('input[name^="registration_questions"][name$="[prompt]"]'),
  ).toHaveCount(questions.length);
};

// Set event hosts and speakers through selector APIs and assert submitted inputs.
const setEventPeople = async (page, values) => {
  await page
    .locator('user-search-selector[field-name="hosts"]')
    .evaluate(async (element, hosts) => {
      const hostSelector = element;

      hostSelector.selectedUsers = hosts;
      await hostSelector.updateComplete;
    }, values.hosts);
  await page
    .locator('speakers-selector[field-name-prefix="speakers"]')
    .evaluate(async (element, speakers) => {
      const speakersSelector = element;

      speakersSelector.selectedSpeakers = speakers;
      await speakersSelector.updateComplete;
    }, values.speakers);

  await expect(
    page.locator(
      'user-search-selector[field-name="hosts"] input[name="hosts[]"]',
    ),
  ).toHaveCount(values.hosts.length);
  await expect(
    page.locator(
      'speakers-selector[field-name-prefix="speakers"] input[name^="speakers"][name$="[user_id]"]',
    ),
  ).toHaveCount(values.speakers.length);
};

test.describe("group dashboard events view", () => {
  test("organizer can switch between upcoming and past events tabs", async ({
    organizerGroupPage,
  }) => {
    // Load the events list before switching tab state.
    await navigateToPath(organizerGroupPage, "/dashboard/group?tab=events");

    // Target tab controls and content regions inside dashboard content.
    const dashboardContent = organizerGroupPage.locator("#dashboard-content");
    const upcomingTab = dashboardContent.locator("#upcoming-tab");
    const pastTab = dashboardContent.locator("#past-tab");
    const upcomingContent = dashboardContent.locator("#upcoming-content");
    const pastContent = dashboardContent.locator("#past-content");

    // Verify the upcoming tab starts active with seeded event rows.
    await expect(upcomingTab).toHaveAttribute("data-active", "true");
    await expect(pastTab).toHaveAttribute("data-active", "false");
    await expect(upcomingContent).toBeVisible();
    await expect(pastContent).toBeHidden();
    await expect(
      upcomingContent.locator("tr", { hasText: TEST_EVENT_NAMES.alpha[0] }),
    ).toBeVisible();

    // Switch to past events and verify historical rows render.
    await pastTab.click();

    // Verify the past tab becomes active with historical rows.
    await expect(pastTab).toHaveAttribute("data-active", "true");
    await expect(upcomingTab).toHaveAttribute("data-active", "false");
    await expect(pastContent).toBeVisible();
    await expect(upcomingContent).toBeHidden();
    await expect(
      pastContent.locator("tr", { hasText: "Past Event For Filtering" }),
    ).toBeVisible();

    // Return to upcoming events and verify the original tab state.
    await upcomingTab.click();

    // Verify the upcoming tab returns to active state.
    await expect(upcomingTab).toHaveAttribute("data-active", "true");
    await expect(pastTab).toHaveAttribute("data-active", "false");
    await expect(upcomingContent).toBeVisible();
    await expect(pastContent).toBeHidden();
    await expect(
      upcomingContent.locator("tr", { hasText: TEST_EVENT_NAMES.alpha[0] }),
    ).toBeVisible();
  });

  test("organizer can create and delete an event", async ({
    organizerGroupPage,
  }) => {
    // Create a unique event name for the temporary event flow.
    const eventName = `E2E Group Event ${Date.now()}`;

    // Load the events list before creating a temporary event.
    await navigateToPath(organizerGroupPage, "/dashboard/group?tab=events");

    // Target dashboard content after the events tab loads.
    const dashboardContent = organizerGroupPage.locator("#dashboard-content");
    await expect(
      dashboardContent.getByText("Events", { exact: true }),
    ).toBeVisible();

    // Open the event form from the dashboard list.
    await dashboardContent.getByRole("button", { name: "Add Event" }).click();
    await expect(organizerGroupPage.locator("#name")).toBeVisible();

    // Fill the core event details required for creation.
    await organizerGroupPage.locator("#name").fill(eventName);
    await organizerGroupPage.locator("#kind_id").selectOption("virtual");
    await organizerGroupPage
      .locator("#category_id")
      .selectOption("33333333-3333-3333-3333-333333333331");
    await organizerGroupPage
      .locator("#description_short")
      .fill("A dashboard-created event from the e2e suite.");
    await fillMarkdownEditor(
      organizerGroupPage,
      "description",
      "A dashboard event created and removed by the e2e suite.",
    );

    // Fill capacity only when automatic meeting fixtures require it.
    if (E2E_MEETINGS_ENABLED) {
      await organizerGroupPage.locator("#capacity").fill("50");
    }

    // Fill schedule and online meeting details.
    await organizerGroupPage.locator("button[data-section-next]").click();
    await expect(
      organizerGroupPage.locator('button[data-section="date-venue"]'),
    ).toHaveAttribute("data-active", "true");
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
    await expect(
      organizerGroupPage.locator("#pending-changes-alert"),
    ).not.toHaveClass(/hidden/);
    await expect(visibleAddEventButton).toBeVisible();

    // Create the event and wait for the POST response.
    await Promise.all([
      organizerGroupPage.waitForResponse(
        (response) =>
          response.request().method() === "POST" &&
          response.url().includes("/dashboard/group/events/add") &&
          response.status() === 201,
      ),
      visibleAddEventButton.click(),
    ]);

    // Verify the temporary event appears in the events list.
    const eventRow = dashboardContent.locator("tr", { hasText: eventName });
    await expect(eventRow).toBeVisible();

    // Reopen the event and verify online details persisted.
    await openEventUpdateFormByName(organizerGroupPage, eventName);
    await organizerGroupPage
      .locator('button[data-section="date-venue"]')
      .click();

    // Verify the correct online meeting state persisted.
    if (E2E_MEETINGS_ENABLED) {
      await expectAutomaticMeetingControls(organizerGroupPage);
      await expect(
        organizerGroupPage.locator(
          'online-event-details input[name="meeting_requested"]',
        ),
      ).toHaveValue("true");
    } else {
      await expect(organizerGroupPage.locator("#meeting_join_url")).toHaveValue(
        "https://meet.example.com/e2e-created-event",
      );
    }

    // Delete the temporary event to keep the seeded list reusable.
    await navigateToPath(organizerGroupPage, "/dashboard/group?tab=events");
    await eventRow.locator(".btn-actions").click();

    // Open the delete confirmation for the temporary event.
    const deleteButton = eventRow.locator('button[id^="delete-event-"]');
    await expect(deleteButton).toBeVisible();
    await deleteButton.click();
    await expect(organizerGroupPage.locator(".swal2-popup")).toContainText(
      "Are you sure you wish to delete this event?",
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
    await expect(
      dashboardContent.locator("tr", { hasText: eventName }),
    ).toHaveCount(0);
  });

  test("organizer can create and delete a recurring event series", async ({
    organizerGroupPage,
  }) => {
    // Create a unique event name for the recurring series flow.
    const eventName = `E2E Recurring Group Event ${Date.now()}`;

    // Load the events list before creating a recurring series.
    await navigateToPath(organizerGroupPage, "/dashboard/group?tab=events");

    // Target dashboard content after the events tab loads.
    const dashboardContent = organizerGroupPage.locator("#dashboard-content");
    await expect(
      dashboardContent.getByText("Events", { exact: true }),
    ).toBeVisible();

    // Open the event form from the dashboard list.
    await dashboardContent.getByRole("button", { name: "Add Event" }).click();
    await expect(organizerGroupPage.locator("#name")).toBeVisible();

    // Fill the core event details for the recurring series.
    await organizerGroupPage.locator("#name").fill(eventName);
    await organizerGroupPage.locator("#kind_id").selectOption("virtual");
    await organizerGroupPage
      .locator("#category_id")
      .selectOption("33333333-3333-3333-3333-333333333331");
    await organizerGroupPage
      .locator("#description_short")
      .fill("A recurring dashboard-created event from the e2e suite.");
    await fillMarkdownEditor(
      organizerGroupPage,
      "description",
      "A recurring dashboard event created and removed by the e2e suite.",
    );

    // Fill the recurring schedule and occurrence count.
    await organizerGroupPage
      .locator('button[data-section="date-venue"]')
      .click();
    await selectTimezone(organizerGroupPage, "UTC");
    await expect(organizerGroupPage.locator("#starts_at")).toBeVisible();
    await organizerGroupPage.locator("#starts_at").fill("2030-05-15T10:00");
    await organizerGroupPage.locator("#ends_at").fill("2030-05-15T12:00");
    await organizerGroupPage
      .locator("#meeting_join_url")
      .fill("https://meet.example.com/e2e-recurring-event");
    await organizerGroupPage
      .locator("#recurrence_pattern")
      .selectOption("weekly");
    await expect(
      organizerGroupPage.locator(
        "#recurrence-additional-occurrences-container",
      ),
    ).toBeVisible();
    await organizerGroupPage
      .locator("#recurrence_additional_occurrences")
      .fill("2");

    // Target the visible submit button after pending changes appear.
    const visibleAddEventButton = organizerGroupPage.locator(
      "#pending-changes-alert:not(.hidden) #add-event-button",
    );
    await expect(
      organizerGroupPage.locator("#pending-changes-alert"),
    ).not.toHaveClass(/hidden/);
    await expect(visibleAddEventButton).toBeVisible();

    // Create the recurring series and wait for the POST response.
    await Promise.all([
      organizerGroupPage.waitForResponse(
        (response) =>
          response.request().method() === "POST" &&
          response.url().includes("/dashboard/group/events/add") &&
          response.status() === 201,
      ),
      visibleAddEventButton.click(),
    ]);

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
      seriesConfirmationDialog
        .getByRole("button", { name: "All in series" })
        .click(),
    ]);

    // Verify every recurring series row is removed from the list.
    await expect(
      dashboardContent.locator("tr", { hasText: eventName }),
    ).toHaveCount(0);
  });

  test("organizer can preview pending event details before saving", async ({
    organizerGroupPage,
  }) => {
    // Create unique draft values for the preview modal.
    const eventName = `E2E Preview Event ${Date.now()}`;
    const lumaUrl = "https://luma.com/e2e-preview-event";

    // Load the events list before opening the create form.
    await navigateToPath(organizerGroupPage, "/dashboard/group?tab=events");
    const dashboardContent = organizerGroupPage.locator("#dashboard-content");
    await dashboardContent.getByRole("button", { name: "Add Event" }).click();
    await expect(organizerGroupPage.locator("#name")).toBeVisible();

    // Fill enough pending details for the preview request.
    await organizerGroupPage.locator("#name").fill(eventName);
    await organizerGroupPage.locator("#kind_id").selectOption("virtual");
    await organizerGroupPage
      .locator("#category_id")
      .selectOption("33333333-3333-3333-3333-333333333331");
    await organizerGroupPage
      .locator("#description_short")
      .fill("Preview coverage for pending event details.");
    await fillMarkdownEditor(
      organizerGroupPage,
      "description",
      "Preview coverage for pending event details before saving.",
    );
    await organizerGroupPage.locator("#luma_url").fill(lumaUrl);
    await organizerGroupPage
      .locator('button[data-section="date-venue"]')
      .click();
    await selectTimezone(organizerGroupPage, "UTC");
    await organizerGroupPage.locator("#starts_at").fill("2030-07-10T10:00");
    await organizerGroupPage.locator("#ends_at").fill("2030-07-10T12:00");
    await organizerGroupPage
      .locator("#meeting_join_url")
      .fill("https://meet.example.com/e2e-preview-event");

    // Open the preview modal and verify pending values are rendered.
    await Promise.all([
      organizerGroupPage.waitForResponse(
        (response) =>
          response.request().method() === "POST" &&
          response.url().includes("/dashboard/group/events/preview") &&
          response.ok(),
      ),
      organizerGroupPage.locator("#event-preview-button").click(),
    ]);
    const previewModal = organizerGroupPage.locator("#event-preview-modal");
    await expect(previewModal).toBeVisible();
    await expect(previewModal).toContainText(eventName);
    await expect(previewModal).toContainText("Preview coverage");
    await expect(previewModal.locator(`a[href="${lumaUrl}"]`)).toBeVisible();

    // Close the modal before leaving the form.
    await previewModal.locator("[data-event-preview-close]").click();
    await expect(previewModal).toHaveCount(0);
  });

  test("organizer can copy details from an existing event", async ({
    organizerGroupPage,
  }) => {
    // Load the events list before opening the create form.
    await navigateToPath(organizerGroupPage, "/dashboard/group?tab=events");
    const dashboardContent = organizerGroupPage.locator("#dashboard-content");
    await dashboardContent.getByRole("button", { name: "Add Event" }).click();
    await expect(organizerGroupPage.locator("#name")).toBeVisible();

    // Open the copy selector and choose the first available existing event.
    await organizerGroupPage.locator("#copy-event-selector").click();
    const eventOption = organizerGroupPage.locator(
      '#dropdown-events button[id^="select-event-"]',
    ).first();
    await expect(eventOption).toBeVisible();
    const copiedEventName = (
      await eventOption.locator("div").nth(1).innerText()
    ).trim();

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
    await expect(organizerGroupPage.locator("#name")).toHaveValue(
      `${copiedEventName} (copy)`,
    );
    await organizerGroupPage
      .locator('button[data-section="date-venue"]')
      .click();
    await expect(organizerGroupPage.locator("#starts_at")).toHaveValue("");
    await expect(organizerGroupPage.locator("#ends_at")).toHaveValue("");
    await expect(organizerGroupPage.locator(".swal2-popup")).toContainText(
      "Event details copied.",
    );
    await organizerGroupPage.getByRole("button", { name: "OK" }).click();
  });

  test("organizer can override recording urls for automatic event and session meetings", async ({
    organizerGroupPage,
  }) => {
    // Skip automatic meeting coverage when the environment disables it.
    test.skip(
      !E2E_MEETINGS_ENABLED,
      "Automatic meetings are disabled in this environment.",
    );

    // Create unique event, session, and recording values for this flow.
    const eventName = `E2E Automatic Recording Override ${Date.now()}`;
    const eventRecordingUrl = `https://youtube.com/watch?v=event-${Date.now()}`;
    const sessionName = `Session ${Date.now()}`;
    const sessionRecordingUrl = `https://youtube.com/watch?v=session-${Date.now()}`;

    // Load the events list before configuring recording overrides.
    await navigateToPath(organizerGroupPage, "/dashboard/group?tab=events");

    // Target dashboard content after the events tab loads.
    const dashboardContent = organizerGroupPage.locator("#dashboard-content");
    await expect(
      dashboardContent.getByText("Events", { exact: true }),
    ).toBeVisible();

    // Open the event form from the dashboard list.
    await dashboardContent.getByRole("button", { name: "Add Event" }).click();
    await expect(organizerGroupPage.locator("#name")).toBeVisible();

    // Fill the core event details for the automatic meeting flow.
    await organizerGroupPage.locator("#name").fill(eventName);
    await organizerGroupPage.locator("#kind_id").selectOption("virtual");
    await organizerGroupPage
      .locator("#category_id")
      .selectOption("33333333-3333-3333-3333-333333333331");
    await organizerGroupPage
      .locator("#description_short")
      .fill("Automatic recording override coverage.");
    await fillMarkdownEditor(
      organizerGroupPage,
      "description",
      "Coverage for automatic event and session recording overrides.",
    );
    await organizerGroupPage.locator("#capacity").fill("25");

    // Fill the event schedule before configuring online recording.
    await organizerGroupPage
      .locator('button[data-section="date-venue"]')
      .click();
    await selectTimezone(organizerGroupPage, "UTC");
    await organizerGroupPage.locator("#starts_at").fill("2030-06-10T10:00");
    await organizerGroupPage.locator("#ends_at").fill("2030-06-10T12:00");

    // Configure automatic meeting recording for the event.
    const eventOnlineDetails = organizerGroupPage.locator(
      "#online-event-details",
    );
    await eventOnlineDetails
      .locator('input[type="radio"][value="automatic"]')
      .check({
        force: true,
      });
    const recordMeetingLabel = eventOnlineDetails.getByText("Record meeting", {
      exact: true,
    });
    const publishRecordingLabel = eventOnlineDetails.getByText(
      "Publish recording publicly",
      {
        exact: true,
      },
    );
    await expect(recordMeetingLabel).toBeVisible();
    await expect(publishRecordingLabel).toBeVisible();
    const [recordMeetingLabelBox, publishRecordingLabelBox] = await Promise.all(
      [recordMeetingLabel.boundingBox(), publishRecordingLabel.boundingBox()],
    );
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
    const eventRecordingPublishedToggle = eventOnlineDetails.getByLabel(
      "Publish recording publicly",
    );
    await expect(eventRecordingPublishedInput).toHaveValue("false");
    await expect(eventRecordingPublishedToggle).not.toBeChecked();
    await eventRecordingPublishedControl.click();
    await expect(eventRecordingPublishedToggle).toBeChecked();
    await expect(eventRecordingPublishedInput).toHaveValue("true");

    // Fill the event recording override URL.
    await eventOnlineDetails
      .locator(
        'input[type="url"][placeholder="https://youtube.com/watch?v=..."]',
      )
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
    await sessionModal
      .locator('select[data-name="kind"]')
      .selectOption("virtual");
    await sessionModal.locator('input[type="time"]').nth(0).fill("10:30");
    await sessionModal.locator('input[type="time"]').nth(1).fill("11:30");

    // Configure automatic meeting recording for the session.
    const sessionOnlineDetails = sessionModal.locator("online-event-details");
    await expect(sessionOnlineDetails).toHaveAttribute("kind", "virtual");
    await expect(sessionOnlineDetails).toHaveAttribute(
      "starts-at",
      "2030-06-10T10:30",
    );
    await expect(sessionOnlineDetails).toHaveAttribute(
      "ends-at",
      "2030-06-10T11:30",
    );
    await sessionOnlineDetails
      .getByText("Create meeting automatically", { exact: true })
      .click();
    await expect(
      sessionOnlineDetails.getByText("Meeting provider", { exact: true }),
    ).toBeVisible();
    const sessionRecordingPublishedInput = sessionOnlineDetails.locator(
      'input[type="hidden"][name="sessions[0][meeting_recording_published]"]',
    );
    const sessionRecordingPublishedControl = sessionOnlineDetails.locator(
      "label",
      {
        hasText: "Publish recording publicly",
      },
    );
    const sessionRecordingPublishedToggle = sessionOnlineDetails.getByLabel(
      "Publish recording publicly",
    );
    await expect(sessionRecordingPublishedInput).toHaveValue("false");
    await expect(sessionRecordingPublishedToggle).not.toBeChecked();
    await sessionRecordingPublishedControl.click();
    await expect(sessionRecordingPublishedToggle).toBeChecked();
    await expect(sessionRecordingPublishedInput).toHaveValue("true");

    // Fill the session recording override and save the session.
    await sessionOnlineDetails
      .locator(
        'input[type="url"][placeholder="https://youtube.com/watch?v=..."]',
      )
      .fill(sessionRecordingUrl);
    await sessionModal.getByRole("button", { name: "Add session" }).click();
    await expect(sessionDialog).toBeHidden();
    await expect(
      sessionsSection.locator(
        'input[name="sessions[0][meeting_recording_published]"]',
      ),
    ).toHaveValue("true");

    // Target the visible submit button after pending changes appear.
    const visibleAddEventButton = organizerGroupPage.locator(
      "#pending-changes-alert:not(.hidden) #add-event-button",
    );
    await expect(visibleAddEventButton).toBeVisible();

    // Create the event and wait for the POST response.
    await Promise.all([
      organizerGroupPage.waitForResponse(
        (response) =>
          response.request().method() === "POST" &&
          response.url().includes("/dashboard/group/events/add") &&
          response.status() === 201,
      ),
      visibleAddEventButton.click(),
    ]);

    // Reopen the event and verify event recording values persisted.
    await openEventUpdateFormByName(organizerGroupPage, eventName);

    // Open date and venue details before checking event recording fields.
    await organizerGroupPage
      .locator('button[data-section="date-venue"]')
      .click();
    await expect(
      eventOnlineDetails.locator(
        'input[type="url"][placeholder="https://youtube.com/watch?v=..."]',
      ),
    ).toHaveValue(eventRecordingUrl);
    await expect(
      eventOnlineDetails.getByLabel("Publish recording publicly"),
    ).toBeChecked();
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
    const reopenedSessionOnlineDetails = sessionModal.locator(
      "online-event-details",
    );
    await expect(
      reopenedSessionOnlineDetails.locator(
        'input[type="url"][placeholder="https://youtube.com/watch?v=..."]',
      ),
    ).toHaveValue(sessionRecordingUrl);
    await expect(
      reopenedSessionOnlineDetails.getByLabel("Publish recording publicly"),
    ).toBeChecked();
    await expect(
      reopenedSessionOnlineDetails.locator(
        'input[type="hidden"][name="sessions[0][meeting_recording_published]"]',
      ),
    ).toHaveValue("true");
    await sessionModal.getByRole("button", { name: "Cancel" }).click();
    await expect(sessionDialog).toBeHidden();
  });

  test("organizer does not see the payments tab when group payments are unavailable", async ({
    organizerGroupWithoutPaymentsPage,
  }) => {
    // Open the create form for a group without payment settings.
    await navigateToPath(
      organizerGroupWithoutPaymentsPage,
      "/dashboard/group?tab=events",
    );

    // Open the create form from the dashboard content.
    const dashboardContent =
      organizerGroupWithoutPaymentsPage.locator("#dashboard-content");
    await dashboardContent.getByRole("button", { name: "Add Event" }).click();

    // Verify the create form hides unavailable payment controls.
    await expect(
      organizerGroupWithoutPaymentsPage.locator(
        'button[data-section="payments"]',
      ),
    ).toHaveCount(0);
    await expect(
      organizerGroupWithoutPaymentsPage.locator('[data-content="payments"]'),
    ).toHaveCount(0);

    // Return to the events list before checking an existing event.
    await navigateToPath(
      organizerGroupWithoutPaymentsPage,
      "/dashboard/group?tab=events",
    );

    // Open an existing event for a group without payment settings.
    const eventRow = dashboardContent.locator("tr", {
      hasText: "Delta Event Two",
    });
    await expect(eventRow).toBeVisible();

    // Open the existing event and wait for update content.
    await Promise.all([
      organizerGroupWithoutPaymentsPage.waitForResponse(
        (response) =>
          response.request().method() === "GET" &&
          response.url().includes("/dashboard/group/events/") &&
          response.url().includes("/update") &&
          response.ok(),
      ),
      eventRow.locator('td button[aria-label^="Edit event:"]').click(),
    ]);

    // Verify the update form hides unavailable payment controls.
    await expect(
      organizerGroupWithoutPaymentsPage.locator(
        'button[data-section="payments"]',
      ),
    ).toHaveCount(0);
    await expect(
      organizerGroupWithoutPaymentsPage.locator('[data-content="payments"]'),
    ).toHaveCount(0);
  });

  test("organizer sees the payments tab when group payments are ready", async ({
    organizerGroupPage,
  }) => {
    // Skip payment tab coverage when the environment disables payments.
    test.skip(
      !E2E_PAYMENTS_ENABLED,
      "Payments are disabled in this environment.",
    );

    // Open the create form for a payment-ready group.
    await navigateToPath(organizerGroupPage, "/dashboard/group?tab=events");

    // Open the create form from the dashboard content.
    const dashboardContent = organizerGroupPage.locator("#dashboard-content");
    await dashboardContent.getByRole("button", { name: "Add Event" }).click();

    // Verify the create form exposes ticketing controls.
    await expect(
      organizerGroupPage.locator('button[data-section="payments"]'),
    ).toBeVisible();
    await openPaymentsSection(organizerGroupPage);
    await expect(
      organizerGroupPage.locator("#payment_currency_code"),
    ).toBeVisible();
    await expect(
      organizerGroupPage.locator("#add-ticket-type-button"),
    ).toBeVisible();
    await expect(
      organizerGroupPage.locator("#add-discount-code-button"),
    ).toBeVisible();

    // Open an existing payment-ready event.
    await navigateToPath(organizerGroupPage, "/dashboard/group?tab=events");
    await openEventUpdateFormByName(
      organizerGroupPage,
      TEST_PAYMENT_EVENT_NAMES.draft,
      TEST_PAYMENT_EVENT_IDS.draft,
    );

    // Verify the update form keeps seeded payment values.
    await expect(
      organizerGroupPage.locator('button[data-section="payments"]'),
    ).toBeVisible();
    await openPaymentsSection(organizerGroupPage);
    await expect(
      organizerGroupPage.locator("#payment_currency_code"),
    ).toHaveValue("USD");
  });

  test("organizer can create a ticketed event with ticket tiers and discount codes", async ({
    organizerGroupPage,
  }) => {
    // Skip ticketing coverage when the environment disables payments.
    test.skip(
      !E2E_PAYMENTS_ENABLED,
      "Payments are disabled in this environment.",
    );

    // Create a unique event name for the ticketing flow.
    const eventName = `E2E Ticketed Event ${Date.now()}`;

    // Open the event form for a payment-ready group.
    await navigateToPath(organizerGroupPage, "/dashboard/group?tab=events");

    // Open the create form from the dashboard content.
    const dashboardContent = organizerGroupPage.locator("#dashboard-content");
    await dashboardContent.getByRole("button", { name: "Add Event" }).click();

    // Fill the core ticketed event details.
    await organizerGroupPage.locator("#name").fill(eventName);
    await organizerGroupPage.locator("#kind_id").selectOption("virtual");
    await organizerGroupPage
      .locator("#category_id")
      .selectOption("33333333-3333-3333-3333-333333333331");
    await organizerGroupPage
      .locator("#description_short")
      .fill("Ticketed dashboard event for payment coverage.");
    await fillMarkdownEditor(
      organizerGroupPage,
      "description",
      "Ticketed dashboard event used to cover ticket tiers and discount codes.",
    );
    await organizerGroupPage.locator("#capacity").fill("25");
    await organizerGroupPage
      .locator("#toggle_waitlist_enabled")
      .check({ force: true });

    // Fill schedule and online meeting details.
    await organizerGroupPage
      .locator('button[data-section="date-venue"]')
      .click();
    await selectTimezone(organizerGroupPage, "UTC");
    await organizerGroupPage.locator("#starts_at").fill("2030-11-12T18:00");
    await organizerGroupPage.locator("#ends_at").fill("2030-11-12T20:00");
    if (E2E_MEETINGS_ENABLED) {
      await enableAutomaticMeetingCreation(organizerGroupPage);
    } else {
      await organizerGroupPage
        .locator("#meeting_join_url")
        .fill("https://meet.example.com/e2e-ticketed-event");
    }

    // Open payments before adding ticketing details.
    await openPaymentsSection(organizerGroupPage);

    // Configure ticketing values and related capacity side effects.
    await addTicketType(organizerGroupPage, {
      title: "Free community pass",
      description: "Free tier used for zero-price coverage.",
      seatsTotal: "12",
      priceWindows: [{ amount: "0" }],
    });

    // Verify currency validation after adding the first ticket type.
    const paymentCurrencyInput = organizerGroupPage.locator(
      "#payment_currency_code",
    );
    await expect(paymentCurrencyInput).toHaveJSProperty("required", true);
    const validationMessage = await paymentCurrencyInput.evaluate(
      (element) => element.validationMessage,
    );
    expect(validationMessage).toBe(
      "Ticketed events require an event currency.",
    );

    // Verify ticketing disables capacity and waitlist fields.
    await expect(
      organizerGroupPage.locator("#toggle_waitlist_enabled"),
    ).toBeDisabled();
    await expect(organizerGroupPage.locator("#waitlist_enabled")).toHaveValue(
      "false",
    );
    await expect(organizerGroupPage.locator("#capacity")).toBeDisabled();
    await expect(organizerGroupPage.locator("#capacity")).toHaveValue("12");

    // Select currency before adding paid ticketing details.
    await paymentCurrencyInput.selectOption("USD");

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

    // Verify ticket capacity contributes to event capacity.
    await expect(organizerGroupPage.locator("#capacity")).toHaveValue("42");

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

    // Create the ticketed event and wait for the POST response.
    const visibleAddEventButton = organizerGroupPage.locator(
      "#pending-changes-alert:not(.hidden) #add-event-button",
    );
    await expect(visibleAddEventButton).toBeVisible();

    // Submit the ticketed event and wait for creation.
    await Promise.all([
      organizerGroupPage.waitForResponse(
        (response) =>
          response.request().method() === "POST" &&
          response.url().includes("/dashboard/group/events/add") &&
          response.status() === 201,
      ),
      visibleAddEventButton.click(),
    ]);

    // Verify the ticketed event appears and dismiss the success dialog.
    const eventRow = dashboardContent.locator("tr", { hasText: eventName });
    await expect(eventRow).toBeVisible();
    await organizerGroupPage.getByRole("button", { name: "OK" }).click();
    await expect(organizerGroupPage.locator(".swal2-popup")).toHaveCount(0);

    // Reopen the event and verify ticketing values persisted.
    await openEventUpdateFormByName(organizerGroupPage, eventName);
    await organizerGroupPage
      .locator('button[data-section="date-venue"]')
      .click();

    // Verify the reopened event keeps online meeting details.
    if (E2E_MEETINGS_ENABLED) {
      await expectAutomaticMeetingControls(organizerGroupPage);
      await expect(
        organizerGroupPage.locator(
          'online-event-details input[name="meeting_requested"]',
        ),
      ).toHaveValue("true");
    } else {
      await expect(organizerGroupPage.locator("#meeting_join_url")).toHaveValue(
        "https://meet.example.com/e2e-ticketed-event",
      );
    }

    // Open payments before checking persisted ticketing details.
    await openPaymentsSection(organizerGroupPage);

    // Verify ticket types and discounts persisted in payment tables.
    await expect(
      organizerGroupPage.locator("#payment_currency_code"),
    ).toHaveValue("USD");
    await expect(
      organizerGroupPage.locator(
        '#ticket-types-ui [data-ticketing-role="table-body"]',
      ),
    ).toContainText("Free community pass");
    await expect(
      organizerGroupPage.locator(
        '#ticket-types-ui [data-ticketing-role="table-body"]',
      ),
    ).toContainText("General admission");
    await expect(
      organizerGroupPage.locator(
        '#discount-codes-ui [data-ticketing-role="table-body"]',
      ),
    ).toContainText("SAVE10");
    await expect(
      organizerGroupPage.locator(
        '#discount-codes-ui [data-ticketing-role="table-body"]',
      ),
    ).toContainText("EARLY20");

    // Delete the temporary event to keep the seeded list reusable.
    await navigateToPath(organizerGroupPage, "/dashboard/group?tab=events");
    await eventRow.locator(".btn-actions").click();

    // Open the delete confirmation for the temporary event.
    const deleteButton = eventRow.locator('button[id^="delete-event-"]');
    await expect(deleteButton).toBeVisible();
    await deleteButton.click();
    await expect(organizerGroupPage.locator(".swal2-popup")).toContainText(
      "Are you sure you wish to delete this event?",
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
    await expect(
      dashboardContent.locator("tr", { hasText: eventName }),
    ).toHaveCount(0);
  });

  test("organizer sees seeded ticketing values on a payment-ready event", async ({
    organizerGroupPage,
  }) => {
    // Skip seeded ticketing coverage when the environment disables payments.
    test.skip(
      !E2E_PAYMENTS_ENABLED,
      "Payments are disabled in this environment.",
    );

    // Open the seeded payment-ready event before checking ticketing.
    await navigateToPath(organizerGroupPage, "/dashboard/group?tab=events");
    await openEventUpdateFormByName(
      organizerGroupPage,
      TEST_PAYMENT_EVENT_NAMES.draft,
      TEST_PAYMENT_EVENT_IDS.draft,
    );
    await openPaymentsSection(organizerGroupPage);

    // Verify seeded ticketing values and capacity side effects.
    await expect(
      organizerGroupPage.locator("#payment_currency_code"),
    ).toHaveValue("USD");
    await expect(organizerGroupPage.locator("#capacity")).toBeDisabled();
    await expect(organizerGroupPage.locator("#capacity")).toHaveValue("42");
    await expect(
      organizerGroupPage.locator("#toggle_waitlist_enabled"),
    ).toBeDisabled();
    await expect(organizerGroupPage.locator("#waitlist_enabled")).toHaveValue(
      "false",
    );
    await expect(
      organizerGroupPage.locator(
        '#ticket-types-ui [data-ticketing-role="table-body"]',
      ),
    ).toContainText("General admission");
    await expect(
      organizerGroupPage.locator(
        '#ticket-types-ui [data-ticketing-role="table-body"]',
      ),
    ).toContainText("Community ticket");
    await expect(
      organizerGroupPage.locator(
        '#ticket-types-ui [data-ticketing-role="table-body"]',
      ),
    ).toContainText("Backstage pass");
    await expect(
      organizerGroupPage.locator(
        '#discount-codes-ui [data-ticketing-role="table-body"]',
      ),
    ).toContainText("SAVE10");
    await expect(
      organizerGroupPage.locator(
        '#discount-codes-ui [data-ticketing-role="table-body"]',
      ),
    ).toContainText("EARLY20");
  });

  test("organizer sees seats and status columns in the ticket types table", async ({
    organizerGroupPage,
  }) => {
    // Skip ticket table coverage when the environment disables payments.
    test.skip(
      !E2E_PAYMENTS_ENABLED,
      "Payments are disabled in this environment.",
    );

    // Open the seeded payment-ready event before checking table columns.
    await navigateToPath(organizerGroupPage, "/dashboard/group?tab=events");
    await openEventUpdateFormByName(
      organizerGroupPage,
      TEST_PAYMENT_EVENT_NAMES.draft,
      TEST_PAYMENT_EVENT_IDS.draft,
    );
    await openPaymentsSection(organizerGroupPage);

    // Target the seeded ticket table and general admission row.
    const ticketTypesTable = organizerGroupPage.locator(
      "#ticket-types-ui table",
    );
    const generalAdmissionRow = ticketTypesTable.locator("tbody tr", {
      hasText: "General admission",
    });

    // Verify the ticket table keeps seat and status columns visible.
    await expect(ticketTypesTable.locator("thead th").nth(1)).toBeVisible();
    await expect(ticketTypesTable.locator("thead th").nth(1)).toContainText(
      "Seats",
    );
    await expect(ticketTypesTable.locator("thead th").nth(2)).toBeVisible();
    await expect(ticketTypesTable.locator("thead th").nth(2)).toContainText(
      "Status",
    );
    await expect(generalAdmissionRow.locator("td").nth(1)).toBeVisible();
    await expect(generalAdmissionRow.locator("td").nth(2)).toBeVisible();
  });

  test("organizer can create, update, and delete an event with images and rich fields", async ({
    organizerGroupPage,
  }) => {
    // Define rich event values for the create and update flow.
    const initialValues = {
      bannerMobilePath: TEST_UPLOAD_ASSET_PATHS.bannerMobile,
      bannerPath: TEST_UPLOAD_ASSET_PATHS.banner,
      capacity: "120",
      categoryId: "33333333-3333-3333-3333-333333333331",
      cfsDescription: "Initial speaker program details for a temporary event.",
      cfsEndsAt: "2030-09-20T17:00",
      cfsLabels: ["track / platform"],
      cfsStartsAt: "2030-09-01T09:00",
      description:
        "Initial full description for a temporary event with rich form coverage.",
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
          id: "initial-question",
          kind: "free-text",
          options: [],
          prompt: "What do you want to learn?",
          required: true,
        },
      ],
      registrationRequired: true,
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
      venueLatitude: "41.3874",
      venueLongitude: "2.1686",
      venueName: "Platform Hall",
      venueZipCode: "08001",
      attendeeApprovalRequired: false,
      waitlistEnabled: true,
    };
    const updatedValues = {
      bannerMobilePath: TEST_UPLOAD_ASSET_PATHS.bannerMobile,
      bannerPath: TEST_UPLOAD_ASSET_PATHS.banner,
      capacity: "180",
      categoryId: "33333333-3333-3333-3333-333333333331",
      cfsDescription: "Updated speaker program details for a temporary event.",
      cfsEndsAt: "2030-09-24T18:00",
      cfsLabels: ["track / devex", "track / cloud"],
      cfsStartsAt: "2030-09-03T10:30",
      description:
        "Updated full description for a temporary event with rich form coverage.",
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
          id: "updated-question",
          kind: "single-select",
          options: [
            { id: "option-one", label: "Platform engineering" },
            { id: "option-two", label: "Developer experience" },
          ],
          prompt: "Which track are you most interested in?",
          required: true,
        },
      ],
      registrationRequired: false,
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
      venueLatitude: "40.4168",
      venueLongitude: "-3.7038",
      venueName: "Cloud Forum",
      venueZipCode: "28001",
      attendeeApprovalRequired: true,
      waitlistEnabled: false,
    };

    // Fill every rich event field used by create and update flows.
    const fillEventForm = async (values) => {
      await organizerGroupPage.locator("#name").fill(values.name);
      await organizerGroupPage.locator("#kind_id").selectOption(values.kindId);
      await organizerGroupPage
        .locator("#category_id")
        .selectOption(values.categoryId);
      await uploadImageField(organizerGroupPage, "logo_url", values.logoPath);
      await uploadImageField(
        organizerGroupPage,
        "banner_url",
        values.bannerPath,
      );
      await uploadImageField(
        organizerGroupPage,
        "banner_mobile_url",
        values.bannerMobilePath,
      );
      await organizerGroupPage
        .locator("#description_short")
        .fill(values.descriptionShort);
      await fillMarkdownEditor(
        organizerGroupPage,
        "description",
        values.description,
      );
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
      if (values.testEvent) {
        await organizerGroupPage
          .locator("#toggle_test_event")
          .check({ force: true });
      } else {
        await organizerGroupPage
          .locator("#toggle_test_event")
          .uncheck({ force: true });
      }
      if (values.attendeeApprovalRequired) {
        await organizerGroupPage
          .locator("#toggle_attendee_approval_required")
          .check({ force: true });
      } else {
        await organizerGroupPage
          .locator("#toggle_attendee_approval_required")
          .uncheck({ force: true });
      }
      if (values.waitlistEnabled) {
        await organizerGroupPage
          .locator("#toggle_waitlist_enabled")
          .check({ force: true });
      } else {
        await organizerGroupPage
          .locator("#toggle_waitlist_enabled")
          .uncheck({ force: true });
      }
      await organizerGroupPage.locator("#meetup_url").fill(values.meetupUrl);
      await organizerGroupPage.locator("#luma_url").fill(values.lumaUrl);
      await fillMultipleInputs(
        organizerGroupPage.locator('multiple-inputs[field-name="tags"]'),
        values.tags,
      );
      await uploadGalleryImages(
        organizerGroupPage,
        "photos_urls",
        values.galleryPaths,
      );

      // Fill registration questions for this values set.
      await organizerGroupPage
        .locator('button[data-section="questions"]')
        .click({ force: true });
      await setRegistrationQuestions(
        organizerGroupPage,
        values.registrationQuestions,
      );

      // Fill hosts and speakers for this values set.
      await organizerGroupPage
        .locator('button[data-section="hosts-sponsors"]')
        .click({ force: true });
      await setEventPeople(organizerGroupPage, values);

      // Fill date, venue, and meeting details for this values set.
      await organizerGroupPage
        .locator('button[data-section="date-venue"]')
        .click({
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
      await organizerGroupPage
        .locator("#meeting_join_url")
        .fill(values.meetingJoinUrl);
      await organizerGroupPage
        .locator("#meeting_recording_url")
        .fill(values.meetingRecordingUrl);

      // Fill CFS fields for this values set.
      const cfsSectionButton = organizerGroupPage.locator(
        'button[data-section="cfs"]',
      );
      await cfsSectionButton.scrollIntoViewIfNeeded();
      await cfsSectionButton.click({ force: true });
      await organizerGroupPage
        .locator("#toggle_cfs_enabled")
        .check({ force: true });
      await organizerGroupPage
        .locator("#cfs_starts_at")
        .fill(values.cfsStartsAt, {
          force: true,
        });
      await organizerGroupPage.locator("#cfs_ends_at").fill(values.cfsEndsAt, {
        force: true,
      });
      await fillMarkdownEditor(
        organizerGroupPage,
        "cfs_description",
        values.cfsDescription,
      );
      await setCfsLabels(organizerGroupPage, values.cfsLabels);
    };

    // Open the edit form from a rich event row and wait for HTMX content.
    const openEventUpdateForm = async (eventRow) => {
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

    // Load the events list before opening the rich event form.
    await navigateToPath(organizerGroupPage, "/dashboard/group?tab=events");

    // Target dashboard content after the events tab loads.
    const dashboardContent = organizerGroupPage.locator("#dashboard-content");
    await expect(
      dashboardContent.getByText("Events", { exact: true }),
    ).toBeVisible();

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
    await Promise.all([
      organizerGroupPage.waitForResponse(
        (response) =>
          response.request().method() === "POST" &&
          response.url().includes("/dashboard/group/events/add") &&
          response.status() === 201,
      ),
      addEventButton.click(),
    ]);

    // Verify the initial temporary event appears in the list.
    let eventRow = dashboardContent.locator("tr", {
      hasText: initialValues.name,
    });
    await expect(eventRow).toBeVisible();

    // Update the event with the second set of rich values.
    await openEventUpdateForm(eventRow);
    await fillEventForm(updatedValues);

    // Submit the update and wait for the server response.
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

    // Verify the updated event name appears in the list.
    eventRow = dashboardContent.locator("tr", { hasText: updatedValues.name });
    await expect(eventRow).toBeVisible();

    // Reopen the form and verify the rich values persisted.
    await openEventUpdateForm(eventRow);
    await expect(organizerGroupPage.locator("#name")).toHaveValue(
      updatedValues.name,
    );
    await expect(organizerGroupPage.locator("#kind_id")).toHaveValue(
      updatedValues.kindId,
    );
    await expect(organizerGroupPage.locator("#category_id")).toHaveValue(
      updatedValues.categoryId,
    );
    await expect
      .poll(async () =>
        (
          await organizerGroupPage.locator("#description_short").inputValue()
        ).trim(),
      )
      .toBe(updatedValues.descriptionShort);
    await expect(organizerGroupPage.locator("#capacity")).toHaveValue(
      updatedValues.capacity,
    );
    await expect(
      organizerGroupPage.locator("#registration_required"),
    ).toHaveValue(String(updatedValues.registrationRequired));
    await expect(organizerGroupPage.locator("#test_event")).toHaveValue(
      String(updatedValues.testEvent),
    );
    await expect(
      organizerGroupPage.locator("#attendee_approval_required"),
    ).toHaveValue(String(updatedValues.attendeeApprovalRequired));
    await expect(organizerGroupPage.locator("#waitlist_enabled")).toHaveValue(
      String(updatedValues.waitlistEnabled),
    );
    await expect(organizerGroupPage.locator("#meetup_url")).toHaveValue(
      updatedValues.meetupUrl,
    );
    await expect(organizerGroupPage.locator("#luma_url")).toHaveValue(
      updatedValues.lumaUrl,
    );
    await expect(
      organizerGroupPage.locator(
        'image-field[name="logo_url"] input[name="logo_url"]',
      ),
    ).toHaveValue(/\/images\//);
    await expect(
      organizerGroupPage.locator(
        'image-field[name="banner_url"] input[name="banner_url"]',
      ),
    ).toHaveValue(/\/images\//);
    await expect(
      organizerGroupPage.locator(
        'image-field[name="banner_mobile_url"] input[name="banner_mobile_url"]',
      ),
    ).toHaveValue(/\/images\//);
    await expect(
      organizerGroupPage.locator(
        'multiple-inputs[field-name="tags"] input[name="tags[]"]',
      ),
    ).toHaveCount(updatedValues.tags.length);
    await organizerGroupPage.locator('button[data-section="questions"]').click();
    await expect(
      organizerGroupPage.locator(
        'questions-editor input[name="registration_questions[0][prompt]"]',
      ),
    ).toHaveValue(updatedValues.registrationQuestions[0].prompt);
    await expect(
      organizerGroupPage.locator(
        'questions-editor input[name="registration_questions[0][options][0][label]"]',
      ),
    ).toHaveValue(updatedValues.registrationQuestions[0].options[0].label);
    await organizerGroupPage
      .locator('button[data-section="hosts-sponsors"]')
      .click();
    await expect(
      organizerGroupPage.locator(
        'user-search-selector[field-name="hosts"] input[name="hosts[]"]',
      ),
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
    await organizerGroupPage
      .locator('button[data-section="date-venue"]')
      .click();
    await expect(
      organizerGroupPage.locator('input[name="timezone"]'),
    ).toHaveValue(updatedValues.timezone);
    await expect(organizerGroupPage.locator("#starts_at")).toHaveValue(
      updatedValues.startsAt,
    );
    await expect(organizerGroupPage.locator("#ends_at")).toHaveValue(
      updatedValues.endsAt,
    );
    await expect(
      organizerGroupPage.locator("#event_reminder_enabled"),
    ).toHaveValue(String(updatedValues.eventReminderEnabled));
    await expect(
      organizerGroupPage.locator("#location-search-venue_name"),
    ).toHaveValue(updatedValues.venueName);
    await expect(
      organizerGroupPage.locator("#location-search-venue_address"),
    ).toHaveValue(updatedValues.venueAddress);
    await expect(
      organizerGroupPage.locator("#location-search-venue_city"),
    ).toHaveValue(updatedValues.venueCity);
    await expect(organizerGroupPage.locator("#meeting_join_url")).toHaveValue(
      updatedValues.meetingJoinUrl,
    );
    await expect(
      organizerGroupPage.locator("#meeting_recording_url"),
    ).toHaveValue(updatedValues.meetingRecordingUrl);
    await organizerGroupPage.locator('button[data-section="cfs"]').click();
    await expect(organizerGroupPage.locator("#cfs_enabled")).toHaveValue(
      "true",
    );
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
      organizerGroupPage.locator(
        'gallery-field[field-name="photos_urls"] input[name="photos_urls[]"]',
      ),
    ).toHaveCount(
      initialValues.galleryPaths.length + updatedValues.galleryPaths.length,
    );

    // Delete the temporary event to keep the seeded list reusable.
    await navigateToPath(organizerGroupPage, "/dashboard/group?tab=events");
    eventRow = dashboardContent.locator("tr", { hasText: updatedValues.name });
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
    await expect(
      dashboardContent.locator("tr", { hasText: updatedValues.name }),
    ).toHaveCount(0);
  });

  test("organizer can unpublish and publish an event from the list", async ({
    organizerGroupPage,
  }) => {
    // Load the events list before changing publish status.
    await navigateToPath(organizerGroupPage, "/dashboard/group?tab=events");

    // Target the seeded published event in the list.
    const dashboardContent = organizerGroupPage.locator("#dashboard-content");
    const eventRow = dashboardContent.locator("tr", {
      hasText: "Upcoming In-Person Event",
    });
    await expect(eventRow).toBeVisible();
    await expect(eventRow).toContainText("Published");

    // Unpublish the seeded event from the actions menu.
    const actionsButton = eventRow.locator(
      `.btn-actions[data-event-id="${TEST_EVENT_IDS.alpha.one}"]`,
    );
    await actionsButton.click();

    // Target the unpublish action after opening the menu.
    const unpublishButton = organizerGroupPage.locator(
      `#unpublish-event-${TEST_EVENT_IDS.alpha.one}`,
    );
    await expect(unpublishButton).toBeVisible();

    // Confirm unpublish and wait for the server response.
    await Promise.all([
      organizerGroupPage.waitForResponse(
        (response) =>
          response.request().method() === "PUT" &&
          response
            .url()
            .includes(
              `/dashboard/group/events/${TEST_EVENT_IDS.alpha.one}/unpublish`,
            ) &&
          response.ok(),
      ),
      unpublishButton.click(),
      organizerGroupPage.getByRole("button", { name: "Yes" }).click(),
    ]);

    // Verify the event row reflects draft state.
    await expect(eventRow).toContainText("Draft");

    // Publish the seeded event again to restore the original state.
    await eventRow
      .locator(`.btn-actions[data-event-id="${TEST_EVENT_IDS.alpha.one}"]`)
      .click();

    // Target the publish action after opening the menu.
    const publishButton = organizerGroupPage.locator(
      `#publish-event-${TEST_EVENT_IDS.alpha.one}`,
    );
    await expect(publishButton).toBeVisible();

    // Confirm publish and wait for the server response.
    await Promise.all([
      organizerGroupPage.waitForResponse(
        (response) =>
          response.request().method() === "PUT" &&
          response
            .url()
            .includes(
              `/dashboard/group/events/${TEST_EVENT_IDS.alpha.one}/publish`,
            ) &&
          response.ok(),
      ),
      publishButton.click(),
      organizerGroupPage.getByRole("button", { name: "Yes" }).click(),
    ]);

    // Verify the event row returns to published state.
    await expect(eventRow).toContainText("Published");
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
      await Promise.all([
        organizerGroupPage.waitForResponse(
          (response) =>
            response.request().method() === "GET" &&
            response
              .url()
              .includes(
                `/dashboard/group/events/${TEST_EVENT_IDS.alpha.cfsSummit}/update`,
              ) &&
            response.ok(),
        ),
        eventRow
          .locator(
            `td button[hx-get="/dashboard/group/events/${TEST_EVENT_IDS.alpha.cfsSummit}/update"]`,
          )
          .click(),
      ]);
    };

    // Read editable values from the seeded CFS summit form.
    const readEventValues = async () => {
      await openCfsSummitEditor();

      // Return the editable values needed for update and restore.
      return {
        cfsEndsAt: await organizerGroupPage
          .locator("#cfs_ends_at")
          .inputValue(),
        cfsStartsAt: await organizerGroupPage
          .locator("#cfs_starts_at")
          .inputValue(),
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
      await expect(
        organizerGroupPage.locator('button[data-section="date-venue"]'),
      ).toHaveAttribute("data-active", "true");
      await expect(organizerGroupPage.locator("#starts_at")).toBeVisible();
      await organizerGroupPage.locator("#starts_at").fill(values.startsAt);
      await organizerGroupPage.locator("#ends_at").fill(values.endsAt);

      // Fill CFS values in the CFS tab.
      await organizerGroupPage.locator('button[data-section="cfs"]').click();
      await expect(organizerGroupPage.locator("#cfs_starts_at")).toBeVisible();
      await organizerGroupPage
        .locator("#cfs_starts_at")
        .fill(values.cfsStartsAt);
      await organizerGroupPage.locator("#cfs_ends_at").fill(values.cfsEndsAt);
      await expect(
        organizerGroupPage.locator("#pending-changes-alert"),
      ).not.toHaveClass(/hidden/);

      // Submit the seeded event update and wait for the server response.
      await Promise.all([
        organizerGroupPage.waitForResponse(
          (response) =>
            response.request().method() === "PUT" &&
            response
              .url()
              .includes(
                `/dashboard/group/events/${TEST_EVENT_IDS.alpha.cfsSummit}/update`,
              ) &&
            response.ok(),
        ),
        organizerGroupPage.locator("#update-event-button").click(),
      ]);
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
    await expect(organizerGroupPage.locator("#name")).toHaveValue(
      updatedValues.name,
    );
    await expect(organizerGroupPage.locator("#meetup_url")).toHaveValue(
      updatedValues.meetupUrl,
    );
    await organizerGroupPage
      .locator('button[data-section="date-venue"]')
      .click();
    await expect(organizerGroupPage.locator("#starts_at")).toHaveValue(
      updatedValues.startsAt,
    );
    await expect(organizerGroupPage.locator("#ends_at")).toHaveValue(
      updatedValues.endsAt,
    );
    await organizerGroupPage.locator('button[data-section="cfs"]').click();
    await expect(organizerGroupPage.locator("#cfs_starts_at")).toHaveValue(
      updatedValues.cfsStartsAt,
    );
    await expect(organizerGroupPage.locator("#cfs_ends_at")).toHaveValue(
      updatedValues.cfsEndsAt,
    );

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
    await Promise.all([
      organizerGroupPage.waitForResponse(
        (response) =>
          response.request().method() === "GET" &&
          response
            .url()
            .includes(
              `/dashboard/group/events/${TEST_EVENT_IDS.alpha.one}/update`,
            ) &&
          response.ok(),
      ),
      eventRow
        .locator(
          `td button[hx-get="/dashboard/group/events/${TEST_EVENT_IDS.alpha.one}/update"]`,
        )
        .click(),
    ]);

    // Remove dates from the event to trigger the sessions warning.
    await organizerGroupPage
      .locator('button[data-section="date-venue"]')
      .click();
    await expect(organizerGroupPage.locator("#starts_at")).toBeVisible();
    await organizerGroupPage.locator("#starts_at").fill("");
    await organizerGroupPage.locator("#ends_at").fill("");

    // Verify pending changes are visible before submitting.
    await expect(
      organizerGroupPage.locator("#pending-changes-alert"),
    ).not.toHaveClass(/hidden/);

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
