import { expect, test } from "../../../fixtures.js";

import { readFile } from "node:fs/promises";

import { TEST_REGISTRATION_QUESTIONS_EVENT, TEST_TICKETING_EVENTS } from "../../../seed.js";

import { openAttendeesTab, openInvitationRequestsTab } from "./attendees-helpers.js";

test.describe("group dashboard attendees tab — answers", () => {
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
    const rowActionsMenu = attendeeRow.locator("[data-actions-menu]");

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

  test("organizer can review invitation request registration answers", async ({ organizerGroupPage }) => {
    // Load Requests for the seeded approval-required registration event.
    const requestEvent = TEST_TICKETING_EVENTS.ticketRequest;
    const requestsContent = await openInvitationRequestsTab(
      organizerGroupPage,
      requestEvent.name,
      requestEvent.id,
    );
    const requestRow = requestsContent.locator("tr", {
      hasText: "E2E Pending One",
    });
    const actionsButton = requestRow.getByRole("button", {
      name: "Open actions for E2E Pending One",
    });
    const actionsDropdown = requestRow.locator("[data-event-actions-dropdown]");

    // Open the request actions and select its answer review action.
    await expect(requestRow).toBeVisible();
    await actionsButton.click();
    await expect(actionsDropdown).toBeVisible();
    await requestRow.getByRole("button", { name: "View answers" }).click();

    // Verify the dropdown closes and the request answers fill the modal.
    const answersModal = organizerGroupPage.locator("#invitation-request-answers-modal");
    await expect(actionsDropdown).toBeHidden();
    await expect(actionsButton).toHaveAttribute("aria-expanded", "false");
    await expect(answersModal).toBeVisible();
    await expect(answersModal.getByRole("heading", { name: "Registration answers" })).toBeVisible();
    await expect(answersModal.locator("#invitation-request-answers-name")).toHaveText("E2E Pending One");
    await expect(answersModal).toContainText("Why would you like this ticket?");
    await expect(answersModal).toContainText("community programs can make technical events more welcoming");
    await expect
      .poll(() => answersModal.evaluate((modal) => modal.contains(document.activeElement)))
      .toBe(true);

    // Close the modal and return focus to the visible actions disclosure.
    await answersModal.locator("#cancel-invitation-request-answers-modal").click();
    await expect(answersModal).toBeHidden();
    await expect(actionsButton).toBeFocused();
  });

  test("viewer can review invitation request answers without managing the request", async ({
    groupViewerPage,
  }) => {
    // Load Requests with read-only group permissions.
    const requestEvent = TEST_TICKETING_EVENTS.ticketRequest;
    const requestsContent = await openInvitationRequestsTab(
      groupViewerPage,
      requestEvent.name,
      requestEvent.id,
    );
    const requestRow = requestsContent.locator("tr", {
      hasText: "E2E Pending One",
    });
    const actionsButton = requestRow.getByRole("button", {
      name: "Open actions for E2E Pending One",
    });

    // Open the read-only actions and review the submitted answer.
    await expect(actionsButton).toBeEnabled();
    await actionsButton.click();
    await expect(requestRow.getByRole("button", { name: "Accept", exact: true })).toBeDisabled();
    await expect(requestRow.getByRole("button", { name: "Reject", exact: true })).toBeDisabled();
    await requestRow.getByRole("button", { name: "View answers" }).click();

    // Verify answers remain available, then dismiss with the keyboard.
    const answersModal = groupViewerPage.locator("#invitation-request-answers-modal");
    await expect(answersModal).toBeVisible();
    await expect(answersModal).toContainText("community programs can make technical events more welcoming");
    await groupViewerPage.keyboard.press("Escape");
    await expect(answersModal).toBeHidden();
    await expect(actionsButton).toBeFocused();
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
});
