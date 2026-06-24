import { expect, test } from "@playwright/test";

import {
  TEST_ALLIANCE_NAME,
  TEST_ALLIANCE_TITLE,
  TEST_GROUP_NAMES,
  navigateToPath,
} from "../../utils.js";

test.describe("site explore groups page", () => {
  test("supports searching groups and switching to map view", async ({
    page,
  }) => {
    // Load the groups explore page with the alliance filter applied.
    await navigateToPath(
      page,
      `/explore?entity=groups&alliance[0]=${TEST_ALLIANCE_NAME}`,
    );

    // Find the Search groups control.
    const searchInput = page.getByPlaceholder("Search groups");

    // Verify groups render before applying search.
    await expect(
      page.getByRole("heading", {
        level: 1,
        name: `${TEST_ALLIANCE_TITLE} Groups`,
      }),
    ).toBeVisible();
    await expect(searchInput).toBeVisible();
    await expect(
      page.getByText(TEST_GROUP_NAMES.alpha, { exact: true }),
    ).toBeVisible();
    await expect(
      page.getByText(TEST_GROUP_NAMES.gamma, { exact: true }),
    ).toBeVisible();

    // Submit a group search and wait for the results to refresh.
    await Promise.all([
      page.waitForResponse(
        (response) =>
          response.request().method() === "GET" &&
          response.url().includes("/explore/groups-section") &&
          response.url().includes("ts_query=Observability") &&
          response.ok(),
      ),
      searchInput.fill("Observability").then(() => searchInput.press("Enter")),
    ]);

    // Verify the search narrows the list to the matching group.
    await expect(
      page.getByText(TEST_GROUP_NAMES.gamma, { exact: true }),
    ).toBeVisible();
    await expect(
      page.getByText(TEST_GROUP_NAMES.alpha, { exact: true }),
    ).toHaveCount(0);

    // Switch to the map view and wait for list controls to refresh.
    await Promise.all([
      page.waitForResponse(
        (response) =>
          response.request().method() === "GET" &&
          response.url().includes("/explore/groups-section") &&
          response.url().includes("view_mode=map") &&
          response.ok(),
      ),
      page.locator('label[for="map"]').click(),
    ]);

    // Verify map mode renders the map and hides sorting controls.
    await expect(page.locator("#map-box")).toBeVisible();
    await expect(page.locator("#map-box.leaflet-container")).toBeVisible();
    await expect(page.locator("#sort_selector")).toHaveCount(0);
  });

  test("shows an empty state when no groups match the search", async ({
    page,
  }) => {
    // Load the groups explore page with the alliance filter applied.
    await navigateToPath(
      page,
      `/explore?entity=groups&alliance[0]=${TEST_ALLIANCE_NAME}`,
    );

    // Submit a group search that has no matches.
    const searchInput = page.getByPlaceholder("Search groups");
    await expect(searchInput).toBeVisible();

    // Submit the unmatched search query and wait for filtered results.
    await Promise.all([
      page.waitForResponse(
        (response) =>
          response.request().method() === "GET" &&
          response.url().includes("/explore/groups-section") &&
          response.url().includes("ts_query=No%20matching%20group") &&
          response.ok(),
      ),
      searchInput
        .fill("No matching group")
        .then(() => searchInput.press("Enter")),
    ]);

    // Verify the filtered empty state explains the missing matches.
    await expect(page.getByText("We're sorry!", { exact: true })).toBeVisible();
    await expect(
      page.getByText(
        "We can't seem to find any groups that match your search criteria. You can reset your filters or try a different search.",
      ),
    ).toBeVisible();
  });
});
