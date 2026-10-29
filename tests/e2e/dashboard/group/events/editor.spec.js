import { expect, test } from "../../../fixtures.js";

import { queryCount, queryE2eDatabase, queryE2eDatabaseRows, sqlString, sqlUuid } from "../../../database.js";
import { cleanupEventsByIds } from "../../../data-graphs/events.js";
import {
  TEST_CANCELED_PUBLIC_EVENT,
  TEST_COMMUNITY_NAME,
  TEST_EVENT_CATEGORY_IDS,
  TEST_EVENT_IDS,
  TEST_GROUP_IDS,
  TEST_GROUP_SLUGS,
  TEST_PAYMENT_EVENT_IDS,
  TEST_PAYMENT_EVENT_NAMES,
  TEST_UNPUBLISHED_EVENT,
  TEST_USER_IDS,
} from "../../../seed.js";

import {
  confirmAlert,
  futureDate,
  navigateToEvent,
  navigateToPath,
  selectTimezone,
  uniqueName,
  waitForActionResponse,
} from "../../../utils.js";

import { fillMarkdownEditor } from "../../form-helpers.js";
import { getAttendanceContainer, waitForAttendanceState } from "../../../site/event/helpers.js";

import {
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

// Header and save controls a role without event management sees disabled on an unpublished event.
const DISABLED_ROLE_EDITOR_CONTROLS = {
  "#event-preview-button": "Your role cannot preview events.",
  "#event-public-page-link": "Event must be published.",
  "#publish-event-button": "Your role cannot publish events.",
  "#update-event-button": "Your role cannot update events.",
};

// Event editors that render read-only, by role fixture and event state.
const EDITOR_READ_ONLY_CASES = [
  {
    disabledControls: DISABLED_ROLE_EDITOR_CONTROLS,
    event: TEST_UNPUBLISHED_EVENT,
    eventLabel: "unpublished",
    fixture: "checkInManagerGroupPage",
    label: "check-in manager",
    warning: "Your role cannot update events.",
  },
  {
    disabledControls: DISABLED_ROLE_EDITOR_CONTROLS,
    event: TEST_UNPUBLISHED_EVENT,
    eventLabel: "unpublished",
    fixture: "groupViewerPage",
    label: "group viewer",
    warning: "Your role cannot update events.",
  },
  {
    disabledControls: {
      "#publish-event-button": "Canceled events cannot be published.",
      "#update-event-button": "Canceled events are read-only.",
    },
    event: TEST_CANCELED_PUBLIC_EVENT,
    eventLabel: "canceled",
    fixture: "organizerGroupPage",
    label: "organizer",
    warning:
      "This event is canceled. Event details are read-only, but attendee and refund review tools remain available.",
  },
];

// Non-UTC event timezone used to prove registration window conversions.
const REGISTRATION_WINDOW_TIME_ZONE = "America/New_York";

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
        'button[data-section="payments"], button[data-section="questions"], button[data-section="labels"], button[data-section="cfs"], button[data-section="sessions"]',
      ),
    ).toHaveText(["Tickets", "Questions", "Labels", "CFS", "Sessions"]);
    await expect(addSectionSelect.locator('option[value="attendees"]')).toHaveCount(0);
    await expect(addSectionSelect.locator('option[value="surveys"]')).toHaveCount(0);
    await expect(addSectionSelect.locator('option[value="waitlist"]')).toHaveCount(0);

    // Verify the add form groups only the authoring tabs by lifecycle.
    await expect
      .poll(() =>
        addSectionSelect.locator("optgroup").evaluateAll((groups) => groups.map((group) => group.label)),
      )
      .toEqual(["EVENT", "REGISTRATION", "PROGRAM"]);
    await expect(
      organizerGroupPage
        .getByRole("navigation", { name: "Event form sections" })
        .locator('[id^="add-event-section-"][id$="-heading"]'),
    ).toHaveText(["Event", "Registration", "Program"]);

    // Advance the add form through the date and venue section to co-hosts.
    await organizerGroupPage.locator("button[data-section-next]").click();
    await expect(organizerGroupPage.locator('button[data-section="date-venue"]')).toHaveAttribute(
      "data-active",
      "true",
    );
    await organizerGroupPage.locator("button[data-section-next]").click();
    await expect(organizerGroupPage.locator('button[data-section="cohosts"]')).toHaveAttribute(
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
    await expect
      .poll(() =>
        editSectionSelect.locator("optgroup").evaluateAll((groups) => groups.map((group) => group.label)),
      )
      .toEqual(["EVENT", "REGISTRATION", "PROGRAM", "PEOPLE", "FOLLOW-UP"]);
    await expect(editSectionSelect.locator('optgroup[label="PEOPLE"] option[value="waitlist"]')).toHaveCount(
      1,
    );
    await expect(editSectionSelect.locator('optgroup[label="FOLLOW-UP"] option')).toHaveText([
      "Surveys",
      "Analytics",
    ]);
    await expect
      .poll(() =>
        organizerGroupPage
          .getByRole("navigation", { name: "Event form sections" })
          .locator("button[data-section]")
          .evaluateAll((buttons) => buttons.map((button) => button.dataset.section)),
      )
      .toEqual(
        await editSectionSelect
          .locator("option")
          .evaluateAll((options) => options.map((option) => option.value)),
      );
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
    await organizerGroupPage.locator("#category_id").selectOption(TEST_EVENT_CATEGORY_IDS.general);
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
    await organizerGroupPage.locator("#starts_at").fill(futureDate({ days: 225, hour: 10 }));
    await organizerGroupPage.locator("#ends_at").fill(futureDate({ days: 225, hour: 12 }));
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
    await organizerGroupPage.locator("#category_id").selectOption(TEST_EVENT_CATEGORY_IDS.general);
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
    const startsAt = futureDate({ days: 256, hour: 10 });
    await organizerGroupPage.locator("#starts_at").fill(startsAt);
    await organizerGroupPage.locator("#ends_at").fill(futureDate({ days: 256, hour: 12 }));
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
      await expect(organizerGroupPage.locator("#starts_at")).toHaveValue(startsAt);
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
    await organizerGroupPage.locator("#category_id").selectOption(TEST_EVENT_CATEGORY_IDS.general);
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
    await organizerGroupPage.locator("#starts_at").fill(futureDate({ days: 257, hour: 10 }));
    await organizerGroupPage.locator("#ends_at").fill(futureDate({ days: 257, hour: 12 }));
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
        () => confirmAlert(organizerGroupPage, { message: "Are you sure you wish to publish this event?" }),
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
      cleanupEventsByIds([eventId]);
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
    await organizerGroupPage.locator("#category_id").selectOption(TEST_EVENT_CATEGORY_IDS.general);
    await organizerGroupPage.locator("#description_short").fill(descriptionShort);
    await fillMarkdownEditor(
      organizerGroupPage,
      "description",
      "Editor coverage for clearing the event short description.",
    );
    await organizerGroupPage.locator('button[data-section="date-venue"]').click();
    await selectTimezone(organizerGroupPage, "UTC");
    await organizerGroupPage.locator("#starts_at").fill(futureDate({ days: 258, hour: 10 }));
    await organizerGroupPage.locator("#ends_at").fill(futureDate({ days: 258, hour: 12 }));
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
      cleanupEventsByIds([eventId]);
    }
  });

  test("registration window is saved in the event timezone and shown on the public page", async ({
    member2Page,
    organizerGroupPage,
    owned,
  }) => {
    // Create a published New York event with no registration window.
    const event = owned.event({
      groupId: TEST_GROUP_IDS.community1.alpha,
      meetingJoinUrl: "https://meet.example.com/e2e-registration-window",
      name: uniqueName("Registration Window Event"),
      startsAt: futureDate({ days: 60, hour: 10 }),
      timezone: REGISTRATION_WINDOW_TIME_ZONE,
    });

    // Set a future window; 9:30 PM in New York is the next day in UTC.
    const registrationStartsAt = futureDate({ days: 50, hour: 9, minute: 15 });
    const registrationEndsAt = futureDate({ days: 55, hour: 21, minute: 30 });
    await reopenEventEditor(organizerGroupPage, event.name, event.eventId);
    await organizerGroupPage.locator('button[data-section="date-venue"]').click();
    await organizerGroupPage.locator("#registration_starts_at").fill(registrationStartsAt);
    await organizerGroupPage.locator("#registration_ends_at").fill(registrationEndsAt);
    await saveEventUpdate(organizerGroupPage, event.eventId);

    // Verify the stored instants are the entered New York wall-clock times.
    const [savedWindow] = queryE2eDatabaseRows(`
      select
        to_char(registration_starts_at at time zone ${sqlString(REGISTRATION_WINDOW_TIME_ZONE)}, 'YYYY-MM-DD"T"HH24:MI'),
        to_char(registration_ends_at at time zone ${sqlString(REGISTRATION_WINDOW_TIME_ZONE)}, 'YYYY-MM-DD"T"HH24:MI'),
        extract(epoch from registration_starts_at)::bigint,
        extract(epoch from registration_ends_at)::bigint
      from event
      where event_id = ${sqlUuid(event.eventId)};
    `);
    const [savedStartsAt, savedEndsAt, startsAtEpoch, endsAtEpoch] = savedWindow;
    expect([savedStartsAt, savedEndsAt]).toEqual([registrationStartsAt, registrationEndsAt]);

    // Reopen the editor and verify the inputs render the same local times.
    await reopenEventEditor(organizerGroupPage, event.name, event.eventId);
    await organizerGroupPage.locator('button[data-section="date-venue"]').click();
    await expect(organizerGroupPage.locator("#registration_starts_at")).toHaveValue(registrationStartsAt);
    await expect(organizerGroupPage.locator("#registration_ends_at")).toHaveValue(registrationEndsAt);

    // Verify the public page keeps registration closed and shows the window in New York time.
    const expectedMessage =
      `Registration opens ${formatRegistrationWindowTime(startsAtEpoch)} ` +
      `and closes ${formatRegistrationWindowTime(endsAtEpoch)}.`;
    await navigateToEvent(member2Page, TEST_COMMUNITY_NAME, TEST_GROUP_SLUGS.community1.alpha, event.slug);
    await waitForAttendanceState(member2Page);
    const attendanceContainer = getAttendanceContainer(member2Page);
    await expect(attendanceContainer).toHaveAttribute("data-registration-window-open", "false");
    await expect(attendanceContainer).toHaveAttribute("data-registration-window-message", expectedMessage);
    await expect(member2Page.locator("[data-registration-window-message-display]")).toHaveText(
      expectedMessage,
    );
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
    await waitForActionResponse(organizerGroupPage, () => eventOption.click(), {
      method: "GET",
      pathname: `/dashboard/group/events/${TEST_PAYMENT_EVENT_IDS.draft}/details`,
      status: 200,
    });

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
    owned,
  }) => {
    const eventName = uniqueName("Labels Single Save Event");
    const sessionName = uniqueName("Labeled session");

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
    const eventId = owned.track(await saveNewEvent(organizerGroupPage), (id) => cleanupEventsByIds([id]));
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
  });

  test("organizer can rename and recolor a label used by a session", async ({
    organizerGroupPage,
    owned,
  }) => {
    const eventName = uniqueName("Labels Rename Event");
    const sessionName = uniqueName("Renamed label session");

    // Create an event with one label assigned to a session.
    const eventId = owned.track(
      await createEventWithLabeledSession(organizerGroupPage, {
        days: 91,
        eventName,
        labels: ["track / ops"],
        session: { labels: ["track / ops"], name: sessionName, startTime: "10:30" },
      }),
      (id) => cleanupEventsByIds([id]),
    );
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
    await expect(sessionChip).toHaveAttribute("style", new RegExp(`--label-color:${RECOLORED_LABEL_COLOR}`));

    // The label keeps its id, so the session assignment is unchanged.
    expect(listEventLabels(eventId)).toEqual([
      { color: RECOLORED_LABEL_COLOR, id: originalLabel.id, name: "track / platform ops" },
    ]);
    expect(listSessionLabels(eventId)).toEqual([{ labels: ["track / platform ops"], name: sessionName }]);
  });

  test("a blank saved label name blocks the save and fixing it keeps session assignments", async ({
    organizerGroupPage,
    owned,
  }) => {
    const eventName = uniqueName("Labels Blank Name Event");
    const sessionName = uniqueName("Blank label session");

    // Create an event with one label assigned to a session.
    const eventId = owned.track(
      await createEventWithLabeledSession(organizerGroupPage, {
        days: 92,
        eventName,
        labels: ["track / data"],
        session: { labels: ["track / data"], name: sessionName, startTime: "10:30" },
      }),
      (id) => cleanupEventsByIds([id]),
    );
    const [originalLabel] = listEventLabels(eventId);

    // Blank the saved label name with whitespace only.
    await openLabelsSection(organizerGroupPage);
    const labelNameInput = organizerGroupPage.locator("labels-editor").getByLabel("Label", { exact: true });
    await labelNameInput.fill("   ");

    // Try to save and verify the browser blocks it on the Labels tab.
    let updateRequestsCount = 0;
    const countUpdateRequests = (request) => {
      if (request.method() === "PUT" && request.url().includes(`/dashboard/group/events/${eventId}/update`)) {
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
  });

  test("deleting a label with its trash button removes it from sessions", async ({
    organizerGroupPage,
    owned,
  }) => {
    const eventName = uniqueName("Labels Delete Event");
    const sessionName = uniqueName("Deleted label session");

    // Create an event with two labels assigned to a session.
    const eventId = owned.track(
      await createEventWithLabeledSession(organizerGroupPage, {
        days: 93,
        eventName,
        labels: ["track / keep", "track / remove"],
        session: { labels: ["track / keep", "track / remove"], name: sessionName, startTime: "10:30" },
      }),
      (id) => cleanupEventsByIds([id]),
    );
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
  });

  test("organizer can clear the labels of a session", async ({ organizerGroupPage, owned }) => {
    const eventName = uniqueName("Labels Clear Session Event");
    const sessionName = uniqueName("Cleared labels session");

    // Create an event with two labels assigned to a session.
    const eventId = owned.track(
      await createEventWithLabeledSession(organizerGroupPage, {
        days: 94,
        eventName,
        labels: ["track / one", "track / two"],
        session: { labels: ["track / one", "track / two"], name: sessionName, startTime: "10:30" },
      }),
      (id) => cleanupEventsByIds([id]),
    );

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
    await expect(sessionsSection.locator('input[name="sessions[0][label_ids_present]"]')).toHaveValue("true");
    await expect(sessionsSection.locator('input[name^="sessions[0][label_ids]["]')).toHaveCount(0);

    // Save and verify the session has no labels while the event keeps them.
    await saveEventUpdate(organizerGroupPage, eventId);
    await openSessionsSection(organizerGroupPage);
    await expectSessionCardLabels(organizerGroupPage, sessionName, []);
    expect(listEventLabels(eventId).map((label) => label.name)).toEqual(["track / one", "track / two"]);
    expect(listSessionLabels(eventId)).toEqual([{ labels: [], name: sessionName }]);
  });

  test("copying an event copies its label definitions with new ids and no sessions", async ({
    organizerGroupPage,
    owned,
  }) => {
    const sourceEventName = uniqueName("Labels Source Event");

    // Create a source event with labels and a labeled session.
    const sourceEventId = owned.track(
      await createEventWithLabeledSession(organizerGroupPage, {
        days: 95,
        eventName: sourceEventName,
        labels: ["track / copy a", "track / copy b"],
        session: {
          labels: ["track / copy b"],
          name: uniqueName("Copied source session"),
          startTime: "10:30",
        },
      }),
      (id) => cleanupEventsByIds([id]),
    );
    const sourceLabelIds = listEventLabels(sourceEventId).map((label) => label.id);

    // The copy selector searches published events, so publish the source without notifications.
    queryE2eDatabase(`
      update event
      set published = true, published_at = current_timestamp, published_by = '${TEST_USER_IDS.organizer1}'
      where event_id = '${sourceEventId}'
    `);

    // Open the add form and copy the source event.
    await navigateToPath(organizerGroupPage, "/dashboard/group?tab=events");
    await organizerGroupPage.locator("#dashboard-content").getByRole("button", { name: "Add Event" }).click();
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

    // Verify the group logo fallback of the source is not copied as the event logo.
    await expect(
      organizerGroupPage.locator('image-field[name="logo_url"] input[name="logo_url"]'),
    ).toHaveValue("");

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

    // Schedule and save the copy, then verify its stored logo, labels and sessions.
    await organizerGroupPage.locator('button[data-section="date-venue"]').click();
    await organizerGroupPage.locator("#starts_at").fill(futureDate({ days: 96, hour: 10 }));
    await organizerGroupPage.locator("#ends_at").fill(futureDate({ days: 96, hour: 12 }));
    const copiedEventId = owned.track(await saveNewEvent(organizerGroupPage), (id) =>
      cleanupEventsByIds([id]),
    );
    expect(
      queryCount(`
        select count(*)
        from event
        where event_id = ${sqlUuid(copiedEventId)}
        and logo_url is null
      `),
    ).toBe(1);
    const copiedLabels = listEventLabels(copiedEventId);
    expect(copiedLabels.map((label) => label.name)).toEqual(["track / copy a", "track / copy b"]);
    expect(copiedLabels.filter((label) => sourceLabelIds.includes(label.id))).toEqual([]);
    expect(listSessionLabels(copiedEventId)).toEqual([]);
  });

  test("labels tab is locked for viewers", async ({ groupViewerPage }) => {
    // Open the seeded CFS event editor as a read-only viewer.
    await openEventUpdateFormByName(groupViewerPage, "Event With Active CFS", TEST_EVENT_IDS.alpha.cfsSummit);
    await openLabelsSection(groupViewerPage);

    // Verify the saved labels are shown but cannot be edited.
    await expectLockedLabelsTab(groupViewerPage, ["Platform", "Workshop"]);
  });

  test("labels tab is locked on canceled events", async ({ organizerGroupPage }) => {
    // Open the seeded canceled event editor as an organizer.
    await openEventUpdateFormByName(
      organizerGroupPage,
      TEST_CANCELED_PUBLIC_EVENT.name,
      TEST_CANCELED_PUBLIC_EVENT.id,
    );
    await openLabelsSection(organizerGroupPage);

    // Verify the starter label row cannot be edited.
    await expectLockedLabelsTab(organizerGroupPage, [""]);
  });

  for (const { disabledControls, event, eventLabel, fixture, label, warning } of EDITOR_READ_ONLY_CASES) {
    test(`${label} sees the ${eventLabel} event editor as read-only`, async ({ pageAs }) => {
      // Open the seeded event editor with the case role.
      const page = await pageAs(fixture);
      await openEventUpdateFormByName(page, event.name, event.id);
      const eventPage = page.locator('[data-event-page="update"]');

      // Verify each blocked control is disabled and explains why.
      // The save button sits in the hidden pending-changes alert, so visibility is not asserted.
      for (const [selector, title] of Object.entries(disabledControls)) {
        const control = eventPage.locator(selector);
        await expect(control).toBeDisabled();
        await expect(control).toHaveAttribute("title", title);
      }
      await expect(eventPage.getByText(warning, { exact: true })).toBeVisible();

      // Verify the form is inert and its fields cannot receive focus.
      await expect(eventPage.locator(".inert-form")).toHaveAttribute("inert", "");
      const nameInput = eventPage.locator("#name");
      await nameInput.focus();
      await expect(nameInput).not.toBeFocused();
    });
  }

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
 * Verifies the labels tab renders its rows inside the inert read-only form.
 * @param {import("@playwright/test").Page} page - Playwright page.
 * @param {string[]} labelNames - Expected label row names in display order.
 */
const expectLockedLabelsTab = async (page, labelNames) => {
  // Inert controls leave the accessibility tree, so CSS locators target them.
  const labelsForm = page.locator(".inert-form[inert] #labels-form");
  await expect(labelsForm).toBeVisible();
  const nameInputs = labelsForm.locator('labels-editor input[type="text"]');
  await expect(nameInputs).toHaveCount(labelNames.length);
  for (const [index, labelName] of labelNames.entries()) {
    await expect(nameInputs.nth(index)).toHaveValue(labelName);
  }

  // Inert controls cannot receive focus.
  await nameInputs.first().focus();
  await expect(nameInputs.first()).not.toBeFocused();
  const addLabelButton = labelsForm.locator("labels-editor button", { hasText: "Add label" });
  await addLabelButton.focus();
  await expect(addLabelButton).not.toBeFocused();
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
  await page.locator("#category_id").selectOption(TEST_EVENT_CATEGORY_IDS.general);
  await page.locator("#description_short").fill("A dashboard event used to cover event labels.");
  await fillMarkdownEditor(page, "description", "Event labels coverage for sessions and the editor.");
  await page.locator('button[data-section="date-venue"]').click();
  await selectTimezone(page, "UTC");
  await page.locator("#starts_at").fill(futureDate({ days, hour: 10 }));
  await page.locator("#ends_at").fill(futureDate({ days, hour: 12 }));
  await page.locator("#meeting_join_url").fill("https://meet.example.com/e2e-event-labels");
};

/**
 * Formats an instant like the server registration window copy (`%b %-e, %Y at %-I:%M %p %Z`).
 * @param {string} epochSeconds - Unix timestamp in seconds, as returned by the database.
 * @returns {string} Time such as `Mar 9, 2031 at 9:15 AM EDT` in the registration window timezone.
 */
const formatRegistrationWindowTime = (epochSeconds) => {
  const parts = new Intl.DateTimeFormat("en-US", {
    day: "numeric",
    hour: "numeric",
    hour12: true,
    minute: "2-digit",
    month: "short",
    timeZone: REGISTRATION_WINDOW_TIME_ZONE,
    timeZoneName: "short",
    year: "numeric",
  }).formatToParts(new Date(Number(epochSeconds) * 1000));
  const part = Object.fromEntries(parts.map(({ type, value }) => [type, value]));

  return `${part.month} ${part.day}, ${part.year} at ${part.hour}:${part.minute} ${part.dayPeriod} ${part.timeZoneName}`;
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
