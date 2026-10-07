import { expect, test } from "../../../fixtures.js";

import { queryE2eDatabase } from "../../../database.js";
import { cleanupEventsByIds } from "../../../data-graphs/events.js";
import { TEST_EVENT_IDS, TEST_PAYMENT_EVENT_NAMES, TEST_USER_IDS } from "../../../seed.js";

import {
  futureDate,
  navigateToPath,
  selectTimezone,
  uniqueName,
  waitForActionResponse,
} from "../../../utils.js";

import { fillMarkdownEditor } from "../../form-helpers.js";

import {
  deleteEventFromList,
  expectSearchDropdownInViewport,
  listEventLabels,
  listSessionLabels,
  openEventUpdateFormByName,
  openPaymentsSection,
  scrollToViewportBottom,
  waitForEventEditorAfterSave,
} from "./helpers.js";

import {
  addSession,
  expectSessionCardLabels,
  openLabelsSection,
  openSessionsSection,
  setLabels,
} from "./event-form-helpers.js";

// Palette colors used by the label editor; new labels start with the first one.
const DEFAULT_LABEL_COLOR = "#FFD866";
const RECOLORED_LABEL_COLOR = "#AB9DF2";

test.describe("group dashboard event editor", () => {
  test("organizer sees the expected add and edit event form tabs", async ({ organizerGroupPage }) => {
    // Load the events dashboard before opening the add form.
    await navigateToPath(organizerGroupPage, "/dashboard/group?tab=events");

    // Open the add form and verify its available sections.
    const additionalInformationToggles = organizerGroupPage.locator(
      "label:has(#toggle_waitlist_enabled), label:has(#toggle_attendee_approval_required), label:has(#toggle_test_event)",
    );
    const dashboardContent = organizerGroupPage.locator("#dashboard-content");
    await dashboardContent.getByRole("button", { name: "Add Event" }).click();
    await expect(organizerGroupPage.locator("#name")).toBeVisible();
    await expect(additionalInformationToggles).toHaveText([
      "Enable Waitlist",
      "Require Invitation Approval",
      "Test Event",
    ]);

    // The add form exposes authoring tabs and omits review-only tabs.
    const addSectionSelect = organizerGroupPage.locator('select[aria-label="Event form section"]');
    await expect(addSectionSelect.locator('option[value="details"]')).toHaveText("Details");
    await expect(addSectionSelect.locator('option[value="cohosts"]')).toHaveText("Co-hosts");
    await expect(addSectionSelect.locator('option[value="date-venue"]')).toHaveText("Date & Venue");
    await expect(addSectionSelect.locator('option[value="payments"], option[value="sessions"]')).toHaveText([
      "Tickets",
      "Sessions",
    ]);
    await expect(
      organizerGroupPage.locator('button[data-section="payments"], button[data-section="sessions"]'),
    ).toHaveText(["Tickets", "Sessions"]);
    await expect(
      organizerGroupPage.locator(
        'button[data-section="sessions"], button[data-section="labels"], button[data-section="questions"], button[data-section="cfs"]',
      ),
    ).toHaveText(["Sessions", "Labels", "Questions", "CFS"]);
    await expect(addSectionSelect.locator('option[value="attendees"]')).toHaveCount(0);
    await expect(addSectionSelect.locator('option[value="waitlist"]')).toHaveCount(0);

    // Advance the add form through co-hosts to the date and venue section.
    await organizerGroupPage.locator("button[data-section-next]").click();
    await expect(organizerGroupPage.locator('button[data-section="cohosts"]')).toHaveAttribute(
      "data-active",
      "true",
    );
    await organizerGroupPage.locator("button[data-section-next]").click();
    await expect(organizerGroupPage.locator('button[data-section="date-venue"]')).toHaveAttribute(
      "data-active",
      "true",
    );

    // Open an existing event and verify review tabs lazy-load their tables.
    await navigateToPath(organizerGroupPage, "/dashboard/group?tab=events");
    await openEventUpdateFormByName(
      organizerGroupPage,
      "Full Event With Waitlist",
      TEST_EVENT_IDS.alpha.waitlistLab,
    );
    await expect(additionalInformationToggles).toHaveText([
      "Enable Waitlist",
      "Require Invitation Approval",
      "Test Event",
    ]);

    // Verify the existing event exposes review-only attendee sections.
    const editSectionSelect = organizerGroupPage.locator('select[aria-label="Event form section"]');
    await expect(editSectionSelect.locator('option[value="payments"], option[value="sessions"]')).toHaveText([
      "Tickets",
      "Sessions",
    ]);
    await expect(
      organizerGroupPage.locator('button[data-section="payments"], button[data-section="sessions"]'),
    ).toHaveText(["Tickets", "Sessions"]);
    await expect(editSectionSelect.locator('option[value="attendees"]')).toHaveText("Attendees");
    await expect(editSectionSelect.locator('option[value="waitlist"]')).toHaveText("Waitlist");
    await expect(organizerGroupPage.locator("#waitlist-loading")).toHaveCount(1);

    // Open the waitlist tab and wait for its lazy-loaded content.
    await waitForActionResponse(
      organizerGroupPage,
      () => organizerGroupPage.locator('button[data-section="waitlist"]').click(),
      {
        method: "GET",
        urlIncludes: `/dashboard/group/events/${TEST_EVENT_IDS.alpha.waitlistLab}/waitlist`,
      },
    );

    // Verify the waitlist tab activates and swaps in table content.
    await expect(organizerGroupPage.locator('button[data-section="waitlist"]')).toHaveAttribute(
      "data-active",
      "true",
    );
    await expect(organizerGroupPage.locator("#waitlist-content").getByRole("table")).toBeVisible();
  });

  test("event form sections switch through the compact selector below the xl breakpoint", async ({
    organizerGroupPage,
  }) => {
    // Open an existing event form using a viewport below the xl breakpoint.
    await organizerGroupPage.setViewportSize({ width: 1024, height: 900 });
    await navigateToPath(organizerGroupPage, "/dashboard/group?tab=events");
    await openEventUpdateFormByName(
      organizerGroupPage,
      "Full Event With Waitlist",
      TEST_EVENT_IDS.alpha.waitlistLab,
    );

    // Verify the compact selector replaces the tab list below the xl breakpoint.
    const sectionSelect = organizerGroupPage.locator('select[aria-label="Event form section"]');
    const dateVenueTabButton = organizerGroupPage.locator('button[data-section="date-venue"]');
    await expect(sectionSelect).toBeVisible();
    await expect(dateVenueTabButton).toBeHidden();

    // Switch sections through the selector and verify the section content swaps.
    await expect(organizerGroupPage.locator("#name")).toBeVisible();
    await sectionSelect.selectOption("date-venue");
    await expect(organizerGroupPage.locator("#starts_at")).toBeVisible();
    await expect(organizerGroupPage.locator("#name")).toBeHidden();

    // Verify the selector also lazy-loads review sections while tabs stay hidden.
    await waitForActionResponse(organizerGroupPage, () => sectionSelect.selectOption("waitlist"), {
      method: "GET",
      urlIncludes: `/dashboard/group/events/${TEST_EVENT_IDS.alpha.waitlistLab}/waitlist`,
    });
    await expect(organizerGroupPage.locator("#waitlist-content").getByRole("table")).toBeVisible();

    // Verify the tab list replaces the selector once the xl breakpoint is reached.
    await organizerGroupPage.setViewportSize({ width: 1280, height: 900 });
    await expect(sectionSelect).toBeHidden();
    await expect(dateVenueTabButton).toBeVisible();
  });

  test("organizer can preview pending event details before saving", async ({ organizerGroupPage }) => {
    // Create unique draft values for the preview modal.
    const eventName = uniqueName("Preview Event");
    const lumaUrl = "https://luma.com/e2e-preview-event";

    // Load the events list before opening the create form.
    await navigateToPath(organizerGroupPage, "/dashboard/group?tab=events");
    const dashboardContent = organizerGroupPage.locator("#dashboard-content");
    await dashboardContent.getByRole("button", { name: "Add Event" }).click();
    await expect(organizerGroupPage.locator("#name")).toBeVisible();

    // Fill enough pending details for the preview request.
    await organizerGroupPage.locator("#name").fill(eventName);
    await organizerGroupPage.locator("#kind_id").selectOption("virtual");
    await organizerGroupPage.locator("#category_id").selectOption("33333333-3333-3333-3333-333333333331");
    await organizerGroupPage
      .locator("#description_short")
      .fill("Preview coverage for pending event details.");
    await fillMarkdownEditor(
      organizerGroupPage,
      "description",
      "Preview coverage for pending event details before saving.",
    );
    await organizerGroupPage.locator("#luma_url").fill(lumaUrl);
    await organizerGroupPage.locator('button[data-section="date-venue"]').click();
    await selectTimezone(organizerGroupPage, "UTC");
    await organizerGroupPage.locator("#starts_at").fill("2030-07-10T10:00");
    await organizerGroupPage.locator("#ends_at").fill("2030-07-10T12:00");
    await organizerGroupPage.locator("#meeting_join_url").fill("https://meet.example.com/e2e-preview-event");

    // Open the preview modal and verify pending values are rendered.
    await waitForActionResponse(
      organizerGroupPage,
      () => organizerGroupPage.locator("#event-preview-button").click(),
      {
        method: "POST",
        urlIncludes: "/dashboard/group/events/preview",
      },
    );
    const previewModal = organizerGroupPage.locator("#event-preview-modal");
    await expect(previewModal).toBeVisible();
    await expect(previewModal).toContainText(eventName);
    await expect(previewModal).toContainText("Preview coverage");
    const lumaLinks = previewModal.locator(`a[href="${lumaUrl}"]`);
    await expect(lumaLinks).toHaveCount(2);
    await expect(lumaLinks.first()).toBeVisible();

    // Close the modal before leaving the form.
    await previewModal.getByRole("button", { name: "Close modal" }).click();
    await expect(previewModal).toHaveCount(0);
  });

  test("failed event save preserves the entered details for retry", async ({ organizerGroupPage }) => {
    // Load the add form before intercepting its create request.
    await navigateToPath(organizerGroupPage, "/dashboard/group?tab=events");
    const dashboardContent = organizerGroupPage.locator("#dashboard-content");
    await dashboardContent.getByRole("button", { name: "Add Event" }).click();
    await expect(organizerGroupPage.locator("#name")).toBeVisible();

    // Fill the add form with draft values that must survive failure.
    const eventName = uniqueName("Failed Save Event");
    await organizerGroupPage.locator("#name").fill(eventName);
    await organizerGroupPage.locator("#kind_id").selectOption("virtual");
    await organizerGroupPage.locator("#category_id").selectOption("33333333-3333-3333-3333-333333333331");
    await organizerGroupPage
      .locator("#description_short")
      .fill("A dashboard event used to cover failed save preservation.");
    await fillMarkdownEditor(
      organizerGroupPage,
      "description",
      "Failed save coverage keeps the draft on the add page.",
    );
    await organizerGroupPage.locator('button[data-section="date-venue"]').click();
    await selectTimezone(organizerGroupPage, "UTC");
    await organizerGroupPage.locator("#starts_at").fill("2030-08-10T10:00");
    await organizerGroupPage.locator("#ends_at").fill("2030-08-10T12:00");
    await organizerGroupPage.locator("#meeting_join_url").fill("https://meet.example.com/e2e-failed-save");

    // Target the visible save action and its intercepted add endpoint.
    const visibleAddEventButton = organizerGroupPage.locator(
      "#pending-changes-alert:not(.hidden) #add-event-button",
    );
    await expect(visibleAddEventButton).toBeVisible();
    const addPath = "**/dashboard/group/events/add";

    try {
      // Return a local server failure without creating the event.
      await organizerGroupPage.route(addPath, async (route) => {
        if (route.request().method() !== "POST") {
          await route.continue();
          return;
        }
        await route.fulfill({
          body: "Temporary event failure",
          contentType: "text/plain",
          status: 500,
        });
      });
      await waitForActionResponse(organizerGroupPage, () => visibleAddEventButton.click(), {
        method: "POST",
        status: 500,
        urlIncludes: "/dashboard/group/events/add",
      });

      // Verify the error and retry state keep the unsaved draft intact.
      await expect(organizerGroupPage.locator(".swal2-popup")).toContainText(
        "Something went wrong creating the event. Please try again later.",
      );
      await expect(organizerGroupPage.locator('[data-event-page="add"]')).toBeVisible();
      await expect(organizerGroupPage.locator("#name")).toHaveValue(eventName);
      await expect(organizerGroupPage.locator("#starts_at")).toHaveValue("2030-08-10T10:00");
      await expect(visibleAddEventButton).toBeEnabled();
    } finally {
      // Remove the failing add-event route after the preservation check.
      await organizerGroupPage.unroute(addPath);
    }
  });

  test("organizer stays on the event editor after save and publish", async ({ organizerGroupPage }) => {
    // Create a unique draft for editor save and publish coverage.
    const eventName = uniqueName("Editor Stay Event");
    await navigateToPath(organizerGroupPage, "/dashboard/group?tab=events");
    const dashboardContent = organizerGroupPage.locator("#dashboard-content");
    await dashboardContent.getByRole("button", { name: "Add Event" }).click();
    await expect(organizerGroupPage.locator("#name")).toBeVisible();
    await organizerGroupPage.locator("#name").fill(eventName);
    await organizerGroupPage.locator("#kind_id").selectOption("virtual");
    await organizerGroupPage.locator("#category_id").selectOption("33333333-3333-3333-3333-333333333331");
    await organizerGroupPage
      .locator("#description_short")
      .fill("A dashboard event used to cover staying on the editor.");
    await fillMarkdownEditor(
      organizerGroupPage,
      "description",
      "Editor save coverage keeps the organizer on the update page.",
    );
    await organizerGroupPage.locator('button[data-section="date-venue"]').click();
    await selectTimezone(organizerGroupPage, "UTC");
    await organizerGroupPage.locator("#starts_at").fill("2030-08-11T10:00");
    await organizerGroupPage.locator("#ends_at").fill("2030-08-11T12:00");
    await organizerGroupPage.locator("#meeting_join_url").fill("https://meet.example.com/e2e-editor-stay");

    // Save the draft and wait for the editor to reopen on the created event.
    const visibleAddEventButton = organizerGroupPage.locator(
      "#pending-changes-alert:not(.hidden) #add-event-button",
    );
    await expect(visibleAddEventButton).toBeVisible();
    await waitForActionResponse(organizerGroupPage, () => visibleAddEventButton.click(), {
      method: "POST",
      status: 201,
      urlIncludes: "/dashboard/group/events/add",
    });
    const eventId = await waitForEventEditorAfterSave(organizerGroupPage);

    try {
      // A later save stays on the update page with a clean pending-changes banner.
      await organizerGroupPage.locator('button[data-section="details"]').click();
      const updatedName = `${eventName} Updated`;
      await organizerGroupPage.locator("#name").fill(updatedName);
      await waitForEventEditorAfterSave(
        organizerGroupPage,
        () => organizerGroupPage.locator("#update-event-button").click(),
        {
          eventId,
          method: "PUT",
          urlIncludes: `/dashboard/group/events/${eventId}/update`,
        },
      );
      await expect(organizerGroupPage.locator("#name")).toHaveValue(updatedName);
      await expect(organizerGroupPage.locator("#pending-changes-alert")).toHaveClass(/hidden/);

      // Publish from the editor reloads the same update page.
      await organizerGroupPage.locator("#publish-event-button").click();
      await waitForEventEditorAfterSave(
        organizerGroupPage,
        () => organizerGroupPage.getByRole("button", { name: "Yes" }).click(),
        {
          eventId,
          method: "PUT",
          urlIncludes: `/dashboard/group/events/${eventId}/publish`,
        },
      );
      await expect(organizerGroupPage.locator("#event-public-page-link")).toBeVisible();
      await expect(organizerGroupPage.locator("#publish-event-button")).toBeDisabled();

      // The reloaded editor must still replace the attendees loading placeholder.
      await waitForActionResponse(
        organizerGroupPage,
        () => organizerGroupPage.locator('button[data-section="attendees"]').click(),
        {
          method: "GET",
          status: 200,
          urlIncludes: `/dashboard/group/events/${eventId}/attendees`,
        },
      );
      await expect(organizerGroupPage.getByRole("table", { name: "Attendees list" })).toBeVisible();
      await expect(organizerGroupPage.locator("#attendees-loading")).toHaveCount(0);
    } finally {
      // Delete the temporary event created for the editor flow.
      await deleteEventFromList(organizerGroupPage, eventId);
    }
  });

  test("organizer can clear the event short description", async ({ organizerGroupPage }) => {
    // Create a unique draft with a short description.
    const descriptionShort = "A dashboard event used to cover clearing the short description.";
    await navigateToPath(organizerGroupPage, "/dashboard/group?tab=events");
    const dashboardContent = organizerGroupPage.locator("#dashboard-content");
    await dashboardContent.getByRole("button", { name: "Add Event" }).click();
    await expect(organizerGroupPage.locator("#name")).toBeVisible();
    await organizerGroupPage.locator("#name").fill(uniqueName("Editor Short Description Event"));
    await organizerGroupPage.locator("#kind_id").selectOption("virtual");
    await organizerGroupPage.locator("#category_id").selectOption("33333333-3333-3333-3333-333333333331");
    await organizerGroupPage.locator("#description_short").fill(descriptionShort);
    await fillMarkdownEditor(
      organizerGroupPage,
      "description",
      "Editor coverage for clearing the event short description.",
    );
    await organizerGroupPage.locator('button[data-section="date-venue"]').click();
    await selectTimezone(organizerGroupPage, "UTC");
    await organizerGroupPage.locator("#starts_at").fill("2030-08-12T10:00");
    await organizerGroupPage.locator("#ends_at").fill("2030-08-12T12:00");
    await organizerGroupPage
      .locator("#meeting_join_url")
      .fill("https://meet.example.com/e2e-editor-short-description");

    // Save the draft and wait for the editor to reopen on the created event.
    const visibleAddEventButton = organizerGroupPage.locator(
      "#pending-changes-alert:not(.hidden) #add-event-button",
    );
    await expect(visibleAddEventButton).toBeVisible();
    await waitForActionResponse(organizerGroupPage, () => visibleAddEventButton.click(), {
      method: "POST",
      status: 201,
      urlIncludes: "/dashboard/group/events/add",
    });
    const eventId = await waitForEventEditorAfterSave(organizerGroupPage);

    try {
      // The reloaded editor renders the saved short description without padding.
      await organizerGroupPage.locator('button[data-section="details"]').click();
      await expect(organizerGroupPage.locator("#description_short")).toHaveValue(descriptionShort);

      // Clearing the short description saves and reloads an empty field.
      await organizerGroupPage.locator("#description_short").fill("");
      await waitForEventEditorAfterSave(
        organizerGroupPage,
        () => organizerGroupPage.locator("#update-event-button").click(),
        {
          eventId,
          method: "PUT",
          urlIncludes: `/dashboard/group/events/${eventId}/update`,
        },
      );
      await organizerGroupPage.locator('button[data-section="details"]').click();
      await expect(organizerGroupPage.locator("#description_short")).toHaveValue("");
    } finally {
      // Delete the temporary event created for the editor flow.
      await deleteEventFromList(organizerGroupPage, eventId);
    }
  });

  test("organizer can copy event details and payment configuration", async ({ organizerGroupPage }) => {
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

  test("organizer can create labels and assign one to a new session in one save with CFS disabled", async ({
    organizerGroupPage,
  }) => {
    const eventName = uniqueName("Labels Single Save Event");
    const sessionName = uniqueName("Labeled session");
    let eventId;

    try {
      // Fill a draft event and keep the Call for Speakers disabled.
      await fillEventDraft(organizerGroupPage, eventName, 90);
      await expect(organizerGroupPage.locator("#toggle_cfs_enabled")).not.toBeChecked();

      // Create two labels through the Labels tab.
      await openLabelsSection(organizerGroupPage);
      const labelsEditor = organizerGroupPage.locator("labels-editor");
      const labelNameInputs = labelsEditor.getByLabel("Label", { exact: true });
      await labelNameInputs.nth(0).fill("track / backend");
      await labelsEditor.getByRole("button", { name: "Add label" }).click();
      await labelNameInputs.nth(1).fill("track / frontend");

      // Assign one of the new labels to a new session.
      await addSession(organizerGroupPage, {
        endTime: "11:00",
        labels: ["track / frontend"],
        name: sessionName,
        startTime: "10:30",
      });
      await expectSessionCardLabels(organizerGroupPage, sessionName, ["track / frontend"]);

      // Save labels and session together and verify the submitted contract.
      const addRequest = organizerGroupPage.waitForRequest(
        (request) => request.method() === "POST" && request.url().includes("/dashboard/group/events/add"),
      );
      eventId = await saveNewEvent(organizerGroupPage);
      const params = new URLSearchParams((await addRequest).postData() ?? "");
      expect(params.get("labels_present")).toBe("true");
      expect(params.get("labels[1][name]")).toBe("track / frontend");
      expect(params.get("labels[1][is_new]")).toBe("true");
      expect(params.get("sessions[0][label_ids_present]")).toBe("true");
      expect(params.get("sessions[0][label_ids][0]")).toBe(params.get("labels[1][event_label_id]"));

      // Reload the editor and verify the labels and the session assignment persisted.
      await reopenEventEditor(organizerGroupPage, eventName, eventId);
      await openLabelsSection(organizerGroupPage);
      await expect(labelNameInputs).toHaveCount(2);
      await expect(labelNameInputs.nth(0)).toHaveValue("track / backend");
      await expect(labelNameInputs.nth(1)).toHaveValue("track / frontend");
      await openSessionsSection(organizerGroupPage);
      await expectSessionCardLabels(organizerGroupPage, sessionName, ["track / frontend"]);
      expect(listSessionLabels(eventId)).toEqual([{ labels: ["track / frontend"], name: sessionName }]);
    } finally {
      // Remove the temporary event and its labels.
      if (eventId) {
        cleanupEventsByIds([eventId]);
      }
    }
  });

  test("organizer can rename and recolor a label used by a session", async ({ organizerGroupPage }) => {
    const eventName = uniqueName("Labels Rename Event");
    const sessionName = uniqueName("Renamed label session");
    let eventId;

    try {
      // Create an event with one label assigned to a session.
      eventId = await createEventWithLabeledSession(organizerGroupPage, {
        days: 91,
        eventName,
        labels: ["track / ops"],
        session: { labels: ["track / ops"], name: sessionName, startTime: "10:30" },
      });
      const [originalLabel] = listEventLabels(eventId);
      expect(originalLabel.color).toBe(DEFAULT_LABEL_COLOR);

      // Rename the label and pick another palette color.
      await openLabelsSection(organizerGroupPage);
      const labelsEditor = organizerGroupPage.locator("labels-editor");
      await labelsEditor.getByLabel("Label", { exact: true }).fill("track / platform ops");
      await labelsEditor.getByRole("button", { name: /^Pick label color/ }).click();
      await labelsEditor.getByRole("option", { name: `Select color ${RECOLORED_LABEL_COLOR}` }).click();
      await expect(labelsEditor.getByRole("button", { name: /^Pick label color/ })).toHaveAttribute(
        "aria-label",
        `Pick label color. Selected color is ${RECOLORED_LABEL_COLOR}`,
      );

      // Save and verify the session chip uses the new name and color.
      await saveEventUpdate(organizerGroupPage, eventId);
      await openSessionsSection(organizerGroupPage);
      await expectSessionCardLabels(organizerGroupPage, sessionName, ["track / platform ops"]);
      const sessionChip = organizerGroupPage
        .locator("sessions-section session-card")
        .filter({ hasText: sessionName })
        .locator(".custom-badge");
      await expect(sessionChip).toHaveAttribute(
        "style",
        new RegExp(`--label-color:${RECOLORED_LABEL_COLOR}`),
      );

      // The label keeps its id, so the session assignment is unchanged.
      expect(listEventLabels(eventId)).toEqual([
        { color: RECOLORED_LABEL_COLOR, id: originalLabel.id, name: "track / platform ops" },
      ]);
      expect(listSessionLabels(eventId)).toEqual([{ labels: ["track / platform ops"], name: sessionName }]);
    } finally {
      // Remove the temporary event and its labels.
      if (eventId) {
        cleanupEventsByIds([eventId]);
      }
    }
  });

  test("a blank saved label name blocks the save and fixing it keeps session assignments", async ({
    organizerGroupPage,
  }) => {
    const eventName = uniqueName("Labels Blank Name Event");
    const sessionName = uniqueName("Blank label session");
    let eventId;

    try {
      // Create an event with one label assigned to a session.
      eventId = await createEventWithLabeledSession(organizerGroupPage, {
        days: 92,
        eventName,
        labels: ["track / data"],
        session: { labels: ["track / data"], name: sessionName, startTime: "10:30" },
      });
      const [originalLabel] = listEventLabels(eventId);

      // Blank the saved label name with whitespace only.
      await openLabelsSection(organizerGroupPage);
      const labelNameInput = organizerGroupPage.locator("labels-editor").getByLabel("Label", { exact: true });
      await labelNameInput.fill("   ");

      // Try to save and verify the browser blocks it on the Labels tab.
      let updateRequestsCount = 0;
      const countUpdateRequests = (request) => {
        if (
          request.method() === "PUT" &&
          request.url().includes(`/dashboard/group/events/${eventId}/update`)
        ) {
          updateRequestsCount += 1;
        }
      };
      organizerGroupPage.on("request", countUpdateRequests);
      try {
        await openSessionsSection(organizerGroupPage);
        await organizerGroupPage.locator("#update-event-button").click();
        await expect(organizerGroupPage.locator('button[data-section="labels"]')).toHaveAttribute(
          "data-active",
          "true",
        );
        await expect(labelNameInput).toHaveJSProperty("validationMessage", "Label name is required");
        expect(updateRequestsCount).toBe(0);
      } finally {
        organizerGroupPage.off("request", countUpdateRequests);
      }

      // Fix the name, save, and verify the session keeps the same label.
      await labelNameInput.fill("track / data science");
      await expect(labelNameInput).toHaveJSProperty("validationMessage", "");
      await saveEventUpdate(organizerGroupPage, eventId);
      await openSessionsSection(organizerGroupPage);
      await expectSessionCardLabels(organizerGroupPage, sessionName, ["track / data science"]);
      expect(listEventLabels(eventId)).toEqual([
        { color: originalLabel.color, id: originalLabel.id, name: "track / data science" },
      ]);
      expect(listSessionLabels(eventId)).toEqual([{ labels: ["track / data science"], name: sessionName }]);
    } finally {
      // Remove the temporary event and its labels.
      if (eventId) {
        cleanupEventsByIds([eventId]);
      }
    }
  });

  test("deleting a label with its trash button removes it from sessions", async ({ organizerGroupPage }) => {
    const eventName = uniqueName("Labels Delete Event");
    const sessionName = uniqueName("Deleted label session");
    let eventId;

    try {
      // Create an event with two labels assigned to a session.
      eventId = await createEventWithLabeledSession(organizerGroupPage, {
        days: 93,
        eventName,
        labels: ["track / keep", "track / remove"],
        session: { labels: ["track / keep", "track / remove"], name: sessionName, startTime: "10:30" },
      });
      await openSessionsSection(organizerGroupPage);
      await expectSessionCardLabels(organizerGroupPage, sessionName, ["track / keep", "track / remove"]);

      // Delete one label through its trash button.
      await openLabelsSection(organizerGroupPage);
      const labelsEditor = organizerGroupPage.locator("labels-editor");
      const labelNameInputs = labelsEditor.getByLabel("Label", { exact: true });
      await expect(labelNameInputs.nth(1)).toHaveValue("track / remove");
      await labelsEditor.getByRole("button", { name: "Remove label" }).nth(1).click();
      await expect(labelNameInputs).toHaveCount(1);
      await expect(labelNameInputs).toHaveValue("track / keep");

      // The session drops the deleted label before and after saving.
      await openSessionsSection(organizerGroupPage);
      await expectSessionCardLabels(organizerGroupPage, sessionName, ["track / keep"]);
      await saveEventUpdate(organizerGroupPage, eventId);
      await openSessionsSection(organizerGroupPage);
      await expectSessionCardLabels(organizerGroupPage, sessionName, ["track / keep"]);
      expect(listEventLabels(eventId).map((label) => label.name)).toEqual(["track / keep"]);
      expect(listSessionLabels(eventId)).toEqual([{ labels: ["track / keep"], name: sessionName }]);
    } finally {
      // Remove the temporary event and its labels.
      if (eventId) {
        cleanupEventsByIds([eventId]);
      }
    }
  });

  test("organizer can clear the labels of a session", async ({ organizerGroupPage }) => {
    const eventName = uniqueName("Labels Clear Session Event");
    const sessionName = uniqueName("Cleared labels session");
    let eventId;

    try {
      // Create an event with two labels assigned to a session.
      eventId = await createEventWithLabeledSession(organizerGroupPage, {
        days: 94,
        eventName,
        labels: ["track / one", "track / two"],
        session: { labels: ["track / one", "track / two"], name: sessionName, startTime: "10:30" },
      });

      // Remove every label from the session in the edit modal.
      await openSessionsSection(organizerGroupPage);
      await organizerGroupPage
        .locator("sessions-section session-card")
        .filter({ hasText: sessionName })
        .getByTitle("Edit")
        .click();
      const sessionModal = organizerGroupPage.locator("session-form-modal");
      const sessionDialog = sessionModal.getByRole("dialog", { name: "Edit session" });
      await expect(sessionDialog).toBeVisible();
      const labelSelector = sessionModal.locator("label-selector");
      await labelSelector.getByRole("button", { name: "Remove track / one", exact: true }).click();
      await labelSelector.getByRole("button", { name: "Remove track / two", exact: true }).click();
      await sessionModal.getByRole("button", { name: "Save changes" }).click();
      await expect(sessionDialog).toHaveCount(0);

      // The session submits an explicit empty label list.
      await expectSessionCardLabels(organizerGroupPage, sessionName, []);
      const sessionsSection = organizerGroupPage.locator("sessions-section");
      await expect(sessionsSection.locator('input[name="sessions[0][label_ids_present]"]')).toHaveValue(
        "true",
      );
      await expect(sessionsSection.locator('input[name^="sessions[0][label_ids]["]')).toHaveCount(0);

      // Save and verify the session has no labels while the event keeps them.
      await saveEventUpdate(organizerGroupPage, eventId);
      await openSessionsSection(organizerGroupPage);
      await expectSessionCardLabels(organizerGroupPage, sessionName, []);
      expect(listEventLabels(eventId).map((label) => label.name)).toEqual(["track / one", "track / two"]);
      expect(listSessionLabels(eventId)).toEqual([{ labels: [], name: sessionName }]);
    } finally {
      // Remove the temporary event and its labels.
      if (eventId) {
        cleanupEventsByIds([eventId]);
      }
    }
  });

  test("copying an event copies its label definitions with new ids and no sessions", async ({
    organizerGroupPage,
  }) => {
    const sourceEventName = uniqueName("Labels Source Event");
    let copiedEventId;
    let sourceEventId;

    try {
      // Create a source event with labels and a labeled session.
      sourceEventId = await createEventWithLabeledSession(organizerGroupPage, {
        days: 95,
        eventName: sourceEventName,
        labels: ["track / copy a", "track / copy b"],
        session: {
          labels: ["track / copy b"],
          name: uniqueName("Copied source session"),
          startTime: "10:30",
        },
      });
      const sourceLabelIds = listEventLabels(sourceEventId).map((label) => label.id);

      // The copy selector searches published events, so publish the source without notifications.
      queryE2eDatabase(`
        update event
        set published = true, published_at = current_timestamp, published_by = '${TEST_USER_IDS.organizer1}'
        where event_id = '${sourceEventId}'
      `);

      // Open the add form and copy the source event.
      await navigateToPath(organizerGroupPage, "/dashboard/group?tab=events");
      await organizerGroupPage
        .locator("#dashboard-content")
        .getByRole("button", { name: "Add Event" })
        .click();
      await expect(organizerGroupPage.locator("#name")).toBeVisible();
      await organizerGroupPage.locator("#copy-event-selector").click();
      await organizerGroupPage.locator("#dropdown-events #event-search-input").fill(sourceEventName);
      const eventOption = organizerGroupPage
        .locator('#dropdown-events button[id^="select-event-"]')
        .filter({ hasText: sourceEventName });
      await waitForActionResponse(organizerGroupPage, () => eventOption.click(), {
        method: "GET",
        urlIncludes: `/dashboard/group/events/${sourceEventId}/details`,
      });
      await expect(organizerGroupPage.locator(".swal2-popup")).toContainText("Event details copied.");
      await organizerGroupPage.getByRole("button", { name: "OK" }).click();

      // Verify the label definitions are copied as new labels.
      await openLabelsSection(organizerGroupPage);
      const labelsEditor = organizerGroupPage.locator("labels-editor");
      await expect(labelsEditor.getByLabel("Label", { exact: true })).toHaveCount(2);
      const copiedNameInputs = labelsEditor.locator('input[name^="labels"][name$="[name]"]');
      await expect(copiedNameInputs.nth(0)).toHaveValue("track / copy a");
      await expect(copiedNameInputs.nth(1)).toHaveValue("track / copy b");
      await expect(labelsEditor.locator('input[name^="labels"][name$="[is_new]"]')).toHaveCount(2);
      const copiedFormLabelIds = await labelsEditor
        .locator('input[name^="labels"][name$="[event_label_id]"]')
        .evaluateAll((inputs) => inputs.map((input) => input.value));
      expect(copiedFormLabelIds).toHaveLength(2);
      expect(copiedFormLabelIds.filter((labelId) => sourceLabelIds.includes(labelId))).toEqual([]);

      // Verify sessions are not copied.
      await openSessionsSection(organizerGroupPage);
      await expect(organizerGroupPage.locator("sessions-section session-card")).toHaveCount(0);
      await expect(organizerGroupPage.locator('sessions-section input[name^="sessions["]')).toHaveCount(0);

      // Schedule and save the copy, then verify its stored labels and sessions.
      await organizerGroupPage.locator('button[data-section="date-venue"]').click();
      await organizerGroupPage.locator("#starts_at").fill(futureDate({ days: 96, hour: 10 }));
      await organizerGroupPage.locator("#ends_at").fill(futureDate({ days: 96, hour: 12 }));
      copiedEventId = await saveNewEvent(organizerGroupPage);
      const copiedLabels = listEventLabels(copiedEventId);
      expect(copiedLabels.map((label) => label.name)).toEqual(["track / copy a", "track / copy b"]);
      expect(copiedLabels.filter((label) => sourceLabelIds.includes(label.id))).toEqual([]);
      expect(listSessionLabels(copiedEventId)).toEqual([]);
    } finally {
      // Remove the source and copied events with their labels.
      cleanupEventsByIds([sourceEventId, copiedEventId].filter(Boolean));
    }
  });

  test("location search results stay inside the viewport near its bottom", async ({ organizerGroupPage }) => {
    // Return a full page of deterministic location results.
    await organizerGroupPage.route(/nominatim\.openstreetmap\.org\/search/, (route) =>
      route.fulfill({
        json: Array.from({ length: 10 }, (_, index) => ({
          place_id: index + 1,
          display_name: `E2E Venue ${index + 1}, Málaga, Andalusia, Spain`,
        })),
      }),
    );

    // Open the add form venue section in a short viewport.
    await organizerGroupPage.setViewportSize({ width: 1280, height: 600 });
    await navigateToPath(organizerGroupPage, "/dashboard/group?tab=events");
    await organizerGroupPage.locator("#dashboard-content").getByRole("button", { name: "Add Event" }).click();
    await expect(organizerGroupPage.locator("#name")).toBeVisible();
    await organizerGroupPage.locator('button[data-section="date-venue"]').click();

    // Search locations with the input at the viewport bottom.
    const locationInput = organizerGroupPage.locator("#location-search-input");
    const locationDropdown = organizerGroupPage.locator("[data-location-search-dropdown]");
    await scrollToViewportBottom(locationInput);
    await locationInput.fill("Málaga");
    await locationInput.press("Enter");
    await expect(locationDropdown.getByRole("option")).toHaveCount(10);

    // Verify the results open above the input inside the viewport.
    await expectSearchDropdownInViewport(organizerGroupPage, locationInput, locationDropdown, {
      above: true,
    });
  });
});

/**
 * Creates a draft event with labels and one labeled session in a single save.
 * @param {import("@playwright/test").Page} page - Playwright page.
 * @param {{
 *   days: number,
 *   eventName: string,
 *   labels: string[],
 *   session: { labels: string[], name: string, startTime: string }
 * }} values - Event, label, and session values.
 * @returns {Promise<string>} Created event id, with its editor open.
 */
const createEventWithLabeledSession = async (page, values) => {
  await fillEventDraft(page, values.eventName, values.days);
  await setLabels(page, values.labels);
  await addSession(page, values.session);

  return saveNewEvent(page);
};

/**
 * Opens the add event form and fills the details and single-day schedule of a draft.
 * @param {import("@playwright/test").Page} page - Playwright page.
 * @param {string} eventName - Event name.
 * @param {number} days - Days from today when the event takes place.
 */
const fillEventDraft = async (page, eventName, days) => {
  await navigateToPath(page, "/dashboard/group?tab=events");
  await page.locator("#dashboard-content").getByRole("button", { name: "Add Event" }).click();
  await expect(page.locator("#name")).toBeVisible();
  await page.locator("#name").fill(eventName);
  await page.locator("#kind_id").selectOption("virtual");
  await page.locator("#category_id").selectOption("33333333-3333-3333-3333-333333333331");
  await page.locator("#description_short").fill("A dashboard event used to cover event labels.");
  await fillMarkdownEditor(page, "description", "Event labels coverage for sessions and the editor.");
  await page.locator('button[data-section="date-venue"]').click();
  await selectTimezone(page, "UTC");
  await page.locator("#starts_at").fill(futureDate({ days, hour: 10 }));
  await page.locator("#ends_at").fill(futureDate({ days, hour: 12 }));
  await page.locator("#meeting_join_url").fill("https://meet.example.com/e2e-event-labels");
};

/** Reopens the update editor of an event from the events list. */
const reopenEventEditor = async (page, eventName, eventId) => {
  await navigateToPath(page, "/dashboard/group?tab=events");
  await openEventUpdateFormByName(page, eventName, eventId);
};

/** Saves the event update form and waits for the editor to reload. */
const saveEventUpdate = async (page, eventId) => {
  await waitForEventEditorAfterSave(page, () => page.locator("#update-event-button").click(), {
    eventId,
    method: "PUT",
    urlIncludes: `/dashboard/group/events/${eventId}/update`,
  });
};

/** Saves the add event form and returns the created event id once its editor opens. */
const saveNewEvent = async (page) => {
  const visibleAddEventButton = page.locator("#pending-changes-alert:not(.hidden) #add-event-button");
  await expect(visibleAddEventButton).toBeVisible();
  await waitForActionResponse(page, () => visibleAddEventButton.click(), {
    method: "POST",
    status: 201,
    urlIncludes: "/dashboard/group/events/add",
  });

  return waitForEventEditorAfterSave(page);
};
