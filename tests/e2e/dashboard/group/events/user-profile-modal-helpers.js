import { expect } from "../../../fixtures.js";

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
