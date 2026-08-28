import { expect, test } from "../../../fixtures.js";

import { queryE2eDatabase } from "../../../database.js";
import {
  E2E_PAYMENTS_ENABLED,
  TEST_COMMUNITY_NAME,
  TEST_EVENT_NAMES,
  TEST_GROUP_SLUGS,
  TEST_PAYMENT_EVENT_IDS,
  TEST_PAYMENT_EVENT_NAMES,
  TEST_REGISTRATION_QUESTIONS_EVENT,
  TEST_REGISTRATION_WINDOW_EVENTS,
  TEST_USER_IDS,
  expectPaginationNavigation,
  expectTableColumnsAtViewport,
  expectTableHeaders,
  getAttendButton,
  getLeaveButton,
  navigateToEvent,
  navigateToPath,
  waitForActionResponse,
  waitForAttendanceState,
} from "../../../utils.js";

// Restore the active checkout hold and its unanswered registration state.
const resetClosedCheckoutAnswers = () => {
  const eventId =
    TEST_REGISTRATION_WINDOW_EVENTS.pendingPaymentClosed.id;

  queryE2eDatabase(`
    update event_attendee
    set
      registration_answers = null,
      status = 'registration-questions-pending'
    where event_id = '${eventId}'
    and user_id = '${TEST_USER_IDS.member2}';

    update event_purchase
    set
      hold_expires_at = current_timestamp + interval '2 days',
      provider_checkout_url = 'https://example.test/checkout/registration-window-pending',
      status = 'pending'
    where event_purchase_id = '59555555-5555-5555-5555-555555555911';
  `);
};

// Cancel attendance from the public event page when a reusable user is registered.
const cancelPublicAttendance = async (page, eventId) => {
  const leaveButton = getLeaveButton(page);
  await leaveButton.click();
  await expect(page.getByRole("button", { name: "Yes" })).toBeVisible();

  await waitForActionResponse(page, () => page.getByRole("button", { name: "Yes" }).click(), {
    method: "DELETE",
    urlIncludes: `/event/${eventId}/leave`,
  });
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
  test("empty state explains when the user has no upcoming events", async ({
    emptyUserPage,
  }) => {
    // Load My Events for the dedicated user without event participation.
    await navigateToPath(emptyUserPage, "/dashboard/user?tab=events");
    const dashboardContent = emptyUserPage.locator("#dashboard-content");

    // Verify the zero count and empty result guidance remain visible.
    await expect(dashboardContent).toContainText("0 events");
    await expect(dashboardContent).toContainText(
      "You don't have any upcoming events yet.",
    );
  });

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

  test("my events shows rejected refund status and reason", async ({
    pending1Page,
  }) => {
    // Load My Events for the attendee with a seeded rejected refund request.
    await navigateToPath(pending1Page, "/dashboard/user?tab=events");
    const dashboardContent = pending1Page.locator("#dashboard-content");
    const refundEventRow = dashboardContent.locator("tr", {
      hasText: TEST_PAYMENT_EVENT_NAMES.refunds,
    });

    // Verify the danger state and complete organizer-provided reason.
    await expect(refundEventRow).toBeVisible();
    const refundStatusButton = refundEventRow.getByRole("button", {
      name: "Refund rejected",
    });
    const rejectionReason = refundEventRow.getByRole("tooltip");
    await expect(refundStatusButton).toBeVisible();
    await refundStatusButton.focus();
    await expect(rejectionReason).toBeVisible();
    await expect(rejectionReason.getByText("Refund request")).toBeVisible();
    await expect(
      rejectionReason.getByText("Reason", { exact: true }),
    ).toBeVisible();
    await expect(
      rejectionReason.getByText(
        "The request falls outside the refund policy window.",
      ),
    ).toBeVisible();
  });

  test("my events exposes the eligibility-gated request refund action", async ({
    organizerGroupPage,
  }) => {
    test.skip(
      !E2E_PAYMENTS_ENABLED,
      "Payments are disabled in this environment.",
    );

    // Load My Events and wait for the paid row's eligibility check.
    await waitForActionResponse(
      organizerGroupPage,
      () => navigateToPath(organizerGroupPage, "/dashboard/user?tab=events"),
      {
        method: "GET",
        urlIncludes: `/event/${TEST_PAYMENT_EVENT_IDS.refunds}/enrollment`,
      },
    );

    const refundEventRow = organizerGroupPage
      .locator("#dashboard-content")
      .locator("tr", { hasText: TEST_PAYMENT_EVENT_NAMES.refunds });
    await openEventActions(refundEventRow);
    const refundAction = refundEventRow.getByRole("menuitem", {
      name: "Request refund",
    });

    // The eligible action opens the event's refund control in a new tab.
    await expect(refundAction).toBeVisible();
    const popupPromise = organizerGroupPage.waitForEvent("popup");
    await refundAction.click();
    const refundPage = await popupPromise;
    await refundPage.waitForLoadState("domcontentloaded");
    await expect(refundPage).toHaveURL(/#refund-btn-main$/u);
    await expect(
      refundPage.locator('[data-attendance-role="refund-btn"]'),
    ).toContainText("Request refund");
    await refundPage.close();
  });

  test("my events actions update registration answers and cancel attendance", async ({
    pending2Page,
  }) => {
    // Load the registration-questions event before creating attendance.
    await navigateToEvent(
      pending2Page,
      TEST_COMMUNITY_NAME,
      TEST_GROUP_SLUGS.community1.alpha,
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
    await waitForActionResponse(
      pending2Page,
      () => publicRegistrationModal.locator('[data-attendance-role="registration-modal-submit"]').click(),
      {
        method: "POST",
        urlIncludes: `/event/${TEST_REGISTRATION_QUESTIONS_EVENT.id}/attend`,
      },
    );
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
    await waitForActionResponse(
      pending2Page,
      () => dashboardRegistrationModal.getByRole("button", { name: "Save answers" }).click(),
      {
        method: "PUT",
        urlIncludes: `/dashboard/user/events/${TEST_COMMUNITY_NAME}/${TEST_REGISTRATION_QUESTIONS_EVENT.id}/registration-answers`,
      },
    );
    await expect(dashboardRegistrationModal).toBeHidden();

    // Reopen the row menu and cancel attendance from My Events.
    await eventRow.getByLabel("Open event actions").click();
    await eventRow.getByRole("menuitem", { name: "Cancel attendance" }).click();
    await expect(pending2Page.locator(".swal2-popup")).toContainText(
      "Are you sure you want to cancel your attendance?",
    );

    // Confirm cancellation and verify the dashboard row disappears.
    await waitForActionResponse(
      pending2Page,
      () => pending2Page.getByRole("button", { name: "Yes" }).click(),
      {
        method: "DELETE",
        urlIncludes: `/dashboard/user/events/${TEST_COMMUNITY_NAME}/${TEST_REGISTRATION_QUESTIONS_EVENT.id}/attendance`,
      },
    );
    await expect(
      dashboardContent.locator("tr", {
        hasText: TEST_REGISTRATION_QUESTIONS_EVENT.name,
      }),
    ).toHaveCount(0);
  });

  test("my events exposes offers and active checkout actions after registration closes", async ({
    member2Page,
  }) => {
    // Load My Events before checking registration-window actions.
    await navigateToPath(member2Page, "/dashboard/user?tab=events");

    // Target dashboard content after the events tab loads.
    const dashboardContent = member2Page.locator("#dashboard-content");
    await expect(
      dashboardContent.getByText("My Events", { exact: true }),
    ).toBeVisible();

    // Verify a waiting-list offer is claimed from the invitations dashboard.
    const closedQuestionsRow = dashboardContent.locator("tr", {
      hasText: TEST_REGISTRATION_WINDOW_EVENTS.questionsClosed.name,
    });
    await expect(closedQuestionsRow).toContainText("Event offer");
    await openEventActions(closedQuestionsRow);
    await expect(
      closedQuestionsRow.getByRole("menuitem", { name: "View event offer" }),
    ).toHaveAttribute(
      "href",
      /\/dashboard\/user\?tab=invitations#event-offer-/,
    );
    await closeEventActions(closedQuestionsRow);

    // Verify an organizer invitation uses the same offer claim surface.
    const manualInviteRow = dashboardContent.locator("tr", {
      hasText: TEST_REGISTRATION_WINDOW_EVENTS.questionsManualInviteClosed.name,
    });
    await expect(manualInviteRow).toContainText("Event offer");
    await openEventActions(manualInviteRow);
    await expect(
      manualInviteRow.getByRole("menuitem", { name: "View event offer" }),
    ).toHaveAttribute(
      "href",
      /\/dashboard\/user\?tab=invitations#event-offer-/,
    );
    await closeEventActions(manualInviteRow);

    // Verify an active checkout hold can still be resumed after closing.
    const pendingPaymentRow = dashboardContent.locator("tr", {
      hasText: TEST_REGISTRATION_WINDOW_EVENTS.pendingPaymentClosed.name,
    });
    await expect(pendingPaymentRow).toContainText("Payment pending");
    await expect(
      pendingPaymentRow.getByText("Attendee", { exact: true }),
    ).toHaveCount(0);
    await openEventActions(pendingPaymentRow);
    await expect(
      pendingPaymentRow.getByRole("menuitem", {
        name: "Continue to checkout",
      }),
    ).toHaveAttribute(
      "href",
      "https://example.test/checkout/registration-window-pending",
    );
    await expect(
      pendingPaymentRow.getByRole("menuitem", {
        name: "Complete registration",
      }),
    ).toBeEnabled();
    await expect(
      pendingPaymentRow.getByRole("menuitem", {
        name: "Cancel checkout",
      }),
    ).toBeEnabled();
  });

  test("active checkout holds save required answers after registration closes", async ({
    member2Page,
  }) => {
    const event =
      TEST_REGISTRATION_WINDOW_EVENTS.pendingPaymentClosed;

    // Restore the active checkout hold after registration closes.
    resetClosedCheckoutAnswers();

    try {
      // Load the held registration and open its completion flow.
      await navigateToPath(member2Page, "/dashboard/user?tab=events");
      const dashboardContent = member2Page.locator("#dashboard-content");
      const eventRow = dashboardContent.locator("tr", {
        hasText: event.name,
      });
      await expect(eventRow).toContainText("Payment pending");
      await openEventActions(eventRow);
      const completeRegistrationAction = eventRow.getByRole("menuitem", {
        name: "Complete registration",
      });
      await expect(completeRegistrationAction).toBeEnabled();
      await completeRegistrationAction.click();

      // Answer the required registration question in the completion modal.
      const registrationModal = member2Page.getByRole("dialog", {
        name: "Registration questions",
      });
      const answer =
        "I will finish these answers while my checkout hold is active.";
      await expect(registrationModal).toBeVisible();
      await registrationModal
        .locator("fieldset", {
          hasText: "What should the organizers know?",
        })
        .locator("textarea")
        .fill(answer);

      // Submit the answer and verify its serialized request contract.
      const answersRequest = member2Page.waitForRequest(
        (request) =>
          request.method() === "PUT" &&
          request.url().includes(`/${event.id}/registration-answers`),
      );
      await waitForActionResponse(
        member2Page,
        () =>
          registrationModal
            .getByRole("button", {
              name: "Save answers",
              exact: true,
            })
            .click(),
        {
          method: "PUT",
          urlIncludes: `/dashboard/user/events/${TEST_COMMUNITY_NAME}/${event.id}/registration-answers`,
        },
      );
      const requestData = new URLSearchParams(
        (await answersRequest).postData() ?? "",
      );
      expect(JSON.parse(requestData.get("registration_answers"))).toEqual({
        answers: [
          {
            question_id: "57555555-5555-5555-5555-555555555911",
            value: answer,
          },
        ],
      });
      await expect(registrationModal).toBeHidden();
      await expect(member2Page.locator(".swal2-popup")).toContainText(
        "Registration answers saved.",
      );
      await member2Page.getByRole("button", { name: "OK" }).click();

      // Reloaded state keeps the hold resumable and the answer editable.
      await expect(eventRow).toContainText("Payment pending");
      await openEventActions(eventRow);
      await expect(
        eventRow.getByRole("menuitem", { name: "Continue to checkout" }),
      ).toHaveAttribute(
        "href",
        "https://example.test/checkout/registration-window-pending",
      );
      await eventRow
        .getByRole("menuitem", { name: "Update answers" })
        .click();
      await expect(
        member2Page
          .getByRole("dialog", { name: "Registration questions" })
          .locator("textarea"),
      ).toHaveValue(answer);
    } finally {
      // Restore the seeded checkout hold for later tests.
      resetClosedCheckoutAnswers();
    }
  });
});
test("my events table exposes every column at its responsive breakpoint", async ({
  member1Page,
}) => {
  // Load My Events before checking table structure.
  await navigateToPath(member1Page, "/dashboard/user?tab=events");

  // Find the events table and its complete ordered header set.
  const eventsTable = member1Page
    .locator("#dashboard-content")
    .getByRole("table");
  const headers = ["Title", "Location", "Date", "Role", "Status", "Actions"];

  // Verify header order and column visibility across dashboard breakpoints.
  await expectTableColumnsAtViewport(
    member1Page,
    eventsTable,
    1024,
    ["Title", "Status / role", "Actions"],
    ["Location", "Date", "Status"],
  );
  await expectTableColumnsAtViewport(
    member1Page,
    eventsTable,
    1280,
    ["Title", "Date", "Role", "Status", "Actions"],
    ["Location"],
  );
  await expectTableColumnsAtViewport(
    member1Page,
    eventsTable,
    1536,
    headers,
    [],
  );
  await expectTableHeaders(eventsTable, headers);
});

test("member can move between event result pages", async ({ member1Page }) => {
  // Paginate the seeded user-event rows with one result per page.
  await expectPaginationNavigation(
    member1Page,
    "/dashboard/user?tab=events&limit=1&offset=0",
    "#dashboard-content tbody tr",
  );
});
