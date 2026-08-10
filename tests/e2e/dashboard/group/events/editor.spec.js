import { expect, test } from "../../../fixtures.js";

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
} from "../../../utils.js";
import {
  TEST_UPLOAD_ASSET_PATHS,
  fillEventVenue,
  fillMarkdownEditor,
  fillMultipleInputs,
  uploadGalleryImages,
  uploadImageField,
} from "../../form-helpers.js";
import {
  addDiscountCode,
  openEventUpdateFormByName,
  openPaymentsSection,
} from "./helpers.js";

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
} from "./event-form-helpers.js";

test.describe("group dashboard event editor", () => {
  test("organizer sees the expected add and edit event form tabs", async ({
    organizerGroupPage,
  }) => {
    // Load the events dashboard before opening the add form.
    await navigateToPath(organizerGroupPage, "/dashboard/group?tab=events");

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
    const addSectionSelect = organizerGroupPage.locator(
      'select[aria-label="Event form section"]',
    );
    await expect(
      addSectionSelect.locator('option[value="details"]'),
    ).toHaveText("Details");
    await expect(
      addSectionSelect.locator('option[value="date-venue"]'),
    ).toHaveText("Date & Venue");
    await expect(
      addSectionSelect.locator(
        'option[value="payments"], option[value="sessions"]',
      ),
    ).toHaveText(["Tickets", "Sessions"]);
    await expect(
      organizerGroupPage.locator(
        'button[data-section="payments"], button[data-section="sessions"]',
      ),
    ).toHaveText(["Tickets", "Sessions"]);
    await expect(
      addSectionSelect.locator('option[value="attendees"]'),
    ).toHaveCount(0);
    await expect(
      addSectionSelect.locator('option[value="waitlist"]'),
    ).toHaveCount(0);

    await organizerGroupPage.locator("button[data-section-next]").click();
    await expect(
      organizerGroupPage.locator('button[data-section="date-venue"]'),
    ).toHaveAttribute("data-active", "true");

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

    const editSectionSelect = organizerGroupPage.locator(
      'select[aria-label="Event form section"]',
    );
    await expect(
      editSectionSelect.locator(
        'option[value="payments"], option[value="sessions"]',
      ),
    ).toHaveText(["Tickets", "Sessions"]);
    await expect(
      organizerGroupPage.locator(
        'button[data-section="payments"], button[data-section="sessions"]',
      ),
    ).toHaveText(["Tickets", "Sessions"]);
    await expect(
      editSectionSelect.locator('option[value="attendees"]'),
    ).toHaveText("Attendees");
    await expect(
      editSectionSelect.locator('option[value="waitlist"]'),
    ).toHaveText("Waitlist");
    await expect(organizerGroupPage.locator("#waitlist-loading")).toHaveCount(
      1,
    );

    await waitForActionResponse(
      organizerGroupPage,
      () =>
        organizerGroupPage.locator('button[data-section="waitlist"]').click(),
      {
        method: "GET",
        urlIncludes: `/dashboard/group/events/${TEST_EVENT_IDS.alpha.waitlistLab}/waitlist`,
      },
    );

    // Verify the waitlist tab activates and swaps in table content.
    await expect(
      organizerGroupPage.locator('button[data-section="waitlist"]'),
    ).toHaveAttribute("data-active", "true");
    await expect(
      organizerGroupPage.locator("#waitlist-content").getByRole("table"),
    ).toBeVisible();
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
    const sectionSelect = organizerGroupPage.locator(
      'select[aria-label="Event form section"]',
    );
    const dateVenueTabButton = organizerGroupPage.locator(
      'button[data-section="date-venue"]',
    );
    await expect(sectionSelect).toBeVisible();
    await expect(dateVenueTabButton).toBeHidden();

    // Switch sections through the selector and verify the section content swaps.
    await expect(organizerGroupPage.locator("#name")).toBeVisible();
    await sectionSelect.selectOption("date-venue");
    await expect(organizerGroupPage.locator("#starts_at")).toBeVisible();
    await expect(organizerGroupPage.locator("#name")).toBeHidden();

    // Verify the selector also lazy-loads review sections while tabs stay hidden.
    await waitForActionResponse(
      organizerGroupPage,
      () => sectionSelect.selectOption("waitlist"),
      {
        method: "GET",
        urlIncludes: `/dashboard/group/events/${TEST_EVENT_IDS.alpha.waitlistLab}/waitlist`,
      },
    );
    await expect(
      organizerGroupPage.locator("#waitlist-content").getByRole("table"),
    ).toBeVisible();

    // Verify the tab list replaces the selector once the xl breakpoint is reached.
    await organizerGroupPage.setViewportSize({ width: 1280, height: 900 });
    await expect(sectionSelect).toBeHidden();
    await expect(dateVenueTabButton).toBeVisible();
  });

  test("requests tab is only offered for approval-required events", async ({
    organizerGroupPage,
  }) => {
    // Open the seeded approval-required event form first.
    await navigateToPath(organizerGroupPage, "/dashboard/group?tab=events");
    await openEventUpdateFormByName(
      organizerGroupPage,
      TEST_APPROVAL_REQUIRED_EVENT.name,
      TEST_APPROVAL_REQUIRED_EVENT.id,
    );

    // Verify the requests tab is present in both section pickers.
    const sectionSelect = organizerGroupPage.locator(
      'select[aria-label="Event form section"]',
    );
    await expect(
      organizerGroupPage.locator('button[data-section="invitation-requests"]'),
    ).toBeVisible();
    await expect(
      sectionSelect.locator('option[value="invitation-requests"]'),
    ).toHaveCount(1);

    // Open an event without attendee approval and verify the tab is absent.
    await navigateToPath(organizerGroupPage, "/dashboard/group?tab=events");
    await openEventUpdateFormByName(
      organizerGroupPage,
      "Full Event With Waitlist",
      TEST_EVENT_IDS.alpha.waitlistLab,
    );
    await expect(
      organizerGroupPage.locator('button[data-section="invitation-requests"]'),
    ).toHaveCount(0);
    await expect(
      sectionSelect.locator('option[value="invitation-requests"]'),
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
});
