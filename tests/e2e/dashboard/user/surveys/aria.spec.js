import { randomUUID } from "node:crypto";

import { expect, test } from "../../../fixtures.js";

import { cleanupEventsByIds } from "../../../data-graphs/events.js";
import {
  setupOwnedEventSurvey,
  setupOwnedSurveyEvent,
  setupOwnedSurveyResponse,
} from "../../../data-graphs/surveys.js";
import { TEST_USER_IDS } from "../../../seed.js";
import { enableDesktopVersion, expectAriaSnapshot, expectPageLayout } from "../../../snapshots.js";
import { openUserDashboardView } from "../aria-helpers.js";

// Titles of the owned surveys of the user without data; the owned event name is matched with a regex.
const ANSWERED_SURVEY_TITLE = "E2E ARIA answered survey";
const OPEN_SURVEY_TITLE = "E2E ARIA open survey";

// The surveys are owned: seeded ones open relative to the seed day and other tests answer them.
test.describe("user dashboard surveys ARIA snapshots", () => {
  test("matches the desktop views", async ({ emptyUserPage, owned }) => {
    await expectSurveysViews({ emptyUserPage, owned });
  });

  test("matches the views in the mobile desktop version @mobile", async ({ emptyUserPage, owned }) => {
    await enableDesktopVersion(emptyUserPage);
    await expectSurveysViews({ emptyUserPage, owned });
  });
});

/** Checks the layout of the surveys tab views and captures them. */
const expectSurveysViews = async ({ emptyUserPage, owned }) => {
  await test.step("empty state", async () => {
    // Load the surveys of a user without surveys and check the layout.
    const content = await openUserDashboardView(emptyUserPage, "tab=surveys");

    // Capture the title, the column headers and the empty state.
    await expectAriaSnapshot(emptyUserPage, content, "surveys-empty");
  });

  await test.step("unavailable survey", async () => {
    // Follow a survey link the user cannot open and check the layout.
    const content = await openUserDashboardView(emptyUserPage, `tab=surveys&event_survey_id=${randomUUID()}`);

    // Capture the warning above the list.
    await expectAriaSnapshot(emptyUserPage, content, "surveys-unavailable");
  });

  // Give the user an identified survey to answer and an anonymous one already answered.
  const surveys = setupSurveys(owned);
  const dialog = emptyUserPage.getByRole("dialog");

  await test.step("survey list", async () => {
    // Load both surveys and check the layout.
    const table = emptyUserPage.locator("#dashboard-content").getByRole("table");
    await openUserDashboardView(emptyUserPage, "tab=surveys", { regions: [table] });

    // Capture the open survey first, then the answered one, with their actions.
    await expectAriaSnapshot(emptyUserPage, table, "surveys-list");
  });

  await test.step("answer dialog", async () => {
    // Follow the link to the open survey and check the layout.
    await openUserDashboardView(emptyUserPage, `tab=surveys&event_survey_id=${surveys.openId}`);
    await expect(dialog.getByRole("heading", { name: OPEN_SURVEY_TITLE })).toBeVisible();
    await expectPageLayout(emptyUserPage, { regions: [dialog] });

    // Capture the identified survey form.
    await expectAriaSnapshot(emptyUserPage, dialog, "surveys-answer-dialog");
  });

  await test.step("edit answers dialog", async () => {
    // Follow the link to the answered survey and check the layout.
    await openUserDashboardView(emptyUserPage, `tab=surveys&event_survey_id=${surveys.answeredId}`);
    await expect(dialog.getByRole("heading", { name: ANSWERED_SURVEY_TITLE })).toBeVisible();
    await expectPageLayout(emptyUserPage, { regions: [dialog] });

    // Capture the anonymous survey form with the saved answers; the answer date follows the run day.
    await expectAriaSnapshot(emptyUserPage, dialog, "surveys-edit-answers-dialog");
  });
};

/**
 * Creates an owned past event the user without data attended, with an open identified survey and
 * an answered anonymous one. The event cleanup removes the surveys and the response.
 */
const setupSurveys = (owned) => {
  const event = owned.track(setupOwnedSurveyEvent({ attendeeUserIds: [TEST_USER_IDS.empty] }), ({ id }) =>
    cleanupEventsByIds([id]),
  );
  const open = setupOwnedEventSurvey({
    anonymous: false,
    eventId: event.id,
    questions: [
      {
        id: randomUUID(),
        kind: "single-select",
        options: [
          { id: randomUUID(), label: "Excellent" },
          { id: randomUUID(), label: "Good" },
        ],
        prompt: "How would you rate the sessions?",
        required: true,
      },
      {
        id: randomUUID(),
        kind: "multi-select",
        options: [
          { id: randomUUID(), label: "Kubernetes" },
          { id: randomUUID(), label: "Security" },
        ],
        prompt: "Which topics should we cover next?",
        required: false,
      },
      {
        id: randomUUID(),
        kind: "free-text",
        options: [],
        prompt: "What should we improve?",
        required: false,
      },
    ],
    status: "ready",
    title: OPEN_SURVEY_TITLE,
  });
  const answered = setupOwnedEventSurvey({
    eventId: event.id,
    status: "ready",
    title: ANSWERED_SURVEY_TITLE,
  });
  setupOwnedSurveyResponse({
    answers: { answers: [{ question_id: answered.questionId, value: "Great venue, thanks!" }] },
    surveyId: answered.id,
    userId: TEST_USER_IDS.empty,
  });

  return { answeredId: answered.id, openId: open.id };
};
