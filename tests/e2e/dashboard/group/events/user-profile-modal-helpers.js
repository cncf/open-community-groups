import { expect } from "../../../fixtures.js";

/**
 * Verifies a dashboard table reserves enough width for its user column.
 * @param {import("@playwright/test").Locator} table Table locator.
 * @param {string} headerName Accessible column header name.
 */
export const expectUserColumnHasRoom = async (table, headerName) => {
  const [tableWidth, userColumnWidth] = await Promise.all([
    table.evaluate((element) => element.getBoundingClientRect().width),
    table
      .getByRole("columnheader", { name: headerName, exact: true })
      .evaluate((element) => element.getBoundingClientRect().width),
  ]);

  expect(userColumnWidth / tableWidth).toBeGreaterThanOrEqual(0.29);
};

export const expectUserProfileModalFromRow = async (
  page,
  row,
  triggerName,
  displayName,
  expectedDetails = [],
) => {
  // Open the profile modal from the dashboard row trigger.
  await row.getByRole("button", { name: triggerName }).click();

  const profileDialog = page.getByRole("dialog", {
    name: /User(?: Information)?/,
  });

  // Verify the modal renders the expected profile payload.
  await expect(profileDialog).toBeVisible();
  await expect(profileDialog).toContainText(displayName);
  for (const expectedDetail of expectedDetails) {
    await expect(profileDialog).toContainText(expectedDetail);
  }

  // Close the modal so later row actions can continue from a clean page state.
  await profileDialog.getByRole("button", { name: "Close modal" }).click();
  await expect(profileDialog).toBeHidden();
};
