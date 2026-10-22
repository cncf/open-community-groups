import { expect, test } from "../../../fixtures.js";
import { queryE2eDatabase } from "../../../database.js";
import {
  TEST_EVENT_SURVEYS,
  cleanupEventSurveys,
  cleanupEventSurveysByTitle,
  setupOwnedEventSurvey,
  setupOwnedSurveyResponse,
  setupOwnedSurveyTextAnswers,
} from "../../../data-graphs/surveys.js";
import { expectTableHeaders, uniqueName, waitForActionResponse } from "../../../utils.js";
import { openCurrentEventEditorSection, openEventUpdateFormByName } from "./helpers.js";

const { attendeeIds, event, surveys } = TEST_EVENT_SURVEYS;

test.describe("group dashboard event surveys tab", () => {
  test("organizer reviews the seeded surveys in every state", async ({ organizerGroupPage }) => {
    // Open the surveys tab of the seeded survey event.
    const content = await openSurveysTab(organizerGroupPage);

    // Verify each survey row shows its state and responses.
    const identifiedRow = getSurveyRow(content, surveys.openIdentified.title);
    await expect(identifiedRow.locator(".custom-badge")).toHaveText("Open");
    await expect(identifiedRow).toContainText("2 / 4 (50%)");
    await expect(identifiedRow).toContainText("Confirmed attendees · Identified");
    const anonymousRow = getSurveyRow(content, surveys.openAnonymous.title);
    await expect(anonymousRow.locator(".custom-badge")).toHaveText("Open");
    await expect(anonymousRow).toContainText("3 / 3 (100%)");
    await expect(anonymousRow).toContainText("Checked-in attendees · Anonymous");
    await expect(getSurveyRow(content, surveys.draft.title).locator(".custom-badge")).toHaveText("Draft");
    await expect(getSurveyRow(content, surveys.scheduled.title).locator(".custom-badge")).toHaveText(
      "Scheduled",
    );
    await expect(getSurveyRow(content, surveys.closed.title).locator(".custom-badge")).toHaveText("Closed");

    // Verify draft and scheduled states explain when they open in a tooltip.
    const scheduledRow = getSurveyRow(content, surveys.scheduled.title);
    await scheduledRow.getByRole("button", { name: "Scheduled" }).hover();
    await expect(scheduledRow.getByRole("tooltip")).toContainText("Opens");

    // Verify each row offers the status action of its state in its actions menu.
    await openSurveyActions(content, surveys.draft.title);
    await expect(content.getByRole("button", { name: `Mark ready: ${surveys.draft.title}` })).toBeVisible();
    await closeSurveyActions(content, surveys.draft.title);
    await openSurveyActions(content, surveys.scheduled.title);
    await expect(
      content.getByRole("button", { name: `Back to draft: ${surveys.scheduled.title}` }),
    ).toBeVisible();
    await closeSurveyActions(content, surveys.scheduled.title);
    await openSurveyActions(content, surveys.openIdentified.title);
    await expect(
      content.getByRole("button", { name: `Close: ${surveys.openIdentified.title}` }),
    ).toBeVisible();
    await closeSurveyActions(content, surveys.openIdentified.title);
    await openSurveyActions(content, surveys.closed.title);
    await expect(content.getByRole("button", { name: `Reopen: ${surveys.closed.title}` })).toBeEnabled();
  });

  test("organizer creates, schedules, closes, reopens and deletes a survey", async ({
    organizerGroupPage,
  }) => {
    test.setTimeout(120_000);

    const page = organizerGroupPage;
    const title = uniqueName("Survey");

    try {
      // Open the add form in place.
      const content = await openSurveysTab(page);
      await waitForActionResponse(page, () => content.getByRole("button", { name: "Add survey" }).click(), {
        method: "GET",
        urlIncludes: `/dashboard/group/events/${event.id}/surveys/add`,
      });
      const form = page.locator("#event-survey-form");
      await expect(form).toBeVisible();

      // Fill the survey and add a single-select question.
      await form.getByLabel("Title").fill(title);
      await form.getByLabel("Introduction").fill("Tell us about the event.");
      await addSurveyQuestion(page, {
        kind: "single-select",
        options: ["Yes", "No"],
        prompt: "Would you attend again?",
      });

      // Save the draft and check the submitted form fields.
      const addRequest = page.waitForRequest(
        (request) => request.method() === "POST" && request.url().endsWith(`/surveys/add`),
      );
      await waitForActionResponse(page, () => form.getByRole("button", { name: "Add survey" }).click(), {
        method: "POST",
        status: 204,
        urlIncludes: `/dashboard/group/events/${event.id}/surveys/add`,
      });
      const addParams = new URLSearchParams((await addRequest).postData() || "");
      expect(addParams.get("title")).toBe(title);
      expect(addParams.get("anonymous")).toBe("true");
      expect(addParams.get("audience")).toBe("confirmed");
      expect(addParams.get("questions[0][kind]")).toBe("single-select");
      expect(addParams.has("name")).toBe(false);
      await dismissAlert(page, "You have successfully added the survey.");

      // Verify the refreshed list shows the draft.
      const row = getSurveyRow(content, title);
      await expect(row.locator(".custom-badge")).toHaveText("Draft");

      // Add a closing date and check it is sent in the normalized format.
      await waitForActionResponse(
        page,
        () => row.getByRole("button", { name: `Edit survey: ${title}` }).click(),
        {
          method: "GET",
          urlIncludes: "/update",
        },
      );
      await form.getByLabel("Closes at").fill("2099-05-20T18:30");
      const updateRequest = page.waitForRequest(
        (request) => request.method() === "PUT" && request.url().endsWith("/update"),
      );
      await waitForActionResponse(page, () => form.getByRole("button", { name: "Save survey" }).click(), {
        method: "PUT",
        status: 204,
        urlIncludes: `/dashboard/group/events/${event.id}/surveys/`,
      });
      const updateParams = new URLSearchParams((await updateRequest).postData() || "");
      expect(updateParams.get("closes_at")).toBe("2099-05-20T18:30:00");
      expect(updateParams.get("revision")).toBe("1");
      await dismissAlert(page, "You have successfully updated the survey.");
      await expect(row).toContainText("May 20, 2099");
      await expect(row).toContainText("06:30 PM CEST");

      // Mark the survey ready, confirming it opens now for the ended event.
      const statusRequest = page.waitForRequest(
        (request) => request.method() === "PUT" && request.url().endsWith("/status"),
      );
      await openSurveyActions(content, title);
      await row.getByRole("button", { name: `Mark ready: ${title}` }).click();
      await confirmAlert(page, "Mark this survey ready? Test events do not email attendees.", "Mark ready");
      await dismissAlert(page, "You have successfully marked the survey ready.");
      const statusParams = new URLSearchParams((await statusRequest).postData() || "");
      expect(statusParams.get("action")).toBe("mark-ready");
      expect(statusParams.get("revision")).toBe("2");
      expect(statusParams.get("expected_effective_opens_at")).toMatch(/^\d+$/);
      await expect(row.locator(".custom-badge")).toHaveText("Open");

      // Close and reopen the survey.
      await openSurveyActions(content, title);
      await row.getByRole("button", { name: `Close: ${title}` }).click();
      await confirmAlert(page, "Close this survey?", "Close");
      await dismissAlert(page, "You have successfully closed the survey.");
      await expect(row.locator(".custom-badge")).toHaveText("Closed");
      await openSurveyActions(content, title);
      await row.getByRole("button", { name: `Reopen: ${title}` }).click();
      await confirmAlert(page, "Reopen this survey?", "Reopen");
      await dismissAlert(page, "You have successfully reopened the survey.");
      await expect(row.locator(".custom-badge")).toHaveText("Open");

      // Delete the survey behind its confirmation.
      await openSurveyActions(content, title);
      await row.getByRole("button", { name: `Delete survey: ${title}` }).click();
      await confirmAlert(page, "Delete this survey? This cannot be undone.", "Delete");
      await dismissAlert(page, "You have successfully deleted the survey.");
      await expect(row).toHaveCount(0);
    } finally {
      cleanupEventSurveysByTitle({ eventId: event.id, title });
    }
  });

  test("organizer reviews results, individual responses and the CSV of an identified survey", async ({
    organizerGroupPage,
  }) => {
    const page = organizerGroupPage;

    // Open the Summary view in place.
    const content = await openSurveysTab(page);
    await waitForActionResponse(
      page,
      () => content.getByRole("button", { name: `View results: ${surveys.openIdentified.title}` }).click(),
      { method: "GET", urlIncludes: `/surveys/${surveys.openIdentified.id}/results` },
    );

    // Verify the event form buttons give way to the results actions.
    const eventCancelButton = page.locator("#cancel-button");
    await expect(eventCancelButton).toBeHidden();

    // Verify the breakdown and free-text answers.
    await expect(content.locator("[data-survey-responses-label]")).toHaveText("2 / 4 (50%)");
    const rating = content.locator(
      `[data-event-survey-question="${surveys.openIdentified.questionIds.rating}"]`,
    );
    await expect(rating).toContainText("How would you rate the sessions?");
    await expect(rating).toContainText("Excellent");
    const improve = content.locator(
      `[data-event-survey-question="${surveys.openIdentified.questionIds.improve}"]`,
    );
    await expect(improve).toContainText("More time for questions after each talk.");
    await expect(improve).toContainText("A longer networking break.");

    // Switch to the Individual view and verify the respondents.
    await waitForActionResponse(page, () => content.getByRole("button", { name: "Individual" }).click(), {
      method: "GET",
      urlIncludes: `/surveys/${surveys.openIdentified.id}/responses`,
    });
    await expect(content.getByRole("button", { name: "Individual" })).toHaveAttribute("aria-pressed", "true");
    await expect(content.getByText("E2E Survey Attendee One")).toBeVisible();
    await expect(content.getByText("E2E Survey Attendee Two")).toBeVisible();
    await expect(eventCancelButton).toBeHidden();

    // Download the CSV and verify its identified columns.
    const [download] = await Promise.all([
      page.waitForEvent("download"),
      content.getByRole("link", { name: "Download CSV" }).click(),
    ]);
    expect(download.suggestedFilename()).toBe(`event-${event.slug}-survey-${surveys.openIdentified.id}.csv`);
    const csv = await readDownload(download);
    expect(csv.split("\n")[0]).toBe(
      "Name,Company,Title,Submitted,Updated,What should we improve?,How would you rate the sessions?,Which topics should we cover next?",
    );
    expect(csv).toContain("E2E Survey Attendee One,Survey Labs,Platform Engineer,");

    // Go back to the list.
    await waitForActionResponse(
      page,
      () => content.getByRole("button", { name: "Back to surveys" }).click(),
      {
        method: "GET",
        urlEndsWith: `/dashboard/group/events/${event.id}/surveys`,
      },
    );
    await expect(content.getByRole("table", { name: "Event surveys list" })).toBeVisible();
    await expect(eventCancelButton).toBeVisible();
  });

  test("organizer searches respondents and reviews their responses in a modal", async ({
    organizerGroupPage,
  }) => {
    const page = organizerGroupPage;

    // Open the Individual view of the identified survey.
    const content = await openSurveysTab(page);
    await waitForActionResponse(
      page,
      () => content.getByRole("button", { name: `View results: ${surveys.openIdentified.title}` }).click(),
      { method: "GET", urlIncludes: `/surveys/${surveys.openIdentified.id}/results` },
    );
    await waitForActionResponse(page, () => content.getByRole("button", { name: "Individual" }).click(), {
      method: "GET",
      urlIncludes: `/surveys/${surveys.openIdentified.id}/responses`,
    });

    // Verify the respondents table shows tickets, answered questions and edits.
    const table = content.getByRole("table", { name: "Survey respondents" });
    await expectTableHeaders(table, ["Respondent", "Ticket type", "Answered", "Submitted"]);
    const firstRow = table.locator("tbody tr", { hasText: "E2E Survey Attendee One" });
    const secondRow = table.locator("tbody tr", { hasText: "E2E Survey Attendee Two" });
    await expect(firstRow).toContainText("Platform Engineer · Survey Labs");
    await expect(firstRow).toContainText("General admission");
    await expect(firstRow).toContainText("3 of 3");
    await expect(firstRow).toContainText("Edited");
    await expect(secondRow).toContainText("3 of 3");
    await expect(secondRow).not.toContainText("Edited");
    await expect(content.locator("[data-event-survey-respondents-range]")).toContainText(
      "1 - 2 of 2 respondents",
    );

    // Search respondents by company.
    const search = content.getByLabel("Search respondents");
    await waitForActionResponse(
      page,
      async () => {
        await search.fill("survey labs");
        await search.press("Enter");
      },
      { method: "GET", urlIncludes: "ts_query=survey" },
    );
    await expect(table.locator("tbody tr")).toHaveCount(1);
    await expect(firstRow).toBeVisible();
    await expect(content.getByLabel("Search respondents")).toHaveValue("survey labs");

    // Clear the search.
    await waitForActionResponse(
      page,
      () => content.getByRole("button", { name: "Clear respondent search" }).click(),
      { method: "GET", urlEndsWith: `/surveys/${surveys.openIdentified.id}/responses` },
    );
    await expect(table.locator("tbody tr")).toHaveCount(2);

    // Open the first respondent from the keyboard.
    await firstRow.focus();
    await waitForActionResponse(page, () => firstRow.press("Enter"), {
      method: "GET",
      urlIncludes: `/responses/${attendeeIds.checkedIn1}`,
    });
    const firstDialog = page.getByRole("dialog", { name: "E2E Survey Attendee One" });
    await expect(firstDialog).toBeVisible();
    await expect(firstDialog).toContainText("General admission");
    await expect(firstDialog).toContainText("Answered 3 of 3 questions");
    await expect(firstDialog).toContainText("More time for questions after each talk.");
    await expect(firstDialog).toContainText("Excellent");
    await expect(firstDialog).toContainText("Respondent 1 of 2");
    await expect(firstDialog.getByRole("button", { name: "Prev", exact: true })).toBeDisabled();

    // Move to the next respondent.
    await waitForActionResponse(page, () => firstDialog.getByRole("button", { name: "Next" }).click(), {
      method: "GET",
      urlIncludes: `/responses/${attendeeIds.checkedIn2}`,
    });
    const secondDialog = page.getByRole("dialog", { name: "E2E Survey Attendee Two" });
    await expect(secondDialog).toContainText("A longer networking break.");
    await expect(secondDialog).toContainText("Respondent 2 of 2");
    await expect(secondDialog.getByRole("button", { name: "Next" })).toBeDisabled();
    await expect(secondDialog.getByRole("button", { name: "Close", exact: true })).toBeFocused();

    // Close the modal on Escape and verify focus returns to the row that opened it.
    await page.keyboard.press("Escape");
    await expect(secondDialog).toBeHidden();
    await expect(firstRow).toBeFocused();
    await expect(page.locator("body")).not.toHaveCSS("overflow", "hidden");

    // Open the second respondent with a click and close it from the footer.
    await waitForActionResponse(page, () => secondRow.click(), {
      method: "GET",
      urlIncludes: `/responses/${attendeeIds.checkedIn2}`,
    });
    await expect(secondDialog).toBeVisible();
    await expect(secondDialog.getByRole("button", { name: "Prev", exact: true })).toBeEnabled();
    await secondDialog.getByRole("button", { name: "Close", exact: true }).click();
    await expect(secondDialog).toBeHidden();
  });

  test("organizer only sees aggregated results of an anonymous survey", async ({ organizerGroupPage }) => {
    const page = organizerGroupPage;

    // Open the Summary view of the anonymous survey.
    const content = await openSurveysTab(page);
    await waitForActionResponse(
      page,
      () => content.getByRole("button", { name: `View results: ${surveys.openAnonymous.title}` }).click(),
      { method: "GET", urlIncludes: `/surveys/${surveys.openAnonymous.id}/results` },
    );

    // Verify identities stay hidden and the few responses notice is shown.
    await expect(content.getByRole("button", { name: "Individual" })).toBeDisabled();
    await expect(content.locator("[data-event-survey-few-responses-notice]")).toBeVisible();
    await expect(content.getByText("Great venue, thanks!")).toBeVisible();
    await expect(content.getByText("E2E Survey Attendee One")).toHaveCount(0);
  });

  test("organizer searches and pages every free-text answer of an anonymous survey in a modal", async ({
    organizerGroupPage,
  }) => {
    const page = organizerGroupPage;
    const owned = setupOwnedEventSurvey({ eventId: event.id, status: "ready" });
    const answers = Array.from({ length: 12 }, (_, index) => {
      const number = String(index + 1).padStart(2, "0");
      return index % 4 === 2 ? `Owned answer ${number} about coffee` : `Owned answer ${number}`;
    });

    try {
      // Answer the free-text question of the anonymous survey twelve times.
      setupOwnedSurveyTextAnswers({ answers, questionId: owned.questionId, surveyId: owned.id });

      // Open the Summary view of the survey.
      const content = await openSurveysTab(page);
      await waitForActionResponse(
        page,
        () => content.getByRole("button", { name: `View results: ${owned.title}` }).click(),
        { method: "GET", urlIncludes: `/surveys/${owned.id}/results` },
      );

      // Verify the compact preview shows the first 10 answers only.
      const question = content.locator(`[data-event-survey-question="${owned.questionId}"]`);
      const preview = question.locator("[data-event-survey-text-answers-preview] li");
      await expect(preview).toHaveCount(10);
      await expect(preview.first()).toHaveText("Owned answer 01");
      await expect(question).not.toContainText("Owned answer 11");
      await expect(question).toContainText("Showing 10 of 12 answers");

      // Open every answer in the modal.
      const viewAll = question.getByRole("button", { name: "View all 12 answers" });
      await waitForActionResponse(page, () => viewAll.click(), {
        method: "GET",
        urlIncludes: `/results/questions/${owned.questionId}/answers`,
      });
      const dialog = page.getByRole("dialog", { name: "Any feedback?" });
      const range = dialog.locator("[data-event-survey-text-answers-range]");
      const search = dialog.getByLabel("Search answers");
      await expect(dialog).toBeVisible();
      await expect(search).toBeFocused();
      await expect(range).toHaveText("1 - 10 of 12 answers");
      await expect(dialog.getByRole("button", { name: "Prev", exact: true })).toBeDisabled();

      // Move to the second page.
      await waitForActionResponse(page, () => dialog.getByRole("button", { name: "Next" }).click(), {
        method: "GET",
        urlIncludes: "offset=10",
      });
      await expect(range).toHaveText("11 - 12 of 12 answers");
      await expect(dialog.getByRole("list", { name: "Answers" }).getByRole("listitem")).toHaveText([
        "Owned answer 11 about coffee",
        "Owned answer 12",
      ]);
      await expect(dialog.getByRole("button", { name: "Next" })).toBeDisabled();
      await expect(dialog.getByRole("button", { name: "Close", exact: true })).toBeFocused();

      // Search the answers from the first page.
      await waitForActionResponse(
        page,
        async () => {
          await search.fill("COFFEE");
          await search.press("Enter");
        },
        { method: "GET", urlIncludes: "ts_query=COFFEE" },
      );
      await expect(range).toHaveText("1 - 3 of 3 answers");
      await expect(dialog.getByRole("list", { name: "Answers" }).getByRole("listitem")).toHaveText([
        "Owned answer 03 about coffee",
        "Owned answer 07 about coffee",
        "Owned answer 11 about coffee",
      ]);
      await expect(search).toHaveValue("COFFEE");
      await expect(search).toBeFocused();

      // Clear the search and verify focus stays in the modal on its search box.
      await waitForActionResponse(
        page,
        () => dialog.getByRole("button", { name: "Clear answer search" }).click(),
        { method: "GET", urlIncludes: `/results/questions/${owned.questionId}/answers` },
      );
      await expect(range).toHaveText("1 - 10 of 12 answers");
      await expect(search).toHaveValue("");
      await expect(search).toBeFocused();

      // Close the modal on Escape and verify focus returns to its opener.
      await page.keyboard.press("Escape");
      await expect(dialog).toBeHidden();
      await expect(viewAll).toBeFocused();
      await expect(page.locator("body")).not.toHaveCSS("overflow", "hidden");
    } finally {
      cleanupEventSurveys([owned.id]);
    }
  });

  test("organizer edits a locked survey without changing its locked fields", async ({
    organizerGroupPage,
  }) => {
    const page = organizerGroupPage;
    const owned = setupOwnedEventSurvey({ anonymous: false, eventId: event.id, status: "ready" });
    const editedTitle = `${owned.title} edited`;

    try {
      // Lock the survey with a response.
      setupOwnedSurveyResponse({
        answers: { answers: [{ question_id: owned.questionId, value: "Nice event" }] },
        surveyId: owned.id,
        userId: attendeeIds.checkedIn1,
      });

      // Open the edit form of the locked survey from its title.
      const content = await openSurveysTab(page);
      await waitForActionResponse(
        page,
        () => content.getByRole("button", { name: `Open survey: ${owned.title}` }).click(),
        { method: "GET", urlIncludes: `/surveys/${owned.id}/update` },
      );
      const form = page.locator("#event-survey-form");

      // Verify the locked fields are read-only under the banner.
      await expect(content.locator("[data-event-survey-locked-notice]")).toBeVisible();
      await expect(form.locator("#event-survey-anonymous-toggle")).toBeDisabled();
      await expect(form.getByLabel("Checked-in attendees only")).toBeDisabled();
      await expect(
        form.locator("#event-survey-questions").getByRole("button", { name: "Add question" }),
      ).toBeDisabled();

      // Save a new title with the locked fields unchanged.
      await form.getByLabel("Title").fill(editedTitle);
      await waitForActionResponse(page, () => form.getByRole("button", { name: "Save survey" }).click(), {
        method: "PUT",
        status: 204,
        urlIncludes: `/surveys/${owned.id}/update`,
      });
      await dismissAlert(page, "You have successfully updated the survey.");

      // Verify the list shows the new title and the questions are unchanged.
      await expect(getSurveyRow(content, editedTitle)).toBeVisible();
      expect(
        queryE2eDatabase(`
          select jsonb_array_length(questions)
          from event_survey
          where event_survey_id = '${owned.id}'::uuid;
        `),
      ).toBe("1");
    } finally {
      cleanupEventSurveys([owned.id]);
    }
  });

  test("organizer is asked before unsaved survey edits are discarded", async ({ organizerGroupPage }) => {
    const page = organizerGroupPage;
    const title = uniqueName("Unsaved survey");

    // Open the add form and type a title.
    const content = await openSurveysTab(page);
    await waitForActionResponse(page, () => content.getByRole("button", { name: "Add survey" }).click(), {
      method: "GET",
      urlIncludes: `/dashboard/group/events/${event.id}/surveys/add`,
    });
    const titleInput = page.locator("#event-survey-title");
    await titleInput.fill(title);

    // Verify the event form buttons give way to the survey form actions.
    const eventCancelButton = page.locator("#cancel-button");
    await expect(eventCancelButton).toBeHidden();

    // Keep editing when the Back link would discard the edits.
    await content.getByRole("button", { name: "Back to surveys" }).click();
    await confirmAlert(page, "You have unsaved survey changes.", "Keep editing");
    await expect(titleInput).toHaveValue(title);

    // Switch sections and verify the edits survive.
    await page.locator('button[data-section="analytics"]').click();
    await expect(titleInput).toBeHidden();
    await expect(eventCancelButton).toBeVisible();
    await page.locator('button[data-section="surveys"]').click();
    await expect(titleInput).toHaveValue(title);
    await expect(eventCancelButton).toBeHidden();

    // Discard the edits through the Back link.
    await waitForActionResponse(
      page,
      async () => {
        await content.getByRole("button", { name: "Back to surveys" }).click();
        await confirmAlert(page, "You have unsaved survey changes.", "Discard changes");
      },
      { method: "GET", urlEndsWith: `/dashboard/group/events/${event.id}/surveys` },
    );
    await expect(content.getByRole("table", { name: "Event surveys list" })).toBeVisible();
    await expect(getSurveyRow(content, title)).toHaveCount(0);
    await expect(eventCancelButton).toBeVisible();
  });

  test("group viewer reviews survey results with mutation controls disabled", async ({ groupViewerPage }) => {
    const page = groupViewerPage;

    // Open the surveys tab as a read-only role.
    const content = await openSurveysTab(page);

    // Verify mutation controls are disabled while results and downloads stay available.
    await expect(content.getByText("Your role cannot manage surveys.")).toBeVisible();
    await expect(content.getByRole("button", { name: "Add survey" })).toBeDisabled();
    const row = getSurveyRow(content, surveys.openIdentified.title);
    await openSurveyActions(content, surveys.openIdentified.title);
    await expect(
      row.getByRole("button", { name: `Delete survey: ${surveys.openIdentified.title}` }),
    ).toBeDisabled();
    await expect(
      content.getByRole("link", { name: `Download responses CSV: ${surveys.openIdentified.title}` }),
    ).toBeVisible();

    // Open the read-only form of the identified survey.
    await waitForActionResponse(
      page,
      () => row.getByRole("button", { name: `Edit survey: ${surveys.openIdentified.title}` }).click(),
      { method: "GET", urlIncludes: `/surveys/${surveys.openIdentified.id}/update` },
    );
    const form = page.locator("#event-survey-form");
    await expect(content.getByText("Your role cannot update surveys.")).toBeVisible();
    await expect(content.locator("[data-event-survey-locked-notice]")).toHaveCount(0);
    await expect(form.getByLabel("Title")).toBeDisabled();
    const saveButton = form.getByRole("button", { name: "Save survey" });
    await expect(saveButton).toBeDisabled();
    await expect(saveButton).toHaveAttribute("title", "Your role cannot update surveys.");

    // Go back and open the results of the identified survey.
    await waitForActionResponse(
      page,
      () => content.getByRole("button", { name: "Back to surveys" }).click(),
      {
        method: "GET",
        urlEndsWith: `/dashboard/group/events/${event.id}/surveys`,
      },
    );
    await waitForActionResponse(
      page,
      () => content.getByRole("button", { name: `View results: ${surveys.openIdentified.title}` }).click(),
      { method: "GET", urlIncludes: `/surveys/${surveys.openIdentified.id}/results` },
    );
    await expect(content.locator("[data-survey-responses-label]")).toHaveText("2 / 4 (50%)");
  });
});

/** Adds a question through the survey questions editor modal. */
const addSurveyQuestion = async (page, question) => {
  const editor = page.locator("#event-survey-questions");

  await editor.getByRole("button", { name: "Add question" }).click();
  const dialog = page.getByRole("dialog", { name: "Add question" });
  await expect(dialog).toBeVisible();
  await dialog.getByLabel("Question", { exact: true }).fill(question.prompt);
  await dialog.getByLabel("Type", { exact: true }).selectOption(question.kind);
  for (let index = 0; index < question.options.length; index += 1) {
    if (index > 0) {
      await dialog.getByRole("button", { name: "Add option" }).click();
    }
    await dialog.getByLabel(`Option ${index + 1}`).fill(question.options[index]);
  }
  await dialog.getByRole("button", { name: "Add question" }).click();
  await expect(dialog).toHaveCount(0);
  await expect(editor.getByText(question.prompt, { exact: true })).toBeVisible();
};

/** Closes the open actions menu of a survey row. */
const closeSurveyActions = async (content, title) => {
  const trigger = getSurveyRow(content, title).getByLabel(`Open survey actions for ${title}`);
  await content.page().keyboard.press("Escape");
  await expect(trigger.locator("..")).not.toHaveAttribute("open", "");
};

/** Confirms or declines the open confirmation dialog after checking its message. */
const confirmAlert = async (page, message, buttonName) => {
  const popup = page.locator(".swal2-popup");
  await expect(popup).toContainText(message);
  await popup.getByRole("button", { name: buttonName }).click();
};

/** Verifies and dismisses a success alert. */
const dismissAlert = async (page, message) => {
  const popup = page.locator(".swal2-popup");
  await expect(popup).toContainText(message);
  await page.locator(".swal2-confirm").click();
  await expect(popup).toBeHidden();
};

/** Returns the row of a survey in the surveys list. */
const getSurveyRow = (content, title) =>
  content.getByRole("table", { name: "Event surveys list" }).locator("tr", { hasText: title });

/** Opens the actions menu of a survey row. */
const openSurveyActions = async (content, title) => {
  const trigger = getSurveyRow(content, title).getByLabel(`Open survey actions for ${title}`);
  await trigger.click();
  await expect(trigger.locator("..")).toHaveAttribute("open", "");
};

/** Opens the surveys tab of the seeded survey event. */
const openSurveysTab = async (page) => {
  await openEventUpdateFormByName(page, event.name, event.id, { eventsTab: "past" });
  return openCurrentEventEditorSection(page, event.id, "surveys", "#surveys-content", {
    tableName: "Event surveys list",
  });
};

/** Reads a downloaded file as UTF-8 text. */
const readDownload = async (download) => {
  const stream = await download.createReadStream();
  const chunks = [];
  for await (const chunk of stream) {
    chunks.push(chunk);
  }
  return Buffer.concat(chunks).toString("utf8");
};
