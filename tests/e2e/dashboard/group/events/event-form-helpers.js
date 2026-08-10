import { expect } from "../../../fixtures.js";

import { openPaymentsSection } from "./helpers.js";

/** Add a ticket type through the ticketing modal and save it. */
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

    const amountField = modal
      .locator('[data-ticket-window-field="amount"]')
      .nth(index);
    await amountField.fill(priceWindow.amount);

    if (priceWindow.startsAt) {
      await modal
        .locator('[data-ticket-window-field="starts_at"]')
        .nth(index)
        .fill(priceWindow.startsAt);
    }

    if (priceWindow.endsAt) {
      await modal
        .locator('[data-ticket-window-field="ends_at"]')
        .nth(index)
        .fill(priceWindow.endsAt);
    }
  }

  await modal.locator('[data-ticketing-action="save-ticket"]').click();
  await expect(modal).toBeHidden();
};

/** Edit an existing ticket type through the ticketing modal and save it. */
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

/** Select automatic meeting creation and assert the hidden request value. */
export const enableAutomaticMeetingCreation = async (page) => {
  const onlineEventDetails = page.locator("online-event-details");
  const automaticModeInput = onlineEventDetails.locator(
    'input[type="radio"][value="automatic"]',
  );

  await expectAutomaticMeetingControls(page);
  await expect(automaticModeInput).toBeEnabled();

  await automaticModeInput.check({ force: true });

  await expect(
    onlineEventDetails.locator(
      'input[type="hidden"][name="meeting_requested"]',
    ),
  ).toHaveValue("true");
};

/** Verify automatic meeting controls are visible in the online details form. */
export const expectAutomaticMeetingControls = async (page) => {
  const onlineEventDetails = page.locator("online-event-details");
  const automaticModeCard = onlineEventDetails.locator(
    'input[type="radio"][value="automatic"] + div',
  );

  await expect(onlineEventDetails).toBeVisible();
  await expect(automaticModeCard).toBeVisible();
  await expect(
    automaticModeCard.getByText("Create meeting automatically", {
      exact: true,
    }),
  ).toBeVisible();
};

/** Verify manual meeting URL fields are visible in the event form. */
export const expectManualMeetingFields = async (page) => {
  await expect(page.locator("#meeting_join_url")).toBeVisible();
  await expect(page.locator("#meeting_recording_url")).toBeVisible();
};

/** Open the event details section and wait until it is active. */
export const openDetailsSection = async (page) => {
  const detailsSectionButton = page.locator('button[data-section="details"]');

  await detailsSectionButton.scrollIntoViewIfNeeded();
  await detailsSectionButton.click({ force: true });
  await expect(detailsSectionButton).toHaveAttribute("data-active", "true");
};

/** Remove a discount code from the ticketing summary. */
export const removeDiscountCode = async (page, code) => {
  const discountRow = page
    .locator('#discount-codes-ui [data-ticketing-role="table-body"] tr')
    .filter({ hasText: code });
  await discountRow.getByTitle("Delete").click();
  await expect(discountRow).toHaveCount(0);
};

/** Keep automatic meeting coverage within the configured provider capacity. */
export const setAutomaticMeetingCapacity = async (page) => {
  await openPaymentsSection(page);
  await editTicketType(page, "General Admission", {
    description: "Default free admission tier.",
    seatsTotal: "50",
    title: "General Admission",
  });
  await openDetailsSection(page);
};

/** Set CFS label names through the editor component API and assert inputs. */
export const setCfsLabels = async (page, labels) => {
  const editor = page.locator("cfs-labels-editor");

  await editor.evaluate(async (element, nextLabels) => {
    const cfsLabelsEditor = element;

    cfsLabelsEditor.setLabels?.(
      nextLabels.map((name) => ({
        color: "",
        name,
      })),
    );
    await cfsLabelsEditor.updateComplete;
  }, labels);

  // Verify the editor rendered one submitted input for each label.
  await expect(
    editor.locator('input[name^="cfs_labels"][name$="[name]"]'),
  ).toHaveCount(labels.length);
};

/** Set event hosts and speakers through selector APIs and assert submitted inputs. */
export const setEventPeople = async (page, values) => {
  await page
    .locator('user-search-selector[field-name="hosts"]')
    .evaluate(async (element, hosts) => {
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

  await expect(
    page.locator(
      'user-search-selector[field-name="hosts"] input[name="hosts[]"]',
    ),
  ).toHaveCount(values.hosts.length);
  await expect(
    page.locator(
      'speakers-selector[field-name-prefix="speakers"] input[name^="speakers"][name$="[user_id]"]',
    ),
  ).toHaveCount(values.speakers.length);
};

/** Set registration questions through the editor API and assert submitted inputs. */
export const setRegistrationQuestions = async (page, questions) => {
  const editor = page.locator("questions-editor");

  await editor.evaluate(async (element, nextQuestions) => {
    const questionsEditor = element;

    questionsEditor.questions = nextQuestions;
    await questionsEditor.updateComplete;
  }, questions);

  await expect(
    editor.locator('input[name^="registration_questions"][name$="[prompt]"]'),
  ).toHaveCount(questions.length);
};
