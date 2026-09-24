import { expect, test } from "../../../fixtures.js";

import { TEST_EVENT_IDS, TEST_PAYMENT_EVENT_NAMES } from "../../../seed.js";

import { navigateToPath, selectTimezone, uniqueName, waitForActionResponse } from "../../../utils.js";

import { fillMarkdownEditor } from "../../form-helpers.js";

import {
  deleteEventFromList,
  openEventUpdateFormByName,
  openPaymentsSection,
  waitForEventEditorAfterSave,
} from "./helpers.js";

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
    await expect(addSectionSelect.locator('option[value="date-venue"]')).toHaveText("Date & Venue");
    await expect(addSectionSelect.locator('option[value="payments"], option[value="sessions"]')).toHaveText([
      "Tickets",
      "Sessions",
    ]);
    await expect(
      organizerGroupPage.locator('button[data-section="payments"], button[data-section="sessions"]'),
    ).toHaveText(["Tickets", "Sessions"]);
    await expect(addSectionSelect.locator('option[value="attendees"]')).toHaveCount(0);
    await expect(addSectionSelect.locator('option[value="waitlist"]')).toHaveCount(0);

    // Advance the add form to the date and venue section.
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
    await organizerGroupPage.locator("button[data-section-next]").click();
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
    await organizerGroupPage.locator("button[data-section-next]").click();
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
});
