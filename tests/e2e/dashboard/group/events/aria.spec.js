import { randomUUID } from "node:crypto";

import { expect, test } from "../../../fixtures.js";

import { setupOwnedTicketedAttendee } from "../../../data-graphs/attendance.js";
import { setupCfsSubmission } from "../../../data-graphs/cfs.js";
import {
  setupCompletedFreePurchases,
  setupTicketInvitationRequest,
  setupTicketWaitlistEntry,
} from "../../../data-graphs/events.js";
import {
  cleanupEventSurveys,
  setupOwnedEventSurvey,
  setupOwnedSurveyResponse,
} from "../../../data-graphs/surveys.js";
import { TEST_USER_IDS } from "../../../seed.js";
import { enableDesktopVersion, expectAriaSnapshot, expectPageLayout } from "../../../snapshots.js";
import {
  ARIA_EVENT,
  openActionsMenu,
  openGroupDashboardView,
  setupAriaEvent,
  setupAriaGroup,
} from "../aria-helpers.js";
import { openEventUpdateFormByName } from "./helpers.js";

// Sections of the add event form, in tab order.
const ADD_SECTIONS = [
  "details",
  "date-venue",
  "cohosts",
  "contributors",
  "payments",
  "questions",
  "labels",
  "cfs",
  "sessions",
];

// Sections of the event editor of a published event without approval or waitlist, in tab order.
const EDITOR_SECTIONS = [...ADD_SECTIONS, "submissions", "attendees", "surveys", "analytics"];

// Name and fixed start (UTC) of the owned past event of the temporary group.
const PAST_EVENT = { name: "E2E ARIA past event", slug: "e2e-aria-past-event", startsAt: "2024-03-10 18:00" };

// Each view runs as a desktop test and as a @mobile test in the desktop version.
for (const viewport of ["desktop", "mobile"]) {
  const title = (name) =>
    viewport === "desktop"
      ? `matches the desktop ${name}`
      : `matches the ${name} in the mobile desktop version @mobile`;

  test.describe(`group dashboard events ARIA snapshots (${viewport})`, () => {
    test.beforeEach(async ({ organizerGroupPage }) => {
      if (viewport === "mobile") {
        await enableDesktopVersion(organizerGroupPage);
      }
    });

    test(title("events list views"), async ({ organizerGroupPage, owned }) => {
      await expectEventsListViews({ owned, page: organizerGroupPage });
    });

    test(title("add event form sections"), async ({ organizerGroupPage, owned }) => {
      await expectAddEventViews({ owned, page: organizerGroupPage });
    });

    test(title("event editor sections"), async ({ organizerGroupPage, owned }) => {
      await expectEventEditorViews({ owned, page: organizerGroupPage });
    });

    test(title("event editor dialogs"), async ({ organizerGroupPage, owned }) => {
      await expectEventEditorDialogs({ owned, page: organizerGroupPage });
    });

    test(title("event attendees views"), async ({ organizerGroupPage, owned }) => {
      await expectAttendeesViews({ owned, page: organizerGroupPage });
    });

    test(title("event requests and waitlist views"), async ({ organizerGroupPage, owned }) => {
      await expectRequestsAndWaitlistViews({ owned, page: organizerGroupPage });
    });

    test(title("event submissions views"), async ({ organizerGroupPage, owned }) => {
      await expectSubmissionsViews({ owned, page: organizerGroupPage });
    });

    test(title("event surveys views"), async ({ organizerGroupPage, owned }) => {
      await expectSurveysViews({ owned, page: organizerGroupPage });
    });
  });
}

/** Checks the layout of the add event form sections and captures them. */
const expectAddEventViews = async ({ owned, page }) => {
  await setupAriaGroup({ owned, page });

  await test.step("form navigation", async () => {
    // Open the add form and check the layout.
    const navigation = page.getByRole("navigation", { name: "Event form sections" });
    await openGroupDashboardView(page, "tab=events");
    await page.getByRole("button", { name: "Add Event" }).click();
    await expect(navigation).toBeVisible();
    await expectPageLayout(page, { regions: [navigation] });

    // Capture the authoring sections offered before the event exists.
    await expectAriaSnapshot(page, navigation, "event-add-navigation");
  });

  for (const section of ADD_SECTIONS) {
    await test.step(`${section} section`, async () => {
      // Open the section and capture its empty fields.
      const content = await openFormSection(page, section);
      await expectAriaSnapshot(page, content, `event-add-${section}`);
    });
  }
};

/** Checks the layout of the attendees section views of an owned event and captures them. */
const expectAttendeesViews = async ({ owned, page }) => {
  const { groupId } = await setupAriaGroup({ owned, page });
  const { eventId, ticketTypeIds } = setupAriaEvent({ groupId, owned });
  setupOwnedTicketedAttendee({ eventId, ticketTypeId: ticketTypeIds.general, userId: TEST_USER_IDS.member3 });
  const table = page.getByRole("table", { name: "Attendees list" });

  await test.step("attendees list", async () => {
    // Open the attendees of the owned event and check the layout.
    await openEventUpdateFormByName(page, ARIA_EVENT.name, eventId);
    const content = await openFormSection(page, "attendees");
    await expect(table.getByRole("row").filter({ hasText: "E2E Member Three" })).toBeVisible();

    // Capture the toolbar, the filters and the ticketed attendee row.
    await expectAriaSnapshot(page, content, "event-attendees-list");
  });

  await test.step("attendee actions menu", async () => {
    // Open the actions of the attendee and capture them.
    const menu = await openActionsMenu(page, "Open attendee actions");
    await expectAriaSnapshot(page, menu, "event-attendees-row-actions");
    await page.getByLabel("Open attendee actions", { exact: true }).click();
    await expect(menu).toBeHidden();
  });

  await test.step("attendees toolbar menu", async () => {
    // Open the toolbar actions and capture them.
    const menu = await openActionsMenu(page, "Open attendee actions menu");
    await expectAriaSnapshot(page, menu, "event-attendees-toolbar-actions");
  });

  await test.step("invite attendee dialog", async () => {
    // Open the invitation form from the toolbar menu and check the layout.
    const dialog = page.locator("#attendee-invitation-modal");
    await page.locator("#open-attendee-invitation-modal").click();
    await expect(dialog).toBeVisible();
    await expectPageLayout(page, { regions: [dialog] });

    // Capture the user search and the ticket choice.
    await expectAriaSnapshot(page, dialog, "event-attendees-invite-dialog");
    await page.keyboard.press("Escape");
    await expect(dialog).toBeHidden();
  });

  await test.step("send email menu and dialog", async () => {
    // Open the email actions of the toolbar and capture them.
    const menu = page.locator("#attendee-email-actions-menu");
    await page.locator('[aria-controls="attendee-email-actions-menu"]').click();
    await expect(menu).toBeVisible();
    await expectPageLayout(page, { regions: [menu] });
    await expectAriaSnapshot(page, menu, "event-attendees-email-actions");

    // Open the email form for every eligible attendee, check the layout and capture the empty form.
    const dialog = page.getByRole("dialog", { name: "Send email" });
    await menu.getByRole("menuitem", { name: "All eligible attendees" }).click();
    await expect(dialog).toBeVisible();
    await expectPageLayout(page, { regions: [dialog] });
    await expectAriaSnapshot(page, dialog, "event-attendees-email-dialog");
    await page.keyboard.press("Escape");
    await expect(dialog).toBeHidden();
  });

  await test.step("column filters", async () => {
    // Open the ticket type and checked in column filters and capture their options.
    const ticketOptions = await openActionsMenu(page, "Ticket type filters");
    await expectAriaSnapshot(page, ticketOptions, "event-attendees-ticket-filter");
    await page.getByLabel("Ticket type filters").click();
    await expect(ticketOptions).toBeHidden();
    const checkInOptions = await openActionsMenu(page, "Checked In filters");
    await expectAriaSnapshot(page, checkInOptions, "event-attendees-checked-in-filter");
  });
};

/** Checks the layout of the add dialogs of the event editor sections and captures them. */
const expectEventEditorDialogs = async ({ owned, page }) => {
  const { groupId } = await setupAriaGroup({ owned, page });
  const { eventId } = setupAriaEvent({ groupId, owned });

  // The speaker picker is a plain modal; the other add forms are dialogs.
  for (const [section, buttonName, getDialog, name] of [
    [
      "contributors",
      "Add speaker",
      (content) => content.locator("session-speaker-modal .modal-card"),
      "event-editor-add-speaker-dialog",
    ],
    ["payments", "Add ticket type", () => page.getByRole("dialog"), "event-editor-add-ticket-type-dialog"],
    ["questions", "Add question", () => page.getByRole("dialog"), "event-editor-add-question-dialog"],
    ["sessions", "Add session", () => page.getByRole("dialog"), "event-editor-add-session-dialog"],
  ]) {
    await test.step(`${section} add dialog`, async () => {
      // Open the editor of the owned event, the section and its add form, and check the layout.
      await openEventUpdateFormByName(page, ARIA_EVENT.name, eventId);
      const content = await openFormSection(page, section);
      const dialog = getDialog(content);
      await content.getByRole("button", { name: buttonName, exact: true }).click();
      await expect(dialog).toHaveCount(1);
      await expect(dialog).toBeVisible();
      await expectPageLayout(page, { regions: [dialog] });

      // Capture the empty form.
      await expectAriaSnapshot(page, dialog, name);
    });
  }
};

/** Checks the layout of the event editor sections of an owned event and captures them. */
const expectEventEditorViews = async ({ owned, page }) => {
  const { groupId } = await setupAriaGroup({ owned, page });
  const { eventId } = setupAriaEvent({ groupId, owned });

  await test.step("editor header and navigation", async () => {
    // Open the editor of the owned event and check the layout.
    const header = page.locator("#event-update-page > div").first();
    const navigation = page.getByRole("navigation", { name: "Event form sections" });
    await openEventUpdateFormByName(page, ARIA_EVENT.name, eventId);
    await expectPageLayout(page, { regions: [header, navigation] });

    // Capture the back link, the title, the facts, the actions and the sections of a published event.
    await expectAriaSnapshot(page, header, "event-editor-header");
    await expectAriaSnapshot(page, navigation, "event-editor-navigation");
  });

  for (const section of EDITOR_SECTIONS) {
    await test.step(`${section} section`, async () => {
      // Open the section and capture the fields or lists of the owned event.
      const content = await openFormSection(page, section);
      await expectAriaSnapshot(page, content, `event-editor-${section}`);
    });
  }

  await test.step("event preview dialog", async () => {
    // Open the preview of the owned event and check the layout.
    const dialog = page.getByRole("dialog", { name: "Event preview" });
    await page.getByRole("button", { name: "Preview" }).click();
    await expect(dialog).toBeVisible();
    await expectPageLayout(page, { regions: [dialog] });

    // Capture the preview of the event page.
    await expectAriaSnapshot(page, dialog, "event-preview-dialog");
  });
};

/** Checks the layout of the events list views and captures them. */
const expectEventsListViews = async ({ owned, page }) => {
  const { groupId } = await setupAriaGroup({ owned, page });

  await test.step("empty upcoming events", async () => {
    // Load the events of a temporary group without events and check the layout.
    const content = await openGroupDashboardView(page, "tab=events");

    // Capture the title, the list tabs, the add button and the empty upcoming list.
    await expectAriaSnapshot(page, content, "events-upcoming-empty");
  });

  await test.step("empty past events", async () => {
    // Open the past events tab and check the layout.
    const past = page.locator("#past-content");
    await page.getByRole("button", { name: "Past events" }).click();
    await expect(past).toBeVisible();
    await expectPageLayout(page, { regions: [past] });

    // Capture the empty past list.
    await expectAriaSnapshot(page, past, "events-past-empty");
  });

  // Give the group an owned upcoming event and an owned past event.
  setupAriaEvent({ groupId, owned });
  setupAriaEvent({ groupId, owned, ...PAST_EVENT });

  await test.step("upcoming events", async () => {
    // Load the upcoming owned event and check the layout.
    const table = page.getByRole("table", { name: "Upcoming events list" });
    await openGroupDashboardView(page, "tab=events", { regions: [table] });

    // Capture the column headers and the event row with its actions.
    await expectAriaSnapshot(page, table, "events-upcoming-list");
  });

  await test.step("event actions menu", async () => {
    // Open the actions of the upcoming event and capture them.
    const menu = await openActionsMenu(page, `Open actions for ${ARIA_EVENT.name}`);
    await expectAriaSnapshot(page, menu, "events-actions");
  });

  await test.step("past events", async () => {
    // Load the past owned event and check the layout.
    const table = page.getByRole("table", { name: "Past events list" });
    await openGroupDashboardView(page, "tab=events&events_tab=past", { regions: [table] });

    // Capture the column headers and the past event row.
    await expectAriaSnapshot(page, table, "events-past-list");
  });
};

/** Checks the layout of the requests and waitlist sections of owned events and captures them. */
const expectRequestsAndWaitlistViews = async ({ owned, page }) => {
  const { groupId } = await setupAriaGroup({ owned, page });

  await test.step("invitation requests", async () => {
    // Open the requests of an owned approval event with a pending request and check the layout.
    const { eventId, ticketTypeIds } = setupAriaEvent({ approvalRequired: true, groupId, owned });
    setupTicketInvitationRequest({
      eventId,
      ticketTypeId: ticketTypeIds.general,
      userId: TEST_USER_IDS.member3,
    });
    await openEventUpdateFormByName(page, ARIA_EVENT.name, eventId);
    const content = await openFormSection(page, "invitation-requests");
    await expect(content.getByRole("row").filter({ hasText: "E2E Member Three" })).toBeVisible();

    // Capture the filters and the pending request.
    await expectAriaSnapshot(page, content, "event-requests-list");

    // Open the request actions and capture them.
    const menu = await openActionsMenu(page, "Open actions for E2E Member Three");
    await expectAriaSnapshot(page, menu, "event-requests-actions");
  });

  await test.step("waitlist", async () => {
    // Open the waitlist of an owned sold-out event with a queued member and check the layout.
    const { eventId, ticketTypeIds } = setupAriaEvent({
      attendeeUserIds: [TEST_USER_IDS.pending1],
      groupId,
      name: "E2E ARIA waitlist event",
      owned,
      slug: "e2e-aria-waitlist-event",
      tiers: [{ key: "general", seats: 1, title: "General admission" }],
      waitlistEnabled: true,
    });
    // Hold the only seat with a purchase before queueing the member, so the enrollment worker
    // never finds a free seat to offer to the queue.
    setupCompletedFreePurchases({
      eventId,
      ticketTypeId: ticketTypeIds.general,
      userIds: [TEST_USER_IDS.pending1],
    });
    setupTicketWaitlistEntry({
      eventId,
      ticketTypeId: ticketTypeIds.general,
      userId: TEST_USER_IDS.member3,
    });
    await openEventUpdateFormByName(page, "E2E ARIA waitlist event", eventId);
    const content = await openFormSection(page, "waitlist");
    await expect(content.getByRole("row").filter({ hasText: "E2E Member Three" })).toBeVisible();

    // Capture the waitlist entry.
    await expectAriaSnapshot(page, content, "event-waitlist-list");

    // Open the entry actions and capture them; the invite form has no free seat to assign.
    const menu = await openActionsMenu(page, "Open waitlist actions for E2E Member Three");
    await expectAriaSnapshot(page, menu, "event-waitlist-actions");
  });
};

/** Checks the layout of the submissions section views of an owned event and captures them. */
const expectSubmissionsViews = async ({ owned, page }) => {
  const { groupId } = await setupAriaGroup({ owned, page });
  const { eventId } = setupAriaEvent({ groupId, owned });
  const { proposalId } = owned.sessionProposal({ title: "E2E ARIA proposal", userId: TEST_USER_IDS.member3 });
  setupCfsSubmission({ eventId, proposalId });

  await test.step("submissions list", async () => {
    // Open the submissions of the owned event and check the layout.
    await openEventUpdateFormByName(page, ARIA_EVENT.name, eventId);
    const content = await openFormSection(page, "submissions");
    await expect(content.getByRole("row").filter({ hasText: "E2E ARIA proposal" })).toBeVisible();

    // Capture the filters and the not reviewed submission.
    await expectAriaSnapshot(page, content, "event-submissions-list");
  });

  await test.step("review submission dialog", async () => {
    // Open the review of the submission and check the layout.
    const dialog = page.getByRole("dialog");
    await page.getByRole("button", { name: /^Review submission/ }).click();
    await expect(dialog).toBeVisible();
    await expectPageLayout(page, { regions: [dialog] });

    // Capture the review tabs with the proposal details.
    await expectAriaSnapshot(page, dialog, "event-submissions-review-dialog");
  });

  for (const tab of ["Ratings", "Decision"]) {
    await test.step(`review submission ${tab.toLowerCase()} tab`, async () => {
      // Open the review tab and capture its panel.
      const dialog = page.getByRole("dialog", { name: "Review submission" });
      await dialog.getByRole("tab", { name: tab }).click();
      await expect(dialog.getByRole("tab", { name: tab })).toHaveAttribute("aria-selected", "true");
      const panel = dialog.getByRole("tabpanel");
      await expectPageLayout(page, { regions: [panel] });
      await expectAriaSnapshot(page, panel, `event-submissions-review-${tab.toLowerCase()}`);
    });
  }
};

/** Checks the layout of the surveys section views of an owned past event and captures them. */
const expectSurveysViews = async ({ owned, page }) => {
  const { groupId } = await setupAriaGroup({ owned, page });
  const { eventId } = setupAriaEvent({
    attendeeUserIds: [TEST_USER_IDS.member3],
    groupId,
    owned,
    ...PAST_EVENT,
  });
  const choices = [
    { id: randomUUID(), label: "Yes" },
    { id: randomUUID(), label: "No" },
  ];
  const textQuestionId = randomUUID();
  const choiceQuestionId = randomUUID();
  const survey = owned.track(
    setupOwnedEventSurvey({
      anonymous: false,
      eventId,
      questions: [
        {
          id: choiceQuestionId,
          kind: "single-select",
          options: choices,
          prompt: "Would you come again?",
          required: true,
        },
        { id: textQuestionId, kind: "free-text", options: [], prompt: "Any feedback?", required: false },
      ],
      status: "ready",
      title: "E2E ARIA survey",
    }),
    ({ id }) => cleanupEventSurveys([id]),
  );
  setupOwnedSurveyResponse({
    answers: {
      answers: [
        { question_id: choiceQuestionId, value: choices[0].id },
        { question_id: textQuestionId, value: "Great talks." },
      ],
    },
    surveyId: survey.id,
    userId: TEST_USER_IDS.member3,
  });
  const content = page.locator('[data-content="surveys"]');

  await test.step("surveys list", async () => {
    // Open the surveys of the owned past event and check the layout.
    await openEventUpdateFormByName(page, PAST_EVENT.name, eventId, { eventsTab: "past" });
    await openFormSection(page, "surveys");
    await expect(content.getByRole("row").filter({ hasText: survey.title })).toBeVisible();

    // Capture the survey row with its status, responses and actions.
    await expectAriaSnapshot(page, content, "event-surveys-list");
  });

  await test.step("survey results summary", async () => {
    // Open the results of the survey and check the layout.
    await content.getByRole("button", { name: `View results: ${survey.title}` }).click();
    await expect(content.getByRole("button", { name: "Individual" })).toBeVisible();
    await expectPageLayout(page, { regions: [content] });

    // Capture the summary of each question.
    await expectAriaSnapshot(page, content, "event-surveys-results");
  });

  await test.step("survey text answers dialog", async () => {
    // Open every answer of the free-text question and check the layout.
    const dialog = page.getByRole("dialog", { name: "Any feedback?" });
    await content.getByRole("button", { name: /^View 1 answer/ }).click();
    await expect(dialog).toBeVisible();
    await expectPageLayout(page, { regions: [dialog] });

    // Capture the answers list; the answer date is the test day.
    await expectAriaSnapshot(page, dialog, "event-surveys-text-answers-dialog");
    await dialog.getByRole("button", { name: "Close", exact: true }).click();
    await expect(dialog).toBeHidden();
  });

  await test.step("survey respondents", async () => {
    // Open the individual responses and check the layout.
    await content.getByRole("button", { name: "Individual" }).click();
    await expect(content.getByRole("table", { name: "Survey respondents" })).toBeVisible();
    await expectPageLayout(page, { regions: [content] });

    // Capture the respondents table; the response date is the test day.
    await expectAriaSnapshot(page, content, "event-surveys-respondents");
  });

  await test.step("survey response dialog", async () => {
    // Open the response of the respondent and check the layout.
    const dialog = page.getByRole("dialog");
    await content.getByRole("row").filter({ hasText: "E2E Member Three" }).click();
    await expect(dialog).toBeVisible();
    await expectPageLayout(page, { regions: [dialog] });

    // Capture the answers of the respondent.
    await expectAriaSnapshot(page, dialog, "event-surveys-response-dialog");
  });

  await test.step("add survey form", async () => {
    // Go back to the surveys list, open the add form and check the layout.
    await page.keyboard.press("Escape");
    await content.getByRole("button", { name: "Back to surveys" }).click();
    await content.getByRole("button", { name: "Add survey" }).click();
    await expect(content.getByRole("textbox", { name: "Title *" })).toBeVisible();
    await expectPageLayout(page, { regions: [content] });

    // Capture the empty survey form.
    await expectAriaSnapshot(page, content, "event-surveys-add-form");
  });
};

/** Opens a section of the add or update event form and checks the layout with it as a key region. */
const openFormSection = async (page, section) => {
  const content = page.locator(`[data-content="${section}"]`);
  await page.locator(`button[data-section="${section}"]`).click();
  await expect(content).toBeVisible();
  await expectPageLayout(page, { regions: [content] });
  return content;
};
