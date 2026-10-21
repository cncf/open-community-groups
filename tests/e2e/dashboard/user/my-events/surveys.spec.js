import { randomUUID } from "node:crypto";

import { expect, test } from "../../../fixtures.js";
import {
  bumpOwnedSurveyRevision,
  cleanupEventSurveys,
  readSurveyResponseAnswers,
  setupOwnedEventSurvey,
  TEST_EVENT_SURVEYS,
} from "../../../data-graphs/surveys.js";
import { TEST_USER_CREDENTIALS, TEST_USER_IDS } from "../../../seed.js";
import { navigateToPath, waitForActionResponse } from "../../../utils.js";

// Message shown when the survey an email links to can't be answered.
const UNAVAILABLE_SURVEY_WARNING = "This survey is closed or isn't available to you.";

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
          urlIncludes: `/dashboard/user/events/surveys/${survey.id}/response`,
        },
      );
      await expect(member1Page.locator(".swal2-popup")).toContainText("Survey answers saved.");
      await expect(modal).toBeHidden();
      await expect(member1Page).toHaveURL(
        (url) =>
          url.pathname === "/dashboard/user" &&
          url.searchParams.get("tab") === "events" &&
          !url.searchParams.has("event_survey_id"),
      );
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
        { method: "PUT", status: 204, urlIncludes: `/dashboard/user/events/surveys/${survey.id}/response` },
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
          urlIncludes: `/dashboard/user/events/surveys/${survey.id}/response`,
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

  test("the surveys panel opens a survey in the modal", async ({ member1Page }) => {
    // Load My Events and open the seeded survey from its panel row.
    await navigateToPath(member1Page, "/dashboard/user?tab=events");
    const row = member1Page.locator(
      `[data-user-event-survey="${TEST_EVENT_SURVEYS.surveys.openIdentified.id}"]`,
    );
    await waitForActionResponse(member1Page, () => row.getByRole("button", { name: /Answer/ }).click(), {
      method: "GET",
      urlIncludes: `/dashboard/user/events/surveys/${TEST_EVENT_SURVEYS.surveys.openIdentified.id}`,
    });

    // Verify the modal shows the survey without leaving the dashboard.
    const modal = member1Page.locator("#user-event-survey-modal");
    await expect(modal).toBeVisible();
    await expect(
      modal.getByRole("heading", { name: TEST_EVENT_SURVEYS.surveys.openIdentified.title }),
    ).toBeVisible();
    await expect(member1Page).toHaveURL(/\/dashboard\/user\?tab=events$/);

    // Close the modal with Escape.
    await member1Page.keyboard.press("Escape");
    await expect(modal).toBeHidden();
  });

  test("email links to surveys that can't be answered show a warning", async ({
    member1Page,
    member2Page,
  }) => {
    // Verify closed, scheduled and draft surveys do not open.
    for (const surveyId of [
      TEST_EVENT_SURVEYS.surveys.closed.id,
      TEST_EVENT_SURVEYS.surveys.draft.id,
      TEST_EVENT_SURVEYS.surveys.scheduled.id,
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

    // Log in and verify the survey opens in My Events.
    await page.getByLabel("Username").fill(TEST_USER_CREDENTIALS.member1.username);
    await page
      .getByRole("textbox", { name: "Password required" })
      .fill(TEST_USER_CREDENTIALS.member1.password);
    await Promise.all([
      page.waitForURL(
        (url) => url.pathname === "/dashboard/user" && url.searchParams.get("event_survey_id") === surveyId,
      ),
      page.getByRole("button", { name: "Sign In" }).click(),
    ]);
    await expect(page.locator("#user-event-survey-modal")).toBeVisible();
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
 * Builds the My Events path the survey opening email links to.
 * @param {string} surveyId - Survey identifier.
 * @returns {string} Dashboard path that opens the survey.
 */
const surveyLinkPath = (surveyId) => `/dashboard/user?tab=events&event_survey_id=${surveyId}`;
