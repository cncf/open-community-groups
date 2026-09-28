import { expect } from "../../../fixtures.js";

import { TEST_COMMUNITY_IDS } from "../../../seed.js";
import { futureDate, navigateToPath, selectTimezone, waitForActionResponse } from "../../../utils.js";
import { fillMarkdownEditor } from "../../form-helpers.js";

// Confirmation button labels by co-host action.
const ACTION_CONFIRM_LABELS = {
  approve: "Approve",
  cancel: "Cancel co-hosting",
  reject: "Reject",
};
// Dashboard statuses shown after each co-host action succeeds.
const ACTION_RESULT_STATUSES = {
  approve: "Approved",
  cancel: "Canceled",
  reject: "Rejected",
};
// Seeded event category used by co-hosting drafts.
const EVENT_CATEGORY_ID = "33333333-3333-3333-3333-333333333331";
// Group options endpoint used by the event editor co-host selector.
const GROUP_OPTIONS_PATH = "/dashboard/group/events/cohosts/groups";

/**
 * Selects a group from another community in the event editor co-hosts section.
 * @param {import("@playwright/test").Page} page - Playwright page with an open event editor.
 * @param {{ communityId?: string, groupId: string, groupName: string, search: string }} group - Group to add.
 * @returns {Promise<void>}
 */
export const addCohostThroughEditor = async (
  page,
  { communityId = TEST_COMMUNITY_IDS.community2, groupId, groupName, search },
) => {
  await openCohostsSection(page);
  const cohostsSelector = getCohostsSelector(page);

  // Load the target community group options.
  await Promise.all([
    waitForGroupOptions(page, communityId),
    cohostsSelector.getByLabel("Community", { exact: true }).selectOption(communityId),
  ]);

  // Search and pick the matching group option.
  const groupSearch = getCohostGroupSearch(page);
  await expect(groupSearch).toBeEnabled();
  await groupSearch.fill(search);
  const cohostOption = cohostsSelector.getByRole("option", { name: new RegExp(groupName, "u") });
  await expect(cohostOption).toBeVisible();
  await cohostOption.click();

  // Verify the selection is rendered and staged for submission.
  await expect(cohostsSelector.getByRole("button", { name: `Remove ${groupName}` })).toBeVisible();
  await expect(cohostsSelector.locator(`input[type="hidden"][value="${groupId}"]`)).toHaveCount(1);
};

/**
 * Finds a co-host dashboard row and verifies its current status.
 * @param {import("@playwright/test").Page} page - Playwright page showing the co-hosts tab.
 * @param {string} eventName - Event name shown in the row.
 * @param {string} status - Expected status label.
 * @returns {Promise<import("@playwright/test").Locator>} Matching row.
 */
export const expectCohostDashboardRow = async (page, eventName, status) => {
  const row = getCohostDashboardRows(page, eventName).first();
  await expect(row).toBeVisible();
  await expect(row).toContainText(status);
  return row;
};

/**
 * Fills the minimum add-event fields required to create a future virtual draft.
 * @param {import("@playwright/test").Page} page - Playwright page with the add-event form open.
 * @param {string} eventName - Event name.
 * @param {{ additionalOccurrences?: number, days: number }} schedule - Start offset and weekly repeats.
 * @returns {Promise<void>}
 */
export const fillVirtualEventDraft = async (page, eventName, { additionalOccurrences = 0, days }) => {
  // Fill the event details.
  await page.locator("#name").fill(eventName);
  await page.locator("#kind_id").selectOption("virtual");
  await page.locator("#category_id").selectOption(EVENT_CATEGORY_ID);
  await page.locator("#description_short").fill("A co-hosting workflow event from the e2e suite.");
  await fillMarkdownEditor(page, "description", "A co-hosting workflow event created by the e2e suite.");

  // Fill the schedule and virtual meeting link.
  await page.locator('button[data-section="date-venue"]').click();
  await expect(page.locator('button[data-section="date-venue"]')).toHaveAttribute("data-active", "true");
  await selectTimezone(page, "UTC");
  await page.locator("#starts_at").fill(futureDate({ days, hour: 10 }));
  await page.locator("#ends_at").fill(futureDate({ days, hour: 12 }));
  await page.locator("#meeting_join_url").fill("https://meet.example.com/e2e-co-hosting");

  // Repeat the event weekly when a series is requested.
  if (additionalOccurrences > 0) {
    await page.locator("#recurrence_pattern").selectOption("weekly");
    await expect(page.locator("#recurrence-additional-occurrences-container")).toBeVisible();
    await page.locator("#recurrence_additional_occurrences").fill(String(additionalOccurrences));
  }
};

/**
 * Returns the co-host dashboard rows for one event name.
 * @param {import("@playwright/test").Page} page - Playwright page showing the co-hosts tab.
 * @param {string} eventName - Event name shown in the rows.
 * @returns {import("@playwright/test").Locator} Matching rows.
 */
export const getCohostDashboardRows = (page, eventName) =>
  page.getByRole("table", { name: "Co-hosted events list" }).locator("tbody tr", { hasText: eventName });

/**
 * Returns the co-host group search input inside the event editor.
 * @param {import("@playwright/test").Page} page - Playwright page with an open event editor.
 * @returns {import("@playwright/test").Locator} Group search input.
 */
export const getCohostGroupSearch = (page) =>
  getCohostsSelector(page).getByRole("combobox", { name: "Co-host group" });

/**
 * Returns the co-hosts selector inside the event editor.
 * @param {import("@playwright/test").Page} page - Playwright page with an open event editor.
 * @returns {import("@playwright/test").Locator} Co-hosts selector element.
 */
export const getCohostsSelector = (page) => page.locator("#cohosts-form cohosts-selector");

/**
 * Returns the selected co-host card identified by its remove button.
 * @param {import("@playwright/test").Page} page - Playwright page with an open event editor.
 * @param {string} groupName - Selected group name.
 * @returns {import("@playwright/test").Locator} Selected co-host card.
 */
export const getSelectedCohostCard = (page, groupName) =>
  // Cards are unlabeled containers, so the deepest ancestor holding the remove button is the card.
  getCohostsSelector(page)
    .locator("div")
    .filter({ has: page.getByRole("button", { name: `Remove ${groupName}` }) })
    .last();

/**
 * Returns submitted co-host group ids in field index order.
 * @param {URLSearchParams} submittedForm - Submitted event form fields.
 * @returns {string[]} Co-host group ids.
 */
export const listSubmittedCohostIds = (submittedForm) =>
  [...submittedForm.entries()]
    .filter(([key]) => key.startsWith("cohost_group_ids["))
    .sort(([left], [right]) => left.localeCompare(right, "en", { numeric: true }))
    .map(([, value]) => value);

/**
 * Opens the co-hosts section of the current event editor.
 * @param {import("@playwright/test").Page} page - Playwright page with an open event editor.
 * @returns {Promise<void>}
 */
export const openCohostsSection = async (page) => {
  const sectionButton = page.locator('button[data-section="cohosts"]');
  await sectionButton.click();
  await expect(sectionButton).toHaveAttribute("data-active", "true");
};

/**
 * Approves, rejects, or cancels co-hosting from the co-host dashboard list.
 * @param {import("@playwright/test").Page} page - Playwright page for a co-host group admin.
 * @param {string} eventName - Event name shown in the row.
 * @param {"approve"|"cancel"|"reject"} action - Co-host action.
 * @returns {Promise<void>}
 */
export const respondToCohostInvitation = async (page, eventName, action) => {
  // Open the row actions for the invitation.
  await navigateToPath(page, "/dashboard/group?tab=cohosts");
  const row = await expectCohostDashboardRow(page, eventName, action === "cancel" ? "Approved" : "Pending");
  await row.getByLabel(`Open co-host actions for ${eventName}`).click();
  await row.locator(`[data-cohost-action="${action}"]`).click();

  // Verify approval consequences before confirming.
  const dialog = page.locator(".swal2-popup");
  if (action === "approve") {
    await expect(dialog).toContainText("The event appears on your group page");
    await expect(dialog).toContainText("you get no access to it");
  }

  // Confirm the action and verify the refreshed status.
  await waitForActionResponse(
    page,
    () => dialog.getByRole("button", { name: ACTION_CONFIRM_LABELS[action] }).click(),
    {
      method: "PUT",
      status: 204,
      urlEndsWith: `/${action}`,
    },
  );
  await expectCohostDashboardRow(page, eventName, ACTION_RESULT_STATUSES[action]);
};

/**
 * Waits for the co-host group options of one community to load.
 * @param {import("@playwright/test").Page} page - Playwright page with an open event editor.
 * @param {string} communityId - Community whose groups are loaded.
 * @returns {Promise<import("@playwright/test").Response>} Group options response.
 */
export const waitForGroupOptions = (page, communityId) =>
  page.waitForResponse(
    (response) =>
      response.request().method() === "GET" &&
      response.url().includes(GROUP_OPTIONS_PATH) &&
      response.url().includes(communityId) &&
      response.ok(),
  );
