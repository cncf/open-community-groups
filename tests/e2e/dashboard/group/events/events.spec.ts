import type { Locator, Page } from "@playwright/test";

import { expect, test } from "../../../fixtures";

import {
  E2E_MEETINGS_ENABLED,
  E2E_PAYMENTS_ENABLED,
  TEST_COMMUNITY_NAME,
  TEST_EVENT_IDS,
  TEST_EVENT_NAMES,
  TEST_EVENT_SLUGS,
  TEST_PAYMENT_EVENT_IDS,
  TEST_PAYMENT_EVENT_NAMES,
  TEST_GROUP_SLUGS,
  navigateToPath,
  selectTimezone,
} from "../../../utils";
import {
  TEST_UPLOAD_ASSET_PATHS,
  fillEventVenue,
  fillMarkdownEditor,
  fillMultipleInputs,
  uploadGalleryImages,
  uploadImageField,
} from "../../form-helpers";

type TicketPriceWindow = {
  amount: string;
  endsAt?: string;
  startsAt?: string;
};

const openPaymentsSection = async (page: Page) => {
  const paymentsSectionButton = page.locator('button[data-section="payments"]');

  await paymentsSectionButton.scrollIntoViewIfNeeded();
  await expect(paymentsSectionButton).toBeVisible();

  if ((await paymentsSectionButton.getAttribute("data-active")) === "true") {
    return;
  }

  for (let attempt = 0; attempt < 3; attempt += 1) {
    await paymentsSectionButton.click({ force: true });

    try {
      await expect(paymentsSectionButton).toHaveAttribute("data-active", "true", {
        timeout: 1000,
      });
      return;
    } catch (error) {
      if (attempt === 2) {
        throw error;
      }
    }
  }
};

const openEventUpdateFormByName = async (page: Page, eventName: string, eventId?: string) => {
  const editButton = page.locator(`td button[aria-label="Edit event: ${eventName}"]:visible`);
  await expect(editButton).toBeVisible();

  await Promise.all([
    page.waitForResponse(
      (response) =>
        response.request().method() === "GET" &&
        response.url().includes("/dashboard/group/events/") &&
        response.url().includes("/update") &&
        (eventId ? response.url().includes(eventId) : true) &&
        response.ok(),
    ),
    editButton.click(),
  ]);
};

const expectManualMeetingFields = async (page: Page) => {
  await expect(page.locator("#meeting_join_url")).toBeVisible();
  await expect(page.locator("#meeting_recording_url")).toBeVisible();
};

const expectAutomaticMeetingControls = async (page: Page) => {
  const onlineEventDetails = page.locator("online-event-details");
  const automaticModeCard = onlineEventDetails.locator(
    'input[type="radio"][value="automatic"] + div',
  );

  await expect(onlineEventDetails).toBeVisible();
  await expect(automaticModeCard).toBeVisible();
  await expect(
    automaticModeCard.getByText("Create meeting automatically", { exact: true }),
  ).toBeVisible();
};

const enableAutomaticMeetingCreation = async (page: Page) => {
  const onlineEventDetails = page.locator("online-event-details");
  const automaticModeInput = onlineEventDetails.locator('input[type="radio"][value="automatic"]');

  await expectAutomaticMeetingControls(page);
  await expect(automaticModeInput).toBeEnabled();

  await automaticModeInput.check({ force: true });

  await expect(
    onlineEventDetails.locator('input[type="hidden"][name="meeting_requested"]'),
  ).toHaveValue("true");
};

const addTicketType = async (
  page: Page,
  values: {
    description: string;
    priceWindows: TicketPriceWindow[];
    seatsTotal: string;
    title: string;
  },
) => {
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

const addDiscountCode = async (
  page: Page,
  values: {
    amount?: string;
    available?: string;
    code: string;
    endsAt?: string;
    kind: "fixed_amount" | "percentage";
    percentage?: string;
    startsAt?: string;
    title: string;
    totalAvailable?: string;
  },
) => {
  await page.locator("#add-discount-code-button").click();

  const modal = page.locator('[data-ticketing-role="discount-modal"]');
  await expect(modal).toBeVisible();
  await modal.locator("#discount-title-draft").fill(values.title);
  await modal.locator("#discount-code-draft").fill(values.code);

  const activeCheckbox = modal.locator('[data-discount-field="active"]');
  if (!(await activeCheckbox.isChecked())) {
    await activeCheckbox.check({ force: true });
  }

  await modal.locator("#discount-kind-draft").selectOption(values.kind);

  if (values.kind === "fixed_amount" && values.amount) {
    await modal.locator("#discount-amount-draft").fill(values.amount);
  }

  if (values.kind === "percentage" && values.percentage) {
    await modal.locator("#discount-percentage-draft").fill(values.percentage);
  }

  if (values.totalAvailable) {
    await modal.locator("#discount-total-draft").fill(values.totalAvailable);
  }

  if (values.available) {
    await modal.locator("#discount-available-draft").fill(values.available);
  }

  if (values.startsAt) {
    await modal.locator("#discount-starts-draft").fill(values.startsAt);
  }

  if (values.endsAt) {
    await modal.locator("#discount-ends-draft").fill(values.endsAt);
  }

  await modal.locator('[data-ticketing-action="save-discount"]').click();
  await expect(modal).toBeHidden();
};

const setCfsLabels = async (page: Page, labels: string[]) => {
  const editor = page.locator("cfs-labels-editor");

  await editor.evaluate(async (element, nextLabels) => {
    const cfsLabelsEditor = element as HTMLElement & {
      setLabels?: (labels: Array<{ color: string; event_cfs_label_id?: string; name: string }>) => void;
      updateComplete?: Promise<unknown>;
    };

    cfsLabelsEditor.setLabels?.(
      nextLabels.map((name) => ({
        color: "",
        name,
      })),
    );
    await cfsLabelsEditor.updateComplete;
  }, labels);

  await expect(editor.locator('input[name^="cfs_labels"][name$="[name]"]')).toHaveCount(labels.length);
};

test.describe("group dashboard events view", () => {
  test("organizer can switch between upcoming and past events tabs", async ({ organizerGroupPage }) => {
    await navigateToPath(organizerGroupPage, "/dashboard/group?tab=events");

    const dashboardContent = organizerGroupPage.locator("#dashboard-content");
    const upcomingTab = dashboardContent.locator("#upcoming-tab");
    const pastTab = dashboardContent.locator("#past-tab");
    const upcomingContent = dashboardContent.locator("#upcoming-content");
    const pastContent = dashboardContent.locator("#past-content");

    await expect(upcomingTab).toHaveAttribute("data-active", "true");
    await expect(pastTab).toHaveAttribute("data-active", "false");
    await expect(upcomingContent).toBeVisible();
    await expect(pastContent).toBeHidden();
    await expect(upcomingContent.locator("tr", { hasText: TEST_EVENT_NAMES.alpha[0] })).toBeVisible();

    await pastTab.click();

    await expect(pastTab).toHaveAttribute("data-active", "true");
    await expect(upcomingTab).toHaveAttribute("data-active", "false");
    await expect(pastContent).toBeVisible();
    await expect(upcomingContent).toBeHidden();
    await expect(pastContent.locator("tr", { hasText: "Past Event For Filtering" })).toBeVisible();

    await upcomingTab.click();

    await expect(upcomingTab).toHaveAttribute("data-active", "true");
    await expect(pastTab).toHaveAttribute("data-active", "false");
    await expect(upcomingContent).toBeVisible();
    await expect(pastContent).toBeHidden();
    await expect(upcomingContent.locator("tr", { hasText: TEST_EVENT_NAMES.alpha[0] })).toBeVisible();
  });

  test("organizer can create and delete an event", async ({ organizerGroupPage }) => {
    const eventName = `E2E Group Event ${Date.now()}`;

    await navigateToPath(organizerGroupPage, "/dashboard/group?tab=events");

    const dashboardContent = organizerGroupPage.locator("#dashboard-content");
    await expect(dashboardContent.getByText("Events", { exact: true })).toBeVisible();

    await dashboardContent.getByRole("button", { name: "Add Event" }).click();
    await expect(organizerGroupPage.locator("#name")).toBeVisible();

    await organizerGroupPage.locator("#name").fill(eventName);
    await organizerGroupPage.locator("#kind_id").selectOption("virtual");
    await organizerGroupPage.locator("#category_id").selectOption("33333333-3333-3333-3333-333333333331");
    await organizerGroupPage
      .locator("#description_short")
      .fill("A dashboard-created event from the e2e suite.");
    await fillMarkdownEditor(
      organizerGroupPage,
      "description",
      "A dashboard event created and removed by the e2e suite.",
    );
    
    if (E2E_MEETINGS_ENABLED) {
      await organizerGroupPage.locator("#capacity").fill("50");
    }
    
    await organizerGroupPage.locator('button[data-section="date-venue"]').click();
    await selectTimezone(organizerGroupPage, "UTC");
    await expect(organizerGroupPage.locator("#starts_at")).toBeVisible();
    await organizerGroupPage.locator("#starts_at").fill("2030-05-10T10:00");
    await organizerGroupPage.locator("#ends_at").fill("2030-05-10T12:00");
    if (E2E_MEETINGS_ENABLED) {
      await enableAutomaticMeetingCreation(organizerGroupPage);
    } else {
      await organizerGroupPage.locator("#meeting_join_url").fill(
        "https://meet.example.com/e2e-created-event",
      );
    }
    const visibleAddEventButton = organizerGroupPage.locator(
      "#pending-changes-alert:not(.hidden) #add-event-button",
    );
    await expect(organizerGroupPage.locator("#pending-changes-alert")).not.toHaveClass(/hidden/);
    await expect(visibleAddEventButton).toBeVisible();

    await Promise.all([
      organizerGroupPage.waitForResponse(
        (response) =>
          response.request().method() === "POST" &&
          response.url().includes("/dashboard/group/events/add") &&
          response.status() === 201,
      ),
      visibleAddEventButton.click(),
    ]);

    const eventRow = dashboardContent.locator("tr", { hasText: eventName });
    await expect(eventRow).toBeVisible();

    await openEventUpdateFormByName(organizerGroupPage, eventName);
    await organizerGroupPage.locator('button[data-section="date-venue"]').click();

    if (E2E_MEETINGS_ENABLED) {
      await expectAutomaticMeetingControls(organizerGroupPage);
      await expect(
        organizerGroupPage.locator('online-event-details input[name="meeting_requested"]'),
      ).toHaveValue("true");
    } else {
      await expect(organizerGroupPage.locator("#meeting_join_url")).toHaveValue(
        "https://meet.example.com/e2e-created-event",
      );
    }

    await navigateToPath(organizerGroupPage, "/dashboard/group?tab=events");
    await eventRow.locator(".btn-actions").click();

    const deleteButton = eventRow.locator('button[id^="delete-event-"]');
    await expect(deleteButton).toBeVisible();
    await deleteButton.click();
    await expect(organizerGroupPage.locator(".swal2-popup")).toContainText(
      "Are you sure you wish to delete this event?",
    );

    await Promise.all([
      organizerGroupPage.waitForResponse(
        (response) =>
          response.request().method() === "DELETE" &&
          response.url().includes("/dashboard/group/events/") &&
          response.url().includes("/delete") &&
          response.ok(),
      ),
      organizerGroupPage.getByRole("button", { name: "Yes" }).click(),
    ]);

    await expect(dashboardContent.locator("tr", { hasText: eventName })).toHaveCount(0);
  });

  test("organizer can create and delete a recurring event series", async ({ organizerGroupPage }) => {
    const eventName = `E2E Recurring Group Event ${Date.now()}`;

    await navigateToPath(organizerGroupPage, "/dashboard/group?tab=events");

    const dashboardContent = organizerGroupPage.locator("#dashboard-content");
    await expect(dashboardContent.getByText("Events", { exact: true })).toBeVisible();

    await dashboardContent.getByRole("button", { name: "Add Event" }).click();
    await expect(organizerGroupPage.locator("#name")).toBeVisible();

    await organizerGroupPage.locator("#name").fill(eventName);
    await organizerGroupPage.locator("#kind_id").selectOption("virtual");
    await organizerGroupPage
      .locator("#category_id")
      .selectOption("33333333-3333-3333-3333-333333333331");
    await organizerGroupPage
      .locator("#description_short")
      .fill("A recurring dashboard-created event from the e2e suite.");
    await fillMarkdownEditor(
      organizerGroupPage,
      "description",
      "A recurring dashboard event created and removed by the e2e suite.",
    );
    await organizerGroupPage.locator('button[data-section="date-venue"]').click();
    await selectTimezone(organizerGroupPage, "UTC");
    await expect(organizerGroupPage.locator("#starts_at")).toBeVisible();
    await organizerGroupPage.locator("#starts_at").fill("2030-05-15T10:00");
    await organizerGroupPage.locator("#ends_at").fill("2030-05-15T12:00");
    await organizerGroupPage
      .locator("#meeting_join_url")
      .fill("https://meet.example.com/e2e-recurring-event");
    await organizerGroupPage.locator("#recurrence_pattern").selectOption("weekly");
    await expect(
      organizerGroupPage.locator("#recurrence-additional-occurrences-container"),
    ).toBeVisible();
    await organizerGroupPage.locator("#recurrence_additional_occurrences").fill("2");

    const visibleAddEventButton = organizerGroupPage.locator(
      "#pending-changes-alert:not(.hidden) #add-event-button",
    );
    await expect(organizerGroupPage.locator("#pending-changes-alert")).not.toHaveClass(/hidden/);
    await expect(visibleAddEventButton).toBeVisible();

    await Promise.all([
      organizerGroupPage.waitForResponse(
        (response) =>
          response.request().method() === "POST" &&
          response.url().includes("/dashboard/group/events/add") &&
          response.status() === 201,
      ),
      visibleAddEventButton.click(),
    ]);

    const eventRows = dashboardContent.locator("tr", { hasText: eventName });
    await expect(eventRows).toHaveCount(3);

    const eventRow = eventRows.first();
    await eventRow.locator(".btn-actions").click();

    const deleteButton = eventRow.locator('button[id^="delete-event-"]');
    await expect(deleteButton).toBeVisible();
    await deleteButton.click();

    const seriesConfirmationDialog = organizerGroupPage.locator(".swal2-popup");
    await expect(seriesConfirmationDialog).toContainText(
      "This event is part of a recurring series. What would you like to delete?",
    );

    await Promise.all([
      organizerGroupPage.waitForResponse(
        (response) =>
          response.request().method() === "DELETE" &&
          response.url().includes("/dashboard/group/events/") &&
          response.url().includes("/delete") &&
          response.url().includes("scope=series") &&
          response.ok(),
      ),
      seriesConfirmationDialog.getByRole("button", { name: "All in series" }).click(),
    ]);

    await expect(dashboardContent.locator("tr", { hasText: eventName })).toHaveCount(0);
  });

  test("organizer can override recording urls for automatic event and session meetings", async ({
    organizerGroupPage,
  }) => {
    test.skip(!E2E_MEETINGS_ENABLED, "Automatic meetings are disabled in this environment.");

    const eventName = `E2E Automatic Recording Override ${Date.now()}`;
    const eventRecordingUrl = `https://youtube.com/watch?v=event-${Date.now()}`;
    const sessionName = `Session ${Date.now()}`;
    const sessionRecordingUrl = `https://youtube.com/watch?v=session-${Date.now()}`;

    await navigateToPath(organizerGroupPage, "/dashboard/group?tab=events");

    const dashboardContent = organizerGroupPage.locator("#dashboard-content");
    await expect(dashboardContent.getByText("Events", { exact: true })).toBeVisible();

    await dashboardContent.getByRole("button", { name: "Add Event" }).click();
    await expect(organizerGroupPage.locator("#name")).toBeVisible();

    await organizerGroupPage.locator("#name").fill(eventName);
    await organizerGroupPage.locator("#kind_id").selectOption("virtual");
    await organizerGroupPage.locator("#category_id").selectOption("33333333-3333-3333-3333-333333333331");
    await organizerGroupPage.locator("#description_short").fill("Automatic recording override coverage.");
    await fillMarkdownEditor(
      organizerGroupPage,
      "description",
      "Coverage for automatic event and session recording overrides.",
    );
    await organizerGroupPage.locator("#capacity").fill("25");

    await organizerGroupPage.locator('button[data-section="date-venue"]').click();
    await selectTimezone(organizerGroupPage, "UTC");
    await organizerGroupPage.locator("#starts_at").fill("2030-06-10T10:00");
    await organizerGroupPage.locator("#ends_at").fill("2030-06-10T12:00");

    const eventOnlineDetails = organizerGroupPage.locator("#online-event-details");
    await eventOnlineDetails.locator('input[type="radio"][value="automatic"]').check({
      force: true,
    });
    const recordMeetingLabel = eventOnlineDetails.getByText("Record meeting", { exact: true });
    const publishRecordingLabel = eventOnlineDetails.getByText("Publish recording publicly", {
      exact: true,
    });
    await expect(recordMeetingLabel).toBeVisible();
    await expect(publishRecordingLabel).toBeVisible();
    const [recordMeetingLabelBox, publishRecordingLabelBox] = await Promise.all([
      recordMeetingLabel.boundingBox(),
      publishRecordingLabel.boundingBox(),
    ]);
    if (!recordMeetingLabelBox || !publishRecordingLabelBox) {
      throw new Error("Recording visibility controls should be visible.");
    }
    expect(publishRecordingLabelBox.y).toBeGreaterThan(recordMeetingLabelBox.y);

    const eventRecordingPublishedInput = eventOnlineDetails.locator(
      'input[type="hidden"][name="meeting_recording_published"]',
    );
    const eventRecordingPublishedToggle = eventOnlineDetails.getByLabel(
      "Publish recording publicly",
    );
    await expect(eventRecordingPublishedInput).toHaveValue("false");
    await expect(eventRecordingPublishedToggle).not.toBeChecked();
    await eventRecordingPublishedToggle.check({ force: true });
    await expect(eventRecordingPublishedToggle).toBeChecked();
    await expect(eventRecordingPublishedInput).toHaveValue("true");

    await eventOnlineDetails
      .locator('input[type="url"][placeholder="https://youtube.com/watch?v=..."]')
      .fill(eventRecordingUrl);

    await organizerGroupPage.locator('button[data-section="sessions"]').click();
    const sessionsSection = organizerGroupPage.locator("sessions-section");
    const addSessionButton = sessionsSection.getByRole("button", { name: "Add session" });
    await expect(addSessionButton).toBeVisible();
    await addSessionButton.click();

    const sessionModal = organizerGroupPage.locator("session-form-modal");
    const sessionDialog = sessionModal.locator('[role="dialog"]');
    await expect(sessionDialog).toBeVisible();
    await sessionModal.locator('input[data-name="name"]').fill(sessionName);
    await sessionModal.locator('select[data-name="kind"]').selectOption("virtual");
    await sessionModal.locator('input[type="time"]').nth(0).fill("10:30");
    await sessionModal.locator('input[type="time"]').nth(1).fill("11:30");

    const sessionOnlineDetails = sessionModal.locator("online-event-details");
    await expect(sessionOnlineDetails).toHaveAttribute("kind", "virtual");
    await expect(sessionOnlineDetails).toHaveAttribute("starts-at", "2030-06-10T10:30");
    await expect(sessionOnlineDetails).toHaveAttribute("ends-at", "2030-06-10T11:30");
    await sessionOnlineDetails.getByText("Create meeting automatically", { exact: true }).click();
    await expect(sessionOnlineDetails.getByText("Meeting provider", { exact: true })).toBeVisible();
    const sessionRecordingPublishedInput = sessionOnlineDetails.locator(
      'input[type="hidden"][name="sessions[0][meeting_recording_published]"]',
    );
    const sessionRecordingPublishedToggle = sessionOnlineDetails.getByLabel(
      "Publish recording publicly",
    );
    await expect(sessionRecordingPublishedInput).toHaveValue("false");
    await expect(sessionRecordingPublishedToggle).not.toBeChecked();
    await sessionRecordingPublishedToggle.check({ force: true });
    await expect(sessionRecordingPublishedToggle).toBeChecked();
    await expect(sessionRecordingPublishedInput).toHaveValue("true");

    await sessionOnlineDetails
      .locator('input[type="url"][placeholder="https://youtube.com/watch?v=..."]')
      .fill(sessionRecordingUrl);
    await sessionModal.getByRole("button", { name: "Add session" }).click();
    await expect(sessionDialog).toBeHidden();
    await expect(
      sessionsSection.locator('input[name="sessions[0][meeting_recording_published]"]'),
    ).toHaveValue("true");

    const visibleAddEventButton = organizerGroupPage.locator(
      "#pending-changes-alert:not(.hidden) #add-event-button",
    );
    await expect(visibleAddEventButton).toBeVisible();

    await Promise.all([
      organizerGroupPage.waitForResponse(
        (response) =>
          response.request().method() === "POST" &&
          response.url().includes("/dashboard/group/events/add") &&
          response.status() === 201,
      ),
      visibleAddEventButton.click(),
    ]);

    await openEventUpdateFormByName(organizerGroupPage, eventName);

    await organizerGroupPage.locator('button[data-section="date-venue"]').click();
    await expect(
      eventOnlineDetails.locator('input[type="url"][placeholder="https://youtube.com/watch?v=..."]'),
    ).toHaveValue(eventRecordingUrl);
    await expect(eventOnlineDetails.getByLabel("Publish recording publicly")).toBeChecked();
    await expect(eventRecordingPublishedInput).toHaveValue("true");

    await organizerGroupPage.locator('button[data-section="sessions"]').click();
    const sessionCard = organizerGroupPage.locator("session-card").filter({
      hasText: sessionName,
    });
    await expect(sessionCard).toBeVisible();
    await sessionCard.locator('button[title="Edit"]').click();

    await expect(sessionDialog).toBeVisible();
    const reopenedSessionOnlineDetails = sessionModal.locator("online-event-details");
    await expect(
      reopenedSessionOnlineDetails.locator(
        'input[type="url"][placeholder="https://youtube.com/watch?v=..."]',
      ),
    ).toHaveValue(sessionRecordingUrl);
    await expect(
      reopenedSessionOnlineDetails.getByLabel("Publish recording publicly"),
    ).toBeChecked();
    await expect(
      reopenedSessionOnlineDetails.locator(
        'input[type="hidden"][name="sessions[0][meeting_recording_published]"]',
      ),
    ).toHaveValue("true");
    await sessionModal.getByRole("button", { name: "Cancel" }).click();
    await expect(sessionDialog).toBeHidden();
  });

  test("organizer does not see the payments tab when group payments are unavailable", async ({
    organizerGroupWithoutPaymentsPage,
  }) => {
    await navigateToPath(organizerGroupWithoutPaymentsPage, "/dashboard/group?tab=events");

    const dashboardContent = organizerGroupWithoutPaymentsPage.locator("#dashboard-content");
    await dashboardContent.getByRole("button", { name: "Add Event" }).click();

    await expect(organizerGroupWithoutPaymentsPage.locator('button[data-section="payments"]')).toHaveCount(0);
    await expect(organizerGroupWithoutPaymentsPage.locator('[data-content="payments"]')).toHaveCount(0);

    await navigateToPath(organizerGroupWithoutPaymentsPage, "/dashboard/group?tab=events");

    const eventRow = dashboardContent.locator("tr", { hasText: "Delta Event Two" });
    await expect(eventRow).toBeVisible();

    await Promise.all([
      organizerGroupWithoutPaymentsPage.waitForResponse(
        (response) =>
          response.request().method() === "GET" &&
          response.url().includes("/dashboard/group/events/") &&
          response.url().includes("/update") &&
          response.ok(),
      ),
      eventRow.locator('td button[aria-label^="Edit event:"]').click(),
    ]);

    await expect(organizerGroupWithoutPaymentsPage.locator('button[data-section="payments"]')).toHaveCount(0);
    await expect(organizerGroupWithoutPaymentsPage.locator('[data-content="payments"]')).toHaveCount(0);
  });

  test("organizer sees the payments tab when group payments are ready", async ({
    organizerGroupPage,
  }) => {
    test.skip(!E2E_PAYMENTS_ENABLED, "Payments are disabled in this environment.");

    await navigateToPath(organizerGroupPage, "/dashboard/group?tab=events");

    const dashboardContent = organizerGroupPage.locator("#dashboard-content");
    await dashboardContent.getByRole("button", { name: "Add Event" }).click();

    await expect(
      organizerGroupPage.locator('button[data-section="payments"]'),
    ).toBeVisible();
    await openPaymentsSection(organizerGroupPage);
    await expect(organizerGroupPage.locator("#payment_currency_code")).toBeVisible();
    await expect(organizerGroupPage.locator("#add-ticket-type-button")).toBeVisible();
    await expect(organizerGroupPage.locator("#add-discount-code-button")).toBeVisible();

    await navigateToPath(organizerGroupPage, "/dashboard/group?tab=events");
    await openEventUpdateFormByName(
      organizerGroupPage,
      TEST_PAYMENT_EVENT_NAMES.draft,
      TEST_PAYMENT_EVENT_IDS.draft,
    );

    await expect(
      organizerGroupPage.locator('button[data-section="payments"]'),
    ).toBeVisible();
    await openPaymentsSection(organizerGroupPage);
    await expect(organizerGroupPage.locator("#payment_currency_code")).toHaveValue("USD");
  });

  test("organizer can create a ticketed event with ticket tiers and discount codes", async ({
    organizerGroupPage,
  }) => {
    test.skip(!E2E_PAYMENTS_ENABLED, "Payments are disabled in this environment.");

    const eventName = `E2E Ticketed Event ${Date.now()}`;

    await navigateToPath(organizerGroupPage, "/dashboard/group?tab=events");

    const dashboardContent = organizerGroupPage.locator("#dashboard-content");
    await dashboardContent.getByRole("button", { name: "Add Event" }).click();

    await organizerGroupPage.locator("#name").fill(eventName);
    await organizerGroupPage.locator("#kind_id").selectOption("virtual");
    await organizerGroupPage
      .locator("#category_id")
      .selectOption("33333333-3333-3333-3333-333333333331");
    await organizerGroupPage.locator("#description_short").fill(
      "Ticketed dashboard event for payment coverage.",
    );
    await fillMarkdownEditor(
      organizerGroupPage,
      "description",
      "Ticketed dashboard event used to cover ticket tiers and discount codes.",
    );
    await organizerGroupPage.locator("#capacity").fill("25");
    await organizerGroupPage.locator("#toggle_waitlist_enabled").check({ force: true });

    await organizerGroupPage.locator('button[data-section="date-venue"]').click();
    await selectTimezone(organizerGroupPage, "UTC");
    await organizerGroupPage.locator("#starts_at").fill("2030-11-12T18:00");
    await organizerGroupPage.locator("#ends_at").fill("2030-11-12T20:00");
    if (E2E_MEETINGS_ENABLED) {
      await enableAutomaticMeetingCreation(organizerGroupPage);
    } else {
      await organizerGroupPage.locator("#meeting_join_url").fill(
        "https://meet.example.com/e2e-ticketed-event",
      );
    }

    await openPaymentsSection(organizerGroupPage);

    await addTicketType(organizerGroupPage, {
      title: "Free community pass",
      description: "Free tier used for zero-price coverage.",
      seatsTotal: "12",
      priceWindows: [{ amount: "0" }],
    });

    const paymentCurrencyInput = organizerGroupPage.locator("#payment_currency_code");
    await expect(paymentCurrencyInput).toHaveJSProperty("required", true);
    const validationMessage = await paymentCurrencyInput.evaluate(
      (element) => (element as HTMLSelectElement).validationMessage,
    );
    expect(validationMessage).toBe("Ticketed events require an event currency.");

    await expect(organizerGroupPage.locator("#toggle_waitlist_enabled")).toBeDisabled();
    await expect(organizerGroupPage.locator("#waitlist_enabled")).toHaveValue("false");
    await expect(organizerGroupPage.locator("#capacity")).toBeDisabled();
    await expect(organizerGroupPage.locator("#capacity")).toHaveValue("12");

    await paymentCurrencyInput.selectOption("USD");

    await addTicketType(organizerGroupPage, {
      title: "General admission",
      description: "Paid tier with early-bird pricing.",
      seatsTotal: "30",
      priceWindows: [
        { amount: "2500", endsAt: "2030-10-01T23:59" },
        { amount: "3000", startsAt: "2030-10-02T00:00" },
      ],
    });

    await expect(organizerGroupPage.locator("#capacity")).toHaveValue("42");

    await addDiscountCode(organizerGroupPage, {
      title: "Launch savings",
      code: "SAVE10",
      kind: "fixed_amount",
      amount: "1000",
    });
    await addDiscountCode(organizerGroupPage, {
      title: "Early supporter",
      code: "EARLY20",
      kind: "percentage",
      percentage: "20",
      totalAvailable: "50",
    });

    const visibleAddEventButton = organizerGroupPage.locator(
      "#pending-changes-alert:not(.hidden) #add-event-button",
    );
    await expect(visibleAddEventButton).toBeVisible();

    await Promise.all([
      organizerGroupPage.waitForResponse(
        (response) =>
          response.request().method() === "POST" &&
          response.url().includes("/dashboard/group/events/add") &&
          response.status() === 201,
      ),
      visibleAddEventButton.click(),
    ]);

    const eventRow = dashboardContent.locator("tr", { hasText: eventName });
    await expect(eventRow).toBeVisible();
    await organizerGroupPage.getByRole("button", { name: "OK" }).click();
    await expect(organizerGroupPage.locator(".swal2-popup")).toHaveCount(0);

    await openEventUpdateFormByName(organizerGroupPage, eventName);
    await organizerGroupPage.locator('button[data-section="date-venue"]').click();

    if (E2E_MEETINGS_ENABLED) {
      await expectAutomaticMeetingControls(organizerGroupPage);
      await expect(
        organizerGroupPage.locator('online-event-details input[name="meeting_requested"]'),
      ).toHaveValue("true");
    } else {
      await expect(organizerGroupPage.locator("#meeting_join_url")).toHaveValue(
        "https://meet.example.com/e2e-ticketed-event",
      );
    }

    await openPaymentsSection(organizerGroupPage);

    await expect(organizerGroupPage.locator("#payment_currency_code")).toHaveValue("USD");
    await expect(
      organizerGroupPage.locator('#ticket-types-ui [data-ticketing-role="table-body"]'),
    ).toContainText("Free community pass");
    await expect(
      organizerGroupPage.locator('#ticket-types-ui [data-ticketing-role="table-body"]'),
    ).toContainText("General admission");
    await expect(
      organizerGroupPage.locator('#discount-codes-ui [data-ticketing-role="table-body"]'),
    ).toContainText("SAVE10");
    await expect(
      organizerGroupPage.locator('#discount-codes-ui [data-ticketing-role="table-body"]'),
    ).toContainText("EARLY20");

    await navigateToPath(organizerGroupPage, "/dashboard/group?tab=events");
    await eventRow.locator(".btn-actions").click();

    const deleteButton = eventRow.locator('button[id^="delete-event-"]');
    await expect(deleteButton).toBeVisible();
    await deleteButton.click();
    await expect(organizerGroupPage.locator(".swal2-popup")).toContainText(
      "Are you sure you wish to delete this event?",
    );

    await Promise.all([
      organizerGroupPage.waitForResponse(
        (response) =>
          response.request().method() === "DELETE" &&
          response.url().includes("/dashboard/group/events/") &&
          response.url().includes("/delete") &&
          response.ok(),
      ),
      organizerGroupPage.getByRole("button", { name: "Yes" }).click(),
    ]);

    await expect(dashboardContent.locator("tr", { hasText: eventName })).toHaveCount(0);
  });

  test("organizer sees seeded ticketing values on a payment-ready event", async ({
    organizerGroupPage,
  }) => {
    test.skip(!E2E_PAYMENTS_ENABLED, "Payments are disabled in this environment.");

    await navigateToPath(organizerGroupPage, "/dashboard/group?tab=events");
    await openEventUpdateFormByName(
      organizerGroupPage,
      TEST_PAYMENT_EVENT_NAMES.draft,
      TEST_PAYMENT_EVENT_IDS.draft,
    );
    await openPaymentsSection(organizerGroupPage);

    await expect(organizerGroupPage.locator("#payment_currency_code")).toHaveValue("USD");
    await expect(organizerGroupPage.locator("#capacity")).toBeDisabled();
    await expect(organizerGroupPage.locator("#capacity")).toHaveValue("42");
    await expect(organizerGroupPage.locator("#toggle_waitlist_enabled")).toBeDisabled();
    await expect(organizerGroupPage.locator("#waitlist_enabled")).toHaveValue("false");
    await expect(
      organizerGroupPage.locator('#ticket-types-ui [data-ticketing-role="table-body"]'),
    ).toContainText("General admission");
    await expect(
      organizerGroupPage.locator('#ticket-types-ui [data-ticketing-role="table-body"]'),
    ).toContainText("Community ticket");
    await expect(
      organizerGroupPage.locator('#ticket-types-ui [data-ticketing-role="table-body"]'),
    ).toContainText("Backstage pass");
    await expect(
      organizerGroupPage.locator('#discount-codes-ui [data-ticketing-role="table-body"]'),
    ).toContainText("SAVE10");
    await expect(
      organizerGroupPage.locator('#discount-codes-ui [data-ticketing-role="table-body"]'),
    ).toContainText("EARLY20");
  });

  test("organizer sees seats and status columns in the ticket types table", async ({
    organizerGroupPage,
  }) => {
    test.skip(!E2E_PAYMENTS_ENABLED, "Payments are disabled in this environment.");

    await navigateToPath(organizerGroupPage, "/dashboard/group?tab=events");
    await openEventUpdateFormByName(
      organizerGroupPage,
      TEST_PAYMENT_EVENT_NAMES.draft,
      TEST_PAYMENT_EVENT_IDS.draft,
    );
    await openPaymentsSection(organizerGroupPage);

    const ticketTypesTable = organizerGroupPage.locator("#ticket-types-ui table");
    const generalAdmissionRow = ticketTypesTable.locator("tbody tr", {
      hasText: "General admission",
    });

    await expect(ticketTypesTable.locator("thead th").nth(1)).toBeVisible();
    await expect(ticketTypesTable.locator("thead th").nth(1)).toContainText("Seats");
    await expect(ticketTypesTable.locator("thead th").nth(2)).toBeVisible();
    await expect(ticketTypesTable.locator("thead th").nth(2)).toContainText("Status");
    await expect(generalAdmissionRow.locator("td").nth(1)).toBeVisible();
    await expect(generalAdmissionRow.locator("td").nth(2)).toBeVisible();
  });

  test("organizer can create, update, and delete an event with images and rich fields", async ({
    organizerGroupPage,
  }) => {
    const initialValues = {
      bannerMobilePath: TEST_UPLOAD_ASSET_PATHS.bannerMobile,
      bannerPath: TEST_UPLOAD_ASSET_PATHS.banner,
      capacity: "120",
      categoryId: "33333333-3333-3333-3333-333333333331",
      cfsDescription: "Initial speaker program details for a temporary event.",
      cfsEndsAt: "2030-09-20T17:00",
      cfsLabels: ["track / platform"],
      cfsStartsAt: "2030-09-01T09:00",
      description: "Initial full description for a temporary event with rich form coverage.",
      descriptionShort: "Initial temporary event for rich update coverage.",
      endsAt: "2030-10-05T13:30",
      eventReminderEnabled: true,
      galleryPaths: [TEST_UPLOAD_ASSET_PATHS.galleryOne],
      kindId: "hybrid",
      logoPath: TEST_UPLOAD_ASSET_PATHS.logo,
      meetupUrl: "https://meetup.com/e2e-rich-event-initial",
      meetingJoinUrl: "https://meet.example.com/e2e-rich-event-initial",
      meetingRecordingUrl: "https://video.example.com/e2e-rich-event-initial",
      name: `E2E Rich Event ${Date.now()}`,
      registrationRequired: true,
      startsAt: "2030-10-05T10:00",
      tags: ["meetup", "platform"],
      timezone: "UTC",
      venueAddress: "123 Platform Street",
      venueCity: "Barcelona",
      venueLatitude: "41.3874",
      venueLongitude: "2.1686",
      venueName: "Platform Hall",
      venueZipCode: "08001",
      waitlistEnabled: true,
    };
    const updatedValues = {
      bannerMobilePath: TEST_UPLOAD_ASSET_PATHS.bannerMobile,
      bannerPath: TEST_UPLOAD_ASSET_PATHS.banner,
      capacity: "180",
      categoryId: "33333333-3333-3333-3333-333333333331",
      cfsDescription: "Updated speaker program details for a temporary event.",
      cfsEndsAt: "2030-09-24T18:00",
      cfsLabels: ["track / devex", "track / cloud"],
      cfsStartsAt: "2030-09-03T10:30",
      description: "Updated full description for a temporary event with rich form coverage.",
      descriptionShort: "Updated temporary event for rich update coverage.",
      endsAt: "2030-10-08T18:00",
      eventReminderEnabled: false,
      galleryPaths: [TEST_UPLOAD_ASSET_PATHS.galleryTwo],
      kindId: "hybrid",
      logoPath: TEST_UPLOAD_ASSET_PATHS.logo,
      meetupUrl: "https://meetup.com/e2e-rich-event-updated",
      meetingJoinUrl: "https://meet.example.com/e2e-rich-event-updated",
      meetingRecordingUrl: "https://video.example.com/e2e-rich-event-updated",
      name: `E2E Rich Event Updated ${Date.now()}`,
      registrationRequired: false,
      startsAt: "2030-10-08T14:00",
      tags: ["conference", "cloud"],
      timezone: "Europe/Madrid",
      venueAddress: "456 Cloud Avenue",
      venueCity: "Madrid",
      venueLatitude: "40.4168",
      venueLongitude: "-3.7038",
      venueName: "Cloud Forum",
      venueZipCode: "28001",
      waitlistEnabled: false,
    };

    const fillEventForm = async (values: typeof initialValues) => {
      await organizerGroupPage.locator("#name").fill(values.name);
      await organizerGroupPage.locator("#kind_id").selectOption(values.kindId);
      await organizerGroupPage.locator("#category_id").selectOption(values.categoryId);
      await uploadImageField(organizerGroupPage, "logo_url", values.logoPath);
      await uploadImageField(organizerGroupPage, "banner_url", values.bannerPath);
      await uploadImageField(organizerGroupPage, "banner_mobile_url", values.bannerMobilePath);
      await organizerGroupPage.locator("#description_short").fill(values.descriptionShort);
      await fillMarkdownEditor(organizerGroupPage, "description", values.description);
      await organizerGroupPage.locator("#capacity").fill(values.capacity);
      if (values.registrationRequired) {
        await organizerGroupPage.locator("#toggle_registration_required").check({ force: true });
      } else {
        await organizerGroupPage.locator("#toggle_registration_required").uncheck({ force: true });
      }
      if (values.waitlistEnabled) {
        await organizerGroupPage.locator("#toggle_waitlist_enabled").check({ force: true });
      } else {
        await organizerGroupPage.locator("#toggle_waitlist_enabled").uncheck({ force: true });
      }
      await organizerGroupPage.locator("#meetup_url").fill(values.meetupUrl);
      await fillMultipleInputs(organizerGroupPage.locator('multiple-inputs[field-name="tags"]'), values.tags);
      await uploadGalleryImages(organizerGroupPage, "photos_urls", values.galleryPaths);

      await organizerGroupPage.locator('button[data-section="date-venue"]').click({
        force: true,
      });
      await selectTimezone(organizerGroupPage, values.timezone);
      await organizerGroupPage.locator("#starts_at").fill(values.startsAt);
      await organizerGroupPage.locator("#ends_at").fill(values.endsAt);
      if (values.eventReminderEnabled) {
        await organizerGroupPage.locator("#toggle_event_reminder_enabled").check({ force: true });
      } else {
        await organizerGroupPage.locator("#toggle_event_reminder_enabled").uncheck({ force: true });
      }
      await fillEventVenue(organizerGroupPage, {
        address: values.venueAddress,
        city: values.venueCity,
        latitude: values.venueLatitude,
        longitude: values.venueLongitude,
        name: values.venueName,
        zipCode: values.venueZipCode,
      });
      await organizerGroupPage.locator("#meeting_join_url").fill(values.meetingJoinUrl);
      await organizerGroupPage.locator("#meeting_recording_url").fill(values.meetingRecordingUrl);

      const cfsSectionButton = organizerGroupPage.locator('button[data-section="cfs"]');
      await cfsSectionButton.scrollIntoViewIfNeeded();
      await cfsSectionButton.click({ force: true });
      await organizerGroupPage.locator("#toggle_cfs_enabled").check({ force: true });
      await organizerGroupPage.locator("#cfs_starts_at").fill(values.cfsStartsAt, {
        force: true,
      });
      await organizerGroupPage.locator("#cfs_ends_at").fill(values.cfsEndsAt, {
        force: true,
      });
      await fillMarkdownEditor(organizerGroupPage, "cfs_description", values.cfsDescription);
      await setCfsLabels(organizerGroupPage, values.cfsLabels);
    };

    const openEventUpdateForm = async (eventRow: Locator) => {
      await Promise.all([
        organizerGroupPage.waitForResponse(
          (response) =>
            response.request().method() === "GET" &&
            response.url().includes("/dashboard/group/events/") &&
            response.url().includes("/update") &&
            response.ok(),
        ),
        eventRow.locator('td button[aria-label^="Edit event:"]').click(),
      ]);
    };

    await navigateToPath(organizerGroupPage, "/dashboard/group?tab=events");

    const dashboardContent = organizerGroupPage.locator("#dashboard-content");
    await expect(dashboardContent.getByText("Events", { exact: true })).toBeVisible();

    await dashboardContent.getByRole("button", { name: "Add Event" }).click();
    await expect(organizerGroupPage.locator("#name")).toBeVisible();

    await fillEventForm(initialValues);

    const addEventButton = organizerGroupPage.locator(
      "#pending-changes-alert:not(.hidden) #add-event-button",
    );
    await expect(addEventButton).toBeVisible();

    await Promise.all([
      organizerGroupPage.waitForResponse(
        (response) =>
          response.request().method() === "POST" &&
          response.url().includes("/dashboard/group/events/add") &&
          response.status() === 201,
      ),
      addEventButton.click(),
    ]);

    let eventRow = dashboardContent.locator("tr", { hasText: initialValues.name });
    await expect(eventRow).toBeVisible();

    await openEventUpdateForm(eventRow);
    await fillEventForm(updatedValues);

    await Promise.all([
      organizerGroupPage.waitForResponse(
        (response) =>
          response.request().method() === "PUT" &&
          response.url().includes("/dashboard/group/events/") &&
          response.url().includes("/update") &&
          response.ok(),
      ),
      organizerGroupPage.locator("#update-event-button").click(),
    ]);

    eventRow = dashboardContent.locator("tr", { hasText: updatedValues.name });
    await expect(eventRow).toBeVisible();

    await openEventUpdateForm(eventRow);
    await expect(organizerGroupPage.locator("#name")).toHaveValue(updatedValues.name);
    await expect(organizerGroupPage.locator("#kind_id")).toHaveValue(updatedValues.kindId);
    await expect(organizerGroupPage.locator("#category_id")).toHaveValue(updatedValues.categoryId);
    await expect
      .poll(async () => (await organizerGroupPage.locator("#description_short").inputValue()).trim())
      .toBe(updatedValues.descriptionShort);
    await expect(organizerGroupPage.locator("#capacity")).toHaveValue(updatedValues.capacity);
    await expect(organizerGroupPage.locator("#registration_required")).toHaveValue(
      String(updatedValues.registrationRequired),
    );
    await expect(organizerGroupPage.locator("#waitlist_enabled")).toHaveValue(
      String(updatedValues.waitlistEnabled),
    );
    await expect(organizerGroupPage.locator("#meetup_url")).toHaveValue(updatedValues.meetupUrl);
    await expect(
      organizerGroupPage.locator('image-field[name="logo_url"] input[name="logo_url"]'),
    ).toHaveValue(/\/images\//);
    await expect(
      organizerGroupPage.locator('image-field[name="banner_url"] input[name="banner_url"]'),
    ).toHaveValue(/\/images\//);
    await expect(
      organizerGroupPage.locator('image-field[name="banner_mobile_url"] input[name="banner_mobile_url"]'),
    ).toHaveValue(/\/images\//);
    await expect(
      organizerGroupPage.locator('multiple-inputs[field-name="tags"] input[name="tags[]"]'),
    ).toHaveCount(updatedValues.tags.length);
    await organizerGroupPage.locator('button[data-section="date-venue"]').click();
    await expect(organizerGroupPage.locator('input[name="timezone"]')).toHaveValue(updatedValues.timezone);
    await expect(organizerGroupPage.locator("#starts_at")).toHaveValue(updatedValues.startsAt);
    await expect(organizerGroupPage.locator("#ends_at")).toHaveValue(updatedValues.endsAt);
    await expect(organizerGroupPage.locator("#event_reminder_enabled")).toHaveValue(
      String(updatedValues.eventReminderEnabled),
    );
    await expect(organizerGroupPage.locator("#location-search-venue_name")).toHaveValue(
      updatedValues.venueName,
    );
    await expect(organizerGroupPage.locator("#location-search-venue_address")).toHaveValue(
      updatedValues.venueAddress,
    );
    await expect(organizerGroupPage.locator("#location-search-venue_city")).toHaveValue(
      updatedValues.venueCity,
    );
    await expect(organizerGroupPage.locator("#meeting_join_url")).toHaveValue(updatedValues.meetingJoinUrl);
    await expect(organizerGroupPage.locator("#meeting_recording_url")).toHaveValue(
      updatedValues.meetingRecordingUrl,
    );
    await organizerGroupPage.locator('button[data-section="cfs"]').click();
    await expect(organizerGroupPage.locator("#cfs_enabled")).toHaveValue("true");
    await expect(organizerGroupPage.locator("#cfs_starts_at")).toHaveValue(updatedValues.cfsStartsAt);
    await expect(organizerGroupPage.locator("#cfs_ends_at")).toHaveValue(updatedValues.cfsEndsAt);
    await expect(organizerGroupPage.locator('cfs-labels-editor input[name$="[name]"]')).toHaveCount(
      updatedValues.cfsLabels.length,
    );
    await expect(
      organizerGroupPage.locator('gallery-field[field-name="photos_urls"] input[name="photos_urls[]"]'),
    ).toHaveCount(initialValues.galleryPaths.length + updatedValues.galleryPaths.length);

    await navigateToPath(organizerGroupPage, "/dashboard/group?tab=events");
    eventRow = dashboardContent.locator("tr", { hasText: updatedValues.name });
    await expect(eventRow).toBeVisible();

    await eventRow.locator(".btn-actions").click();

    const deleteButton = eventRow.locator('button[id^="delete-event-"]');
    await expect(deleteButton).toBeVisible();

    await Promise.all([
      organizerGroupPage.waitForResponse(
        (response) =>
          response.request().method() === "DELETE" &&
          response.url().includes("/dashboard/group/events/") &&
          response.url().includes("/delete") &&
          response.ok(),
      ),
      deleteButton.click(),
      organizerGroupPage.getByRole("button", { name: "Yes" }).click(),
    ]);

    await expect(dashboardContent.locator("tr", { hasText: updatedValues.name })).toHaveCount(0);
  });

  test("organizer can unpublish and publish an event from the list", async ({ organizerGroupPage }) => {
    await navigateToPath(organizerGroupPage, "/dashboard/group?tab=events");

    const dashboardContent = organizerGroupPage.locator("#dashboard-content");
    const eventRow = dashboardContent.locator("tr", {
      hasText: "Upcoming In-Person Event",
    });
    await expect(eventRow).toBeVisible();
    await expect(eventRow).toContainText("Published");

    const actionsButton = eventRow.locator(`.btn-actions[data-event-id="${TEST_EVENT_IDS.alpha.one}"]`);
    await actionsButton.click();

    const unpublishButton = organizerGroupPage.locator(`#unpublish-event-${TEST_EVENT_IDS.alpha.one}`);
    await expect(unpublishButton).toBeVisible();

    await Promise.all([
      organizerGroupPage.waitForResponse(
        (response) =>
          response.request().method() === "PUT" &&
          response.url().includes(`/dashboard/group/events/${TEST_EVENT_IDS.alpha.one}/unpublish`) &&
          response.ok(),
      ),
      unpublishButton.click(),
      organizerGroupPage.getByRole("button", { name: "Yes" }).click(),
    ]);

    await expect(eventRow).toContainText("Draft");

    await eventRow.locator(`.btn-actions[data-event-id="${TEST_EVENT_IDS.alpha.one}"]`).click();

    const publishButton = organizerGroupPage.locator(`#publish-event-${TEST_EVENT_IDS.alpha.one}`);
    await expect(publishButton).toBeVisible();

    await Promise.all([
      organizerGroupPage.waitForResponse(
        (response) =>
          response.request().method() === "PUT" &&
          response.url().includes(`/dashboard/group/events/${TEST_EVENT_IDS.alpha.one}/publish`) &&
          response.ok(),
      ),
      publishButton.click(),
      organizerGroupPage.getByRole("button", { name: "Yes" }).click(),
    ]);

    await expect(eventRow).toContainText("Published");
  });

  test("organizer can update and restore event fields across multiple tabs", async ({
    organizerGroupPage,
  }) => {
    const cfsSummitPath = `/${TEST_COMMUNITY_NAME}/group/${TEST_GROUP_SLUGS.community1.alpha}/event/${TEST_EVENT_SLUGS.alphaDashboard[0]}`;
    const shiftDateTimeLocalMinutes = (value: string, minutes: number) => {
      const shiftedDate = new Date(`${value}:00Z`);
      shiftedDate.setUTCMinutes(shiftedDate.getUTCMinutes() + minutes);

      return shiftedDate.toISOString().slice(0, 16);
    };

    const openCfsSummitEditor = async () => {
      await navigateToPath(organizerGroupPage, "/dashboard/group?tab=events");

      const eventRow = organizerGroupPage.locator("tr").filter({
        has: organizerGroupPage.locator(`a[href="${cfsSummitPath}"]`),
      });
      await expect(eventRow).toBeVisible();

      await Promise.all([
        organizerGroupPage.waitForResponse(
          (response) =>
            response.request().method() === "GET" &&
            response.url().includes(`/dashboard/group/events/${TEST_EVENT_IDS.alpha.cfsSummit}/update`) &&
            response.ok(),
        ),
        eventRow
          .locator(`td button[hx-get="/dashboard/group/events/${TEST_EVENT_IDS.alpha.cfsSummit}/update"]`)
          .click(),
      ]);
    };

    const readEventValues = async () => {
      await openCfsSummitEditor();

      return {
        cfsEndsAt: await organizerGroupPage.locator("#cfs_ends_at").inputValue(),
        cfsStartsAt: await organizerGroupPage.locator("#cfs_starts_at").inputValue(),
        endsAt: await organizerGroupPage.locator("#ends_at").inputValue(),
        meetupUrl: await organizerGroupPage.locator("#meetup_url").inputValue(),
        name: await organizerGroupPage.locator("#name").inputValue(),
        startsAt: await organizerGroupPage.locator("#starts_at").inputValue(),
      };
    };

    const saveUpdatedValues = async (values: {
      cfsEndsAt: string;
      cfsStartsAt: string;
      endsAt: string;
      meetupUrl: string;
      name: string;
      startsAt: string;
    }) => {
      await openCfsSummitEditor();

      await organizerGroupPage.locator("#name").fill(values.name);
      await organizerGroupPage.locator("#meetup_url").fill(values.meetupUrl);

      await organizerGroupPage.locator('button[data-section="date-venue"]').click();
      await expect(organizerGroupPage.locator("#starts_at")).toBeVisible();
      await organizerGroupPage.locator("#starts_at").fill(values.startsAt);
      await organizerGroupPage.locator("#ends_at").fill(values.endsAt);

      await organizerGroupPage.locator('button[data-section="cfs"]').click();
      await expect(organizerGroupPage.locator("#cfs_starts_at")).toBeVisible();
      await organizerGroupPage.locator("#cfs_starts_at").fill(values.cfsStartsAt);
      await organizerGroupPage.locator("#cfs_ends_at").fill(values.cfsEndsAt);
      await expect(organizerGroupPage.locator("#pending-changes-alert")).not.toHaveClass(/hidden/);

      await Promise.all([
        organizerGroupPage.waitForResponse(
          (response) =>
            response.request().method() === "PUT" &&
            response.url().includes(`/dashboard/group/events/${TEST_EVENT_IDS.alpha.cfsSummit}/update`) &&
            response.ok(),
        ),
        organizerGroupPage.locator("#update-event-button").click(),
      ]);
    };

    const originalValues = await readEventValues();
    const updatedValues = {
      cfsEndsAt: shiftDateTimeLocalMinutes(originalValues.cfsEndsAt, 60),
      cfsStartsAt: shiftDateTimeLocalMinutes(originalValues.cfsStartsAt, 60),
      endsAt: shiftDateTimeLocalMinutes(originalValues.endsAt, -30),
      meetupUrl: "https://meetup.com/e2e-alpha-cfs-summit",
      name: `Event With Active CFS ${Date.now()}`,
      startsAt: shiftDateTimeLocalMinutes(originalValues.startsAt, 30),
    };

    await saveUpdatedValues(updatedValues);

    await openCfsSummitEditor();
    await expect(organizerGroupPage.locator("#name")).toHaveValue(updatedValues.name);
    await expect(organizerGroupPage.locator("#meetup_url")).toHaveValue(updatedValues.meetupUrl);
    await organizerGroupPage.locator('button[data-section="date-venue"]').click();
    await expect(organizerGroupPage.locator("#starts_at")).toHaveValue(updatedValues.startsAt);
    await expect(organizerGroupPage.locator("#ends_at")).toHaveValue(updatedValues.endsAt);
    await organizerGroupPage.locator('button[data-section="cfs"]').click();
    await expect(organizerGroupPage.locator("#cfs_starts_at")).toHaveValue(updatedValues.cfsStartsAt);
    await expect(organizerGroupPage.locator("#cfs_ends_at")).toHaveValue(updatedValues.cfsEndsAt);

    await saveUpdatedValues(originalValues);
  });

  test("organizer is warned before removing dates from an event with sessions", async ({
    organizerGroupPage,
  }) => {
    const alphaEventPath = `/${TEST_COMMUNITY_NAME}/group/${TEST_GROUP_SLUGS.community1.alpha}/event/${TEST_EVENT_SLUGS.alpha[0]}`;

    await navigateToPath(organizerGroupPage, "/dashboard/group?tab=events");

    const eventRow = organizerGroupPage.locator("tr").filter({
      has: organizerGroupPage.locator(`a[href="${alphaEventPath}"]`),
    });
    await expect(eventRow).toBeVisible();

    await Promise.all([
      organizerGroupPage.waitForResponse(
        (response) =>
          response.request().method() === "GET" &&
          response.url().includes(`/dashboard/group/events/${TEST_EVENT_IDS.alpha.one}/update`) &&
          response.ok(),
      ),
      eventRow
        .locator(`td button[hx-get="/dashboard/group/events/${TEST_EVENT_IDS.alpha.one}/update"]`)
        .click(),
    ]);

    await organizerGroupPage.locator('button[data-section="date-venue"]').click();
    await expect(organizerGroupPage.locator("#starts_at")).toBeVisible();
    await organizerGroupPage.locator("#starts_at").fill("");
    await organizerGroupPage.locator("#ends_at").fill("");

    await expect(organizerGroupPage.locator("#pending-changes-alert")).not.toHaveClass(/hidden/);

    await organizerGroupPage.locator("#update-event-button").click();

    const confirmationDialog = organizerGroupPage.locator(".swal2-popup");
    await expect(confirmationDialog).toContainText(
      "Saving this event without start and end dates will remove all sessions.",
    );

    await confirmationDialog.getByRole("button", { name: "No" }).click();
  });
});
