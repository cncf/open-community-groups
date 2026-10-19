import { expect, test } from "../../../fixtures.js";
import { queryE2eDatabase } from "../../../database.js";
import {
  TEST_EVENT_SURVEYS,
  cleanupEventSurveys,
  cleanupEventSurveysByTitle,
  setupOwnedEventSurvey,
  setupOwnedSurveyResponse,
} from "../../../data-graphs/surveys.js";
import { uniqueName, waitForActionResponse } from "../../../utils.js";
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

    // Verify each row offers the status action of its state.
    await expect(content.getByRole("button", { name: `Mark ready: ${surveys.draft.title}` })).toBeVisible();
    await expect(
      content.getByRole("button", { name: `Back to draft: ${surveys.scheduled.title}` }),
    ).toBeVisible();
    await expect(
      content.getByRole("button", { name: `Close: ${surveys.openIdentified.title}` }),
    ).toBeVisible();
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
      await expect(row).toContainText("May 20, 2099 6:30 PM CEST");

      // Mark the survey ready, confirming it opens now for the ended event.
      const statusRequest = page.waitForRequest(
        (request) => request.method() === "PUT" && request.url().endsWith("/status"),
      );
      await row.getByRole("button", { name: `Mark ready: ${title}` }).click();
      await confirmAlert(page, "Mark this survey ready? Test events do not email attendees.", "Mark ready");
      await dismissAlert(page, "You have successfully marked the survey ready.");
      const statusParams = new URLSearchParams((await statusRequest).postData() || "");
      expect(statusParams.get("action")).toBe("mark-ready");
      expect(statusParams.get("revision")).toBe("2");
      expect(statusParams.get("expected_effective_opens_at")).toMatch(/^\d+$/);
      await expect(row.locator(".custom-badge")).toHaveText("Open");

      // Close and reopen the survey.
      await row.getByRole("button", { name: `Close: ${title}` }).click();
      await confirmAlert(page, "Close this survey?", "Close");
      await dismissAlert(page, "You have successfully closed the survey.");
      await expect(row.locator(".custom-badge")).toHaveText("Closed");
      await row.getByRole("button", { name: `Reopen: ${title}` }).click();
      await confirmAlert(page, "Reopen this survey?", "Reopen");
      await dismissAlert(page, "You have successfully reopened the survey.");
      await expect(row.locator(".custom-badge")).toHaveText("Open");

      // Delete the survey behind its confirmation.
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

    // Verify the breakdown and free-text answers.
    await expect(content.getByText("Responses: 2 / 4 (50%)")).toBeVisible();
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

      // Open the edit form of the locked survey.
      const content = await openSurveysTab(page);
      await waitForActionResponse(
        page,
        () => content.getByRole("button", { name: `Edit survey: ${owned.title}` }).click(),
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

    // Keep editing when the Back link would discard the edits.
    await content.getByRole("button", { name: "Back to surveys" }).click();
    await confirmAlert(page, "You have unsaved survey changes.", "Keep editing");
    await expect(titleInput).toHaveValue(title);

    // Switch sections and verify the edits survive.
    await page.locator('button[data-section="analytics"]').click();
    await expect(titleInput).toBeHidden();
    await page.locator('button[data-section="surveys"]').click();
    await expect(titleInput).toHaveValue(title);

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
  });

  test("group viewer reviews survey results with mutation controls disabled", async ({ groupViewerPage }) => {
    const page = groupViewerPage;

    // Open the surveys tab as a read-only role.
    const content = await openSurveysTab(page);

    // Verify mutation controls are disabled while results and downloads stay available.
    await expect(content.getByText("Your role cannot manage surveys.")).toBeVisible();
    await expect(content.getByRole("button", { name: "Add survey" })).toBeDisabled();
    const row = getSurveyRow(content, surveys.openIdentified.title);
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
    await expect(form.getByLabel("Title")).toBeDisabled();
    await expect(form.getByRole("button", { name: "Save survey" })).toBeDisabled();

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
    await expect(content.getByText("Responses: 2 / 4 (50%)")).toBeVisible();
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
