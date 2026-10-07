import { expect } from "../../../fixtures.js";

import { openPaymentsSection } from "./helpers.js";

/**
 * Adds a session through the session modal and assigns the given event labels.
 * @param {import("@playwright/test").Page} page - Playwright page.
 * @param {{
 *   endTime?: string,
 *   kind?: string,
 *   labels?: string[],
 *   name: string,
 *   startTime: string
 * }} values - Session values; times use the `HH:MM` format of the event day.
 */
export const addSession = async (page, values) => {
  await openSessionsSection(page);
  await page.locator("sessions-section").getByRole("button", { name: "Add session" }).first().click();

  const sessionModal = page.locator("session-form-modal");
  const sessionDialog = sessionModal.getByRole("dialog", { name: "Add session" });
  await expect(sessionDialog).toBeVisible();
  await sessionModal.locator('input[data-name="name"]').fill(values.name);
  await sessionModal.locator('select[data-name="kind"]').selectOption(values.kind ?? "virtual");
  await sessionModal.locator('input[type="time"]').nth(0).fill(values.startTime);
  if (values.endTime) {
    await sessionModal.locator('input[type="time"]').nth(1).fill(values.endTime);
  }
  await selectLabels(sessionModal.locator("label-selector"), values.labels ?? []);

  await sessionModal.getByRole("button", { name: "Add session" }).click();
  await expect(sessionDialog).toHaveCount(0);
};

/** Adds a ticket type through the ticketing modal and saves it. */
export const addTicketType = async (page, values) => {
  await page.locator("#add-ticket-type-button").click();

  const modal = page.locator('[data-ticketing-role="ticket-modal"]');
  await expect(modal).toBeVisible();
  await modal.locator("#ticket-title-draft").fill(values.title);
  await modal.locator("#ticket-seats-draft").fill(values.seatsTotal);
  await modal.locator("#ticket-description-draft").fill(values.description);

  const activeCheckbox = modal.locator('[data-ticket-field="active"]');
  if (!(await activeCheckbox.isChecked())) {
    await activeCheckbox.check({ force: true });
  }

  for (let index = 0; index < values.priceWindows.length; index += 1) {
    const priceWindow = values.priceWindows[index];

    if (index > 0) {
      await modal.locator('[data-ticketing-action="add-price-window"]').click();
    }

    const amountField = modal.locator('[data-ticket-window-field="amount"]').nth(index);
    await amountField.fill(priceWindow.amount);

    if (priceWindow.startsAt) {
      await modal.locator('[data-ticket-window-field="starts_at"]').nth(index).fill(priceWindow.startsAt);
    }

    if (priceWindow.endsAt) {
      await modal.locator('[data-ticket-window-field="ends_at"]').nth(index).fill(priceWindow.endsAt);
    }
  }

  await modal.locator('[data-ticketing-action="save-ticket"]').click();
  await expect(modal).toBeHidden();
};

/** Edits an existing ticket type through the ticketing modal and saves it. */
export const editTicketType = async (page, currentTitle, values) => {
  const ticketRow = page
    .locator('#ticket-types-ui [data-ticketing-role="table-body"] tr')
    .filter({ hasText: currentTitle });
  await ticketRow.locator('[data-ticketing-action="edit-ticket"]').click();

  const modal = page.locator('[data-ticketing-role="ticket-modal"]');
  await expect(modal).toBeVisible();
  await modal.locator("#ticket-title-draft").fill(values.title);
  await modal.locator("#ticket-seats-draft").fill(values.seatsTotal);
  await modal.locator("#ticket-description-draft").fill(values.description);
  await modal.locator('[data-ticketing-action="save-ticket"]').click();
  await expect(modal).toBeHidden();
};

/** Selects automatic meeting creation and asserts the hidden request value. */
export const enableAutomaticMeetingCreation = async (page) => {
  const onlineEventDetails = page.locator("online-event-details");
  const automaticModeInput = onlineEventDetails.locator('input[type="radio"][value="automatic"]');

  await expectAutomaticMeetingControls(page);
  await expect(automaticModeInput).toBeEnabled();

  await automaticModeInput.check({ force: true });

  await expect(onlineEventDetails.locator('input[type="hidden"][name="meeting_requested"]')).toHaveValue(
    "true",
  );
};

/** Verifies automatic meeting controls are visible in the online details form. */
export const expectAutomaticMeetingControls = async (page) => {
  const onlineEventDetails = page.locator("online-event-details");
  const automaticModeCard = onlineEventDetails.locator('input[type="radio"][value="automatic"] + div');

  await expect(onlineEventDetails).toBeVisible();
  await expect(automaticModeCard).toBeVisible();
  await expect(
    automaticModeCard.getByText("Create meeting automatically", {
      exact: true,
    }),
  ).toBeVisible();
};

/** Verifies manual meeting URL fields are visible in the event form. */
export const expectManualMeetingFields = async (page) => {
  await expect(page.locator("#meeting_join_url")).toBeVisible();
  await expect(page.locator("#meeting_recording_url")).toBeVisible();
};

/**
 * Verifies the label chips rendered on a session card in the sessions section.
 * @param {import("@playwright/test").Page} page - Playwright page.
 * @param {string} sessionName - Session name shown on the card.
 * @param {string[]} labelNames - Expected label names, in display order.
 */
export const expectSessionCardLabels = async (page, sessionName, labelNames) => {
  const sessionCard = page.locator("sessions-section session-card").filter({ hasText: sessionName });

  await expect(sessionCard).toHaveCount(1);
  await expect(sessionCard.locator(".custom-badge")).toHaveText(labelNames);
};

/** Opens the event details section and waits until it is active. */
export const openDetailsSection = async (page) => {
  const detailsSectionButton = page.locator('button[data-section="details"]');

  await detailsSectionButton.scrollIntoViewIfNeeded();
  await detailsSectionButton.click({ force: true });
  await expect(detailsSectionButton).toHaveAttribute("data-active", "true");
};

/** Opens the event labels section and waits until it is active. */
export const openLabelsSection = async (page) => {
  const labelsSectionButton = page.locator('button[data-section="labels"]');

  await labelsSectionButton.scrollIntoViewIfNeeded();
  await labelsSectionButton.click({ force: true });
  await expect(labelsSectionButton).toHaveAttribute("data-active", "true");
};

/** Opens the event sessions section and waits until it is active. */
export const openSessionsSection = async (page) => {
  const sessionsSectionButton = page.locator('button[data-section="sessions"]');

  await sessionsSectionButton.scrollIntoViewIfNeeded();
  await sessionsSectionButton.click({ force: true });
  await expect(sessionsSectionButton).toHaveAttribute("data-active", "true");
};

/** Removes a discount code from the ticketing summary. */
export const removeDiscountCode = async (page, code) => {
  const discountRow = page
    .locator('#discount-codes-ui [data-ticketing-role="table-body"] tr')
    .filter({ hasText: code });
  await discountRow.getByTitle("Delete").click();
  await expect(discountRow).toHaveCount(0);
};

/**
 * Selects labels by name in a label selector and waits for their chips.
 * @param {import("@playwright/test").Locator} labelSelector - `label-selector` element.
 * @param {string[]} labelNames - Label names to select.
 */
export const selectLabels = async (labelSelector, labelNames) => {
  for (const labelName of labelNames) {
    await labelSelector.getByRole("combobox").fill(labelName);
    await labelSelector.getByRole("option", { name: labelName, exact: true }).click();
    await expect(
      labelSelector.getByRole("button", { name: `Remove ${labelName}`, exact: true }),
    ).toBeVisible();
  }
};

/** Keeps automatic meeting coverage within the configured provider capacity. */
export const setAutomaticMeetingCapacity = async (page) => {
  await openPaymentsSection(page);
  await editTicketType(page, "General Admission", {
    description: "Default free admission tier.",
    seatsTotal: "50",
    title: "General Admission",
  });
  await openDetailsSection(page);
};

/** Sets event hosts and speakers through selector APIs and asserts submitted inputs. */
export const setEventPeople = async (page, values) => {
  await page.locator('user-search-selector[field-name="hosts"]').evaluate(async (element, hosts) => {
    const hostSelector = element;

    hostSelector.selectedUsers = hosts;
    await hostSelector.updateComplete;
  }, values.hosts);
  await page
    .locator('speakers-selector[field-name-prefix="speakers"]')
    .evaluate(async (element, speakers) => {
      const speakersSelector = element;

      speakersSelector.selectedSpeakers = speakers;
      await speakersSelector.updateComplete;
    }, values.speakers);

  await expect(page.locator('user-search-selector[field-name="hosts"] input[name="hosts[]"]')).toHaveCount(
    values.hosts.length,
  );
  await expect(
    page.locator(
      'speakers-selector[field-name-prefix="speakers"] input[name^="speakers"][name$="[user_id]"]',
    ),
  ).toHaveCount(values.speakers.length);
};

/** Opens the Labels tab and sets event label names through the editor component API. */
export const setLabels = async (page, labels) => {
  await openLabelsSection(page);

  const editor = page.locator("labels-editor");
  await editor.evaluate(async (element, nextLabels) => {
    const labelsEditor = element;

    labelsEditor.setLabels?.(
      nextLabels.map((name) => ({
        color: "",
        name,
      })),
    );
    await labelsEditor.updateComplete;
  }, labels);

  // Verify the editor rendered one submitted input for each label.
  await expect(editor.locator('input[name^="labels"][name$="[name]"]')).toHaveCount(labels.length);
};

/** Sets registration questions through the editor API and asserts submitted inputs. */
export const setRegistrationQuestions = async (page, questions) => {
  const editor = page.locator("questions-editor");

  await editor.evaluate(async (element, nextQuestions) => {
    const questionsEditor = element;

    questionsEditor.questions = nextQuestions;
    await questionsEditor.updateComplete;
  }, questions);

  await expect(editor.locator('input[name^="registration_questions"][name$="[prompt]"]')).toHaveCount(
    questions.length,
  );
};
