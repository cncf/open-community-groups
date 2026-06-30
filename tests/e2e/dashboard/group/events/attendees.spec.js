import { readFile } from "node:fs/promises";

import { expect, test } from "../../../fixtures.js";

import {
  buildE2eUrl,
  E2E_PAYMENTS_ENABLED,
  TEST_COMMUNITY_NAME,
  TEST_EVENT_IDS,
  TEST_PAYMENT_EVENT_IDS,
  TEST_PAYMENT_EVENT_NAMES,
  TEST_REGISTRATION_QUESTIONS_EVENT,
  TEST_EVENT_SLUGS,
  TEST_GROUP_SLUGS,
  TEST_USER_IDS,
  navigateToEvent,
  navigateToPath,
  selectTimezone,
} from "../../../utils.js";
import { fillMarkdownEditor } from "../../form-helpers.js";

import { ATTENDEE_NOTIFICATION_BODY, ATTENDEE_NOTIFICATION_SUBJECT } from "../helpers.js";
import { expectUserProfileModalFromRow } from "./user-profile-modal-helpers.js";

// Open the attendees tab for a specific event and return its content.
const openAttendeesTab = async (page, eventName, eventId) => {
  await navigateToPath(page, "/dashboard/group?tab=events");

  const eventRow = page.locator("tr", {
    hasText: eventName,
  });
  await expect(eventRow).toBeVisible();

  await Promise.all([
    page.waitForResponse(
      (response) =>
        response.request().method() === "GET" &&
        response.url().includes(`/dashboard/group/events/${eventId}/update`) &&
        response.ok(),
    ),
    eventRow.locator('td button[aria-label^="Edit event:"]').click(),
  ]);

  await Promise.all([
    page.waitForResponse(
      (response) =>
        response.request().method() === "GET" &&
        response.url().includes(`/dashboard/group/events/${eventId}/attendees`) &&
        response.ok(),
    ),
    page.locator('button[data-section="attendees"]').click(),
  ]);

  const attendeesContent = page.locator("#attendees-content");

  // Wait until the attendees tab has swapped in its table.
  await expect(attendeesContent.getByRole("table", { name: "Attendees list" })).toBeVisible();

  return attendeesContent;
};

// Create a published event that requires organizer approval for attendees.
const createApprovalRequiredEvent = async (page, eventName) => {
  await navigateToPath(page, "/dashboard/group?tab=events");

  const dashboardContent = page.locator("#dashboard-content");
  await expect(dashboardContent.getByText("Events", { exact: true })).toBeVisible();
  await dashboardContent.getByRole("button", { name: "Add Event" }).click();
  await expect(page.locator("#name")).toBeVisible();

  await page.locator("#name").fill(eventName);
  await page.locator("#kind_id").selectOption("virtual");
  await page.locator("#category_id").selectOption("33333333-3333-3333-3333-333333333331");
  await page.locator("#description_short").fill("A temporary approval-required event from the e2e suite.");
  await fillMarkdownEditor(
    page,
    "description",
    "A temporary approval-required event for invitation request coverage.",
  );
  await page.locator("#capacity").fill("25");
  await page.locator("#toggle_attendee_approval_required").check({ force: true });

  await page.locator("button[data-section-next]").click();
  await expect(page.locator('button[data-section="date-venue"]')).toHaveAttribute("data-active", "true");
  await selectTimezone(page, "UTC");
  await page.locator("#starts_at").fill("2030-06-20T10:00");
  await page.locator("#ends_at").fill("2030-06-20T12:00");
  await page.locator("#meeting_join_url").fill("https://meet.example.com/e2e-invitation-requests");

  const visibleAddEventButton = page.locator("#pending-changes-alert:not(.hidden) #add-event-button");
  await expect(visibleAddEventButton).toBeVisible();

  await Promise.all([
    page.waitForResponse(
      (response) =>
        response.request().method() === "POST" &&
        response.url().includes("/dashboard/group/events/add") &&
        response.status() === 201,
    ),
    visibleAddEventButton.click(),
  ]);

  const eventRow = dashboardContent.locator("tr", { hasText: eventName });
  await expect(eventRow).toBeVisible();

  const actionsButton = eventRow.locator(".btn-actions");
  const eventId = await actionsButton.getAttribute("data-event-id");

  expect(eventId).not.toBeNull();

  const publishResponse = await page.request.put(buildE2eUrl(`/dashboard/group/events/${eventId}/publish`));
  expect(publishResponse.ok()).toBeTruthy();

  await Promise.all([
    page.waitForResponse(
      (response) =>
        response.request().method() === "GET" &&
        response.url().includes(`/dashboard/group/events/${eventId}/update`) &&
        response.ok(),
    ),
    eventRow.locator('td button[aria-label^="Edit event:"]').click(),
  ]);
  const viewEventHref = await page.locator("#event-update-page").getAttribute("data-event-public-url");

  expect(viewEventHref).not.toBeNull();

  return {
    eventId: eventId ?? "",
    viewEventHref: viewEventHref ?? "",
  };
};

// Delete the temporary event created for invitation request coverage.
const deleteEventFromList = async (page, eventId) => {
  const deleteResponse = await page.request.delete(buildE2eUrl(`/dashboard/group/events/${eventId}/delete`));
  expect([200, 204, 404]).toContain(deleteResponse.status());
};

test.describe("group dashboard attendees tab", () => {
  test("viewer sees read-only attendee controls on the attendees tab", async ({ groupViewerPage }) => {
    // Load the group events dashboard as a read-only viewer.
    await navigateToPath(groupViewerPage, "/dashboard/group?tab=events");

    // Target the seeded event used for attendee permission checks.
    const eventRow = groupViewerPage.locator("tr", {
      hasText: "Full Event With Waitlist",
    });
    await expect(eventRow).toBeVisible();

    // Open the event update form before switching to attendees.
    await Promise.all([
      groupViewerPage.waitForResponse(
        (response) =>
          response.request().method() === "GET" &&
          response.url().includes(`/dashboard/group/events/${TEST_EVENT_IDS.alpha.waitlistLab}/update`) &&
          response.ok(),
      ),
      eventRow.locator('td button[aria-label="Edit event: Full Event With Waitlist"]').click(),
    ]);

    // Load the attendees tab for the seeded event.
    await Promise.all([
      groupViewerPage.waitForResponse(
        (response) =>
          response.request().method() === "GET" &&
          response.url().includes(`/dashboard/group/events/${TEST_EVENT_IDS.alpha.waitlistLab}/attendees`) &&
          response.ok(),
      ),
      groupViewerPage.locator('button[data-section="attendees"]').click(),
    ]);

    // Target the attendee row and verify controls remain read-only.
    const attendeesContent = groupViewerPage.locator("#attendees-content");
    const attendeeRow = attendeesContent.locator("tr", {
      hasText: "E2E Organizer One",
    });

    // Assert that Attendees list is visible.
    await expect(attendeesContent.getByRole("table", { name: "Attendees list" })).toBeVisible();
    await expect(attendeeRow).toBeVisible();
    await expect(attendeesContent.getByRole("button", { name: "Send email" })).toBeDisabled();
    await expect(attendeesContent.getByRole("button", { name: "Send email" })).toHaveAttribute(
      "title",
      "Your role cannot send emails to attendees.",
    );
    await expect(attendeeRow.locator(".check-in-toggle")).toBeDisabled();
  });

  test("organizer can see a public attendee on the attendees tab", async ({
    member2Page,
    organizerGroupPage,
  }) => {
    // Load the public event page before creating attendance.
    await navigateToEvent(
      member2Page,
      TEST_COMMUNITY_NAME,
      TEST_GROUP_SLUGS.community1.alpha,
      TEST_EVENT_SLUGS.alpha[0],
    );

    // Find the attend button.
    const attendButton = member2Page.locator('[data-attendance-role="attend-btn"]');
    const leaveButton = member2Page.locator('[data-attendance-role="leave-btn"]');

    // Attend the event as a member.
    await expect(attendButton).toContainText("Attend event");

    // Click the attend button.
    await Promise.all([
      member2Page.waitForResponse(
        (response) =>
          response.request().method() === "POST" &&
          response.url().includes(`/event/${TEST_EVENT_IDS.alpha.one}/attend`) &&
          response.ok(),
      ),
      attendButton.click(),
    ]);

    // Assert the expected text is rendered.
    await expect(leaveButton).toContainText("Cancel attendance");

    // Load the group events dashboard as the organizer.
    await navigateToPath(organizerGroupPage, "/dashboard/group?tab=events");

    // Find the event row.
    const eventRow = organizerGroupPage.locator("tr", {
      hasText: "Upcoming In-Person Event",
    });
    await expect(eventRow).toBeVisible();

    // Open the event update form before switching to attendees.
    await Promise.all([
      organizerGroupPage.waitForResponse(
        (response) =>
          response.request().method() === "GET" &&
          response.url().includes(`/dashboard/group/events/${TEST_EVENT_IDS.alpha.one}/update`) &&
          response.ok(),
      ),
      eventRow.locator('td button[aria-label="Edit event: Upcoming In-Person Event"]').click(),
    ]);

    // Load the attendees tab for the event.
    await Promise.all([
      organizerGroupPage.waitForResponse(
        (response) =>
          response.request().method() === "GET" &&
          response.url().includes(`/dashboard/group/events/${TEST_EVENT_IDS.alpha.one}/attendees`) &&
          response.ok(),
      ),
      organizerGroupPage.locator('button[data-section="attendees"]').click(),
    ]);

    // Verify the organizer sees the public attendee.
    const attendeesContent = organizerGroupPage.locator("#attendees-content");
    const attendeeRow = attendeesContent.locator("tr", {
      hasText: "E2E Member Two",
    });

    // Assert that Attendees list is visible.
    await expect(attendeesContent.getByRole("table", { name: "Attendees list" })).toBeVisible();
    await expect(attendeeRow).toBeVisible();
    await expect(attendeeRow).toContainText("e2e-member-2");
    await expect(attendeesContent.getByRole("button", { name: "Send email" })).toBeEnabled();
    await expectUserProfileModalFromRow(
      organizerGroupPage,
      attendeeRow,
      "View profile for E2E Member Two",
      "E2E Member Two",
      [
        "Member Experience Engineer at Platform Ops Lab",
        "Member Two profile for dashboard modal coverage.",
        "openprofile.dev",
      ],
    );

    // Return to the public event page to restore attendance state.
    await navigateToEvent(
      member2Page,
      TEST_COMMUNITY_NAME,
      TEST_GROUP_SLUGS.community1.alpha,
      TEST_EVENT_SLUGS.alpha[0],
    );

    // Cancel the temporary attendance record.
    await leaveButton.click();
    await expect(member2Page.getByRole("button", { name: "Yes" })).toBeVisible();

    // Click Yes.
    await Promise.all([
      member2Page.waitForResponse(
        (response) =>
          response.request().method() === "DELETE" &&
          response.url().includes(`/event/${TEST_EVENT_IDS.alpha.one}/leave`) &&
          response.ok(),
      ),
      member2Page.getByRole("button", { name: "Yes" }).click(),
    ]);

    // Assert the expected text is rendered.
    await expect(attendButton).toContainText("Attend event");
  });

  test("organizer can check in an attendee from the attendees tab", async ({
    member2Page,
    organizerGroupPage,
  }) => {
    // Load the public event page before creating attendance.
    await navigateToEvent(
      member2Page,
      TEST_COMMUNITY_NAME,
      TEST_GROUP_SLUGS.community1.alpha,
      TEST_EVENT_SLUGS.alpha[0],
    );

    // Find the attend button.
    const attendButton = member2Page.locator('[data-attendance-role="attend-btn"]');
    const leaveButton = member2Page.locator('[data-attendance-role="leave-btn"]');

    // Attend the event as a member.
    await expect(attendButton).toContainText("Attend event");

    // Click the attend button.
    await Promise.all([
      member2Page.waitForResponse(
        (response) =>
          response.request().method() === "POST" &&
          response.url().includes(`/event/${TEST_EVENT_IDS.alpha.one}/attend`) &&
          response.ok(),
      ),
      attendButton.click(),
    ]);

    // Assert the expected text is rendered.
    await expect(leaveButton).toContainText("Cancel attendance");

    // Load the group events dashboard as the organizer.
    await navigateToPath(organizerGroupPage, "/dashboard/group?tab=events");

    // Find the event row.
    const eventRow = organizerGroupPage.locator("tr", {
      hasText: "Upcoming In-Person Event",
    });
    await expect(eventRow).toBeVisible();

    // Open the event update form before switching to attendees.
    await Promise.all([
      organizerGroupPage.waitForResponse(
        (response) =>
          response.request().method() === "GET" &&
          response.url().includes(`/dashboard/group/events/${TEST_EVENT_IDS.alpha.one}/update`) &&
          response.ok(),
      ),
      eventRow.locator('td button[aria-label="Edit event: Upcoming In-Person Event"]').click(),
    ]);

    // Load the attendees tab for the event.
    await Promise.all([
      organizerGroupPage.waitForResponse(
        (response) =>
          response.request().method() === "GET" &&
          response.url().includes(`/dashboard/group/events/${TEST_EVENT_IDS.alpha.one}/attendees`) &&
          response.ok(),
      ),
      organizerGroupPage.locator('button[data-section="attendees"]').click(),
    ]);

    // Target the attendee check-in toggle.
    const attendeesContent = organizerGroupPage.locator("#attendees-content");
    const attendeeRow = attendeesContent.locator("tr", {
      hasText: "E2E Member Two",
    });
    const checkInToggle = attendeeRow.locator(".check-in-toggle");

    // Assert the expected content is visible.
    await expect(attendeeRow).toBeVisible();
    await expect(checkInToggle).toBeEnabled();

    // Check in the attendee from the attendees tab.
    await Promise.all([
      organizerGroupPage.waitForResponse(
        (response) =>
          response.request().method() === "POST" &&
          response
            .url()
            .includes(
              `/dashboard/group/events/${TEST_EVENT_IDS.alpha.one}/attendees/${TEST_USER_IDS.member2}/check-in`,
            ) &&
          response.ok(),
      ),
      attendeeRow.locator("label").click(),
    ]);

    // The attendee row reflects the saved interaction.
    await expect(checkInToggle).toBeChecked();
    await expect(checkInToggle).toBeDisabled();

    // Verify the checked-in attendee can access the check-in page.
    await navigateToPath(member2Page, `/${TEST_COMMUNITY_NAME}/check-in/${TEST_EVENT_IDS.alpha.one}`);
    await expect(member2Page.getByText("You're checked in")).toBeVisible();

    // Return to the public event page to restore attendance state.
    await navigateToEvent(
      member2Page,
      TEST_COMMUNITY_NAME,
      TEST_GROUP_SLUGS.community1.alpha,
      TEST_EVENT_SLUGS.alpha[0],
    );

    // Cancel the temporary attendance record.
    await leaveButton.click();
    await expect(member2Page.getByRole("button", { name: "Yes" })).toBeVisible();

    // Click Yes.
    await Promise.all([
      member2Page.waitForResponse(
        (response) =>
          response.request().method() === "DELETE" &&
          response.url().includes(`/event/${TEST_EVENT_IDS.alpha.one}/leave`) &&
          response.ok(),
      ),
      member2Page.getByRole("button", { name: "Yes" }).click(),
    ]);

    // Assert the expected text is rendered.
    await expect(attendButton).toContainText("Attend event");
  });

  test("organizer sees the empty state on the attendees tab for an event without RSVPs", async ({
    organizerGroupPage,
  }) => {
    // Give temporary event setup and cleanup enough time on slower deep runs.
    test.setTimeout(60_000);

    // Create a temporary event without attendees.
    const eventName = `E2E Empty Attendees ${Date.now()}`;
    const { eventId } = await createApprovalRequiredEvent(organizerGroupPage, eventName);

    try {
      // Load the attendees tab for the temporary event.
      const attendeesContent = await openAttendeesTab(organizerGroupPage, eventName, eventId);

      // Assert that Attendees list is visible.
      await expect(attendeesContent.getByRole("table", { name: "Attendees list" })).toBeVisible();
      await expect(attendeesContent).toContainText("No attendees found for this event.");
      await expect(attendeesContent.getByRole("button", { name: "Send email" })).toBeDisabled();
      await expect(attendeesContent.getByRole("button", { name: "Send email" })).toHaveAttribute(
        "title",
        "No attendees with verified email addresses and email notifications enabled.",
      );
    } finally {
      await deleteEventFromList(organizerGroupPage, eventId);
    }
  });

  test("organizer can search attendees and clear the filter", async ({ organizerGroupPage }) => {
    // Load the attendees tab for the seeded event.
    const attendeesContent = await openAttendeesTab(
      organizerGroupPage,
      "Upcoming In-Person Event",
      TEST_EVENT_IDS.alpha.one,
    );

    // Target the search controls used to submit attendee filters.
    const searchInput = attendeesContent.getByRole("textbox", {
      name: "Search attendees",
    });
    const searchForm = attendeesContent.locator("#attendees-search-form");

    // Enter a query expected to match a seeded attendee.
    await searchInput.fill("member");

    // Submit the matching search and wait for filtered results.
    await searchForm.evaluate((form) => {
      if (form instanceof HTMLFormElement) {
        form.requestSubmit();
      }
    });

    // Verify the matching result is shown and non-matching attendees are hidden.
    await expect(attendeesContent.locator("tr", { hasText: "E2E Member One" })).toBeVisible();
    await expect(attendeesContent.locator("tr", { hasText: "E2E Organizer One" })).toHaveCount(0);
    await expect(searchInput).toHaveValue("member");

    // Enter a query expected to return no attendees.
    await searchInput.fill("");
    await searchInput.fill("zzzzzzzzzzzz");

    // Submit the empty-result search and wait for the empty state.
    await searchForm.evaluate((form) => {
      if (form instanceof HTMLFormElement) {
        form.requestSubmit();
      }
    });

    const noResultsMessage = attendeesContent
      .locator("div.text-xl.lg\\:text-2xl.mb-4:visible")
      .filter({ hasText: "No attendees found matching your search." });

    // Verify the filtered empty result message is shown.
    await expect(noResultsMessage.first()).toBeVisible();

    // Clear the attendee search filter.
    await attendeesContent.getByRole("button", { name: "Clear attendee search" }).click();

    // Verify clearing removes the empty state and restores seeded attendees.
    await expect(noResultsMessage).toHaveCount(0);
    await expect(attendeesContent.locator("tr", { hasText: "E2E Member One" })).toBeVisible();
    await expect(attendeesContent.locator("tr", { hasText: "E2E Organizer One" })).toBeVisible();
    await expect(searchInput).toHaveValue("");

    // Sort attendees by name and verify the active sort badge is rendered.
    await attendeesContent.getByRole("button", { name: "Sort Attendee" }).click();

    // Verify the sorted table keeps both seeded attendees visible.
    await expect(attendeesContent.getByText("Sort: Name A-Z")).toBeVisible();
    await expect(attendeesContent.locator("tr", { hasText: "E2E Member One" })).toBeVisible();
    await expect(attendeesContent.locator("tr", { hasText: "E2E Organizer One" })).toBeVisible();
  });

  test("organizer can download attendees as CSV from the attendees tab", async ({ organizerGroupPage }) => {
    // Load the attendees tab for the seeded waitlist event.
    const attendeesContent = await openAttendeesTab(
      organizerGroupPage,
      "Full Event With Waitlist",
      TEST_EVENT_IDS.alpha.waitlistLab,
    );

    // Open attendee actions before selecting the CSV download.
    const actionsButton = attendeesContent.getByRole("button", {
      name: "Open attendee actions menu",
    });
    await expect(actionsButton).toBeVisible();
    await actionsButton.click();

    // Find the Download CSV control.
    const downloadCsvLink = attendeesContent.getByRole("menuitem", {
      name: "Download CSV",
    });
    await expect(downloadCsvLink).toBeVisible();
    await expect(downloadCsvLink).toHaveAttribute(
      "href",
      `/dashboard/group/events/${TEST_EVENT_IDS.alpha.waitlistLab}/attendees.csv`,
    );

    // Download the CSV and verify the seeded attendee row.
    const [download] = await Promise.all([
      organizerGroupPage.waitForEvent("download"),
      downloadCsvLink.click(),
    ]);
    const downloadPath = await download.path();

    // Fail clearly if the CSV download was not captured.
    if (!downloadPath) {
      throw new Error("Expected attendee CSV download to have a local file path.");
    }

    // Assert the downloaded filename.
    expect(download.suggestedFilename()).toBe("event-alpha-waitlist-lab-attendees.csv");
    const csvContents = await readFile(downloadPath, "utf8");
    expect(csvContents).toContain("Name,Company,Title,Invited\nE2E Organizer One,,,No\n");
  });

  test("organizer can review attendee registration answers", async ({ organizerGroupPage }) => {
    // Load the attendees tab for the seeded registration questions event.
    const attendeesContent = await openAttendeesTab(
      organizerGroupPage,
      TEST_REGISTRATION_QUESTIONS_EVENT.name,
      TEST_REGISTRATION_QUESTIONS_EVENT.id,
    );
    const attendeeRow = attendeesContent.locator("tr", {
      hasText: "E2E Member One",
    });
    const rowActionsMenu = attendeeRow.locator("[data-attendee-row-actions-menu]");

    // Assert the expected content is visible.
    await expect(attendeeRow).toBeVisible();
    await expect(rowActionsMenu).toBeVisible();

    // Open the row actions menu and show the attendee answers modal.
    await rowActionsMenu.locator("summary").click();
    await rowActionsMenu.getByRole("menuitem", { name: "View answers" }).click();

    // Verify the modal renders all seeded question answers.
    const answersModal = organizerGroupPage.locator("#attendee-answers-modal");
    await expect(answersModal).toBeVisible();
    await expect(answersModal.getByRole("heading", { name: "Registration answers" })).toBeVisible();
    await expect(answersModal.locator("#attendee-answers-name")).toHaveText("E2E Member One");
    await expect(answersModal).toContainText("What are you hoping to learn from this event?");
    await expect(answersModal).toContainText("practical patterns for incident readiness");
    await expect(answersModal).toContainText("Preferred session format");
    await expect(answersModal).toContainText("Hands-on workshop");
    await expect(answersModal).toContainText("Topics you want covered");
    await expect(answersModal).toContainText("Platform reliability");
    await expect(answersModal).toContainText("Developer experience");
    await expect(answersModal).toContainText("Open source governance");
    await expect(answersModal).toContainText("Anything the organizers should know?");
    await expect(answersModal).toContainText("Vegetarian lunch");

    // Close the answers modal after the review.
    await answersModal.locator("#cancel-attendee-answers-modal").click();
    await expect(answersModal).toBeHidden();
  });

  test("organizer can download attendee answers as CSV", async ({ organizerGroupPage }) => {
    // Load the attendees tab for the seeded registration questions event.
    const attendeesContent = await openAttendeesTab(
      organizerGroupPage,
      TEST_REGISTRATION_QUESTIONS_EVENT.name,
      TEST_REGISTRATION_QUESTIONS_EVENT.id,
    );

    // Open attendee actions before selecting the answers CSV download.
    const actionsButton = attendeesContent.getByRole("button", {
      name: "Open attendee actions menu",
    });
    await expect(actionsButton).toBeVisible();
    await actionsButton.click();

    // Find the Attendees list CSV (including answers) control.
    const downloadCsvLink = attendeesContent.getByRole("menuitem", {
      name: "Attendees list CSV (including answers)",
    });
    await expect(downloadCsvLink).toBeVisible();
    await expect(downloadCsvLink).toHaveAttribute(
      "href",
      `/dashboard/group/events/${TEST_REGISTRATION_QUESTIONS_EVENT.id}/attendees-with-answers.csv`,
    );

    // Download the CSV and verify seeded question answers are included.
    const [download] = await Promise.all([
      organizerGroupPage.waitForEvent("download"),
      downloadCsvLink.click(),
    ]);
    const downloadPath = await download.path();

    // Fail clearly if the CSV download was not captured.
    if (!downloadPath) {
      throw new Error("Expected attendee answers CSV download to have a local file path.");
    }

    // Assert the downloaded filename.
    expect(download.suggestedFilename()).toBe(
      "event-alpha-registration-answers-lab-attendees-with-answers.csv",
    );
    const csvContents = await readFile(downloadPath, "utf8");
    expect(csvContents).toContain("What are you hoping to learn from this event?");
    expect(csvContents).toContain("I want practical patterns for incident readiness");
    expect(csvContents).toContain("Hands-on workshop");
    expect(csvContents).toContain("Platform reliability");
    expect(csvContents).toContain("Open source governance");
    expect(csvContents).toContain("Vegetarian lunch");
  });

  test("organizer can invite and cancel an attendee invitation", async ({ organizerGroupPage }) => {
    // Give the invite and cancel flow enough time on slower deep runs.
    test.setTimeout(60_000);

    // Create a temporary event for the invitation lifecycle.
    const eventName = `E2E Attendee Invitation ${Date.now()}`;
    const { eventId } = await createApprovalRequiredEvent(organizerGroupPage, eventName);

    try {
      // Load the attendees tab for the temporary event.
      const attendeesContent = await openAttendeesTab(organizerGroupPage, eventName, eventId);

      // Open the manual invitation modal for an event without RSVPs.
      const actionsButton = attendeesContent.getByRole("button", {
        name: "Open attendee actions menu",
      });
      await expect(actionsButton).toBeVisible();
      await actionsButton.click();

      const inviteAttendeeButton = attendeesContent.getByRole("menuitem", {
        name: "Invite attendee",
      });
      await expect(inviteAttendeeButton).toBeVisible();
      await inviteAttendeeButton.click();

      // Find the modal.
      const modal = organizerGroupPage.locator("#attendee-invitation-modal");
      const searchField = modal.locator("user-search-field[data-attendee-invitation-search]");
      const searchInput = searchField.locator("#attendee-invitation-search-input");

      // Assert the expected content is visible.
      await expect(modal).toBeVisible();
      await expect(modal.getByRole("heading", { name: "Invite attendee" })).toBeVisible();
      await expect(modal.locator("#submit-attendee-invitation")).toBeDisabled();

      // Keep invalid free-form input from enabling the invitation form.
      await searchInput.fill("not-an-email");
      await expect(modal.locator("#submit-attendee-invitation")).toBeDisabled();

      // Select a seeded user and submit the invitation.
      await searchInput.fill("e2e-pending-2");
      await expect(searchField.getByText("E2E Pending Two")).toBeVisible();
      await searchField.getByText("E2E Pending Two").click();
      await expect(modal.locator("#attendee-invitation-selected-user")).toContainText("E2E Pending Two");
      await expect(modal.locator("#submit-attendee-invitation")).toBeEnabled();

      // Submit and wait for the server response.
      await Promise.all([
        organizerGroupPage.waitForResponse(
          (response) =>
            response.request().method() === "POST" &&
            response.url().includes(`/dashboard/group/events/${eventId}/attendees/invite`) &&
            response.ok(),
        ),
        modal.locator("#submit-attendee-invitation").click(),
      ]);

      // Assert that the content is hidden.
      await expect(modal).toBeHidden();
      await expect(organizerGroupPage.locator(".swal2-popup")).toContainText("Invitation sent.");

      // Verify the invitation appears in the attendees table.
      const attendeeRow = attendeesContent.locator("tr", {
        hasText: "E2E Pending Two",
      });
      await expect(attendeeRow).toBeVisible();
      await expect(attendeeRow).toContainText("Invitation sent");

      // Cancel the temporary invitation and wait for the table to refresh.
      const rowActionsMenu = attendeeRow.locator("[data-attendee-row-actions-menu]");
      await rowActionsMenu.locator("summary").click();
      await rowActionsMenu.getByRole("menuitem", { name: "Cancel invitation" }).click();
      await expect(organizerGroupPage.getByRole("button", { name: "Yes" })).toBeVisible();

      // Click Yes.
      await Promise.all([
        organizerGroupPage.waitForResponse(
          (response) =>
            response.request().method() === "PUT" &&
            response
              .url()
              .includes(
                `/dashboard/group/events/${eventId}/attendees/${TEST_USER_IDS.pending2}/invitation/cancel`,
              ) &&
            response.ok(),
        ),
        organizerGroupPage.getByRole("button", { name: "Yes" }).click(),
      ]);

      // Assert how many matching elements are shown.
      await expect(attendeeRow).toHaveCount(0);
      await expect(attendeesContent).toContainText("No attendees found for this event.");
    } finally {
      await deleteEventFromList(organizerGroupPage, eventId);
    }
  });

  test("organizer can accept and reject attendee invitation requests", async ({
    organizerGroupPage,
    pending1Page,
    pending2Page,
  }) => {
    // Give the invitation request flow enough time on slower deep runs.
    test.setTimeout(60_000);

    // Create a temporary approval-required event.
    const eventName = `E2E Invitation Requests ${Date.now()}`;
    const { eventId } = await createApprovalRequiredEvent(organizerGroupPage, eventName);

    try {
      // Request invitations from two users. The attend endpoint expects a
      // form-encoded body, so send an empty form payload with each request.
      for (const requesterPage of [pending1Page, pending2Page]) {
        const requestResponse = await requesterPage.request.post(
          buildE2eUrl(`/${TEST_COMMUNITY_NAME}/event/${eventId}/attend`),
          { form: {} },
        );
        expect(requestResponse.ok()).toBeTruthy();
      }

      // Open the organizer Requests tab for the temporary event.
      await navigateToPath(organizerGroupPage, "/dashboard/group?tab=events");
      const eventRow = organizerGroupPage.locator("tr", { hasText: eventName });
      await expect(eventRow).toBeVisible();
      await Promise.all([
        organizerGroupPage.waitForResponse(
          (response) =>
            response.request().method() === "GET" &&
            response.url().includes(`/dashboard/group/events/${eventId}/update`) &&
            response.ok(),
        ),
        eventRow.locator('td button[aria-label^="Edit event:"]').click(),
      ]);
      await Promise.all([
        organizerGroupPage.waitForResponse(
          (response) =>
            response.request().method() === "GET" &&
            response.url().includes(`/dashboard/group/events/${eventId}/invitation-requests`) &&
            response.ok(),
        ),
        organizerGroupPage.locator('button[data-section="invitation-requests"]').click(),
      ]);

      const requestsContent = organizerGroupPage.locator("#invitation-requests-content");
      await expect(requestsContent.getByRole("table", { name: "Invitation requests" })).toBeVisible();

      // Target the search controls used to submit request filters.
      const searchInput = requestsContent.getByRole("textbox", {
        name: "Search invitation requests",
      });
      const searchForm = requestsContent.locator("#invitation-requests-search-form");

      // Enter a query expected to match one seeded requester.
      await searchInput.fill("Two");

      // Submit the matching search and wait for filtered results.
      await searchForm.evaluate((form) => {
        if (form instanceof HTMLFormElement) {
          form.requestSubmit();
        }
      });

      // Verify the matching result is shown and non-matching requests are hidden.
      await expect(requestsContent.locator("tr", { hasText: "E2E Pending Two" })).toBeVisible();
      await expect(requestsContent.locator("tr", { hasText: "E2E Pending One" })).toHaveCount(0);
      await expect(searchInput).toHaveValue("Two");

      // Enter a query expected to return no requests.
      await searchInput.fill("");
      await searchInput.fill("zzzzzzzzzzzz");

      // Submit the empty-result search and wait for the empty state.
      await searchForm.evaluate((form) => {
        if (form instanceof HTMLFormElement) {
          form.requestSubmit();
        }
      });

      const noResultsMessage = requestsContent.locator("div.text-xl.lg\\:text-2xl.mb-4:visible").filter({
        hasText: "No invitation requests found matching your search.",
      });

      // Verify the filtered empty result message is shown.
      await expect(noResultsMessage.first()).toBeVisible();

      // Clear the invitation request search filter.
      await requestsContent.getByRole("button", { name: "Clear invitation request search" }).click();

      // Verify clearing removes the empty state and restores request rows.
      await expect(noResultsMessage).toHaveCount(0);
      await expect(requestsContent.locator("tr", { hasText: "E2E Pending One" })).toBeVisible();
      await expect(requestsContent.locator("tr", { hasText: "E2E Pending Two" })).toBeVisible();
      await expect(searchInput).toHaveValue("");

      // Sort requesters by name before applying a status filter.
      await requestsContent.getByRole("button", { name: "Sort Requester" }).click();

      // Verify the sorted request table keeps both pending requesters visible.
      await expect(requestsContent.getByText("Sort: Name A-Z")).toBeVisible();
      await expect(requestsContent.locator("tr", { hasText: "E2E Pending One" })).toBeVisible();
      await expect(requestsContent.locator("tr", { hasText: "E2E Pending Two" })).toBeVisible();

      // Switch the table to all statuses while preserving the active sort.
      await requestsContent.getByLabel("Status filters").click();
      await requestsContent
        .locator('#invitation-requests-status-filter button[name="status"][value="all"]')
        .click();

      // Verify resetting status removes the previous badge while keeping sort.
      await expect(requestsContent.getByText("Status: Pending")).toHaveCount(0);
      await expect(requestsContent.getByText("Sort: Name A-Z")).toBeVisible();

      const pendingOneRow = requestsContent.locator("tr", {
        hasText: "E2E Pending One",
      });

      // Verify profile modals still open from rows after the filtered refresh.
      await expectUserProfileModalFromRow(
        organizerGroupPage,
        pendingOneRow,
        "View profile for E2E Pending One",
        "E2E Pending One",
        [
          "Community Applicant at Approval Queue",
          "Pending One profile for invitation request modal coverage.",
          "openprofile.dev",
        ],
      );

      // Reject one invitation request.
      await expect(pendingOneRow).toContainText("Pending");
      await pendingOneRow.getByLabel("Open actions menu").click();
      await pendingOneRow.getByRole("menuitem", { name: "Reject" }).click();
      await expect(organizerGroupPage.locator(".swal2-popup")).toContainText(
        "Are you sure you want to reject this invitation request?",
      );
      await Promise.all([
        organizerGroupPage.waitForResponse(
          (response) =>
            response.request().method() === "PUT" &&
            response
              .url()
              .includes(
                `/dashboard/group/events/${eventId}/attendees/${TEST_USER_IDS.pending1}/invitation-request/reject`,
              ) &&
            response.ok(),
        ),
        organizerGroupPage.getByRole("button", { name: "Yes" }).click(),
      ]);
      await expect(pendingOneRow).toContainText("Rejected");

      // Accept the other invitation request.
      const pendingTwoRow = requestsContent.locator("tr", {
        hasText: "E2E Pending Two",
      });
      await expect(pendingTwoRow).toContainText("Pending");
      await pendingTwoRow.getByLabel("Open actions menu").click();
      await Promise.all([
        organizerGroupPage.waitForResponse(
          (response) =>
            response.request().method() === "PUT" &&
            response
              .url()
              .includes(
                `/dashboard/group/events/${eventId}/attendees/${TEST_USER_IDS.pending2}/invitation-request/accept`,
              ) &&
            response.ok(),
        ),
        pendingTwoRow.getByRole("menuitem", { name: "Accept" }).click(),
      ]);
      await expect(pendingTwoRow).toContainText("Accepted");
    } finally {
      await deleteEventFromList(organizerGroupPage, eventId);
    }
  });

  test.describe("payment-enabled attendee refund flows", () => {
    test.skip(!E2E_PAYMENTS_ENABLED, "Payments are disabled in this environment.");

    test("organizer can act on a pending refund request from the attendee row menu", async ({
      organizerGroupPage,
    }) => {
      // Load the attendees tab for the seeded refund review event.
      const attendeesContent = await openAttendeesTab(
        organizerGroupPage,
        TEST_PAYMENT_EVENT_NAMES.refunds,
        TEST_PAYMENT_EVENT_IDS.refunds,
      );
      const attendeeRow = attendeesContent.locator("tr", {
        hasText: "E2E Member One",
      });
      const rowActionsMenu = attendeeRow.locator("[data-attendee-row-actions-menu]");

      // Assert that Refund requested is visible.
      await expect(attendeeRow.getByText("Refund requested", { exact: true })).toBeVisible();
      await expect(rowActionsMenu).toBeVisible();

      // Verify pending refunds expose approve and reject actions.
      await rowActionsMenu.locator("summary").click();
      await expect(rowActionsMenu.getByRole("menuitem", { name: "Approve refund" })).toHaveAttribute(
        "hx-put",
        /\/refund\/approve$/,
      );
      await expect(rowActionsMenu.getByRole("menuitem", { name: "Reject refund" })).toHaveAttribute(
        "hx-put",
        /\/refund\/reject$/,
      );
    });

    test("organizer sees retry refund finalization for processing refunds in the row menu", async ({
      organizerGroupPage,
    }) => {
      // Load the attendees tab for the seeded refund review event.
      const attendeesContent = await openAttendeesTab(
        organizerGroupPage,
        TEST_PAYMENT_EVENT_NAMES.refunds,
        TEST_PAYMENT_EVENT_IDS.refunds,
      );
      const attendeeRow = attendeesContent.locator("tr", {
        hasText: "E2E Member Two",
      });
      const rowActionsMenu = attendeeRow.locator("[data-attendee-row-actions-menu]");

      // Assert that Refund processing is visible.
      await expect(attendeeRow.getByText("Refund processing", { exact: true })).toBeVisible();
      await expect(rowActionsMenu).toBeVisible();

      // Verify processing refunds only expose retry finalization.
      await rowActionsMenu.locator("summary").click();
      await expect(
        rowActionsMenu.getByRole("menuitem", {
          name: "Retry refund finalization",
        }),
      ).toHaveAttribute("hx-put", /\/refund\/approve$/);
      await expect(rowActionsMenu.getByRole("menuitem", { name: "Reject refund" })).toHaveCount(0);
    });

    test("organizer sees rejected refunds with disabled attendance cancellation", async ({
      organizerGroupPage,
    }) => {
      // Load the attendees tab for the seeded refund review event.
      const attendeesContent = await openAttendeesTab(
        organizerGroupPage,
        TEST_PAYMENT_EVENT_NAMES.refunds,
        TEST_PAYMENT_EVENT_IDS.refunds,
      );
      const attendeeRow = attendeesContent.locator("tr", {
        hasText: "E2E Pending One",
      });
      const rowActionsMenu = attendeeRow.locator("[data-attendee-row-actions-menu]");

      // Assert that Refund rejected is visible.
      await expect(attendeeRow.getByText("Refund rejected", { exact: true })).toBeVisible();
      await expect(rowActionsMenu).toBeVisible();

      // Verify rejected paid attendees cannot be canceled manually.
      await rowActionsMenu.locator("summary").click();
      const cancelAttendance = rowActionsMenu.getByRole("menuitem", {
        name: "Cancel attendance",
      });
      await expect(cancelAttendance).toBeDisabled();
      await expect(cancelAttendance).toHaveAttribute(
        "title",
        "Paid attendee attendance cannot be canceled from attendee actions.",
      );
    });

    test("organizer sees approved refunds with disabled attendance cancellation", async ({
      organizerGroupPage,
    }) => {
      // Load the attendees tab for the seeded refund review event.
      const attendeesContent = await openAttendeesTab(
        organizerGroupPage,
        TEST_PAYMENT_EVENT_NAMES.refunds,
        TEST_PAYMENT_EVENT_IDS.refunds,
      );
      const attendeeRow = attendeesContent.locator("tr", {
        hasText: "E2E Group Viewer One",
      });
      const rowActionsMenu = attendeeRow.locator("[data-attendee-row-actions-menu]");

      // Assert that Refund approved is visible.
      await expect(attendeeRow.getByText("Refund approved", { exact: true })).toBeVisible();
      await expect(rowActionsMenu).toBeVisible();

      // Verify approved paid attendees cannot be canceled manually.
      await rowActionsMenu.locator("summary").click();
      const cancelAttendance = rowActionsMenu.getByRole("menuitem", {
        name: "Cancel attendance",
      });
      await expect(cancelAttendance).toBeDisabled();
      await expect(cancelAttendance).toHaveAttribute(
        "title",
        "Paid attendee attendance cannot be canceled from attendee actions.",
      );
    });

    test("viewer cannot review or approve attendee refunds", async ({ groupViewerPage }) => {
      // Load the attendees tab for the seeded refund review event.
      const attendeesContent = await openAttendeesTab(
        groupViewerPage,
        TEST_PAYMENT_EVENT_NAMES.refunds,
        TEST_PAYMENT_EVENT_IDS.refunds,
      );

      // Verify refund review controls are hidden for read-only viewers.
      await expect(attendeesContent.locator("[data-refund-review-trigger]")).toHaveCount(0);
      await expect(groupViewerPage.locator("#attendee-refund-modal")).toBeHidden();
    });
  });

  test("organizer can open and close the attendee email modal from the attendees tab", async ({
    organizerGroupPage,
  }) => {
    // Load the group events dashboard before opening the seeded event.
    await navigateToPath(organizerGroupPage, "/dashboard/group?tab=events");

    // Find the event row.
    const eventRow = organizerGroupPage.locator("tr", {
      hasText: "Full Event With Waitlist",
    });
    await expect(eventRow).toBeVisible();

    // Open the event update form before switching to attendees.
    await Promise.all([
      organizerGroupPage.waitForResponse(
        (response) =>
          response.request().method() === "GET" &&
          response.url().includes(`/dashboard/group/events/${TEST_EVENT_IDS.alpha.waitlistLab}/update`) &&
          response.ok(),
      ),
      eventRow.locator('td button[aria-label="Edit event: Full Event With Waitlist"]').click(),
    ]);

    // Load the attendees tab for the event.
    await Promise.all([
      organizerGroupPage.waitForResponse(
        (response) =>
          response.request().method() === "GET" &&
          response.url().includes(`/dashboard/group/events/${TEST_EVENT_IDS.alpha.waitlistLab}/attendees`) &&
          response.ok(),
      ),
      organizerGroupPage.locator('button[data-section="attendees"]').click(),
    ]);

    // Open the attendee email modal.
    const attendeesContent = organizerGroupPage.locator("#attendees-content");
    const openModalButton = attendeesContent.getByRole("button", {
      name: "Send email",
    });

    // Assert that the answers modal can open.
    await expect(openModalButton).toBeEnabled();
    await openModalButton.click();
    await attendeesContent.getByRole("menuitem", { name: "All eligible attendees" }).click();

    // Verify the modal opens with the default message fields.
    const modal = organizerGroupPage.locator("#attendee-notification-modal");
    await expect(modal).toBeVisible();
    await expect(modal.getByRole("heading", { name: "Send email" })).toBeVisible();
    await expect(modal.getByText("This email will be sent to 1 eligible attendee.")).toBeVisible();
    await expect(modal.locator("#attendee-subject")).toHaveValue(
      "Platform Ops Meetup: Full Event With Waitlist",
    );
    await expect(modal.locator("#attendee-body")).toHaveValue("");

    // Close the attendee email modal without sending.
    await modal.getByRole("button", { name: "Cancel" }).click();
    await expect(modal).toBeHidden();
  });

  test("organizer can send an attendee email from the attendees tab", async ({ organizerGroupPage }) => {
    // Load the group events dashboard before opening the seeded event.
    await navigateToPath(organizerGroupPage, "/dashboard/group?tab=events");

    // Find the event row.
    const eventRow = organizerGroupPage.locator("tr", {
      hasText: "Full Event With Waitlist",
    });
    await expect(eventRow).toBeVisible();

    // Open the event update form before switching to attendees.
    await Promise.all([
      organizerGroupPage.waitForResponse(
        (response) =>
          response.request().method() === "GET" &&
          response.url().includes(`/dashboard/group/events/${TEST_EVENT_IDS.alpha.waitlistLab}/update`) &&
          response.ok(),
      ),
      eventRow.locator('td button[aria-label="Edit event: Full Event With Waitlist"]').click(),
    ]);

    // Load the attendees tab for the event.
    await Promise.all([
      organizerGroupPage.waitForResponse(
        (response) =>
          response.request().method() === "GET" &&
          response.url().includes(`/dashboard/group/events/${TEST_EVENT_IDS.alpha.waitlistLab}/attendees`) &&
          response.ok(),
      ),
      organizerGroupPage.locator('button[data-section="attendees"]').click(),
    ]);

    // Open the attendee email modal.
    const attendeesContent = organizerGroupPage.locator("#attendees-content");
    const openModalButton = attendeesContent.getByRole("button", {
      name: "Send email",
    });

    // Assert that the answers modal can open.
    await expect(openModalButton).toBeEnabled();
    await openModalButton.click();
    await attendeesContent.getByRole("menuitem", { name: "All eligible attendees" }).click();

    // Find the modal.
    const modal = organizerGroupPage.locator("#attendee-notification-modal");
    await expect(modal).toBeVisible();

    // Fill and submit the attendee email.
    await modal.locator("#attendee-subject").fill(ATTENDEE_NOTIFICATION_SUBJECT);
    await modal.locator("#attendee-body").fill(ATTENDEE_NOTIFICATION_BODY);

    // Click Send email.
    await Promise.all([
      organizerGroupPage.waitForResponse(
        (response) =>
          response.request().method() === "POST" &&
          response.url().includes(`/dashboard/group/notifications/${TEST_EVENT_IDS.alpha.waitlistLab}`) &&
          response.ok(),
      ),
      modal.getByRole("button", { name: "Send email" }).click(),
    ]);

    // Verify the email modal closes after a successful send.
    await expect(modal).toBeHidden();
    await expect(organizerGroupPage.locator(".swal2-popup")).toContainText(
      "Email sent successfully to all event attendees!",
    );
    await organizerGroupPage.getByRole("button", { name: "OK" }).click();
    await expect(organizerGroupPage.locator(".swal2-popup")).toBeHidden();
  });

  test("organizer can choose attendees for attendee email", async ({ organizerGroupPage }) => {
    // Load the attendees tab for the seeded waitlist event.
    const attendeesContent = await openAttendeesTab(
      organizerGroupPage,
      "Full Event With Waitlist",
      TEST_EVENT_IDS.alpha.waitlistLab,
    );

    // Open attendee email actions and enter selection mode.
    const openEmailActionsButton = attendeesContent.getByRole("button", {
      name: "Send email",
    });
    await expect(openEmailActionsButton).toBeEnabled();
    await openEmailActionsButton.click();
    await attendeesContent.getByRole("menuitem", { name: "Choose attendees" }).click();

    // Find the attendee email selection controls.
    const selectionBar = attendeesContent.locator("[data-attendee-email-selection-bar]");
    const selectionCheckboxes = attendeesContent.locator("[data-attendee-email-selection-checkbox]");
    const selectionSendButton = selectionBar.getByRole("button", {
      name: "Continue",
    });

    // Verify selection mode starts empty and cannot send without a selection.
    await expect(selectionBar).toBeVisible();
    await expect(selectionBar).toContainText("0 attendees selected");
    await expect(openEmailActionsButton).toBeDisabled();
    await expect(selectionSendButton).toBeDisabled();
    await expect(selectionCheckboxes).toHaveCount(1);
    await expect(selectionCheckboxes).toBeVisible();

    // Select the eligible attendee and open the email modal.
    await selectionCheckboxes.check();
    await expect(selectionBar).toContainText("1 attendee selected");
    await expect(selectionSendButton).toBeEnabled();

    await selectionSendButton.click();

    // Verify the email modal is configured for selected recipients.
    const modal = organizerGroupPage.locator("#attendee-notification-modal");
    await expect(modal).toBeVisible();
    await expect(modal.getByText("This email will be sent to 1 selected attendee.")).toBeVisible();
    await expect(modal.locator("#attendee-notification-recipient-scope")).toHaveValue("selected");
    await expect(modal.locator("#attendee-notification-selected-fields input")).toHaveCount(1);

    // Close the modal and exit selection mode.
    await modal.getByRole("button", { name: "Cancel" }).click();
    await expect(modal).toBeHidden();
    await selectionBar.getByRole("button", { name: "Cancel" }).click();
    await expect(selectionBar).toBeHidden();
    await expect(openEmailActionsButton).toBeEnabled();
  });

  test("organizer can send an attendee email to selected attendees", async ({ organizerGroupPage }) => {
    // Load the attendees tab for the seeded waitlist event.
    const attendeesContent = await openAttendeesTab(
      organizerGroupPage,
      "Full Event With Waitlist",
      TEST_EVENT_IDS.alpha.waitlistLab,
    );

    // Open attendee email actions and enter selection mode.
    await attendeesContent.getByRole("button", { name: "Send email" }).click();
    await attendeesContent.getByRole("menuitem", { name: "Choose attendees" }).click();

    // Find the attendee email selection controls.
    const selectionBar = attendeesContent.locator("[data-attendee-email-selection-bar]");
    const selectionCheckboxes = attendeesContent.locator("[data-attendee-email-selection-checkbox]");

    // Select the eligible attendee and open the email modal.
    await expect(selectionCheckboxes).toHaveCount(1);
    await selectionCheckboxes.check();
    await selectionBar.getByRole("button", { name: "Continue" }).click();

    // Verify the email modal is configured for selected recipients.
    const modal = organizerGroupPage.locator("#attendee-notification-modal");
    await expect(modal).toBeVisible();
    await expect(modal.getByText("This email will be sent to 1 selected attendee.")).toBeVisible();
    await expect(modal.locator("#attendee-notification-recipient-scope")).toHaveValue("selected");

    // Fill and submit the selected attendee email.
    await modal.locator("#attendee-subject").fill(ATTENDEE_NOTIFICATION_SUBJECT);
    await modal.locator("#attendee-body").fill(ATTENDEE_NOTIFICATION_BODY);

    const [notificationResponse] = await Promise.all([
      organizerGroupPage.waitForResponse(
        (response) =>
          response.request().method() === "POST" &&
          response.url().includes(`/dashboard/group/notifications/${TEST_EVENT_IDS.alpha.waitlistLab}`) &&
          response.ok(),
      ),
      modal.getByRole("button", { name: "Send email" }).click(),
    ]);

    // Verify the selected-recipient parameters were submitted.
    expect(notificationResponse.request().postData()).toContain("recipient_scope=selected");
    expect(notificationResponse.request().postData()).toContain("recipient_user_ids%5B0%5D=");

    // Verify the selected email send closes the modal and clears selection mode.
    await expect(modal).toBeHidden();
    await expect(selectionBar).toBeHidden();
    await expect(organizerGroupPage.locator(".swal2-popup")).toContainText(
      "Email sent successfully to selected attendees!",
    );
    await organizerGroupPage.getByRole("button", { name: "OK" }).click();
    await expect(organizerGroupPage.locator(".swal2-popup")).toBeHidden();
  });

  test("organizer can open attendee email from an attendee row", async ({ organizerGroupPage }) => {
    // Load the attendees tab for the seeded waitlist event.
    const attendeesContent = await openAttendeesTab(
      organizerGroupPage,
      "Full Event With Waitlist",
      TEST_EVENT_IDS.alpha.waitlistLab,
    );

    // Find the eligible attendee row.
    const attendeeRow = attendeesContent.locator("tr", {
      hasText: "E2E Organizer One",
    });
    await expect(attendeeRow).toBeVisible();

    // Open the attendee row actions and choose the row-level email action.
    const rowActionsMenu = attendeeRow.locator("[data-attendee-row-actions-menu]");
    await rowActionsMenu.locator("summary").click();
    await rowActionsMenu.getByRole("menuitem", { name: "Send email" }).click();

    // Verify the email modal is configured for the selected attendee.
    const modal = organizerGroupPage.locator("#attendee-notification-modal");
    await expect(modal).toBeVisible();
    await expect(modal.getByText("This email will be sent to 1 selected attendee.")).toBeVisible();
    await expect(modal.locator("#attendee-notification-recipient-scope")).toHaveValue("selected");
    await expect(modal.locator("#attendee-notification-selected-fields input")).toHaveCount(1);

    // Close the attendee email modal without sending.
    await modal.getByRole("button", { name: "Cancel" }).click();
    await expect(modal).toBeHidden();
  });

  test("organizer can open the event QR code modal from the attendees tab", async ({
    organizerGroupPage,
  }) => {
    // Load the group events dashboard before opening the seeded event.
    await navigateToPath(organizerGroupPage, "/dashboard/group?tab=events");

    // Find the event row.
    const eventRow = organizerGroupPage.locator("tr", {
      hasText: "Full Event With Waitlist",
    });
    await expect(eventRow).toBeVisible();

    // Open the event update form before switching to attendees.
    await Promise.all([
      organizerGroupPage.waitForResponse(
        (response) =>
          response.request().method() === "GET" &&
          response.url().includes(`/dashboard/group/events/${TEST_EVENT_IDS.alpha.waitlistLab}/update`) &&
          response.ok(),
      ),
      eventRow.locator('td button[aria-label="Edit event: Full Event With Waitlist"]').click(),
    ]);

    // Load the attendees tab for the event.
    await Promise.all([
      organizerGroupPage.waitForResponse(
        (response) =>
          response.request().method() === "GET" &&
          response.url().includes(`/dashboard/group/events/${TEST_EVENT_IDS.alpha.waitlistLab}/attendees`) &&
          response.ok(),
      ),
      organizerGroupPage.locator('button[data-section="attendees"]').click(),
    ]);

    // Open the attendee actions menu.
    const attendeesContent = organizerGroupPage.locator("#attendees-content");
    const actionsButton = attendeesContent.getByRole("button", {
      name: "Open attendee actions menu",
    });
    await expect(actionsButton).toBeVisible();
    await actionsButton.click();

    // Assert the expected content is visible.
    const openModalButton = attendeesContent.getByRole("menuitem", {
      name: "Show check-in QR code",
    });
    await expect(openModalButton).toBeVisible();
    await openModalButton.click();

    // Verify the QR code modal content points at the check-in page.
    const modal = organizerGroupPage.locator("#event-qr-code-modal");
    await expect(modal).toBeVisible();
    await expect(modal.getByRole("heading", { name: "Event check-in QR code" })).toBeVisible();
    await expect(modal.locator("#event-qr-code-group-name")).toHaveText("Platform Ops Meetup");
    await expect(modal.locator("#event-qr-code-name")).toHaveText("Full Event With Waitlist");
    await expect(modal.locator("#event-qr-code-start")).not.toHaveText("");
    await expect(modal.locator("#event-qr-code-link")).toHaveAttribute(
      "href",
      buildE2eUrl(`/${TEST_COMMUNITY_NAME}/check-in/${TEST_EVENT_IDS.alpha.waitlistLab}`),
    );
    await expect(modal.locator("#event-qr-code-image")).toHaveAttribute(
      "src",
      `/dashboard/group/check-in/${TEST_EVENT_IDS.alpha.waitlistLab}/qr-code`,
    );
    await expect(modal.locator("#print-event-qr-code")).toBeEnabled();

    // Close the QR code modal after verifying its content.
    await modal.locator("#close-event-qr-code-modal").click();
    await expect(modal).toBeHidden();
  });
});
