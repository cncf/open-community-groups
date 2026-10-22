import { expect } from "../../fixtures.js";

import { waitForActionResponse } from "../../utils.js";

/**
 * Awards a badge from an award trigger and returns the submitted award payload.
 * @param {import("@playwright/test").Page} page - Page with the award dialog.
 * @param {() => Promise<unknown>} openAward - Action that opens the award dialog.
 * @param {string} badgeId - Badge to award.
 * @param {{ expectedStatus?: string }} [options] - Extra text expected in the award status.
 * @returns {Promise<object>} Award request payload.
 */
export const submitBadgeAward = async (page, openAward, badgeId, { expectedStatus } = {}) => {
  // Open the dialog and select the badge once its options load.
  await waitForActionResponse(page, openAward, {
    method: "GET",
    urlIncludes: "/dashboard/group/badges/options",
  });
  const awardDialog = page.getByRole("dialog", { name: "Award badge" });
  await expect(awardDialog.getByRole("radiogroup", { name: "Badge" })).toBeVisible();
  await awardDialog.locator(`input[value="${badgeId}"]`).check({ force: true });

  // Submit the award and verify the accepted status.
  const response = await waitForActionResponse(
    page,
    () => awardDialog.getByRole("button", { name: "Award", exact: true }).click(),
    {
      method: "POST",
      urlEndsWith: "/dashboard/group/badges/award",
      status: 201,
    },
  );
  const status = awardDialog.getByRole("status");
  await expect(status).toContainText("Award accepted");
  if (expectedStatus) {
    await expect(status).toContainText(expectedStatus);
  }

  // Close the dialog before returning the submitted payload.
  await awardDialog.getByRole("button", { name: "Close", exact: true }).click();

  return response.request().postDataJSON();
};
