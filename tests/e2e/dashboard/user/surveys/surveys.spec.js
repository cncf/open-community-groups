import { randomUUID } from "node:crypto";

import { expect, test } from "../../../fixtures.js";
import { cleanupEventsByIds } from "../../../data-graphs/events.js";
import {
  bumpOwnedSurveyRevision,
  cleanupEventSurveys,
  readSurveyResponseAnswers,
  setupOwnedEventSurvey,
  setupOwnedSurveyEvent,
  setupOwnedSurveyResponse,
  TEST_EVENT_SURVEYS,
} from "../../../data-graphs/surveys.js";
import { TEST_USER_CREDENTIALS, TEST_USER_IDS } from "../../../seed.js";
import { expectCurrentPaginationNavigation, navigateToPath, waitForActionResponse } from "../../../utils.js";

// Message shown when the survey an email links to isn't available.
const UNAVAILABLE_SURVEY_WARNING = "This survey is closed or isn't available to you.";

// Message shown before a survey with unsaved answers is closed.
const UNSAVED_ANSWERS_MESSAGE = "You have unsaved answers. If you close the survey, they will be lost.";

test.describe("user dashboard event surveys", () => {
  test("attendees answer an open survey and edit their answers", async ({ member1Page }) => {
    const survey = setupOpenSurvey();

    try {
      // Open the survey from its email link and verify the anonymity notice.
      await navigateToPath(member1Page, surveyLinkPath(survey.id));
      const modal = member1Page.locator("#user-event-survey-modal");
      await expect(modal).toBeVisible();
      await expect(modal.getByRole("heading", { name: /E2E open survey/ })).toBeVisible();
      await expect(modal.locator("[data-survey-privacy-notice]")).toContainText(
        "Your answers are linked to your account only so you can edit them later.",
      );

      // Submit without the required answer and verify nothing is sent.
      const form = modal.locator("[data-user-event-survey-form]");
      let requestsSent = 0;
      const countRequests = (request) => {
        if (request.method() === "PUT" && request.url().includes(`/surveys/${survey.id}/response`)) {
          requestsSent += 1;
        }
      };
      member1Page.on("request", countRequests);
      await form.getByRole("button", { name: "Submit answers" }).click();
      await expect
        .poll(() => form.getByLabel("Yes").evaluate((input) => input.validationMessage))
        .not.toBe("");
      member1Page.off("request", countRequests);
      expect(requestsSent).toBe(0);

      // Answer the survey and verify the stored response.
      await form.getByLabel("Yes").check();
      await form.getByLabel("Any comments?").fill("Great sessions.");
      await waitForActionResponse(
        member1Page,
        () => form.getByRole("button", { name: "Submit answers" }).click(),
        {
          method: "PUT",
          status: 204,
          urlIncludes: `/dashboard/user/surveys/${survey.id}/response`,
        },
      );
      await expect(member1Page.locator(".swal2-popup")).toContainText("Survey answers saved.");
      await expect(modal).toBeHidden();
      await expect(member1Page).toHaveURL(
        (url) =>
          url.pathname === "/dashboard/user" &&
          url.searchParams.get("tab") === "surveys" &&
          !url.searchParams.has("event_survey_id"),
      );
      await expect(member1Page.locator(`[data-user-event-survey="${survey.id}"]`)).toContainText("Answered");
      expect(readSurveyResponseAnswers({ surveyId: survey.id, userId: TEST_USER_IDS.member1 })).toEqual({
        answers: [
          { question_id: survey.questionIds.again, value: survey.optionIds.yes },
          { question_id: survey.questionIds.comments, value: "Great sessions." },
        ],
      });

      // Reopen the survey and edit the saved answers.
      await navigateToPath(member1Page, surveyLinkPath(survey.id));
      await expect(modal.locator("[data-survey-response-saved]")).toBeVisible();
      const editedForm = modal.locator("[data-user-event-survey-form]");
      await expect(editedForm.getByLabel("Any comments?")).toHaveValue("Great sessions.");
      await editedForm.getByLabel("No").check();
      await editedForm.getByLabel("Any comments?").fill("");
      await waitForActionResponse(
        member1Page,
        () => editedForm.getByRole("button", { name: "Save changes" }).click(),
        { method: "PUT", status: 204, urlIncludes: `/dashboard/user/surveys/${survey.id}/response` },
      );
      expect(readSurveyResponseAnswers({ surveyId: survey.id, userId: TEST_USER_IDS.member1 })).toEqual({
        answers: [{ question_id: survey.questionIds.again, value: survey.optionIds.no }],
      });
    } finally {
      cleanupEventSurveys([survey.id]);
    }
  });

  test("a stale survey keeps the answers the user entered", async ({ member1Page }) => {
    const survey = setupOpenSurvey();

    try {
      // Open the survey, then change it as an organizer would.
      await navigateToPath(member1Page, surveyLinkPath(survey.id));
      const modal = member1Page.locator("#user-event-survey-modal");
      await expect(modal).toBeVisible();
      bumpOwnedSurveyRevision(survey.id);

      // Submit answers given to the previous revision.
      const form = modal.locator("[data-user-event-survey-form]");
      await form.getByLabel("Yes").check();
      await form.getByLabel("Any comments?").fill("Keep this text.");
      await waitForActionResponse(
        member1Page,
        () => form.getByRole("button", { name: "Submit answers" }).click(),
        {
          method: "PUT",
          status: 422,
          urlIncludes: `/dashboard/user/surveys/${survey.id}/response`,
        },
      );

      // Verify the error is shown and the answers stay in the open modal.
      await expect(member1Page.locator(".swal2-popup")).toContainText(
        "the survey changed; review and try again",
      );
      await expect(modal).toBeVisible();
      await expect(form.getByLabel("Any comments?")).toHaveValue("Keep this text.");
      await expect(form.getByLabel("Yes")).toBeChecked();
      expect(readSurveyResponseAnswers({ surveyId: survey.id, userId: TEST_USER_IDS.member1 })).toBeNull();
    } finally {
      cleanupEventSurveys([survey.id]);
    }
  });

  test("attendees select several options of a multi-select question", async ({ member1Page }) => {
    const questionId = randomUUID();
    const optionIds = { kubernetes: randomUUID(), observability: randomUUID(), security: randomUUID() };
    const survey = setupOwnedEventSurvey({
      eventId: TEST_EVENT_SURVEYS.event.id,
      questions: [
        {
          id: questionId,
          kind: "multi-select",
          options: [
            { id: optionIds.kubernetes, label: "Kubernetes" },
            { id: optionIds.observability, label: "Observability" },
            { id: optionIds.security, label: "Security" },
          ],
          prompt: "Which topics should we cover?",
          required: true,
        },
      ],
      status: "ready",
      title: `E2E multi-select survey ${id8()}`,
    });

    try {
      // Open the survey and select two topics.
      await navigateToPath(member1Page, surveyLinkPath(survey.id));
      const modal = member1Page.locator("#user-event-survey-modal");
      const form = modal.locator("[data-user-event-survey-form]");
      await expect(form).toBeVisible();
      await form.getByLabel("Kubernetes").check();
      await form.getByLabel("Security").check();

      // Submit the answers and verify every selected option is stored.
      await waitForActionResponse(
        member1Page,
        () => form.getByRole("button", { name: "Submit answers" }).click(),
        { method: "PUT", status: 204, urlIncludes: `/dashboard/user/surveys/${survey.id}/response` },
      );
      await expect(member1Page.locator(".swal2-popup")).toContainText("Survey answers saved.");
      expect(readSurveyResponseAnswers({ surveyId: survey.id, userId: TEST_USER_IDS.member1 })).toEqual({
        answers: [{ question_id: questionId, value: [optionIds.kubernetes, optionIds.security] }],
      });

      // Reopen the survey and verify the saved selection is restored.
      await navigateToPath(member1Page, surveyLinkPath(survey.id));
      await expect(form.getByLabel("Kubernetes")).toBeChecked();
      await expect(form.getByLabel("Observability")).not.toBeChecked();
      await expect(form.getByLabel("Security")).toBeChecked();
    } finally {
      cleanupEventSurveys([survey.id]);
    }
  });

  test("attendees confirm before closing a survey with unsaved answers", async ({ member1Page }) => {
    const survey = setupOpenSurvey();

    try {
      // Open the survey and close it untouched from the overlay.
      await navigateToPath(member1Page, surveyLinkPath(survey.id));
      const modal = member1Page.locator("#user-event-survey-modal");
      const overlay = modal.locator(".modal-overlay[data-user-event-survey-close]");
      await expect(modal).toBeVisible();
      await overlay.click({ position: { x: 10, y: 10 } });
      await expect(modal).toBeHidden();
      await expect(member1Page.locator(".swal2-popup")).toHaveCount(0);

      // Reopen the survey, answer it and keep answering when Escape would discard the answers.
      await navigateToPath(member1Page, surveyLinkPath(survey.id));
      const form = modal.locator("[data-user-event-survey-form]");
      await form.getByLabel("Yes").check();
      await form.getByLabel("Any comments?").fill("Draft comment.");
      await member1Page.keyboard.press("Escape");
      const popup = member1Page.locator(".swal2-popup");
      await expect(popup).toContainText(UNSAVED_ANSWERS_MESSAGE);
      await popup.getByRole("button", { name: "Keep answering" }).click();
      await expect(popup).toBeHidden();
      await expect(modal).toBeVisible();
      await expect(form.getByLabel("Yes")).toBeChecked();
      await expect(form.getByLabel("Any comments?")).toHaveValue("Draft comment.");

      // Discard the answers from the overlay and verify the survey closes unanswered.
      await overlay.click({ position: { x: 10, y: 10 } });
      await expect(popup).toContainText(UNSAVED_ANSWERS_MESSAGE);
      await popup.getByRole("button", { name: "Discard answers" }).click();
      await expect(modal).toBeHidden();
      await expect(member1Page).toHaveURL(
        (url) => url.searchParams.get("tab") === "surveys" && !url.searchParams.has("event_survey_id"),
      );
      expect(readSurveyResponseAnswers({ surveyId: survey.id, userId: TEST_USER_IDS.member1 })).toBeNull();
    } finally {
      cleanupEventSurveys([survey.id]);
    }
  });

  test("email links to an answered closed survey show the answers read-only", async ({ member1Page }) => {
    const survey = setupOwnedEventSurvey({
      closedAtSql: "current_timestamp - interval '1 hour'",
      eventId: TEST_EVENT_SURVEYS.event.id,
      status: "ready",
      title: `E2E closed answered survey ${id8()}`,
    });
    setupOwnedSurveyResponse({
      answers: { answers: [{ question_id: survey.questionId, value: "Friendly hosts." }] },
      surveyId: survey.id,
      userId: TEST_USER_IDS.member1,
    });

    try {
      // Follow the email link to the closed survey.
      await navigateToPath(member1Page, surveyLinkPath(survey.id));

      // Verify the saved answers are shown without a form to change them.
      const modal = member1Page.locator("#user-event-survey-modal");
      await expect(modal).toBeVisible();
      await expect(modal.locator("[data-survey-closed-notice]")).toContainText(
        "This survey is closed, so your answers can no longer be changed.",
      );
      await expect(modal).toContainText("Friendly hosts.");
      await expect(modal.locator("[data-user-event-survey-form]")).toHaveCount(0);
      await expect(member1Page.locator("#dashboard-content")).not.toContainText(UNAVAILABLE_SURVEY_WARNING);
    } finally {
      cleanupEventSurveys([survey.id]);
    }
  });

  test("email links to surveys that can't be answered show a warning", async ({
    member1Page,
    member2Page,
  }) => {
    // Verify closed surveys the user did not answer, drafts, scheduled and missing surveys do not open.
    for (const surveyId of [
      TEST_EVENT_SURVEYS.surveys.closed.id,
      TEST_EVENT_SURVEYS.surveys.draft.id,
      TEST_EVENT_SURVEYS.surveys.scheduled.id,
      randomUUID(),
    ]) {
      await navigateToPath(member1Page, surveyLinkPath(surveyId));
      await expect(member1Page.locator("#dashboard-content")).toContainText(UNAVAILABLE_SURVEY_WARNING);
      await expect(member1Page.locator("#user-event-survey-modal")).toBeHidden();
    }

    // Verify users outside the audience cannot open an open survey.
    await navigateToPath(member2Page, surveyLinkPath(TEST_EVENT_SURVEYS.surveys.openIdentified.id));
    await expect(member2Page.locator("#dashboard-content")).toContainText(UNAVAILABLE_SURVEY_WARNING);
    await expect(member2Page.locator("#user-event-survey-modal")).toBeHidden();
  });

  test("signed-out visitors log in and return to the survey", async ({ page }) => {
    // Follow the email link without a session.
    const surveyId = TEST_EVENT_SURVEYS.surveys.openIdentified.id;
    await navigateToPath(page, surveyLinkPath(surveyId));
    await expect(page).toHaveURL(/\/log-in\?next_url=/);

    // Log in and verify the survey opens in the Surveys tab.
    await page.getByLabel("Username").fill(TEST_USER_CREDENTIALS.member1.username);
    await page
      .getByRole("textbox", { name: "Password required" })
      .fill(TEST_USER_CREDENTIALS.member1.password);
    await Promise.all([
      page.waitForURL(
        (url) =>
          url.pathname === "/dashboard/user" &&
          url.searchParams.get("tab") === "surveys" &&
          url.searchParams.get("event_survey_id") === surveyId,
      ),
      page.getByRole("button", { name: "Sign In" }).click(),
    ]);
    await expect(page.locator("#user-event-survey-modal")).toBeVisible();
  });

  test("the surveys tab lists open surveys first and answered closed surveys read-only", async ({
    pending2Page,
  }) => {
    // Give the second pending user an open survey to answer, an answered one and closed ones.
    const event = setupOwnedSurveyEvent({ attendeeUserIds: [TEST_USER_IDS.pending2] });
    const toAnswer = setupOwnedEventSurvey({
      eventId: event.id,
      status: "ready",
      title: `To answer ${id8()}`,
    });
    const answered = setupOwnedEventSurvey({
      eventId: event.id,
      status: "ready",
      title: `Answered ${id8()}`,
    });
    const closedAnswered = setupOwnedEventSurvey({
      closedAtSql: "current_timestamp - interval '1 hour'",
      eventId: event.id,
      status: "ready",
      title: `Closed answered ${id8()}`,
    });
    const closedUnanswered = setupOwnedEventSurvey({
      closedAtSql: "current_timestamp - interval '1 hour'",
      eventId: event.id,
      status: "ready",
      title: `Closed unanswered ${id8()}`,
    });
    for (const [survey, value] of [
      [answered, "Good pace."],
      [closedAnswered, "Loved the venue."],
    ]) {
      setupOwnedSurveyResponse({
        answers: { answers: [{ question_id: survey.questionId, value }] },
        surveyId: survey.id,
        userId: TEST_USER_IDS.pending2,
      });
    }

    try {
      // Load the Surveys tab and verify the menu badge counts the survey left to answer.
      await navigateToPath(pending2Page, "/dashboard/user?tab=surveys");
      const surveysMenuItem = pending2Page.locator('#dashboard-menu a[href="/dashboard/user?tab=surveys"]');
      await expect(surveysMenuItem).toHaveText(/^\s*Surveys\s*1\s*$/);

      // Verify open surveys come first, then the answered closed survey.
      const rows = pending2Page.locator("#dashboard-content tbody tr[data-user-event-survey]");
      await expect(rows).toHaveCount(3);
      await expect(rows.nth(0)).toHaveAttribute("data-user-event-survey", toAnswer.id);
      await expect(rows.nth(0)).toContainText("To answer");
      await expect(rows.nth(1)).toHaveAttribute("data-user-event-survey", answered.id);
      await expect(rows.nth(1).getByRole("button", { name: /Edit answers/ })).toBeVisible();
      await expect(rows.nth(2)).toHaveAttribute("data-user-event-survey", closedAnswered.id);
      await expect(rows.nth(2)).toContainText("Closed");
      await expect(pending2Page.locator(`[data-user-event-survey="${closedUnanswered.id}"]`)).toHaveCount(0);

      // Review the answers of the closed survey without being able to change them.
      await waitForActionResponse(
        pending2Page,
        () =>
          rows
            .nth(2)
            .getByRole("button", { name: /View answers/ })
            .click(),
        { method: "GET", urlIncludes: `/dashboard/user/surveys/${closedAnswered.id}` },
      );
      const modal = pending2Page.locator("#user-event-survey-modal");
      await expect(modal).toBeVisible();
      await expect(modal.locator("[data-survey-closed-notice]")).toContainText(
        "This survey is closed, so your answers can no longer be changed.",
      );
      await expect(modal).toContainText("Loved the venue.");
      await expect(modal.locator("[data-user-event-survey-form]")).toHaveCount(0);
      await modal.getByRole("button", { name: "Close", exact: true }).click();
      await expect(modal).toBeHidden();

      // Answer the open survey and verify the list and the menu badge refresh.
      await waitForActionResponse(
        pending2Page,
        () =>
          rows
            .nth(0)
            .getByRole("button", { name: /Answer/ })
            .click(),
        { method: "GET", urlIncludes: `/dashboard/user/surveys/${toAnswer.id}` },
      );
      await modal.getByLabel("Any feedback?").fill("More breaks.");
      await waitForActionResponse(
        pending2Page,
        () => modal.getByRole("button", { name: "Submit answers" }).click(),
        { method: "PUT", status: 204, urlIncludes: `/dashboard/user/surveys/${toAnswer.id}/response` },
      );
      await expect(pending2Page.locator(".swal2-popup")).toContainText("Survey answers saved.");
      await expect(pending2Page.locator(`[data-user-event-survey="${toAnswer.id}"]`)).toContainText(
        "Answered",
      );
      await expect(surveysMenuItem).toHaveText(/^\s*Surveys\s*$/);

      // Move between result pages one survey at a time.
      await navigateToPath(pending2Page, "/dashboard/user?tab=surveys&limit=1&offset=0");
      await expectCurrentPaginationNavigation(
        pending2Page,
        "#dashboard-content tbody tr[data-user-event-survey]",
      );
    } finally {
      cleanupEventsByIds([event.id]);
    }
  });

  test("the surveys tab opens a survey in the modal", async ({ member1Page }) => {
    // Load the Surveys tab and open the seeded survey from its row.
    await navigateToPath(member1Page, "/dashboard/user?tab=surveys");
    const row = member1Page.locator(
      `[data-user-event-survey="${TEST_EVENT_SURVEYS.surveys.openIdentified.id}"]`,
    );
    await waitForActionResponse(member1Page, () => row.getByRole("button", { name: /Answer/ }).click(), {
      method: "GET",
      urlIncludes: `/dashboard/user/surveys/${TEST_EVENT_SURVEYS.surveys.openIdentified.id}`,
    });

    // Verify the modal shows the survey without leaving the dashboard.
    const modal = member1Page.locator("#user-event-survey-modal");
    await expect(modal).toBeVisible();
    await expect(
      modal.getByRole("heading", { name: TEST_EVENT_SURVEYS.surveys.openIdentified.title }),
    ).toBeVisible();
    await expect(member1Page).toHaveURL(/\/dashboard\/user\?tab=surveys$/);

    // Close the modal with Escape.
    await member1Page.keyboard.press("Escape");
    await expect(modal).toBeHidden();
  });

  test("users without surveys see the empty state", async ({ emptyUserPage }) => {
    // Load the Surveys tab for the user without event participation.
    await navigateToPath(emptyUserPage, "/dashboard/user?tab=surveys");

    // Verify the empty state and the menu item without a badge.
    await expect(emptyUserPage.locator("#dashboard-content")).toContainText("No surveys yet");
    await expect(emptyUserPage.locator('#dashboard-menu a[href="/dashboard/user?tab=surveys"]')).toHaveText(
      /^\s*Surveys\s*$/,
    );
  });
});

/** Returns a short unique suffix for owned survey titles. */
const id8 = () => randomUUID().slice(0, 8);

/**
 * Creates an open survey with a required single-select and an optional free-text question.
 * @returns {{ id: string, optionIds: { no: string, yes: string }, questionIds: { comments: string, again: string } }}
 */
const setupOpenSurvey = () => {
  const questionIds = { again: randomUUID(), comments: randomUUID() };
  const optionIds = { no: randomUUID(), yes: randomUUID() };
  const { id } = setupOwnedEventSurvey({
    eventId: TEST_EVENT_SURVEYS.event.id,
    questions: [
      {
        id: questionIds.again,
        kind: "single-select",
        options: [
          { id: optionIds.yes, label: "Yes" },
          { id: optionIds.no, label: "No" },
        ],
        prompt: "Would you attend again?",
        required: true,
      },
      { id: questionIds.comments, kind: "free-text", options: [], prompt: "Any comments?", required: false },
    ],
    status: "ready",
    title: `E2E open survey ${id8()}`,
  });

  return { id, optionIds, questionIds };
};

/**
 * Builds the Surveys tab path the survey opening email links to.
 * @param {string} surveyId - Survey identifier.
 * @returns {string} Dashboard path that opens the survey.
 */
const surveyLinkPath = (surveyId) => `/dashboard/user?tab=surveys&event_survey_id=${surveyId}`;
