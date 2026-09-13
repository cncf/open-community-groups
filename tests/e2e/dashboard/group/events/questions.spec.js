import { expect, test } from "../../../fixtures.js";
import { cleanupEventsByIds } from "../../../data-graphs/events.js";
import { getAttendButton, getLeaveButton, waitForAttendanceState } from "../../../site/event/helpers.js";
import {
  futureDate,
  navigateToPath,
  selectTimezone,
  uniqueName,
  waitForActionResponse,
} from "../../../utils.js";
import { fillMarkdownEditor } from "../../form-helpers.js";
import { waitForEventEditorAfterSave } from "./helpers.js";

test.describe("group dashboard event registration questions", () => {
  test("organizer can configure questions that members must answer before RSVP", async ({
    member1Page,
    organizerGroupPage,
  }) => {
    test.setTimeout(120_000);

    const eventName = uniqueName("Registration Questions");
    let eventId = "";
    let publicEventPath = "";

    try {
      // Create a draft event and open the registration questions editor.
      await fillEventDetails(organizerGroupPage, eventName);
      await organizerGroupPage.locator('button[data-section="questions"]').click();
      const editor = organizerGroupPage.locator("questions-editor");

      // Verify empty question and empty option labels are rejected by the editor modal.
      await editor.getByRole("button", { name: "Add question" }).click();
      const validationDialog = organizerGroupPage.getByRole("dialog", { name: "Add question" });
      await validationDialog.getByRole("button", { name: "Add question" }).click();
      await expect(validationDialog.locator("#question-prompt-draft")).toBeFocused();
      await expect(validationDialog.locator("#question-prompt-draft")).toHaveJSProperty(
        "validationMessage",
        "Please fill out this field.",
      );
      await validationDialog.locator("#question-prompt-draft").fill("Preferred learning format");
      await validationDialog.locator("#question-kind-draft").selectOption("single-select");
      await validationDialog.getByRole("button", { name: "Add question" }).click();
      await expect(validationDialog.getByLabel("Option 1")).toBeFocused();
      await expect(validationDialog.getByLabel("Option 1")).toHaveJSProperty(
        "validationMessage",
        "Please fill out this field.",
      );
      await validationDialog.getByLabel("Option 1").fill("Hands-on lab");
      await validationDialog.getByRole("button", { name: "Add option" }).click();
      await validationDialog.getByLabel("Option 2").fill("Lightning talks");
      await validationDialog.getByRole("button", { name: "Add question" }).click();
      await expect(validationDialog).toHaveCount(0);

      // Add required and optional question types, then reorder and remove one draft question.
      await addQuestion(organizerGroupPage, {
        kind: "free-text",
        prompt: "Accessibility needs",
        required: true,
      });
      await addQuestion(organizerGroupPage, {
        kind: "multi-select",
        options: ["Operations", "Security"],
        prompt: "Which topics are you interested in?",
        required: true,
      });
      await addQuestion(organizerGroupPage, {
        kind: "free-text",
        prompt: "Temporary setup note",
        required: false,
      });

      // Reorder the seeded topics question above the temporary questions.
      await getQuestionCard(organizerGroupPage, editor, "Which topics are you interested in?")
        .getByRole("button", { name: "Reorder question" })
        .focus();
      await organizerGroupPage.keyboard.press("ArrowUp");
      await getQuestionCard(organizerGroupPage, editor, "Which topics are you interested in?")
        .getByRole("button", { name: "Reorder question" })
        .focus();
      await organizerGroupPage.keyboard.press("ArrowUp");
      await assertQuestionOrder(organizerGroupPage, [
        "Which topics are you interested in?",
        "Preferred learning format",
        "Accessibility needs",
        "Temporary setup note",
      ]);
      const temporaryCard = editor.locator(".rounded-md.border.border-stone-200.bg-white", {
        hasText: "Temporary setup note",
      });
      await temporaryCard.getByRole("button", { name: "Delete question" }).click();
      await assertQuestionOrder(organizerGroupPage, [
        "Which topics are you interested in?",
        "Preferred learning format",
        "Accessibility needs",
      ]);

      // Save and publish the event with the configured questionnaire.
      const visibleAddEventButton = organizerGroupPage.locator(
        "#pending-changes-alert:not(.hidden) #add-event-button",
      );
      await expect(visibleAddEventButton).toBeVisible();
      await waitForActionResponse(organizerGroupPage, () => visibleAddEventButton.click(), {
        method: "POST",
        status: 201,
        urlIncludes: "/dashboard/group/events/add",
      });
      eventId = await waitForEventEditorAfterSave(organizerGroupPage);
      publicEventPath =
        (await organizerGroupPage.locator("#event-update-page").getAttribute("data-event-public-url")) || "";
      await publishCurrentEvent(organizerGroupPage, eventId);

      // Open the public event as a member and verify the question form renders persisted fields.
      await navigateToPath(member1Page, publicEventPath);
      await expect(member1Page.getByRole("heading", { level: 1, name: eventName })).toBeVisible();
      await waitForAttendanceState(member1Page);
      await getAttendButton(member1Page).click();
      const registrationModal = member1Page.locator('[data-attendance-role="registration-modal"]');
      await expect(registrationModal.getByRole("heading", { name: "Registration questions" })).toBeVisible();

      // Verify the registration modal renders required, optional, and choice questions.
      const topicsQuestion = registrationModal.locator("fieldset", {
        hasText: "Which topics are you interested in?",
      });
      const formatQuestion = registrationModal.locator("fieldset", {
        hasText: "Preferred learning format",
      });
      const accessQuestion = registrationModal.locator("fieldset", {
        hasText: "Accessibility needs",
      });
      await expect(topicsQuestion).toHaveAttribute("data-question-required", "true");
      await expect(topicsQuestion.locator(".asterisk")).toBeVisible();
      await expect(topicsQuestion.getByText("Operations", { exact: true })).toBeVisible();
      await expect(topicsQuestion.getByText("Security", { exact: true })).toBeVisible();
      await expect(formatQuestion).toHaveAttribute("data-question-required", "false");
      await expect(formatQuestion.locator(".asterisk")).toHaveCount(0);
      await expect(formatQuestion.getByText("Hands-on lab", { exact: true })).toBeVisible();
      await expect(accessQuestion).toHaveAttribute("data-question-required", "true");
      await expect(accessQuestion.locator(".asterisk")).toBeVisible();

      // Verify required answers are enforced: the browser blocks the empty required textarea first,
      // then the custom multi-select rule runs once native validation passes.
      const submitButton = registrationModal.locator('[data-attendance-role="registration-modal-submit"]');
      await submitButton.click();
      await expect(accessQuestion.locator("textarea")).toHaveJSProperty(
        "validationMessage",
        "Please fill out this field.",
      );
      await accessQuestion.locator("textarea").fill("Please reserve front-row seating.");
      await submitButton.click();
      await expect(topicsQuestion.locator("input[type='checkbox']").first()).toHaveJSProperty(
        "validationMessage",
        "Select at least one option.",
      );

      // Submit answers and cancel attendance.
      await topicsQuestion.locator("label", { hasText: "Operations" }).click();
      await formatQuestion.locator("label", { hasText: "Hands-on lab" }).click();
      await waitForActionResponse(member1Page, () => submitButton.click(), {
        method: "POST",
        urlIncludes: `/event/${eventId}/attend`,
      });
      await expect(getLeaveButton(member1Page)).toContainText("Cancel attendance");
      await cancelAttendance(member1Page, eventId);
    } finally {
      // Delete the temporary event with registration questions.
      cleanupEventsByIds(eventId ? [eventId] : []);
    }
  });
});

/** Adds a registration question and verifies it appears in the editor. */
const addQuestion = async (page, question) => {
  const editor = page.locator("questions-editor");

  await editor.getByRole("button", { name: "Add question" }).click();
  const dialog = page.getByRole("dialog", { name: "Add question" });
  await expect(dialog).toBeVisible();
  await dialog.locator("#question-prompt-draft").fill(question.prompt);
  await dialog.locator("#question-kind-draft").selectOption(question.kind);

  if (question.required) {
    await dialog.getByLabel("Required").check({ force: true });
  }

  for (let index = 0; index < (question.options || []).length; index += 1) {
    if (index > 0) {
      await dialog.getByRole("button", { name: "Add option" }).click();
    }

    await dialog.getByLabel(`Option ${index + 1}`).fill(question.options[index]);
  }

  await dialog.getByRole("button", { name: "Add question" }).click();
  await expect(dialog).toHaveCount(0);
  await expect(editor.getByText(question.prompt, { exact: true })).toBeVisible();
};

/** Verifies the registration question cards appear in the expected order. */
const assertQuestionOrder = async (page, prompts) => {
  const cards = page.locator("questions-editor").locator(".rounded-md.border.border-stone-200.bg-white");

  await expect(cards).toHaveCount(prompts.length);
  for (let index = 0; index < prompts.length; index += 1) {
    await expect(cards.nth(index)).toContainText(prompts[index]);
  }
};

/** Cancels the event attendance and waits for the attendee state. */
const cancelAttendance = async (page, eventId) => {
  const leaveButton = getLeaveButton(page);

  await expect(leaveButton).toBeVisible();
  await leaveButton.click();
  await expect(page.getByRole("button", { name: "Yes" })).toBeVisible();
  await waitForActionResponse(page, () => page.getByRole("button", { name: "Yes" }).click(), {
    method: "DELETE",
    urlIncludes: `/event/${eventId}/leave`,
  });
  await waitForAttendanceState(page);
  await expect(getAttendButton(page)).toBeVisible();
};

/** Fills the event form with registration question coverage details. */
const fillEventDetails = async (page, eventName) => {
  await navigateToPath(page, "/dashboard/group?tab=events");
  await page.locator("#dashboard-content").getByRole("button", { name: "Add Event" }).click();
  await expect(page.locator("#name")).toBeVisible();

  await page.locator("#name").fill(eventName);
  await page.locator("#kind_id").selectOption("virtual");
  await page.locator("#category_id").selectOption("33333333-3333-3333-3333-333333333331");
  await page.locator("#description_short").fill("Registration question configuration coverage.");
  await fillMarkdownEditor(
    page,
    "description",
    "Registration question configuration coverage for required and selectable answers.",
  );

  await page.locator('button[data-section="date-venue"]').click();
  await selectTimezone(page, "UTC");
  await page.locator("#starts_at").fill(futureDate({ days: 370, hour: 10 }));
  await page.locator("#ends_at").fill(futureDate({ days: 370, hour: 12 }));
  await page.locator("#meeting_join_url").fill("https://meet.example.com/e2e-question-editor");
};

/** Returns the registration question card matching the prompt. */
const getQuestionCard = (page, editor, prompt) =>
  editor
    .locator(".flex.items-start.gap-2", {
      has: page.getByRole("button", { name: "Reorder question" }),
      hasText: prompt,
    })
    .first();

/** Publishes the current event and waits for the editor save response. */
const publishCurrentEvent = async (page, eventId) => {
  await page.locator("#publish-event-button").click();
  await waitForEventEditorAfterSave(page, () => page.getByRole("button", { name: "Yes" }).click(), {
    eventId,
    method: "PUT",
    urlIncludes: `/dashboard/group/events/${eventId}/publish`,
  });
};
