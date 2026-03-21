import { expect, test } from "@playwright/test";

import {
  TEST_COMMUNITY_NAME,
  TEST_GROUP_NAMES,
  navigateToPath,
} from "../utils";

test.describe("group explore", () => {
  test("supports searching groups and switching to map view", async ({ page }) => {
    await navigateToPath(
      page,
      `/explore?entity=groups&community[0]=${TEST_COMMUNITY_NAME}`,
    );

    const searchInput = page.getByPlaceholder("Search groups");

    await expect(searchInput).toBeVisible();
    await expect(page.getByText(TEST_GROUP_NAMES.alpha, { exact: true })).toBeVisible();
    await expect(page.getByText(TEST_GROUP_NAMES.gamma, { exact: true })).toBeVisible();

    await Promise.all([
      page.waitForResponse(
        (response) =>
          response.request().method() === "GET" &&
          response.url().includes("/explore/groups-section") &&
          response.url().includes("ts_query=Gamma") &&
          response.ok(),
      ),
      searchInput.fill("Gamma").then(() => searchInput.press("Enter")),
    ]);

    await expect(page.getByText(TEST_GROUP_NAMES.gamma, { exact: true })).toBeVisible();
    await expect(page.getByText(TEST_GROUP_NAMES.alpha, { exact: true })).toHaveCount(0);

    await page.locator('label[for="map"]').click();

    await expect(page.locator("#map-box")).toBeVisible();
    await expect(page.locator("#map-box.leaflet-container")).toBeVisible();
    await expect(page.locator("#sort_selector")).toHaveCount(0);
  });
});
