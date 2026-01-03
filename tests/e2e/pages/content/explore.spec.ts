import { expect, test } from "@playwright/test";

import {
  TEST_COMMUNITY_NAME,
  TEST_EVENT_NAMES,
  TEST_GROUP_NAMES,
  navigateToPath,
} from "../../utils";

test.describe("explore pages", () => {
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
      await expect(page.locator("#sort_selector")).toHaveCount(0);
    });

    test("shows a filtered empty state when no events match the search", async ({
      page,
    }) => {
      await navigateToPath(
        page,
        `/explore?entity=events&community[0]=${TEST_COMMUNITY_NAME}`,
      );

      const searchInput = page.getByPlaceholder("Search events");
      await expect(searchInput).toBeVisible();

      await Promise.all([
        page.waitForResponse(
          (response) =>
            response.request().method() === "GET" &&
            response.url().includes("/explore/events-section") &&
            response.url().includes("ts_query=No%20matching%20event") &&
            response.ok(),
        ),
        searchInput.fill("No matching event").then(() => searchInput.press("Enter")),
      ]);

      const filteredEmptyState = page.locator(".no-results-filtered:not(.hidden)");

      await expect(filteredEmptyState).toBeVisible();
      await expect(
        filteredEmptyState.getByText("No events found", { exact: true }),
      ).toBeVisible();
      await expect(
        filteredEmptyState.getByText(
          "We can't seem to find any events that match your search criteria. You can reset your filters or try a different search.",
        ),
      ).toBeVisible();
    });
  });

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
});
