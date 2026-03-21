import { expect, test } from "@playwright/test";

import {
  TEST_COMMUNITY_NAME,
  TEST_EVENT_NAMES,
  navigateToPath,
} from "../utils";

test.describe("event explore", () => {
  test("supports kind filtering and switching to calendar view", async ({ page }) => {
    await navigateToPath(
      page,
      `/explore?entity=events&community[0]=${TEST_COMMUNITY_NAME}`,
    );

    await expect(page.getByPlaceholder("Search events")).toBeVisible();
    await expect(page.getByText(TEST_EVENT_NAMES.alpha[0], { exact: true })).toBeVisible();
    await expect(page.getByText(TEST_EVENT_NAMES.alpha[1], { exact: true })).toBeVisible();

    const inPersonFilter = page.locator('input[name="kind[]"][value="in-person"]').first();
    await inPersonFilter.evaluate((input) => {
      if (!(input instanceof HTMLInputElement)) {
        throw new Error("in-person filter input not found");
      }
      input.checked = true;
      input.dispatchEvent(new Event("change", { bubbles: true }));
    });

    await expect(page.getByText(TEST_EVENT_NAMES.alpha[0], { exact: true })).toBeVisible();
    await expect(page.getByText(TEST_EVENT_NAMES.alpha[1], { exact: true })).toHaveCount(0);

    await page.locator('label[for="calendar"]').click();

    await expect(page.locator("#calendar-box")).toBeVisible();
    await expect(page.locator("#calendar-date")).toBeVisible();
    await expect(page.locator("#current-month-btn")).toBeVisible();
    await expect(page.locator('#sort_selector')).toHaveCount(0);
  });
});
