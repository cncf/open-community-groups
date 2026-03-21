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

  test("shows an empty state when no groups match the search", async ({ page }) => {
    await navigateToPath(
      page,
      `/explore?entity=groups&community[0]=${TEST_COMMUNITY_NAME}`,
    );

    const searchInput = page.getByPlaceholder("Search groups");

    await expect(searchInput).toBeVisible();

    await Promise.all([
      page.waitForResponse(
        (response) =>
          response.request().method() === "GET" &&
          response.url().includes("/explore/groups-section") &&
          response.url().includes("ts_query=No%20matching%20group") &&
          response.ok(),
      ),
      searchInput.fill("No matching group").then(() => searchInput.press("Enter")),
    ]);

    await expect(page.getByText("We're sorry!", { exact: true })).toBeVisible();
    await expect(
      page.getByText(
        "We can't seem to find any groups that match your search criteria. You can reset your filters or try a different search.",
      ),
    ).toBeVisible();
  });
});
