import { expect } from "../fixtures.js";
import { waitForActionResponse } from "../utils.js";

/**
 * Verifies the inbox status filter of a dashboard inbox already loaded on the page: the menu
 * options, applying one status (request, pushed URL, rows and active chip), then removing it
 * with the chip reset and with "Reset all".
 * @param {import("@playwright/test").Page} page - Page showing the inbox list.
 * @param {{
 *   listPath: string,
 *   matchingRowText: string,
 *   options: string[],
 *   otherRowText: string,
 *   status: { label: string, value: string }
 * }} options - Inbox list partial path, a row text with the applied status, the expected option
 *   labels in order, a row text with another status, and the status to apply.
 * @returns {Promise<void>}
 */
export const expectInboxStatusFilter = async (
  page,
  { listPath, matchingRowText, options, otherRowText, status },
) => {
  const list = page.locator("[data-inbox-list]");
  const rows = list.locator("[data-inbox-conversation-row]");
  const matchingRow = rows.filter({ hasText: matchingRowText });
  const otherRow = rows.filter({ hasText: otherRowText });
  const activeFilters = list.getByText("Active filters", { exact: true }).locator("xpath=..");

  // Open the status menu and verify its options, with every status selected
  await list.getByLabel("Status filters").click();
  const menu = list.locator("#inbox-status-filter-options");
  await expect(menu.getByRole("button")).toHaveText(options);
  await expect(menu.getByRole("button", { name: "All", exact: true })).toHaveAttribute(
    "aria-pressed",
    "true",
  );

  // Apply the status and verify the request and the pushed dashboard URL
  await applyStatus(page, menu, listPath, status);

  // Verify only rows with the status remain, under the active status chip
  await expect(matchingRow).toBeVisible();
  await expect(otherRow).toHaveCount(0);
  await expect(rows.filter({ hasNot: page.getByText(status.label, { exact: true }) })).toHaveCount(0);
  await expect(activeFilters).toContainText(`Status: ${status.label}`);
  await expect(
    menu.getByRole("button", { name: status.label, exact: true, includeHidden: true }),
  ).toHaveAttribute("aria-pressed", "true");

  // Remove the status with the chip reset and verify the unfiltered list
  await resetStatus(page, listPath, () =>
    activeFilters.getByRole("button", { name: "Reset status filter" }).click(),
  );
  await expect(otherRow).toBeVisible();

  // Apply the status again and remove it with "Reset all"
  await list.getByLabel("Status filters").click();
  await applyStatus(page, menu, listPath, status);
  await expect(otherRow).toHaveCount(0);
  await resetStatus(page, listPath, () => activeFilters.getByRole("button", { name: "Reset all" }).click());
  await expect(otherRow).toBeVisible();
};

// Helpers.

/**
 * Applies one status from the open status menu and verifies the request and the pushed URL.
 * @param {import("@playwright/test").Page} page - Page showing the inbox list.
 * @param {import("@playwright/test").Locator} menu - Open status menu.
 * @param {string} listPath - Inbox list partial path.
 * @param {{ label: string, value: string }} status - Status to apply.
 * @returns {Promise<void>}
 */
const applyStatus = async (page, menu, listPath, status) => {
  await waitForActionResponse(
    page,
    () => menu.getByRole("button", { name: status.label, exact: true }).click(),
    {
      method: "GET",
      params: { status: status.value },
      pathname: listPath,
      status: 200,
    },
  );
  await expect(page).toHaveURL((url) => isInboxDashboardUrl(url, listPath, status.value));
};

/**
 * Returns whether a URL is the dashboard inbox of a list path with the given status filter.
 * @param {URL} url - Page URL.
 * @param {string} listPath - Inbox list partial path, the dashboard path plus `/inbox`.
 * @param {string|null} status - Expected status filter, or null when unfiltered.
 * @returns {boolean} Whether the URL matches.
 */
const isInboxDashboardUrl = (url, listPath, status) =>
  url.pathname === listPath.replace(/\/inbox$/, "") &&
  url.searchParams.get("tab") === "inbox" &&
  url.searchParams.get("status") === status;

/**
 * Removes the status filter and verifies the request, the pushed URL and the hidden chip.
 * @param {import("@playwright/test").Page} page - Page showing the inbox list.
 * @param {string} listPath - Inbox list partial path.
 * @param {() => Promise<void>} reset - Click on a reset control.
 * @returns {Promise<void>}
 */
const resetStatus = async (page, listPath, reset) => {
  await waitForActionResponse(page, reset, {
    method: "GET",
    params: { status: null },
    pathname: listPath,
    status: 200,
  });
  await expect(page).toHaveURL((url) => isInboxDashboardUrl(url, listPath, null));
  await expect(page.locator("[data-inbox-list]").getByText("Active filters", { exact: true })).toHaveCount(0);
};
