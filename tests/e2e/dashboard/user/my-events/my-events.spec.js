import { expect, test } from "../../../fixtures.js";

import {
  TEST_ALLIANCE_NAME,
  TEST_EVENT_NAMES,
  TEST_GROUP_SLUGS,
  TEST_REGISTRATION_QUESTIONS_EVENT,
  TEST_REGISTRATION_WINDOW_EVENTS,
  getAttendButton,
  getLeaveButton,
  navigateToEvent,
  navigateToPath,
  waitForAttendanceState,
} from "../../../utils.js";

// Cancel attendance from the public event page when a reusable user is registered.
const cancelPublicAttendance = async (page, eventId) => {
  const leaveButton = getLeaveButton(page);
  await leaveButton.click();
  await expect(page.getByRole("button", { name: "Yes" })).toBeVisible();

  await Promise.all([
    page.waitForResponse(
      (response) =>
        response.request().method() === "DELETE" &&
        response.url().includes(`/event/${eventId}/leave`) &&
        response.ok(),
    ),
    page.getByRole("button", { name: "Yes" }).click(),
  ]);
};

// Fill all seeded registration question types in the visible modal.
const fillRegistrationQuestions = async (modal, values) => {
  await modal
    .locator("fieldset", {
      hasText: "What are you hoping to learn from this event?",
    })
    .locator("textarea")
    .fill(values.learningGoal);
  await modal.getByRole("radio", { name: values.sessionFormat }).check();
  await modal.getByRole("checkbox", { name: "Developer experience" }).check();
  await modal
    .getByRole("checkbox", { name: "Security and compliance" })
    .check();
  await modal
    .locator("fieldset", {
      hasText: "Anything the organizers should know?",
    })
    .locator("textarea")
    .fill(values.organizerNote);
};

// Open the actions menu for a My Events row.
const openEventActions = async (eventRow) => {
  await eventRow.getByLabel("Open event actions").click();
};

// Close the actions menu for a My Events row.
const closeEventActions = async (eventRow) => {
  await eventRow
    .locator("[data-user-event-actions-dropdown]")
    .evaluate((dropdown) => {
      dropdown.open = false;
    });
};

test.describe("user dashboard my events view", () => {
  test("my events page lists only upcoming published participation", async ({
    member1Page,
  }) => {
    // Load the user events tab before checking filtered participation.
    await navigateToPath(member1Page, "/dashboard/user?tab=events");

    // Find the dashboard content.
    const dashboardContent = member1Page.locator("#dashboard-content");

    // Verify my events page lists only upcoming published participation.
    await expect(
      dashboardContent.getByText("My Events", { exact: true }),
    ).toBeVisible();

    // Find the attendee speaker row.
    const attendeeSpeakerRow = dashboardContent.locator("tr", {
      hasText: TEST_EVENT_NAMES.alpha[0],
    });
    await expect(attendeeSpeakerRow).toContainText("Attendee");
    await expect(attendeeSpeakerRow).toContainText("Speaker");

    // Assert how many matching elements are shown.
    await expect(
      dashboardContent.getByText("Past Event For Filtering"),
    ).toHaveCount(0);
    await expect(
      dashboardContent.getByText(TEST_EVENT_NAMES.beta[0]),
    ).toHaveCount(0);
  });

  test("my events actions update registration answers and cancel attendance", async ({
    pending2Page,
  }) => {
    // Load the registration-questions event before creating attendance.
    await navigateToEvent(
      pending2Page,
      TEST_ALLIANCE_NAME,
      TEST_GROUP_SLUGS.alliance1.alpha,
      TEST_REGISTRATION_QUESTIONS_EVENT.slug,
    );

    // Reset any leftover attendance for this reusable user.
    await waitForAttendanceState(pending2Page);
    if (await getLeaveButton(pending2Page).isVisible()) {
      await cancelPublicAttendance(
        pending2Page,
        TEST_REGISTRATION_QUESTIONS_EVENT.id,
      );
    }

    // Attend the event through the required questions modal.
    await getAttendButton(pending2Page).click();
    const publicRegistrationModal = pending2Page.locator(
      '[data-attendance-role="registration-modal"]',
    );
    await expect(publicRegistrationModal).toBeVisible();
    await fillRegistrationQuestions(publicRegistrationModal, {
      learningGoal: "I want dashboard coverage for registration answers.",
      organizerNote: "Created from the My Events dashboard e2e flow.",
      sessionFormat: "Panel discussion",
    });

    // Submit the public registration answers.
    await Promise.all([
      pending2Page.waitForResponse(
        (response) =>
          response.request().method() === "POST" &&
          response
            .url()
            .includes(
              `/event/${TEST_REGISTRATION_QUESTIONS_EVENT.id}/attend`,
            ) &&
          response.ok(),
      ),
      publicRegistrationModal
        .locator('[data-attendance-role="registration-modal-submit"]')
        .click(),
    ]);
    await expect(getLeaveButton(pending2Page)).toContainText(
      "Cancel attendance",
    );

    // Open My Events and target the newly registered event row.
    await navigateToPath(pending2Page, "/dashboard/user?tab=events");
    const dashboardContent = pending2Page.locator("#dashboard-content");
    const eventRow = dashboardContent.locator("tr", {
      hasText: TEST_REGISTRATION_QUESTIONS_EVENT.name,
    });
    await expect(eventRow).toContainText("Attendee");

    // Open the row menu and launch the registration answers modal.
    await eventRow.getByLabel("Open event actions").click();
    await eventRow.getByRole("menuitem", { name: "Update answers" }).click();
    const dashboardRegistrationModal = pending2Page.locator(
      `#user-event-questions-modal-${TEST_REGISTRATION_QUESTIONS_EVENT.id}`,
    );
    await expect(dashboardRegistrationModal).toBeVisible();
    await expect(dashboardRegistrationModal).toContainText(
      "What are you hoping to learn from this event?",
    );

    // Update answers from the dashboard modal.
    await fillRegistrationQuestions(dashboardRegistrationModal, {
      learningGoal: "I updated these answers from the dashboard.",
      organizerNote: "Updated through My Events.",
      sessionFormat: "Hands-on workshop",
    });
    await Promise.all([
      pending2Page.waitForResponse(
        (response) =>
          response.request().method() === "PUT" &&
          response
            .url()
            .includes(
              `/dashboard/user/events/${TEST_ALLIANCE_NAME}/${TEST_REGISTRATION_QUESTIONS_EVENT.id}/registration-answers`,
            ) &&
          response.ok(),
      ),
      dashboardRegistrationModal
        .getByRole("button", { name: "Save answers" })
        .click(),
    ]);
    await expect(dashboardRegistrationModal).toBeHidden();

    // Reopen the row menu and cancel attendance from My Events.
    await eventRow.getByLabel("Open event actions").click();
    await eventRow.getByRole("menuitem", { name: "Cancel attendance" }).click();
    await expect(pending2Page.locator(".swal2-popup")).toContainText(
      "Are you sure you want to cancel your attendance?",
    );

    // Confirm cancellation and verify the dashboard row disappears.
    await Promise.all([
      pending2Page.waitForResponse(
        (response) =>
          response.request().method() === "DELETE" &&
          response
            .url()
            .includes(
              `/dashboard/user/events/${TEST_ALLIANCE_NAME}/${TEST_REGISTRATION_QUESTIONS_EVENT.id}/attendance`,
            ) &&
          response.ok(),
      ),
      pending2Page.getByRole("button", { name: "Yes" }).click(),
    ]);
    await expect(
      dashboardContent.locator("tr", {
        hasText: TEST_REGISTRATION_QUESTIONS_EVENT.name,
      }),
    ).toHaveCount(0);
  });

  test("my events respects closed registration windows for pending actions", async ({
    member2Page,
  }) => {
    // Load My Events before checking registration-window actions.
    await navigateToPath(member2Page, "/dashboard/user?tab=events");

    // Target dashboard content after the events tab loads.
    const dashboardContent = member2Page.locator("#dashboard-content");
    await expect(
      dashboardContent.getByText("My Events", { exact: true }),
    ).toBeVisible();

    // Verify normal pending registration cannot continue after closing.
    const closedQuestionsRow = dashboardContent.locator("tr", {
      hasText: TEST_REGISTRATION_WINDOW_EVENTS.questionsClosed.name,
    });
    await expect(closedQuestionsRow).toContainText("Registration pending");
    await openEventActions(closedQuestionsRow);
    const closedCompleteRegistration = closedQuestionsRow.getByRole(
      "menuitem",
      { name: "Complete registration" },
    );
    await expect(closedCompleteRegistration).toBeDisabled();
    await expect(closedCompleteRegistration).toHaveAttribute(
      "title",
      /Registration closed/,
    );
    await closeEventActions(closedQuestionsRow);

    // Verify manual invitations can still complete pending questions.
    const manualInviteRow = dashboardContent.locator("tr", {
      hasText: TEST_REGISTRATION_WINDOW_EVENTS.questionsManualInviteClosed.name,
    });
    await expect(manualInviteRow).toContainText("Registration pending");
    await openEventActions(manualInviteRow);
    const manualCompleteRegistration = manualInviteRow.getByRole("menuitem", {
      name: "Complete registration",
    });
    await expect(manualCompleteRegistration).toBeEnabled();
    await closeEventActions(manualInviteRow);

    // Verify an active checkout hold can still be resumed after closing.
    const pendingPaymentRow = dashboardContent.locator("tr", {
      hasText: TEST_REGISTRATION_WINDOW_EVENTS.pendingPaymentClosed.name,
    });
    await expect(pendingPaymentRow).toContainText("Payment pending");
    await openEventActions(pendingPaymentRow);
    await expect(
      pendingPaymentRow.getByRole("menuitem", { name: "Complete payment" }),
    ).toHaveAttribute(
      "href",
      "https://example.test/checkout/registration-window-pending",
    );
    await expect(
      pendingPaymentRow.getByRole("menuitem", {
        name: "Complete registration",
      }),
    ).toBeEnabled();
  });
});
